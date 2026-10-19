import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// Converts a web recording ([src], a `blob:` URL) to a format every device
/// plays (AAC, or WAV where the browser can't make AAC), using
/// assets/web_audio/audio.js. Returns null when it already plays everywhere.
/// [force] and [fallback] (skip AAC) are for tests.
Future<({String src, String mimeType})?> makePlayableEverywhere(
  String src, {
  bool force = false,
  bool fallback = false,
}) async {
  await _load();
  final options = {'force': force, 'fallback': fallback}.jsify()! as JSObject;
  final result = await _aminotesAudio!.toPlayable(src.toJS, options).toDart;
  if (!result.converted) return null;
  return (src: result.url, mimeType: result.type);
}

@JS('aminotesAudio')
external _AminotesAudio? get _aminotesAudio;

extension type _AminotesAudio._(JSObject _) implements JSObject {
  external JSPromise<_Playable> toPlayable(JSString url, JSObject options);
}

extension type _Playable._(JSObject _) implements JSObject {
  external String get url;
  external String get type;
  external bool get converted;
}

Future<void>? _loading;

// Loaded on first use: most apps record rarely, and most browsers record AAC.
Future<void> _load() => _loading ??= () {
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = ui_web.assetManager.getAssetUrl('packages/aminotes/assets/web_audio/audio.js');
  script.onload = ((web.Event _) => done.complete()).toJS;
  script.onerror = ((web.Event _) {
    _loading = null;
    done.completeError(StateError('Could not load assets/web_audio/audio.js'));
  }).toJS;
  web.document.head!.append(script);
  return done.future;
}();
