import 'voice_notes.dart';

/// Only used on the web (see web_audio_web.dart).
VoiceNoteAudio createWebAudio() => throw UnsupportedError('Web audio is only available on the web.');
