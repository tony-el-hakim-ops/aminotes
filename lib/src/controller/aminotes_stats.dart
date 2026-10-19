import 'package:flutter/foundation.dart';

/// Word and character counts of a note.
///
/// Live for the open note in `controller.state.value.stats`; for any saved
/// note with [AminotesStats.of]. Both count the same way: blocks, line breaks,
/// voice notes and images separate words; formatting doesn't.
@immutable
class AminotesStats {
  const AminotesStats({this.words = 0, this.characters = 0});

  factory AminotesStats.fromJson(Object? json) => json is Map
      ? AminotesStats(
          words: (json['words'] as num?)?.toInt() ?? 0,
          characters: (json['characters'] as num?)?.toInt() ?? 0,
        )
      : const AminotesStats();

  /// Counts a note's Tiptap JSON without an editor.
  factory AminotesStats.of(Map<String, dynamic> doc) {
    final text = StringBuffer();
    var characters = 0;
    void visit(Object? node) {
      if (node is! Map) return;
      final content = node['content'];
      if (node['type'] == 'text') {
        final value = '${node['text'] ?? ''}';
        text.write(value);
        characters += value.runes.length;
      } else {
        // Blocks and inline nodes without text (breaks, voice notes, images).
        text.write(' ');
      }
      if (content is List) content.forEach(visit);
    }

    final content = doc['content'];
    if (content is List) content.forEach(visit);
    final words = text.toString().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    return AminotesStats(words: words, characters: characters);
  }

  /// Words, split on spaces and line breaks (Arabic and English alike).
  final int words;

  /// Letters, digits, spaces and punctuation typed in the note (not counting
  /// line breaks between paragraphs).
  final int characters;

  @override
  bool operator ==(Object other) => other is AminotesStats && other.words == words && other.characters == characters;

  @override
  int get hashCode => Object.hash(words, characters);

  @override
  String toString() => 'AminotesStats($words words, $characters characters)';
}
