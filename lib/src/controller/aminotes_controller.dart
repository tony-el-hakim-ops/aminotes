import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bridge/tiptap_bridge.dart';
import '../bridge/tiptap_host.dart';
import '../editor/aminotes_theme.dart';
import '../licenses.dart';
import '../media/aminotes_media.dart';
import '../media/image_picking.dart';
import '../media/playable_audio.dart';
import '../media/voice_notes.dart';
import 'aminotes_content.dart';
import 'aminotes_error.dart';
import 'aminotes_state.dart';

/// Drives one note: loads it, edits it, reports changes and state.
///
/// Create one per note, show it with an `AminotesEditor`, and [close] (or
/// [dispose]) it when the note closes. The same controller can be shown by a small editor and then
/// a full-screen one (push a route with a second `AminotesEditor`): only the
/// most recently shown editor displays the note, and the note, cursor and undo
/// history move with it.
class AminotesController {
  AminotesController({
    AminotesContent initialContent = AminotesContent.empty,
    this.onChanged,
    this.onLinkTap,
    this.onError,
    this.saveRecordingWhenInterrupted = true,
    this.changeDelay = const Duration(milliseconds: 400),
    this.maxVoiceNoteDuration = const Duration(minutes: 10),
    @visibleForTesting TiptapHost Function(void Function(String message) onMessage)? hostFactory,
    @visibleForTesting VoiceNoteRecorder Function(MediaStore store)? recorderFactory,
    @visibleForTesting AminotesImagePicker? imagePicker,
    @visibleForTesting this._audioFactory,
  }) : _content = initialContent,
       _imagePicker = imagePicker ?? defaultImagePicker,
       _hostFactory = hostFactory ?? ((onMessage) => TiptapHost(onMessage: onMessage)),
       _recorderFactory = recorderFactory ?? VoiceNoteRecorder.new {
    registerAminotesLicenses();
  }

  /// Called with the note's Tiptap JSON after the user edits it: once typing
  /// pauses for [changeDelay], and when the editor loses focus. Save it here.
  final ValueChanged<Map<String, dynamic>>? onChanged;

  /// Called when the user taps a link in the note, e.g. to open it with
  /// `url_launcher` or ask first. Without it, taps on links do nothing.
  /// Links with an unsafe protocol (`javascript:`, `data:`, …) are never
  /// reported; the URL can still be anything else the note contains, so open
  /// it the way you'd open any untrusted link.
  final ValueChanged<String>? onLinkTap;

  /// Problems the package recovered from (a note that can't load, a recording
  /// or file that failed, …), for logging or telling the user.
  final ValueChanged<AminotesError>? onError;

  /// When the app goes to the background (a call, switching apps) during a
  /// recording: true inserts what was recorded so far, false discards it.
  final bool saveRecordingWhenInterrupted;

  /// How long typing must pause before [onChanged] fires.
  final Duration changeDelay;

  /// A recording stops and is inserted on its own after this long.
  final Duration maxVoiceNoteDuration;

  final VoiceNoteRecorder Function(MediaStore store) _recorderFactory;
  late final _recorder = _recorderFactory(_media)..onFailed = _onRecordingFailed;
  final _recording = ValueNotifier<AminotesRecording?>(null);
  Timer? _recordingLimit;

  final TiptapHost Function(void Function(String message) onMessage) _hostFactory;
  final _state = ValueNotifier(const AminotesState());
  final _changes = StreamController<Map<String, dynamic>>.broadcast();
  final _editors = <Object>[];
  final _activeEditor = ValueNotifier<Object?>(null);
  final _ready = Completer<void>();
  // Completes whenever the page shows the note; replaced while the web iframe
  // reloads (it does when moved between editors), so calls wait for it.
  var _pageLoaded = Completer<void>();
  // Web: where the cursor was before the iframe moved (and reloaded).
  Map<String, dynamic>? _selectionAfterReload;
  final _contentHeight = ValueNotifier<double?>(null);
  bool _disposed = false;
  AppLifecycleListener? _lifecycle;

  TiptapHost? _host;
  TiptapBridge? _bridge;

