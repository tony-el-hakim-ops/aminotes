import 'dart:async';
import 'dart:convert';

import '../controller/aminotes_state.dart';

/// The editor page bundled by `npm run build` in tiptap/, as a Flutter asset
/// key. Package assets are addressed through `packages/<name>/`.
const tiptapEditorAsset = 'packages/aminotes/assets/editor/index.html';

/// Name of the JavaScriptChannel the page posts to (`window.TiptapBridge`).
const tiptapBridgeChannel = 'TiptapBridge';

/// A message from the page, decoded from the JSON string it posted.
sealed class TiptapMessage {
  const TiptapMessage();

  /// Returns null for anything that isn't a well-formed bridge message.
  static TiptapMessage? parse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    return switch (json['type']) {
      'ready' => const TiptapReady(),
      'state' => TiptapStateChanged(AminotesState.fromJson(json)),
      'change' when json['doc'] is Map<String, dynamic> => TiptapChanged(json['doc'] as Map<String, dynamic>),
      'json' when json['id'] is int && json['doc'] is Map<String, dynamic> => TiptapDocument(
        json['id'] as int,
        json['doc'] as Map<String, dynamic>,
      ),
      'error' => TiptapError('${json['message']}'),
      'voiceNoteToggle' when json['key'] is String && json['src'] is String => TiptapVoiceNoteToggle(
        json['key'] as String,
        json['src'] as String,
        Duration(milliseconds: (((json['duration'] as num?) ?? 0) * 1000).round()),
      ),
      'voiceNoteStop' when json['key'] is String => TiptapVoiceNoteStop(json['key'] as String),
      'resolveMedia' when json['src'] is String => TiptapResolveMedia(json['src'] as String),
      'linkTap' when json['href'] is String => TiptapLinkTap(json['href'] as String),
      'height' when json['value'] is num => TiptapHeight((json['value'] as num).toDouble()),
      'evalResult' when json['id'] is int => TiptapEvalResult(
        json['id'] as int,
        json['value'],
        json['error'] as String?,
      ),
      _ => null,
    };
  }
}

/// The page's script has loaded and `window.tiptap` is callable. Sent again
/// whenever the page reloads (e.g. the iframe was moved on the web).
class TiptapReady extends TiptapMessage {
  const TiptapReady();
}

class TiptapStateChanged extends TiptapMessage {
  const TiptapStateChanged(this.state);
  final AminotesState state;
}

/// The user edited the note; sent once typing pauses, and on blur.
class TiptapChanged extends TiptapMessage {
  const TiptapChanged(this.doc);
  final Map<String, dynamic> doc;
}

/// The reply to [TiptapBridge.getJSON] with the matching request [id].
class TiptapDocument extends TiptapMessage {
  const TiptapDocument(this.id, this.doc);
  final int id;
  final Map<String, dynamic> doc;
}

class TiptapError extends TiptapMessage {
  const TiptapError(this.message);
  final String message;
}

/// A voice note pill was tapped: play or pause [src]. [key] identifies the pill
/// so playback state can be reported back to it.
class TiptapVoiceNoteToggle extends TiptapMessage {
  const TiptapVoiceNoteToggle(this.key, this.src, [this.duration = Duration.zero]);
  final String key;
  final String src;

  /// The length saved in the note (the player corrects it once loaded).
  final Duration duration;
}

/// The pill playing [key] left the document (deleted, or the note reloaded).
class TiptapVoiceNoteStop extends TiptapMessage {
  const TiptapVoiceNoteStop(this.key);
  final String key;
}

/// The user tapped a link in the note.
class TiptapLinkTap extends TiptapMessage {
  const TiptapLinkTap(this.href);
  final String href;
}

/// The height the note's content needs, in logical pixels.
class TiptapHeight extends TiptapMessage {
  const TiptapHeight(this.value);
  final double value;
}

/// The reply to [TiptapBridge.evaluate].
class TiptapEvalResult extends TiptapMessage {
  const TiptapEvalResult(this.id, this.value, this.error);
  final int id;
  final Object? value;
  final String? error;
}

/// The page needs a displayable URL for a `local:` media [src].
class TiptapResolveMedia extends TiptapMessage {
  const TiptapResolveMedia(this.src);
  final String src;
}

