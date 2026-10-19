import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'aminotes_stats.dart';

/// What the editor reports about itself, for building toolbars and buttons.
/// Read it from [AminotesController.state].
@immutable
class AminotesState {
  const AminotesState({
    this.ready = false,
    this.loadFailed = false,
    this.focused = false,
    this.canUndo = false,
    this.canRedo = false,
    this.canIndent = false,
    this.canOutdent = false,
    this.active = const {},
    this.linkHref,
    this.textColor,
    this.highlightColor,
    this.selectedNode,
    this.stats = const AminotesStats(),
  });

  factory AminotesState.fromJson(Map<String, dynamic> json, {bool ready = true}) {
    final active = json['active'];
    return AminotesState(
      ready: ready,
      loadFailed: json['loadFailed'] == true,
      focused: json['focused'] == true,
      canUndo: json['canUndo'] == true,
      canRedo: json['canRedo'] == true,
      canIndent: json['canSink'] == true,
      canOutdent: json['canLift'] == true,
      active: {
        if (active is Map)
          for (final entry in active.entries)
            if (entry.value == true) entry.key as String,
      },
      linkHref: json['linkHref'] as String?,
      textColor: parseCssColor(json['textColor']),
      highlightColor: parseCssColor(json['highlightColor']),
      selectedNode: AminotesSelectedNode.fromJson(json['selectedNode']),
      stats: AminotesStats.fromJson(json['stats']),
    );
  }

  /// The editor page has loaded and shows the note.
  final bool ready;

  /// The note's content doesn't fit this package's schema (e.g. written by a
  /// newer web app in a way that can't be shown safely). The note is
  /// read-only, `onChanged` never fires, and `getJson` returns it untouched.
  final bool loadFailed;

  /// The cursor is in the editor (on phones: the keyboard is up for it).
  final bool focused;

  /// There's an edit to undo.
  final bool canUndo;

  /// There's an undone edit to redo.
  final bool canRedo;

  /// A list item at the cursor can be nested deeper / moved up a level.
  final bool canIndent;
  final bool canOutdent;

  /// Formatting active at the cursor: `bold`, `italic`, `underline`, `strike`,
  /// `code`, `link`, `heading1`…`heading3`, `paragraph`, `bulletList`,
  /// `orderedList`, `taskList`, `blockquote`, `codeBlock`, `table`.
  final Set<String> active;

  /// The link URL at the cursor, if any.
  final String? linkHref;

  /// Text color at the cursor; null for the default color.
  final Color? textColor;

  /// Highlight (background) color at the cursor; null for none.
  final Color? highlightColor;

  /// The image or voice note the user tapped (selected as a whole), or null.
  /// The toolbar offers View and Delete for it.
  final AminotesSelectedNode? selectedNode;

  /// Live word and character counts.
  final AminotesStats stats;

  /// Whether [name] (see [active]) applies at the cursor.
  bool isActive(String name) => active.contains(name);

  /// The heading level at the cursor (1–3), or null for normal text.
  int? get headingLevel => [1, 2, 3].where((level) => isActive('heading$level')).firstOrNull;

  AminotesState copyWith({bool? ready}) => AminotesState(
    ready: ready ?? this.ready,
    loadFailed: loadFailed,
    focused: focused,
    canUndo: canUndo,
    canRedo: canRedo,
    canIndent: canIndent,
    canOutdent: canOutdent,
    active: active,
    linkHref: linkHref,
    textColor: textColor,
    highlightColor: highlightColor,
    selectedNode: selectedNode,
    stats: stats,
  );

  @override
  bool operator ==(Object other) =>
      other is AminotesState &&
      other.ready == ready &&
      other.loadFailed == loadFailed &&
      other.focused == focused &&
      other.canUndo == canUndo &&
      other.canRedo == canRedo &&
      other.canIndent == canIndent &&
      other.canOutdent == canOutdent &&
      setEquals(other.active, active) &&
      other.linkHref == linkHref &&
      other.textColor == textColor &&
      other.highlightColor == highlightColor &&
      other.selectedNode == selectedNode &&
      other.stats == stats;

  @override
  int get hashCode => Object.hash(
    ready,
    loadFailed,
    focused,
    canUndo,
    canRedo,
    canIndent,
    canOutdent,
    Object.hashAllUnordered(active),
    linkHref,
    textColor,
    highlightColor,
    selectedNode,
    stats,
  );
}

/// Where an image sits on its line: see [AminotesSelectedNode.align] and
/// `AminotesController.setImageAlignment`. Left and right are physical (the
/// same in Arabic notes); no alignment follows the text direction.
enum AminotesImageAlignment {
  /// Against the left edge.
  left,

  /// Centered.
  center,

  /// Against the right edge.
  right,
}

/// What [AminotesSelectedNode.kind] can be.
enum AminotesNodeKind {
  /// An image.
  image,

  /// A voice note.
  voiceNote,
}

/// An image or voice note selected in the editor: see
/// [AminotesState.selectedNode].
@immutable
class AminotesSelectedNode {
  const AminotesSelectedNode({required this.kind, this.src, this.alt, this.align, this.duration = Duration.zero});

  static AminotesSelectedNode? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = switch (json['type']) {
      'image' => AminotesNodeKind.image,
      'voiceNote' => AminotesNodeKind.voiceNote,
      _ => null,
    };
    if (kind == null) return null;
    return AminotesSelectedNode(
      kind: kind,
      src: json['src'] as String?,
      alt: json['alt'] as String?,
      align: AminotesImageAlignment.values.asNameMap()[json['align']],
      duration: Duration(seconds: (json['duration'] as num?)?.round() ?? 0),
    );
  }

  /// Image or voice note.
  final AminotesNodeKind kind;

  /// `local:…`, `https://…` or (web) `blob:…`.
  final String? src;

  /// Images: the description, if any.
  final String? alt;

  /// Images: where it sits on its line; null follows the text direction.
  final AminotesImageAlignment? align;

  /// Voice notes: the length.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is AminotesSelectedNode &&
      other.kind == kind &&
      other.src == src &&
      other.alt == alt &&
      other.align == align &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(kind, src, alt, align, duration);
}

/// Parses `#rgb`, `#rrggbb` or `#rrggbbaa` (what the color commands store);
/// anything else (e.g. named colors from other editors) gives null.
Color? parseCssColor(Object? value) {
  if (value is! String) return null;
  final hex = value.trim().toLowerCase();
  if (!RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$').hasMatch(hex)) return null;
  var digits = hex.substring(1);
  if (digits.length == 3) digits = digits.split('').map((c) => '$c$c').join();
  if (digits.length == 6) digits = '${digits}ff';
  final rgba = int.parse(digits, radix: 16);
  return Color((rgba & 0xff) << 24 | rgba >> 8);
}

/// `#rrggbb` for a color (alpha ignored), as stored in the note's JSON.
String cssHex(Color color) {
  String channel(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}';
}
