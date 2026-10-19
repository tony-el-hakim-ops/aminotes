import 'dart:typed_data';

/// `blob:` URLs exist only on the web.
Future<Uint8List> readBlobBytes(String url) => throw UnsupportedError('blob: URLs exist only on the web: $url');

Future<String?> readBlobType(String url) async => null;