  // What to show when the page (re)loads: the loaded note, then the latest
  // edited JSON, so moving the editor never loses text.
  AminotesContent _content;

  // Applied whenever the page (re)loads.
  String _placeholder = '';
  String _direction = 'ltr';
  Map<String, String> _labels = const {};
  Map<String, String> _themeVars = const {};
  bool _dark = false;

  MediaStore get _media => AminotesMedia.store;
  final AminotesImagePicker _imagePicker;
  final VoiceNoteAudio Function()? _audioFactory;
  late final _player = VoiceNotePlayer(store: _media, onChanged: _onPlayback, audioFactory: _audioFactory);
  final _playback = ValueNotifier<AminotesPlayback?>(null);

  /// The editor's current state, for toolbars: listen with a
  /// `ValueListenableBuilder`.
  ValueListenable<AminotesState> get state => _state;

  /// Whether to show your toolbar: the note is being edited, or a voice note
  /// is recording or playing. Use this rather than `state.focused` alone: recording can
  /// take focus away (e.g. Android's microphone permission dialog), and the
  /// recording bar must stay visible until the user taps Done or Cancel.
  late final ValueListenable<bool> toolbarVisible = _ToolbarVisible(_state, _recording, _playback);

  /// The same JSON as [onChanged], as a stream.
  Stream<Map<String, dynamic>> get changes => _changes.stream;

  /// Completes when the editor page has loaded and shows the note.
  Future<void> get ready => _ready.future;

  /// The height the note's content needs (logical pixels), once loaded. Used
  /// by `AminotesEditor(autoHeight: true)`; listen to it for your own layout.
  ValueListenable<double?> get contentHeight => _contentHeight;

  /// Starts loading the editor before it's shown (e.g. when the screen
  /// opens), so the note appears instantly when the editor is built.
  void preload() => _ensureHost();

  /// Replaces the note. Loading isn't an undoable step.
  Future<void> load(AminotesContent content) async {
    _content = content;
    _selectionAfterReload = null;
    unawaited(_player.stop());
    if (_state.value.ready) await _sendContent();
  }

  /// The note as Tiptap JSON, including edits not yet reported by [onChanged].
  ///
  /// Waits for the editor to load if it hasn't yet. Before any editor is shown,
  /// a note loaded as JSON is returned as is; HTML and text need the editor to
  /// convert them.
  Future<Map<String, dynamic>> getJson() async {
    final content = _content;
    if (_host == null) {
      if (content is AminotesJsonContent) return content.doc;
      throw StateError('Show the controller in an AminotesEditor before reading HTML or text content as JSON.');
    }
    await _pageLoaded.future;
    return _bridge!.getJSON();
  }

  // Formatting commands. Each keeps the cursor in the editor.
  /// Bold on or off for the selection (or what's typed next).
  Future<void> toggleBold() => execute('toggleBold');

  /// Italic on or off for the selection (or what's typed next).
  Future<void> toggleItalic() => execute('toggleItalic');

  /// Underline on or off for the selection (or what's typed next).
  Future<void> toggleUnderline() => execute('toggleUnderline');

  /// Strikethrough on or off for the selection (or what's typed next).
  Future<void> toggleStrike() => execute('toggleStrike');

  /// Inline code on or off for the selection (or what's typed next).
  Future<void> toggleCode() => execute('toggleCode');

  /// Heading level 1–3; calling it again on the same level returns to text.
  Future<void> toggleHeading(int level) {
    assert(level >= 1 && level <= 3, 'Heading levels are 1 to 3');
    return execute('setHeading', {'level': level});
  }

  /// Turns the block at the cursor into normal text (e.g. from a heading).
  Future<void> setParagraph() => execute('setParagraph');

  /// Types [text] at the cursor, replacing any selected text.
  Future<void> insertText(String text) => execute('insertText', {'text': text});

  /// Bullet list on or off for the blocks at the cursor.
  Future<void> toggleBulletList() => execute('toggleBulletList');

  /// Numbered list on or off for the blocks at the cursor.
  Future<void> toggleNumberedList() => execute('toggleOrderedList');

  /// Checklist (to-do items with checkboxes) on or off for the blocks at the cursor.
  Future<void> toggleChecklist() => execute('toggleTaskList');

