import 'package:flutter/material.dart';

import '../controller/aminotes_state.dart' show parseCssColor;
import '../editor/aminotes_theme.dart';
import '../media/aminotes_media.dart';
import '../media/voice_notes.dart';
import '../ui/aminotes_strings.dart';

/// Shows a note (Tiptap JSON) with plain Flutter widgets: no WebView, so it's
/// cheap enough for a list of many notes. Read-only; open an
/// `AminotesEditor` to edit.
///
/// It draws the same content as the editor: headings, text styles, colors,
/// links, lists, checklists, quotes, code, dividers, images, tables, voice
/// notes, and a placeholder for content this package doesn't know.
///
/// Taps go through to your own widget (wrap it in an `InkWell` to open the
/// note). To show only the start of a long note, set [maxBlocks] and/or put it
/// in a fixed-height, clipped box.
class AminotesPreview extends StatelessWidget {
  const AminotesPreview({super.key, required this.json, this.theme, this.maxBlocks, this.imageHeight = 160});

  /// The note, as saved: `{"type": "doc", "content": [...]}`.
  final Map<String, dynamic> json;

  /// Same as the editor's; unset values come from the app's [Theme].
  final AminotesTheme? theme;

  /// Shows at most this many top-level blocks (paragraphs, lists, …).
  final int? maxBlocks;

  /// Height of image thumbnails.
  final double imageHeight;

  /// The note's text without formatting, e.g. for a one-line summary or search.
  /// Voice notes and images are left out; blocks are separated by newlines.
  static String plainText(Map<String, dynamic> json) {
    final out = StringBuffer();
    void walk(Object? node) {
      if (node is! Map) return;
      final type = node['type'];
      if (type == 'text') out.write(node['text'] ?? '');
      if (type == 'hardBreak') out.write('\n');
      final content = node['content'];
      if (content is List) {
        for (final child in content) {
          walk(child);
        }
      }
      if (_blockTypes.contains(type) && out.isNotEmpty && !out.toString().endsWith('\n')) out.write('\n');
    }

    walk(json);
    return out.toString().trim();
  }

  static const _blockTypes = {'paragraph', 'heading', 'codeBlock', 'tableCell', 'tableHeader'};

  @override
  Widget build(BuildContext context) {
    final resolved = (theme ?? const AminotesTheme()).resolve(Theme.of(context), Directionality.of(context));
    final blocks = (json['content'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final shown = maxBlocks == null ? blocks : blocks.take(maxBlocks!).toList();
    final painter = _Painter(resolved, AminotesStrings.of(context), imageHeight);
    return ColoredBox(
      color: resolved.backgroundColor ?? Colors.transparent,
      child: Padding(
        padding: resolved.padding ?? EdgeInsets.zero,
        child: DefaultTextStyle.merge(
          style: painter.base,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: painter.blocks(shown),
          ),
        ),
      ),
    );
  }
}

/// Turns Tiptap nodes into widgets with one resolved theme.
class _Painter {
  _Painter(this.theme, this.strings, this.imageHeight)
    : base = TextStyle(
        color: theme.textColor,
        fontSize: theme.fontSize,
        height: theme.lineHeight,
        fontFamily: theme.fontFamily,
      );

  final AminotesTheme theme;
  final AminotesStrings strings;
  final double imageHeight;
  final TextStyle base;

  double get _fontSize => theme.fontSize ?? 16;
  double get _gap => _fontSize * 0.6;

  // Same spacing as the editor's CSS: paragraphs follow each other with no gap,
  // headings get more room above, other blocks a little.
  List<Widget> blocks(List<Map<String, dynamic>> nodes) => [
    for (var i = 0; i < nodes.length; i++)
      Padding(
        padding: EdgeInsets.only(
          top: i == 0
              ? 0
              : switch (nodes[i]['type']) {
                  'paragraph' => 0,
                  'heading' => _fontSize,
                  _ => _gap,
                },
        ),
        child: block(nodes[i]),
      ),
  ];

