import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'web_audio.dart';

/// Where recorded (and later picked) media lives until it's uploaded.
///
/// Files are kept under `<app documents>/aminotes/` and referenced from the note
/// as `local:<folder>/<file>`, relative to that folder so the reference
/// survives app updates that move the app's container. After upload the host
/// app swaps them for `https://` URLs (see `AminotesMedia`).
///
/// On the web there is no app folder: recordings are `blob:` URLs, which last
/// only until the page reloads, so upload them as soon as possible.
class MediaStore {
  /// [rootDir] replaces the default folder (tests, or a host app's choice).
  MediaStore({Directory? rootDir}) : _root = rootDir;

  /// Prefix of media sources that are files on this device.
  static const scheme = 'local:';

  /// Folder (in [root]) for recordings.
  static const voiceNotesFolder = 'voice_notes';

  /// Folder (in [root]) for picked photos.
  static const imagesFolder = 'images';

  Directory? _root;

  /// The folder everything is stored in.
  Future<Directory> root() async => _root ??= Directory('${(await getApplicationDocumentsDirectory()).path}/aminotes');

  /// A new file path to record into, and the `local:` src that refers to it.
  Future<({String path, String src})> newFile(String folder, String extension) async {
    final dir = Directory('${(await root()).path}/$folder');
    await dir.create(recursive: true);
    final name = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    return (path: '${dir.path}/$name', src: '$scheme$folder/$name');
  }

  /// Whether [src] is a file on this device (not uploaded yet).
  static bool isLocal(String src) => src.startsWith(scheme);

  /// Saves [bytes] as a new file in [folder]; returns its `local:` src.
  Future<String> saveBytes(String folder, String extension, List<int> bytes) async {
    final target = await newFile(folder, extension);
    await File(target.path).writeAsBytes(bytes, flush: true);
    return target.src;
  }

  /// The file behind a `local:` src (null for anything else).
  Future<File?> fileFor(String src) async {
    if (!isLocal(src) || kIsWeb) return null;
    final relative = src.substring(scheme.length);
    // Never resolve outside the store.
    if (relative.split('/').contains('..')) return null;
    return File('${(await root()).path}/$relative');
  }

  /// Every stored file, as its `local:` src.
  Future<List<String>> allSources() async {
    if (kIsWeb) return const [];
    final dir = await root();
    if (!await dir.exists()) return const [];
    final prefix = '${dir.path}/';
    return [
      await for (final entity in dir.list(recursive: true))
        if (entity is File) '$scheme${entity.path.substring(prefix.length)}',
    ];
  }

  /// A playable source for a src: a local file or a URL.
  Future<Source> playable(String src) async {
    final file = await fileFor(src);
    return file != null ? DeviceFileSource(file.path) : UrlSource(src);
  }
}