  /// Quote on or off for the blocks at the cursor.
  Future<void> toggleQuote() => execute('toggleBlockquote');

  /// Code block on or off for the block at the cursor.
  Future<void> toggleCodeBlock() => execute('toggleCodeBlock');

  /// Inserts a horizontal divider line at the cursor.
  Future<void> insertDivider() => execute('setHorizontalRule');

  /// Nests the list item at the cursor one level deeper (see
  /// [AminotesState.canIndent]).
  Future<void> indent() => execute('sinkListItem');

  /// Moves the list item at the cursor up one level (see
  /// [AminotesState.canOutdent]).
  Future<void> outdent() => execute('liftListItem');

  /// Links the selected text to [url]; with nothing selected, inserts [url] as
  /// a link.
  Future<void> setLink(String url) => execute('setLink', {'href': url});

  /// Removes the link at the cursor, keeping its text.
  Future<void> removeLink() => execute('unsetLink');

  /// Colors the selected text (or what's typed next); null restores the
  /// default color. Stored in the note as `#rrggbb`.
  Future<void> setTextColor(Color? color) => execute('setTextColor', {'color': color == null ? null : cssHex(color)});

  /// Highlights the selected text with [color]; null removes the highlight.
  Future<void> setHighlightColor(Color? color) =>
      execute('setHighlight', {'color': color == null ? null : cssHex(color)});

  // ---------------------------------------------------------------------------
  // Voice notes

  /// The recording in progress, or null. Show your own recording UI from it
  /// (or use `AminotesRecordingBar`).
  ValueListenable<AminotesRecording?> get recording => _recording;

  /// Starts recording a voice note (asks for the microphone the first time).
  /// The editor keeps the cursor; [finishVoiceNote] inserts the note there.
  Future<AminotesRecordResult> startVoiceNote() async {
    if (_recording.value != null) return AminotesRecordResult.started;
    await _player.stop();
    try {
      if (!await _recorder.start()) return AminotesRecordResult.permissionDenied;
    } catch (error) {
      _report(AminotesErrorKind.recording, "Recording couldn't start", error);
      return AminotesRecordResult.failed;
    }
    _recording.value = AminotesRecording._(_recorder, maxVoiceNoteDuration);
    _recordingLimit = Timer(maxVoiceNoteDuration, finishVoiceNote);
    return AminotesRecordResult.started;
  }

  /// Stops recording and inserts the voice note at the cursor. Returns its
  /// `src` (a `local:` file until uploaded), or null if nothing was recorded.
  Future<String?> finishVoiceNote() async {
    if (_recording.value == null) return null;
    _endRecording();
    final ({String src, int duration})? note;
    try {
      note = await _recorder.stop();
    } catch (error) {
      _report(AminotesErrorKind.recording, "Recording couldn't be saved", error);
      return null;
    }
    if (_disposed) return null;
    if (note == null) {
      _report(AminotesErrorKind.recording, 'Nothing was recorded');
      return null;
    }
    var src = note.src;
    if (kIsWeb) {
      // Some browsers record Opus, which iPhones can't play: convert it to AAC
      // (or WAV) so the voice note plays on every device.
      try {
        final playable = await makePlayableEverywhere(src);
        if (playable != null) src = playable.src;
      } catch (error) {
        _report(
          AminotesErrorKind.media,
          "Couldn't convert the recording for every device; it may not play on iPhones",
          error,
        );
      }
      if (_disposed) return null;
    }
    await execute('insertVoiceNote', {'src': src, 'duration': note.duration});
    return src;
  }

  /// Stops recording and throws the recording away.
  Future<void> cancelVoiceNote() async {
    if (_recording.value == null) return;
    _endRecording();
    await _recorder.cancel();
  }

  /// The voice note playing (or paused), or null. Tapping a voice note in the
  /// editor plays it; show your own player from this (or use
  /// `AminotesPlaybackBar`, which the toolbar shows on its own).
  ValueListenable<AminotesPlayback?> get playback => _playback;

  /// Pauses the voice note playing (see [playback]).
  Future<void> pauseVoiceNote() => _player.pause();

