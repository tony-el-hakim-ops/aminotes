import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'media_bytes.dart';
import 'voice_notes.dart';

/// A recorded file waiting to be uploaded. Passed to your upload function.
@immutable
class AminotesUpload {
  const AminotesUpload({required this.src, required this.kind, required this.mimeType, this.path, required this.read});

  /// The note's current reference: `local:voice_notes/…` (or `blob:…` on the web).
  final String src;

  /// The node type: `voiceNote` or `image`.
  final String kind;

  /// E.g. `audio/mp4` for voice notes, `image/jpeg` for photos. Web
  /// recordings are `audio/mp4` (AAC) or, from browsers without an AAC
  /// encoder (Firefox), `audio/wav`; both play on every device.
  final String mimeType;

  /// The file on Android/iOS; null on the web.
  final String? path;

  /// Reads the file's contents.
  final Future<Uint8List> Function() read;

  /// A file name for the upload, e.g. `1739….m4a` (web recordings get an
  /// extension from [mimeType], e.g. `….webm`).
  String get fileName {
    final name = src.split('/').last;
    if (name.contains('.')) return name;
    final type = mimeType.split(';').first;
    final extension = const {
      'audio/mp4': 'm4a',
      'audio/webm': 'webm',
      'audio/mpeg': 'mp3',
      'audio/wav': 'wav',
      'audio/ogg': 'ogg',
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
    }[type];
    return extension == null ? name : '$name.$extension';
  }
}

/// Uploads one file and returns its permanent `https://` URL.
typedef AminotesUploader = Future<String> Function(AminotesUpload upload);

/// Helpers for media referenced by notes (pure functions on Tiptap JSON).
abstract final class AminotesMedia {
  /// Where recordings and photos are kept until uploaded
  /// (`<app documents>/aminotes/`). Replace it at startup to use another
  /// folder: `AminotesMedia.store = MediaStore(rootDir: myDir)`.
  static MediaStore store = MediaStore();

  static MediaStore get _store => store;

  /// Every media `src` in [doc] (voice notes and images).
  static Set<String> sources(Map<String, dynamic> doc) {
    final found = <String>{};
    _walk(doc, (node) {
      final src = _mediaSrc(node);
      if (src != null) found.add(src);
    });
    return found;
  }

  /// Media in [doc] that only exists on this device and still needs uploading.
  static Future<List<AminotesUpload>> pendingUploads(Map<String, dynamic> doc) async {
    final uploads = <AminotesUpload>[];
    final seen = <String>{};
    final nodes = <Map<String, dynamic>>[];
    _walk(doc, nodes.add);
    for (final node in nodes) {
      final src = _mediaSrc(node);
      if (src == null || !_isPending(src) || !seen.add(src)) continue;
      final file = await _store.fileFor(src);
      uploads.add(
        AminotesUpload(
          src: src,
          kind: node['type'] as String,
          // A web recording's format depends on the browser: ask the blob.
          mimeType: file == null && src.startsWith('blob:')
              ? await readBlobType(src) ?? mimeTypeFor(node['type'] as String, src)
              : mimeTypeFor(node['type'] as String, src),
          path: file?.path,
          read: file != null ? file.readAsBytes : () => readBlobBytes(src),
        ),
      );
    }
    return uploads;
  }

  /// A copy of [doc] with media sources replaced, e.g. `local:…` → `https://…`.
  static Map<String, dynamic> replaceSources(Map<String, dynamic> doc, Map<String, String> replacements) =>
      _replace(doc, replacements) as Map<String, dynamic>;

  /// Recorded files that none of [notes] use any more (e.g. the voice note was
  /// deleted). Delete them only once those notes are saved everywhere, since
  /// undo or another device could still bring a voice note back.
  static Future<List<String>> unusedLocalFiles(Iterable<Map<String, dynamic>> notes) async {
    final used = {for (final note in notes) ...sources(note)};
    return [
      for (final src in await _store.allSources())
        if (!used.contains(src)) (await _store.fileFor(src))!.path,
    ];
  }

  /// Shows an image of a note with Flutter: the file on this device for a
  /// `local:` src, the network otherwise. Null when a local file is missing
  /// (or on the web, where `local:` files don't exist).
  static Future<ImageProvider?> imageProvider(String src) async {
    if (MediaStore.isLocal(src)) {
      final file = await _store.fileFor(src);
      return file != null && await file.exists() ? FileImage(file) : null;
    }
    return networkImage(src);
  }

  /// A remote image. On the web, a server without CORS headers can't serve
  /// Flutter directly: it then shows as a plain `<img>` (as in the editor).
  static ImageProvider networkImage(String src) =>
      NetworkImage(src, webHtmlElementStrategy: WebHtmlElementStrategy.fallback);

  /// The MIME type for a media file, from its node type and extension.
  static String mimeTypeFor(String kind, String src) {
    if (kind == 'voiceNote') return 'audio/mp4';
    final extension = src.split('?').first.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'application/octet-stream',
    };
  }

  static bool _isPending(String src) => MediaStore.isLocal(src) || src.startsWith('blob:');

  static String? _mediaSrc(Map<String, dynamic> node) {
    if (node['type'] != 'voiceNote' && node['type'] != 'image') return null;
    final src = (node['attrs'] as Map?)?['src'];
    return src is String && src.isNotEmpty ? src : null;
  }

  static void _walk(Object? node, void Function(Map<String, dynamic> node) visit) {
    if (node is! Map<String, dynamic>) return;
    visit(node);
    final content = node['content'];
    if (content is List) {
      for (final child in content) {
        _walk(child, visit);
      }
    }
  }

  static Object? _replace(Object? node, Map<String, String> replacements) {
    if (node is! Map<String, dynamic>) return node;
    final out = Map<String, dynamic>.of(node);
    final src = _mediaSrc(node);
    if (src != null && replacements.containsKey(src)) {
      out['attrs'] = {...node['attrs'] as Map<String, dynamic>, 'src': replacements[src]};
    }
    final content = node['content'];
    if (content is List) out['content'] = [for (final child in content) _replace(child, replacements)];
    return out;
  }
}