  Widget block(Map<String, dynamic> node) {
    final attrs = (node['attrs'] as Map?) ?? const {};
    switch (node['type']) {
      case 'paragraph':
        return _text(node, base);
      case 'heading':
        final level = (attrs['level'] as num?)?.toInt() ?? 1;
        final scale = const [1.7, 1.4, 1.2, 1.1, 1.0, 0.9][(level - 1).clamp(0, 5)];
        return _text(node, base.copyWith(fontSize: _fontSize * scale, fontWeight: FontWeight.w700, height: 1.25));
      case 'bulletList':
        return _list(node, (i) => '•');
      case 'orderedList':
        final start = (attrs['start'] as num?)?.toInt() ?? 1;
        return _list(node, (i) => '${start + i}.');
      case 'taskList':
        return _list(node, null);
      case 'blockquote':
        return Container(
          padding: const EdgeInsetsDirectional.only(start: 12),
          decoration: BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: theme.accentColor!, width: 4)),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: theme.mutedTextColor),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks(_children(node))),
          ),
        );
      case 'codeBlock':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: theme.codeBackgroundColor, borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              AminotesPreview.plainText(node),
              textDirection: TextDirection.ltr,
              style: base.copyWith(fontFamily: 'monospace', fontSize: _fontSize * 0.85),
            ),
          ),
        );
      case 'horizontalRule':
        return Divider(height: 2, thickness: 2, color: theme.borderColor);
      case 'image':
        return _image(
          attrs['src'] as String?,
          width: attrs['width'] as num?,
          height: attrs['height'] as num?,
          align: attrs['align'] as String?,
        );
      case 'table':
        return _table(node);
      default:
        return _unsupported(node);
    }
  }

  List<Map<String, dynamic>> _children(Map<String, dynamic> node) =>
      (node['content'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];

  // A paragraph-like node: its inline content, in its own text direction.
  Widget _text(Map<String, dynamic> node, TextStyle style) {
    final inline = _children(node);
    final plain = AminotesPreview.plainText(node);
    return Text.rich(
      TextSpan(style: style, children: [for (final child in inline) _inline(child)]),
      textDirection: _directionOf(plain),
    );
  }

  InlineSpan _inline(Map<String, dynamic> node) {
    switch (node['type']) {
      case 'text':
        return TextSpan(text: node['text'] as String? ?? '', style: _marks(node['marks']));
      case 'hardBreak':
        return const TextSpan(text: '\n');
      case 'voiceNote':
        final duration = ((node['attrs'] as Map?)?['duration'] as num?)?.round() ?? 0;
        return WidgetSpan(alignment: PlaceholderAlignment.middle, child: _voicePill(duration));
      default:
        final type = node['type'];
        return TextSpan(
          text: '[$type]',
          style: TextStyle(color: theme.mutedTextColor, fontSize: _fontSize * 0.85),
        );
    }
  }

  TextStyle _marks(Object? marks) {
    var style = const TextStyle();
    final decorations = <TextDecoration>[];
    if (marks is! List) return style;
    for (final mark in marks.whereType<Map>()) {
      final attrs = (mark['attrs'] as Map?) ?? const {};
      switch (mark['type']) {
        case 'bold':
          style = style.copyWith(fontWeight: FontWeight.w700);
        case 'italic':
          style = style.copyWith(fontStyle: FontStyle.italic);
        case 'underline':
          decorations.add(TextDecoration.underline);
        case 'strike':
          decorations.add(TextDecoration.lineThrough);
        case 'code':
          style = style.copyWith(
            fontFamily: 'monospace',
            fontSize: _fontSize * 0.9,
            backgroundColor: theme.codeBackgroundColor,
          );
        case 'link':
          style = style.copyWith(color: theme.accentColor);
          decorations.add(TextDecoration.underline);
        case 'textStyle':
          final color = parseCssColor(attrs['color']);
          if (color != null) style = style.copyWith(color: color);
        case 'highlight':
          final color = parseCssColor(attrs['color']) ?? const Color(0xFFFFF59D);
          // Highlight colors are light: keep the text dark on them.
          style = style.copyWith(backgroundColor: color, color: style.color ?? const Color(0xFF1B1B21));
      }
    }
    if (decorations.isNotEmpty) style = style.copyWith(decoration: TextDecoration.combine(decorations));
    return style;
  }

  // bullet/ordered: [marker] gives each item's marker; task lists: null.
  Widget _list(Map<String, dynamic> node, String Function(int index)? marker) {
    final items = _children(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _gap / 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _fontSize * 1.6,
                  child: marker != null
                      ? Text(marker(i), style: base.copyWith(color: theme.mutedTextColor))
                      : _checkbox(((items[i]['attrs'] as Map?)?['checked']) == true),
                ),
                Expanded(
                  child: _listItem(
                    items[i],
                    checked: marker == null && (items[i]['attrs'] as Map?)?['checked'] == true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _listItem(Map<String, dynamic> item, {required bool checked}) {
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks(_children(item)));
    if (!checked) return content;
    // Done tasks: muted and crossed out, like the editor.
    return DefaultTextStyle.merge(
      style: TextStyle(color: theme.mutedTextColor, decoration: TextDecoration.lineThrough),
      child: content,
    );
  }

  // Not a Checkbox: a preview must not swallow taps meant for the host app.
  Widget _checkbox(bool checked) => Padding(
    padding: EdgeInsets.only(top: _fontSize * 0.15),
    child: Icon(
      checked ? Icons.check_box : Icons.check_box_outline_blank,
      size: _fontSize * 1.25,
      color: checked ? theme.accentColor : theme.mutedTextColor,
    ),
  );

  Widget _voicePill(int seconds) {
    final label = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label: '${strings.voiceNote}, $label',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsetsDirectional.fromSTEB(6, 1, 9, 1),
        decoration: BoxDecoration(color: theme.accentContainerColor, borderRadius: BorderRadius.circular(999)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, size: _fontSize * 1.1, color: theme.onAccentContainerColor),
              Icon(Icons.graphic_eq, size: _fontSize, color: theme.onAccentContainerColor),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(fontSize: _fontSize * 0.85, color: theme.onAccentContainerColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [width]/[height]: the size the user resized the image to in the editor
  /// (null: full width).
  Widget _image(String? src, {num? width, num? height, String? align}) {
    Widget placeholder() => Container(
      height: imageHeight,
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderColor!),
      ),
      child: Icon(Icons.image_outlined, color: theme.mutedTextColor),
    );
    if (src == null || src.isEmpty) return placeholder();

    Widget framed(ImageProvider provider) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image(
        image: provider,
        height: imageHeight,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, _, _) => placeholder(),
        frameBuilder: (context, child, frame, sync) => frame == null && !sync ? placeholder() : child,
      ),
    );

    final Widget image = !MediaStore.isLocal(src)
        ? framed(AminotesMedia.networkImage(src))
        : FutureBuilder<ImageProvider?>(
            future: AminotesMedia.imageProvider(src),
            builder: (context, snapshot) {
              final provider = snapshot.data;
              return provider == null ? placeholder() : framed(provider);
            },
          );
    if (width == null || height == null || width <= 0 || height <= 0) return image;
    // Resized in the editor: that size (at most the available width, and the
    // preview's image height), with the picture's proportions.
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = width / height;
        var w = width.toDouble().clamp(0.0, constraints.maxWidth);
        var h = w / ratio;
        if (h > imageHeight) {
          h = imageHeight;
          w = h * ratio;
        }
        return Align(
          alignment: switch (align) {
            'left' => Alignment.centerLeft,
            'center' => Alignment.center,
            'right' => Alignment.centerRight,
            _ => AlignmentDirectional.centerStart,
          },
          child: SizedBox(width: w, height: h, child: image),
        );
      },
    );
  }

  Widget _table(Map<String, dynamic> node) {
    final rows = _children(node);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: theme.borderColor!),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (final cell in _children(row))
                  Container(
                    constraints: const BoxConstraints(minWidth: 90),
                    color: cell['type'] == 'tableHeader' ? theme.surfaceColor : null,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(fontWeight: cell['type'] == 'tableHeader' ? FontWeight.w600 : null),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: blocks(_children(cell)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _unsupported(Map<String, dynamic> node) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.borderColor!),
    ),
    child: Text(
      strings.unsupportedBlock.replaceAll('{type}', '${node['type']}'),
      style: TextStyle(color: theme.mutedTextColor, fontSize: _fontSize * 0.85),
    ),
  );
}

/// Arabic/Hebrew text reads right to left; the first strong letter decides.
TextDirection? _directionOf(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x08FF) || (rune >= 0xFB1D && rune <= 0xFEFC)) return TextDirection.rtl;
    if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A) || (rune >= 0xC0 && rune <= 0x24F)) {
      return TextDirection.ltr;
    }
  }
  return null; // no letters: follow the app
}