  /// Resumes the paused voice note.
  Future<void> resumeVoiceNote() => _player.resume();

  /// Jumps to [position] in the voice note playing.
  Future<void> seekVoiceNote(Duration position) => _player.seek(position);

  /// Stops playback.
  Future<void> stopVoiceNote() => _player.stop();

  /// Removes the voice note that's playing from the note (undo brings it back).
  /// The file stays until you delete it (see `AminotesMedia.unusedLocalFiles`).
  Future<void> deleteVoiceNote() async {
    final current = _player.current;
    if (current == null) return;
    await _player.stop();
    await execute('deleteVoiceNote', {'key': current.key});
  }

  void _onPlayback(AminotesPlayback? next) {
    if (_disposed) return;
    final previous = _playback.value;
    final bridge = _bridge;
    if (bridge != null && _state.value.ready) {
      if (previous != null && previous.key != next?.key) {
        unawaited(bridge.voiceNotePlayback(previous.key, playing: false));
      }
      if (next != null) unawaited(bridge.voiceNotePlayback(next.key, playing: next.playing, position: next.position));
    }
    _playback.value = next;
  }

  // The recording stopped by itself (e.g. the browser's encoder failed): end
  // it, so the recording bar doesn't keep counting.
  void _onRecordingFailed(Object error) {
    if (_disposed || _recording.value == null) return;
    _endRecording();
    _report(AminotesErrorKind.recording, 'The recording stopped unexpectedly and was lost', error);
    unawaited(_recorder.cancel());
  }

  void _endRecording() {
    _recordingLimit?.cancel();
    _recording.value = null;
  }

  // ---------------------------------------------------------------------------
  // Images

  /// Lets the user pick a photo (gallery or camera), stores it on this device
  /// (scaled to at most 2048 px) and inserts it at the cursor. Returns its
  /// `local:` src (a `blob:` URL on the web), or null if the user cancelled.
  /// Upload it later with [uploadPendingMedia], like voice notes.
  Future<String?> pickImage([AminotesImageSource source = AminotesImageSource.gallery]) async {
    final picked = await _imagePicker(source);
    if (picked == null || _disposed) return null;
    final src = kIsWeb
        ? picked.webUrl!
        : await _media.saveBytes(MediaStore.imagesFolder, imageExtension(picked.name), picked.bytes);
    await insertImage(src);
    return src;
  }

  /// Deletes what's selected in the editor, e.g. an image the user tapped
  /// (see [AminotesState.selectedNode]). Undo brings it back.
  Future<void> deleteSelection() => execute('deleteSelection');

  /// Places the selected image (see [AminotesState.selectedNode]) left,
  /// center or right on its line; null follows the text direction. Saved as
  /// the image's `align`.
  Future<void> setImageAlignment(AminotesImageAlignment? alignment) =>
      execute('setImageAlign', {'align': alignment?.name});

  /// Inserts an image you already have, e.g. an `https://` URL.
  Future<void> insertImage(String src, {String? alt}) => execute('insertImage', {'src': src, 'alt': ?alt});

  /// Stores [bytes] on this device and inserts them as an image (Android/iOS).
  /// Returns the `local:` src.
  Future<String> insertImageBytes(Uint8List bytes, {String extension = 'jpg', String? alt}) async {
    if (kIsWeb) throw UnsupportedError('insertImageBytes needs device storage; on the web insert a URL.');
    final src = await _media.saveBytes(MediaStore.imagesFolder, imageExtension('x.$extension'), bytes);
    await insertImage(src, alt: alt);
    return src;
  }

  // The page can't read app files: send it the image as a data: URL.
  Future<void> _resolveMedia(String src) async {
    String? url;
    try {
      final file = await _media.fileFor(src);
      if (file != null && await file.exists()) {
        url = 'data:${AminotesMedia.mimeTypeFor('image', src)};base64,${base64Encode(await file.readAsBytes())}';
      }
    } catch (error) {
      _report(AminotesErrorKind.media, "Couldn't read $src", error);
    }
    if (!_disposed) await _bridge?.mediaResolved(src, url);
  }

