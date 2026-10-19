import 'package:flutter/foundation.dart';

/// A note to load into the editor.
///
/// Notes are saved as Tiptap JSON (the web app's format). Older notes stored as
/// HTML or plain text are converted by Tiptap itself when loaded; read them
/// back with [AminotesController.getJson] and save that from then on.
@immutable
sealed class AminotesContent {
  const AminotesContent();

  /// Tiptap JSON: `{"type": "doc", "content": [...]}`.
  const factory AminotesContent.json(Map<String, dynamic> doc) = AminotesJsonContent;

  /// HTML, e.g. from an older editor.
  const factory AminotesContent.html(String html) = AminotesHtmlContent;

  /// Plain text: each line becomes a paragraph.
  const factory AminotesContent.text(String text) = AminotesTextContent;

  /// An empty note.
  static const empty = AminotesContent.json({
    'type': 'doc',
    'content': [
      {'type': 'paragraph'},
    ],
  });
}

/// A note saved as Tiptap JSON (what `onChanged` and `getJson` give you).
class AminotesJsonContent extends AminotesContent {
  const AminotesJsonContent(this.doc);

  /// The Tiptap document: `{"type": "doc", "content": [...]}`.
  final Map<String, dynamic> doc;
}

/// A note saved as HTML (e.g. from an older app version); converted when loaded.
class AminotesHtmlContent extends AminotesContent {
  const AminotesHtmlContent(this.html);

  /// The HTML; only what the schema knows is kept.
  final String html;
}

/// A note saved as plain text; each line becomes a paragraph.
class AminotesTextContent extends AminotesContent {
  const AminotesTextContent(this.text);

  /// The text, lines separated by `\n`.
  final String text;
}