/// Dart side of the bridge: turns calls into `window.tiptap.*` JavaScript and
/// routes the page's replies back.
///
/// Results come back through the message channel rather than
/// `runJavaScriptReturningResult`, whose value is double-encoded differently on
/// Android and iOS.
class TiptapBridge {
  TiptapBridge(this._runJavaScript);

  final Future<void> Function(String script) _runJavaScript;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;

  /// [format] is `json`, `html` or `text`.
  Future<void> setContent(String format, Object value) =>
      _call('setContent(${jsonEncode({'format': format, 'value': value})})');

  Future<void> configure({
    String? placeholder,
    int? changeDelayMs,
    String? direction,
    Map<String, String>? labels,
  }) => _call(
    'configure(${jsonEncode({'placeholder': ?placeholder, 'changeDelay': ?changeDelayMs, 'direction': ?direction, 'labels': ?labels})})',
  );

  /// [vars] are CSS custom properties, e.g. `{'--text': '#1b1b21'}`.
  Future<void> setTheme({required bool dark, required Map<String, String> vars}) =>
      _call('setTheme(${jsonEncode({'brightness': dark ? 'dark' : 'light', 'vars': vars})})');

  /// The host app's extra CSS and fonts (`[{family, weight, style, data}]`,
  /// data being a `data:` URL).
  Future<void> setStyles({required String css, required List<Map<String, Object>> fonts}) =>
      _call('setStyles(${jsonEncode({'css': css, 'fonts': fonts})})');

  /// Runs an editor command; see `commands` in tiptap/src/editor.js.
  Future<void> command(String name, [Map<String, Object?> args = const {}]) =>
      _call('command(${jsonEncode(name)}, ${jsonEncode(args)})');

  Future<void> focus() => _call('focus()');

  /// Puts the cursor/selection back at document positions (see `getSelection`
  /// in the page).
  Future<void> setSelection(Map<String, Object?> selection) => _call('setSelection(${jsonEncode(selection)})');

  /// Sends edits still waiting for the typing pause as a change message now.
  Future<void> flush() => _call('flush()');
  Future<void> blur() => _call('blur()');

  /// Points media at new sources (`{old: new}`), not as an undo step.
  Future<void> replaceSources(Map<String, String> replacements) => _call('replaceSources(${jsonEncode(replacements)})');

  /// Answers [TiptapResolveMedia]: [url] to display for [src], null if missing.
  Future<void> mediaResolved(String src, String? url) => _call('mediaResolved(${jsonEncode(src)}, ${jsonEncode(url)})');

  /// Tells the pill [key] whether its audio is playing.
  /// [position] is the elapsed time while a note is playing or paused, null
  /// once it stops.
  Future<void> voiceNotePlayback(String key, {required bool playing, Duration? position}) => _call(
    'voiceNotePlayback(${jsonEncode(key)}, $playing, ${position == null ? 'null' : position.inMilliseconds / 1000})',
  );

  Future<Map<String, dynamic>> getJSON({Duration timeout = const Duration(seconds: 5)}) {
    final id = _nextId++;
    final completer = _pending[id] = Completer<Map<String, dynamic>>();
    _call('requestJSON($id)').catchError((Object error) {
      _pending.remove(id)?.completeError(error);
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('The editor did not return its JSON', timeout);
      },
    );
  }

  final _pendingEvals = <int, Completer<Object?>>{};

  /// Runs JavaScript in the page and returns its JSON-encodable result (for
  /// tests).
  Future<Object?> evaluate(String code, {Duration timeout = const Duration(seconds: 10)}) {
    final id = _nextId++;
    final completer = _pendingEvals[id] = Completer<Object?>();
    _call('evaluate($id, ${jsonEncode(code)})').catchError((Object error) {
      _pendingEvals.remove(id)?.completeError(error);
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingEvals.remove(id);
        throw TimeoutException('The editor page did not answer', timeout);
      },
    );
  }

  /// Feed every page message here. Returns the parsed message (null if it
  /// wasn't one).
  TiptapMessage? handle(String raw) {
    final message = TiptapMessage.parse(raw);
    if (message is TiptapDocument) _pending.remove(message.id)?.complete(message.doc);
    if (message is TiptapEvalResult) {
      final completer = _pendingEvals.remove(message.id);
      if (message.error != null) {
        completer?.completeError(StateError('In the editor page: ${message.error}'));
      } else {
        completer?.complete(message.value);
      }
    }
    return message;
  }

  Future<void> _call(String js) => _runJavaScript('window.tiptap && window.tiptap.$js;');
}