  // ---------------------------------------------------------------------------
  // Uploads

  /// Uploads every voice note in this note that only exists on this device,
  /// using [upload] (yours: send the file, return its `https://` URL), then
  /// points the note at the URLs. Call it when online. Returns the note's JSON
  /// after the swap, ready to save (it also arrives through [onChanged]).
  ///
  /// A file that fails to upload stays local and is tried again next time;
  /// the first error is rethrown after the others have been tried.
  Future<Map<String, dynamic>> uploadPendingMedia(AminotesUploader upload) async {
    final doc = await getJson();
    final replacements = <String, String>{};
    Object? firstError;
    StackTrace? firstStack;
    for (final pending in await AminotesMedia.pendingUploads(doc)) {
      try {
        replacements[pending.src] = await upload(pending);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    final updated = replaceMediaSources(replacements, doc);
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
    return updated;
  }

  /// Points media at new sources (`{old: new}`) in the open note, e.g. after
  /// you uploaded files yourself. Not an undo step. Returns the updated JSON.
  Map<String, dynamic> replaceMediaSources(Map<String, String> replacements, [Map<String, dynamic>? current]) {
    if (replacements.isEmpty) return current ?? const {};
    if (_state.value.ready) {
      unawaited(_bridge!.replaceSources(replacements));
    }
    final content = _content;
    final base = current ?? (content is AminotesJsonContent ? content.doc : null);
    final updated = base == null ? const <String, dynamic>{} : AminotesMedia.replaceSources(base, replacements);
    if (base != null) _content = AminotesContent.json(updated);
    return updated;
  }

  // Tables. Row and column commands act on the cell at the cursor (see
  // `state.isActive('table')`).

  /// Inserts a table at the cursor, with a header row by default.
  Future<void> insertTable({int rows = 3, int columns = 3, bool withHeaderRow = true}) {
    assert(rows > 0 && columns > 0, 'A table needs at least one row and column');
    return execute('insertTable', {'rows': rows, 'cols': columns, 'withHeaderRow': withHeaderRow});
  }

  /// Adds a row above the cell at the cursor.
  Future<void> addRowBefore() => execute('addRowBefore');

  /// Adds a row below the cell at the cursor.
  Future<void> addRowAfter() => execute('addRowAfter');

  /// Adds a column before the cell at the cursor.
  Future<void> addColumnBefore() => execute('addColumnBefore');

  /// Adds a column after the cell at the cursor.
  Future<void> addColumnAfter() => execute('addColumnAfter');

  /// Deletes the row at the cursor.
  Future<void> deleteRow() => execute('deleteRow');

  /// Deletes the column at the cursor.
  Future<void> deleteColumn() => execute('deleteColumn');

  /// Turns the table's first row into a header row, or back.
  Future<void> toggleHeaderRow() => execute('toggleHeaderRow');

  /// Deletes the table at the cursor.
  Future<void> deleteTable() => execute('deleteTable');

  /// Undoes the last edit (see [AminotesState.canUndo]).
  Future<void> undo() => execute('undo');

  /// Redoes the last undone edit (see [AminotesState.canRedo]).
  Future<void> redo() => execute('redo');

  /// Runs any command of the editor page by name (see `commands` in
  /// tiptap/src/editor.js). Prefer the typed methods above.
  Future<void> execute(String command, [Map<String, Object?> args = const {}]) async {
    await _pageLoaded.future;
    await _bridge!.command(command, args);
  }

  /// Puts the cursor back in the editor (keeps its position).
  Future<void> focus() async {
    await _pageLoaded.future;
    await _bridge!.focus();
  }

  /// Leaves the editor and closes the keyboard.
  Future<void> unfocus() async {
    if (!_state.value.ready) return;
    await _bridge!.blur();
  }

  /// Sends edits still waiting for the typing pause to [onChanged] now.
  /// Happens on its own when the app goes to the background and on [dispose].
  Future<void> flush() async {
    if (_state.value.ready) await _bridge!.flush();
  }

  /// Ends editing: returns the note's final JSON (save it), then disposes the
  /// controller. A recording in progress is inserted first.
  Future<Map<String, dynamic>> close() async {
    if (_recording.value != null) await finishVoiceNote();
    final json = await getJson();
    dispose();
    return json;
  }

  /// Frees the editor. Edits made in the last moment before this are still
  /// delivered to [onChanged] (shortly after), so nothing typed is lost;
  /// prefer [close] to get them back directly.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycle?.dispose();
    if (_recording.value != null) unawaited(_recorder.cancel());
    _endRecording();
    _recording.dispose();
    _recorder.dispose();
    _player.dispose();
    _playback.dispose();
    final host = _host;
    if (host != null && _state.value.ready) {
      // Let the page send its last edits before the WebView goes away.
      unawaited(_bridge!.flush());
      Timer(const Duration(milliseconds: 500), host.dispose);
    } else {
      host?.dispose();
    }
    _state.dispose();
    _contentHeight.dispose();
    _activeEditor.dispose();
    _changes.close();
  }

  void _report(AminotesErrorKind kind, String message, [Object? error]) {
    final report = AminotesError(kind, message, error);
    if (onError != null) {
      onError!(report);
    } else {
      debugPrint('aminotes: $report${error == null ? '' : ': $error'}');
    }
  }

  // Background: send pending edits; finish (or drop) a recording, since the
  // system may stop the microphone and the app.
  void _onAppHidden() {
    unawaited(flush());
    if (_recording.value != null) {
      unawaited(saveRecordingWhenInterrupted ? finishVoiceNote() : cancelVoiceNote());
    }
  }

  // ---------------------------------------------------------------------------
  // Used by AminotesEditor.

  /// The editor currently showing the WebView. Changes only between frames, so
  /// two editors never show the same WebView at once (a native view can have
  /// one parent).
  @internal
  ValueListenable<Object?> get activeEditor => _activeEditor;

  @internal
  void attach(Object editor) {
    _editors.add(editor);
    _scheduleHandover();
  }

  @internal
  void detach(Object editor) {
    // Not cleared here: this runs while the tree is locked. The disposed
    // editor no longer shows anything, and the handover replaces it.
    _editors.remove(editor);
    _scheduleHandover();
  }

  var _handoverScheduled = false;

  // Editors attach and detach while widgets build; the newest one takes the
  // WebView after this frame, once the previous owner has stopped showing it.
  void _scheduleHandover() {
    if (_handoverScheduled) return;
    _handoverScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _handover())
      ..scheduleFrame();
  }