/// What the voice note player is doing: see
/// `AminotesController.playback`. Null there when nothing is playing.
@immutable
class AminotesPlayback {
  const AminotesPlayback({
    required this.key,
    required this.src,
    required this.playing,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  /// Identifies the voice note in the open editor (not saved in the note).
  final String key;

  /// The voice note's source (`local:`, `https://` or `blob:`).
  final String src;

  /// False while paused.
  final bool playing;

  /// How far it has played.
  final Duration position;

  /// Zero until known.
  final Duration duration;

  AminotesPlayback copyWith({bool? playing, Duration? position, Duration? duration}) => AminotesPlayback(
    key: key,
    src: src,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
  );

  @override
  bool operator ==(Object other) =>
      other is AminotesPlayback &&
      other.key == key &&
      other.src == src &&
      other.playing == playing &&
      other.position == position &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(key, src, playing, position, duration);
}

/// The audio output [VoiceNotePlayer] drives (replaced in tests).
abstract interface class VoiceNoteAudio {
  Future<void> play(String src);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stop();
  Stream<Duration> get positions;
  Stream<Duration> get durations;
  Stream<void> get completions;
  void dispose();
}

class _DeviceAudio implements VoiceNoteAudio {
  _DeviceAudio(this.store);

  final MediaStore store;

  // Created lazily: the plugin talks to the platform as soon as it exists.
  late final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  @override
  Future<void> play(String src) async => _player.play(await store.playable(src));
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Stream<Duration> get positions => _player.onPositionChanged;
  @override
  Stream<Duration> get durations => _player.onDurationChanged;
  @override
  Stream<void> get completions => _player.onPlayerComplete;
  @override
  void dispose() => _player.dispose();
}

/// Plays one voice note at a time, reporting what it does through [onChanged].
class VoiceNotePlayer {
  VoiceNotePlayer({required MediaStore store, required this.onChanged, VoiceNoteAudio Function()? audioFactory})
    : _audioFactory = audioFactory ?? (() => kIsWeb ? createWebAudio() : _DeviceAudio(store));

  /// Called with the new playback state; null when stopped or finished.
  final void Function(AminotesPlayback? playback) onChanged;

  final VoiceNoteAudio Function() _audioFactory;
  VoiceNoteAudio? _audioInstance;
  final _subscriptions = <StreamSubscription<void>>[];
  AminotesPlayback? _current;

  AminotesPlayback? get current => _current;

  VoiceNoteAudio get _audio {
    final existing = _audioInstance;
    if (existing != null) return existing;
    final audio = _audioInstance = _audioFactory();
    _subscriptions.addAll([
      audio.positions.listen((position) => _update((p) => p.copyWith(position: position))),
      audio.durations.listen((duration) {
        if (duration > Duration.zero) _update((p) => p.copyWith(duration: duration));
      }),
      audio.completions.listen((_) => _set(null)),
    ]);
    return audio;
  }

  void _set(AminotesPlayback? playback) {
    if (playback == _current) return;
    _current = playback;
    onChanged(playback);
  }

  void _update(AminotesPlayback Function(AminotesPlayback current) change) {
    final current = _current;
    if (current != null) _set(change(current));
  }

  /// Plays [src] (the pill [key]), or pauses/resumes it if it's the current one.
  Future<void> toggle(String key, String src, {Duration duration = Duration.zero}) async {
    final current = _current;
    if (current != null && current.key == key) return current.playing ? pause() : resume();
    await stop();
    final audio = _audio;
    _set(AminotesPlayback(key: key, src: src, playing: true, duration: duration));
    try {
      await audio.play(src);
    } catch (error) {
      _set(null);
      rethrow;
    }
  }

  Future<void> pause() async {
    if (_current?.playing != true) return;
    _update((p) => p.copyWith(playing: false));
    await _audio.pause();
  }

  Future<void> resume() async {
    final current = _current;
    if (current == null || current.playing) return;
    _set(current.copyWith(playing: true));
    await _audio.resume();
  }

  Future<void> seek(Duration position) async {
    final current = _current;
    if (current == null) return;
    var target = position < Duration.zero ? Duration.zero : position;
    if (current.duration > Duration.zero && target > current.duration) target = current.duration;
    _set(current.copyWith(position: target));
    await _audio.seek(target);
  }

  /// Stops playback ([key] null: whatever is playing).
  Future<void> stop([String? key]) async {
    final current = _current;
    if (current == null || (key != null && key != current.key)) return;
    _set(null);
    await _audioInstance?.stop();
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _audioInstance?.dispose();
  }
}

/// Records one voice note at a time (AAC `.m4a`, mono).
class VoiceNoteRecorder {
  VoiceNoteRecorder(this.store);

  final MediaStore store;

  /// Called when a recording stops by itself (e.g. the browser's encoder
  /// failed). The recording is lost; [stop] then returns null.
  void Function(Object error)? onFailed;

  // Created lazily: the plugin talks to the platform as soon as it exists.
  AudioRecorder? _recorder;
  final _stopwatch = Stopwatch();
  String? _src;
  String? _path;
  StreamSubscription<RecordState>? _states;
  AudioEncoder _encoder = AudioEncoder.aacLc;
  // True while a stop is ours (stop, cancel, switching encoder).
  bool _stopping = false;
  bool _failed = false;

  AudioRecorder get _audio => _recorder ??= AudioRecorder();

  bool get isRecording => _stopwatch.isRunning;
  Duration get elapsed => _stopwatch.elapsed;

  /// Input level in dBFS (about -60 quiet … 0 loud), for a level meter.
  Stream<double> levels() =>
      _audio.onAmplitudeChanged(const Duration(milliseconds: 120)).map((amplitude) => amplitude.current);

  static RecordConfig _config(AudioEncoder encoder) =>
      RecordConfig(encoder: encoder, bitRate: 64000, sampleRate: 44100, numChannels: 1);

  /// Asks for the microphone if needed. False if the user refused.
  Future<bool> start() async {
    if (!await _audio.hasPermission()) return false;
    _failed = false;
    if (kIsWeb) {
      // The web recorder ignores the path and returns a blob: URL from stop().
      _path = null;
      _src = null;
      _states ??= _audio.onStateChanged().listen(_onWebState);
      // AAC plays everywhere (the iOS app too); browsers that can't record it
      // (Firefox) record Opus.
      final aac = await _audio.isEncoderSupported(AudioEncoder.aacLc);
      await _startWeb(aac ? AudioEncoder.aacLc : AudioEncoder.opus);
    } else {
      final target = await store.newFile(MediaStore.voiceNotesFolder, 'm4a');
      _path = target.path;
      _src = target.src;
      await _audio.start(_config(AudioEncoder.aacLc), path: target.path);
    }
    _stopwatch
      ..reset()
      ..start();
    return true;
  }

  Future<void> _startWeb(AudioEncoder encoder) async {
    _encoder = encoder;
    _stopping = true;
    try {
      await _audio.start(_config(encoder), path: '');
    } finally {
      _stopping = false;
    }
  }

  // On the web the browser's encoder can fail just after starting (seen with
  // AAC in Chrome): switch to Opus once. Any other unexpected stop loses the
  // recording.
  void _onWebState(RecordState state) {
    if (state != RecordState.stop || _stopping || !isRecording) return;
    if (_encoder == AudioEncoder.aacLc && _stopwatch.elapsed < const Duration(seconds: 3)) {
      unawaited(
        _startWeb(AudioEncoder.opus).then(
          (_) => _stopwatch
            ..reset()
            ..start(),
          onError: _fail,
        ),
      );
      return;
    }
    _fail(StateError('The recording stopped unexpectedly'));
  }

  void _fail(Object error) {
    _failed = true;
    _stopwatch.stop();
    onFailed?.call(error);
  }

  /// Finishes the recording. Returns the voiceNote attrs, or null if nothing
  /// was recorded.
  Future<({String src, int duration})?> stop() async {
    if (!isRecording) return null;
    _stopwatch.stop();
    _stopping = true;
    final String? result;
    try {
      result = await _audio.stop();
    } finally {
      _stopping = false;
    }
    if (_failed) return null;
    final src = kIsWeb ? result : _src;
    if (src == null) return null;
    // Round up so a short clip never shows 0:00.
    final seconds = (_stopwatch.elapsedMilliseconds / 1000).ceil();
    return (src: src, duration: seconds < 1 ? 1 : seconds);
  }

  /// Discards the recording in progress.
  Future<void> cancel() async {
    if (!isRecording) return;
    _stopwatch.stop();
    _stopping = true;
    try {
      await _audio.cancel();
    } finally {
      _stopping = false;
    }
    final path = _path;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  void dispose() {
    _states?.cancel();
    _recorder?.dispose();
  }
}
