import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Reads a `blob:` URL (a web recording) into bytes.
Future<Uint8List> readBlobBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// The MIME type of a `blob:` URL, e.g. `audio/webm;codecs=opus`.
Future<String?> readBlobType(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final type = (await response.blob().toDart).type;
  return type.isEmpty ? null : type;
}