  Future<void> _handover() async {
    if (_disposed || _activeEditor.value == _editors.lastOrNull) {
      _handoverScheduled = false;
      return;
    }
    final current = _activeEditor.value;
    if (current == null) {
      _handoverScheduled = false;
      _activeEditor.value = _editors.lastOrNull;
      return;
    }
    // Release first, then hand over on the next frame. On the web the iframe
    // reloads when it moves: take the note's latest text from the page first
    // (while it's still shown), so the reload restores everything typed, and
    // make calls wait for the reloaded page.
    if ((_host?.isWeb ?? false) && _pageLoaded.isCompleted) {
      if (_editors.contains(current)) {
        try {
          final snapshot = await _bridge!.evaluate(
            '[window.tiptap.getJSON(), window.tiptap.getSelection()]',
            timeout: const Duration(seconds: 2),
          );
          if (snapshot case [final Map<String, dynamic> doc, final Map<String, dynamic> selection]) {
            _content = AminotesContent.json(doc);
            _selectionAfterReload = selection;
          }
        } catch (_) {
          // Keep the last saved text; the cursor goes to the start.
        }
        if (_disposed) return;
      }
      _pageLoaded = Completer<void>();
    }
    _handoverScheduled = false;
    _activeEditor.value = null;
    _scheduleHandover();
  }

  @internal
  Widget buildHost(BuildContext context, {bool claimVerticalDrags = false}) =>
      _ensureHost().build(context, claimVerticalDrags: claimVerticalDrags);

  /// Runs JavaScript in the editor page and returns its result, e.g. to check
  /// what the real editor shows. For integration tests.
  @visibleForTesting
  Future<Object?> debugEvaluate(String code) async {
    await _pageLoaded.future;
    return _bridge!.evaluate(code);
  }

