import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'voice_notes.dart';

VoiceNoteAudio createWebAudio() => _HtmlAudio();

/// Plays through a plain `<audio>` element. Unlike audioplayers' web player it
/// doesn't make a CORS request, so voice notes on servers without CORS headers
/// play too (as they would in any web page).
class _HtmlAudio implements VoiceNoteAudio {
  _HtmlAudio() {
    _listen('timeupdate', () => _positions.add(_toDuration(_audio.currentTime)));
    _listen('durationchange', () {
      final seconds = _audio.duration;
      if (seconds.isFinite && seconds > 0) _durations.add(_toDuration(seconds));
    });
    _listen('ended', () => _completions.add(null));
  }

  final _audio = web.HTMLAudioElement()..preload = 'auto';
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _completions = StreamController<void>.broadcast();

  void _listen(String event, void Function() handler) =>
      _audio.addEventListener(event, ((web.Event _) => handler()).toJS);

  static Duration _toDuration(num seconds) => Duration(milliseconds: (seconds * 1000).round());

  @override
  Future<void> play(String src) async {
    _audio.src = src;
    await _audio.play().toDart;
  }

  @override
  Future<void> pause() async => _audio.pause();

  @override
  Future<void> resume() async => _audio.play().toDart;

  @override
  Future<void> seek(Duration position) async => _audio.currentTime = position.inMilliseconds / 1000;

  @override
  Future<void> stop() async {
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
  }

  @override
  Stream<Duration> get positions => _positions.stream;
  @override
  Stream<Duration> get durations => _durations.stream;
  @override
  Stream<void> get completions => _completions.stream;

  @override
  void dispose() {
    unawaited(stop());
    _positions.close();
    _durations.close();
    _completions.close();
  }
}