  /// How many times the editor page has loaded (a reload loses the cursor and,
  /// on the web, undo history). For integration tests.
  @visibleForTesting
  int get debugPageLoads => _pageLoads;
  var _pageLoads = 0;

  @internal
  set hostInteractive(bool value) => _ensureHost().interactive = value;

  /// The note as JSON when known without the page (to preview it while the
  /// editor loads).
  @internal
  Map<String, dynamic>? get knownJson => switch (_content) {
    AminotesJsonContent(:final doc) => doc,
    _ => null,
  };

  @internal
  bool get isWebHost => _ensureHost().isWeb;

  @internal
  void configure({
    String? placeholder,
    TextDirection? direction,
    Map<String, String>? labels,
    Map<String, String>? themeVars,
    bool? dark,
    String? css,
    List<AminotesFont>? fonts,
  }) {
    var changed = false;
    if (labels != null && !mapEquals(labels, _labels)) {
      _labels = labels;
      changed = true;
    }
    if (placeholder != null && placeholder != _placeholder) {
      _placeholder = placeholder;
      changed = true;
    }
    final dir = direction == null ? null : (direction == TextDirection.rtl ? 'rtl' : 'ltr');
    if (dir != null && dir != _direction) {
      _direction = dir;
      changed = true;
    }
    if (changed && _state.value.ready) {
      _bridge!.configure(placeholder: _placeholder, direction: _direction, labels: _labels);
    }
    if (themeVars != null && (!mapEquals(themeVars, _themeVars) || dark != _dark)) {
      _themeVars = themeVars;
      _dark = dark ?? _dark;
      if (_state.value.ready) _bridge!.setTheme(dark: _dark, vars: _themeVars);
    }
    if ((css != null && css != _customCss) || (fonts != null && !listEquals(fonts, _fonts))) {
      _customCss = css ?? _customCss;
      _fonts = fonts ?? _fonts;
      if (_state.value.ready) unawaited(_sendStyles());
    }
  }

  // Custom CSS and app fonts (AminotesTheme.css / fonts).
  String _customCss = '';
  List<AminotesFont> _fonts = const [];

  Future<void> _sendStyles() async {
    final bridge = _bridge;
    if (bridge == null) return;
    final css = _customCss;
    final fonts = _fonts;
    final faces = <Map<String, Object>>[];
    for (final font in fonts) {
      try {
        faces.add({
          'family': font.family,
          'weight': font.weight.value,
          'style': font.style == FontStyle.italic ? 'italic' : 'normal',
          'data': await _fontDataUrl(font.asset),
        });
      } catch (error) {
        _report(AminotesErrorKind.editor, "Couldn't load the font ${font.asset}", error);
      }
    }
    // A newer theme arrived meanwhile: it sends its own.
    if (_disposed || css != _customCss || !identical(fonts, _fonts)) return;
    await bridge.setStyles(css: css, fonts: faces);
  }

  // The page can't read the app's assets: fonts go to it as data: URLs,
  // read once per app run.
  static final _fontData = <String, Future<String>>{};

  static Future<String> _fontDataUrl(String asset) => _fontData.putIfAbsent(asset, () async {
    try {
      final data = await rootBundle.load(asset);
      final type = switch (asset.split('.').last.toLowerCase()) {
        'otf' => 'font/otf',
        'woff' => 'font/woff',
        'woff2' => 'font/woff2',
        _ => 'font/ttf',
      };
      return 'data:$type;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
    } catch (_) {
      _fontData.remove(asset);
      rethrow;
    }
  });

  // ---------------------------------------------------------------------------

  TiptapHost _ensureHost() {
    final existing = _host;
    if (existing != null) return existing;
    final host = _host = _hostFactory(_onMessage);
    _bridge = TiptapBridge(host.runJavaScript);
    _lifecycle = AppLifecycleListener(onHide: _onAppHidden, onPause: _onAppHidden);
    return host;
  }

  void _onMessage(String raw) {
    final message = _bridge!.handle(raw);
    if (_disposed) {
      // Last edits sent while closing still reach the app.
      if (message is TiptapChanged) onChanged?.call(message.doc);
      return;
    }
    switch (message) {
      case TiptapReady():
        _onPageReady();
      case TiptapStateChanged(:final state):
        // Kept even before the page counts as ready: the state for the loaded
        // note can arrive just before (dropping it left e.g. the word count at
        // 0 until the first edit). `ready` itself is only set once loaded.
        _state.value = state.copyWith(ready: _state.value.ready);
      case TiptapChanged(:final doc):
        _content = AminotesContent.json(doc);
        onChanged?.call(doc);
        _changes.add(doc);
      case TiptapVoiceNoteToggle(:final key, :final src, :final duration):
        _player
            .toggle(key, src, duration: duration)
            .catchError((Object error) => _report(AminotesErrorKind.media, "Couldn't play the voice note", error));
      case TiptapVoiceNoteStop(:final key):
        _player.stop(key);
      case TiptapResolveMedia(:final src):
        unawaited(_resolveMedia(src));
      case TiptapLinkTap(:final href):
        onLinkTap?.call(href);
      case TiptapHeight(:final value):
        _contentHeight.value = value;
      case TiptapError(:final message):
        _report(switch (message) {
          _ when message.startsWith('load:') => AminotesErrorKind.load,
          _ when message.startsWith('unsupported-webview:') => AminotesErrorKind.webView,
          _ => AminotesErrorKind.editor,
        }, message);
      case TiptapDocument() || TiptapEvalResult() || null:
        break;
    }
  }

  // Runs on first load and whenever the page reloads (on the web, moving the
  // iframe between editors reloads it).
  Future<void> _onPageReady() async {
    _pageLoads++;
    final bridge = _bridge!;
    unawaited(_player.stop());
    await bridge.configure(
      placeholder: _placeholder,
      direction: _direction,
      labels: _labels,
      changeDelayMs: changeDelay.inMilliseconds,
    );
    await bridge.setTheme(dark: _dark, vars: _themeVars);
    if (_customCss.isNotEmpty || _fonts.isNotEmpty) await _sendStyles();
    await _sendContent();
    if (_disposed) return;
    final selection = _selectionAfterReload;
    _selectionAfterReload = null;
    if (selection != null) await bridge.setSelection(selection);
    _state.value = _state.value.copyWith(ready: true);
    if (!_ready.isCompleted) _ready.complete();
    if (!_pageLoaded.isCompleted) _pageLoaded.complete();
  }

  Future<void> _sendContent() => switch (_content) {
    AminotesJsonContent(:final doc) => _bridge!.setContent('json', doc),
    AminotesHtmlContent(:final html) => _bridge!.setContent('html', html),
    AminotesTextContent(:final text) => _bridge!.setContent('text', text),
  };
}

/// Result of [AminotesController.startVoiceNote].
enum AminotesRecordResult {
  /// Recording; finish with `finishVoiceNote` or `cancelVoiceNote`.
  started,

  /// The user refused the microphone (or it's blocked in settings).
  permissionDenied,

  /// No microphone, or the platform refused to record.
  failed,
}

/// A recording in progress: see [AminotesController.recording].
class AminotesRecording {
  AminotesRecording._(this._recorder, this.maxDuration);

  final VoiceNoteRecorder _recorder;

  /// When the recording stops on its own.
  final Duration maxDuration;

  /// How long the recording has been going.
  Duration get elapsed => _recorder.elapsed;

  /// Microphone level, about -60 (silence) to 0 (loudest) dBFS.
  Stream<double> levels() => _recorder.levels();
}

class _ToolbarVisible extends ChangeNotifier implements ValueListenable<bool> {
  _ToolbarVisible(this._state, this._recording, this._playback) {
    _state.addListener(_update);
    _recording.addListener(_update);
    _playback.addListener(_update);
    _value = _compute();
  }

  final ValueListenable<AminotesState> _state;
  final ValueListenable<AminotesRecording?> _recording;
  final ValueListenable<AminotesPlayback?> _playback;
  late bool _value;

  bool _compute() => _state.value.focused || _recording.value != null || _playback.value != null;

  void _update() {
    final next = _compute();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  bool get value => _value;
}
