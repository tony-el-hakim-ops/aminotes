import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../controller/aminotes_controller.dart';
import '../controller/aminotes_state.dart';
import '../media/image_picking.dart';
import 'aminotes_image_viewer.dart';
import 'aminotes_playback_bar.dart';
import 'aminotes_recording_bar.dart';
import 'aminotes_strings.dart';
import 'link_dialog.dart';
import 'touch_bar.dart';

/// Default colors offered by [AminotesToolbar].
abstract final class AminotesPalette {
  /// Text colors: readable on light and dark backgrounds.
  static const textColors = [
    Color(0xFFE53935), // red
    Color(0xFFFB8C00), // orange
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF8E24AA), // purple
    Color(0xFF757575), // grey
  ];

  /// Highlight colors: light, so the (dark) highlighted text stays readable.
  static const highlightColors = [
    Color(0xFFFFF59D), // yellow
    Color(0xFFC5E1A5), // green
    Color(0xFFB3E5FC), // blue
    Color(0xFFF8BBD0), // pink
    Color(0xFFFFCC80), // orange
    Color(0xFFE1BEE7), // purple
  ];
}

/// A button of [AminotesToolbar]. Lists of these choose which buttons show,
/// in order; mix in your own with [AminotesToolbarItem.custom].
@immutable
class AminotesToolbarItem {
  const AminotesToolbarItem._(this.name);

  /// Your own button, anywhere in the list: e.g. "Insert template".
  /// [isActive] highlights it, like Bold when the cursor is in bold text.
  const factory AminotesToolbarItem.custom({
    required Widget icon,
    required String tooltip,
    required void Function(AminotesController controller) onPressed,
    bool Function(AminotesState state)? isActive,
  }) = AminotesCustomToolbarItem;

  /// Identifies the built-in button (e.g. `bold`).
  final String name;

  @override
  String toString() => 'AminotesToolbarItem.$name';

  static const undo = AminotesToolbarItem._('undo');
  static const redo = AminotesToolbarItem._('redo');
  static const bold = AminotesToolbarItem._('bold');
  static const italic = AminotesToolbarItem._('italic');
  static const underline = AminotesToolbarItem._('underline');
  static const strikethrough = AminotesToolbarItem._('strikethrough');
  static const textColor = AminotesToolbarItem._('textColor');
  static const highlight = AminotesToolbarItem._('highlight');
  static const link = AminotesToolbarItem._('link');
  static const heading1 = AminotesToolbarItem._('heading1');
  static const heading2 = AminotesToolbarItem._('heading2');
  static const heading3 = AminotesToolbarItem._('heading3');
  static const bulletList = AminotesToolbarItem._('bulletList');
  static const numberedList = AminotesToolbarItem._('numberedList');
  static const checklist = AminotesToolbarItem._('checklist');
  static const indent = AminotesToolbarItem._('indent');
  static const outdent = AminotesToolbarItem._('outdent');
  static const quote = AminotesToolbarItem._('quote');
  static const inlineCode = AminotesToolbarItem._('inlineCode');
  static const codeBlock = AminotesToolbarItem._('codeBlock');
  static const divider = AminotesToolbarItem._('divider');

  /// Records a voice note; the toolbar shows the recording bar meanwhile.
  static const voiceNote = AminotesToolbarItem._('voiceNote');

  /// Adds a photo from the gallery or camera.
  static const image = AminotesToolbarItem._('image');

  /// Inserts a table. While the cursor is in a table, the toolbar also shows
  /// row/column buttons at its start.
  static const table = AminotesToolbarItem._('table');

  /// A thin vertical line between groups.
  static const separator = AminotesToolbarItem._('separator');

  /// For a small note box: the essentials, short enough to fit most phones.
  static const compact = [
    bold,
    italic,
    underline,
    textColor,
    highlight,
    separator,
    bulletList,
    checklist,
    numberedList,
    separator,
    voiceNote,
    image,
  ];

  /// For a full-screen editor: everything.
  static const full = [
    undo,
    redo,
    separator,
    bold,
    italic,
    underline,
    strikethrough,
    textColor,
    highlight,
    link,
    separator,
    heading1,
    heading2,
    heading3,
    separator,
    bulletList,
    numberedList,
    checklist,
    indent,
    outdent,
    separator,
    quote,
    inlineCode,
    codeBlock,
    divider,
    table,
    separator,
    voiceNote,
    image,
  ];
}

/// See [AminotesToolbarItem.custom].
class AminotesCustomToolbarItem extends AminotesToolbarItem {
  const AminotesCustomToolbarItem({required this.icon, required this.tooltip, required this.onPressed, this.isActive})
    : super._('custom');

  final Widget icon;
  final String tooltip;
  final void Function(AminotesController controller) onPressed;
  final bool Function(AminotesState state)? isActive;
}

/// A ready-made formatting toolbar for an [AminotesController]. Optional: build
/// your own on the controller instead if it doesn't fit your design.
///
/// One row that scrolls sideways when the buttons don't fit. Typically shown
/// above the keyboard while `controller.state.value.focused` is true. The color
/// buttons open a row of swatches above it, so the keyboard stays open.
/// Texts come from [AminotesStrings] (English or Arabic by locale).
///
/// Every button sits under [ExcludeFocus]: a toolbar tap must never take
/// Flutter focus, because the editor's WebView loses native focus (closing the
/// Android keyboard) as soon as the framework focus leaves it.
class AminotesToolbar extends StatefulWidget {
  const AminotesToolbar({
    super.key,
    required this.controller,
    this.items = AminotesToolbarItem.full,
    this.trailing,
    this.textColors = AminotesPalette.textColors,
    this.highlightColors = AminotesPalette.highlightColors,
    this.icons = const {},
  });

  final AminotesController controller;

  /// Which buttons, in order: [AminotesToolbarItem.compact],
  /// [AminotesToolbarItem.full] (default), or your own list.
  final List<AminotesToolbarItem> items;

  /// Pinned at the end (doesn't scroll), e.g. a "full screen" button.
  /// Defaults to "hide keyboard".
  final Widget? trailing;

  /// Swatches for text color and highlight.
  final List<Color> textColors;
  final List<Color> highlightColors;

  /// Replaces built-in icons, e.g. `{AminotesToolbarItem.bold: MyIcons.bold}`.
  final Map<AminotesToolbarItem, IconData> icons;

  @override
  State<AminotesToolbar> createState() => _AminotesToolbarState();
}

enum _Palette { text, highlight }

class _AminotesToolbarState extends State<AminotesToolbar> {
  _Palette? _open;

  AminotesController get _controller => widget.controller;

  void _togglePalette(_Palette palette) => setState(() => _open = _open == palette ? null : palette);

  Future<void> _pick(Color? color) async {
    final palette = _open;
    setState(() => _open = null);
    await (palette == _Palette.text ? _controller.setTextColor(color) : _controller.setHighlightColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AminotesStrings.of(context);
    return ValueListenableBuilder(
      valueListenable: _controller.recording,
      builder: (context, recording, _) => recording != null
          ? AminotesRecordingBar(controller: _controller)
          : ValueListenableBuilder(
              valueListenable: _controller.playback,
              builder: (context, playback, _) =>
                  playback != null ? AminotesPlaybackBar(controller: _controller) : _buildToolbar(context, strings),
            ),
    );
  }

  Widget _buildToolbar(BuildContext context, AminotesStrings strings) {
    return ValueListenableBuilder<AminotesState>(
      valueListenable: _controller.state,
      builder: (context, state, _) {
        // A note that failed to load is read-only.
        final enabled = state.ready && !state.loadFailed;
        final open = enabled ? _open : null;
        final selected = enabled ? state.selectedNode : null;
        final inTable = enabled && state.isActive('table') && widget.items.contains(AminotesToolbarItem.table);
        // PointerInterceptor: on the web, the editor's iframe would otherwise
        // take clicks on a toolbar (or swatches) drawn over it.
        return PointerInterceptor(
          child: ExcludeFocus(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (open != null)
                  _SwatchRow(
                    colors: open == _Palette.text ? widget.textColors : widget.highlightColors,
                    selected: open == _Palette.text ? state.textColor : state.highlightColor,
                    noneLabel: open == _Palette.text ? strings.defaultTextColor : strings.noHighlight,
                    colorNames: strings.colorNames,
                    onPick: _pick,
                  ),
                TouchBar(
                  // Entering or leaving a table, or selecting an image, changes
                  // the first buttons: start the bar from the beginning so
                  // they're seen.
                  key: ValueKey((inTable, selected?.kind)),
                  trailing:
                      widget.trailing ??
                      _ToolButton(
                        tooltip: strings.hideKeyboard,
                        icon: Icons.keyboard_hide,
                        onPressed: _controller.unfocus,
                      ),
                  children: [
                    if (selected != null) ...[..._selectedNodeButtons(context, selected, strings), const _Separator()],
                    if (inTable) ...[..._tableButtons(strings), const _Separator()],
                    for (final item in widget.items) _button(context, item, state, enabled, strings),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _button(
    BuildContext context,
    AminotesToolbarItem item,
    AminotesState state,
    bool enabled,
    AminotesStrings strings,
  ) {
    VoidCallback? when(bool condition, VoidCallback action) => enabled && condition ? action : null;
    Widget toggle(String tooltip, IconData icon, String active, Future<void> Function() run) =>
        _ToolButton(tooltip: tooltip, icon: icon, active: state.isActive(active), onPressed: when(true, run));
    final override = widget.icons[item];
    Widget heading(int level) => _ToolButton(
      tooltip: strings.headingLevel(level),
      icon: override,
      label: 'H$level',
      active: state.isActive('heading$level'),
      onPressed: when(true, () => _controller.toggleHeading(level)),
    );

    return switch (item) {
      AminotesToolbarItem.undo => _ToolButton(
        tooltip: strings.undo,
        icon: override ?? Icons.undo,
        onPressed: when(state.canUndo, _controller.undo),
      ),
      AminotesToolbarItem.redo => _ToolButton(
        tooltip: strings.redo,
        icon: override ?? Icons.redo,
        onPressed: when(state.canRedo, _controller.redo),
      ),
      AminotesToolbarItem.bold => toggle(strings.bold, override ?? Icons.format_bold, 'bold', _controller.toggleBold),
      AminotesToolbarItem.italic => toggle(
        strings.italic,
        override ?? Icons.format_italic,
        'italic',
        _controller.toggleItalic,
      ),
      AminotesToolbarItem.underline => toggle(
        strings.underline,
        override ?? Icons.format_underline,
        'underline',
        _controller.toggleUnderline,
      ),
      AminotesToolbarItem.strikethrough => toggle(
        strings.strikethrough,
        override ?? Icons.format_strikethrough,
        'strike',
        _controller.toggleStrike,
      ),
      AminotesToolbarItem.textColor => _ColorButton(
        tooltip: strings.textColor,
        icon: override ?? Icons.format_color_text,
        color: state.textColor,
        open: _open == _Palette.text,
        onPressed: when(widget.textColors.isNotEmpty, () => _togglePalette(_Palette.text)),
      ),
      AminotesToolbarItem.highlight => _ColorButton(
        tooltip: strings.highlight,
        icon: override ?? Icons.border_color_outlined,
        color: state.highlightColor,
        open: _open == _Palette.highlight,
        onPressed: when(widget.highlightColors.isNotEmpty, () => _togglePalette(_Palette.highlight)),
      ),
      AminotesToolbarItem.link => _ToolButton(
        tooltip: strings.link,
        icon: override ?? Icons.link,
        active: state.isActive('link'),
        onPressed: when(true, () => _editLink(context, state, strings)),
      ),
      AminotesToolbarItem.heading1 => heading(1),
      AminotesToolbarItem.heading2 => heading(2),
      AminotesToolbarItem.heading3 => heading(3),
      AminotesToolbarItem.bulletList => toggle(
        strings.bulletList,
        override ?? Icons.format_list_bulleted,
        'bulletList',
        _controller.toggleBulletList,
      ),
      AminotesToolbarItem.numberedList => toggle(
        strings.numberedList,
        override ?? Icons.format_list_numbered,
        'orderedList',
        _controller.toggleNumberedList,
      ),
      AminotesToolbarItem.checklist => toggle(
        strings.checklist,
        override ?? Icons.checklist,
        'taskList',
        _controller.toggleChecklist,
      ),
      AminotesToolbarItem.indent => _ToolButton(
        tooltip: strings.indent,
        icon: override ?? Icons.format_indent_increase,
        onPressed: when(state.canIndent, _controller.indent),
      ),
      AminotesToolbarItem.outdent => _ToolButton(
        tooltip: strings.outdent,
        icon: override ?? Icons.format_indent_decrease,
        onPressed: when(state.canOutdent, _controller.outdent),
      ),
      AminotesToolbarItem.quote => toggle(
        strings.quote,
        override ?? Icons.format_quote,
        'blockquote',
        _controller.toggleQuote,
      ),
      AminotesToolbarItem.inlineCode => toggle(
        strings.inlineCode,
        override ?? Icons.code,
        'code',
        _controller.toggleCode,
      ),
      AminotesToolbarItem.codeBlock => toggle(
        strings.codeBlock,
        override ?? Icons.data_object,
        'codeBlock',
        _controller.toggleCodeBlock,
      ),
      AminotesToolbarItem.divider => _ToolButton(
        tooltip: strings.divider,
        icon: override ?? Icons.horizontal_rule,
        onPressed: when(true, _controller.insertDivider),
      ),
      AminotesToolbarItem.voiceNote => _ToolButton(
        tooltip: strings.recordVoiceNote,
        icon: override ?? Icons.mic_none,
        onPressed: when(true, () => _recordVoiceNote(context, strings)),
      ),
      AminotesToolbarItem.image => _ToolButton(
        tooltip: strings.image,
        icon: override ?? Icons.image_outlined,
        onPressed: when(true, () => _addImage(context, strings)),
      ),
      AminotesToolbarItem.table => _ToolButton(
        tooltip: strings.insertTable,
        icon: override ?? Icons.table_chart_outlined,
        // No tables inside tables.
        onPressed: when(!state.isActive('table'), _controller.insertTable),
      ),
      AminotesToolbarItem.separator => const _Separator(),
      AminotesCustomToolbarItem(:final icon, :final tooltip, :final onPressed, :final isActive) => _ToolButton(
        tooltip: tooltip,
        iconWidget: icon,
        active: isActive?.call(state) ?? false,
        onPressed: when(true, () => onPressed(_controller)),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  // Shown first while an image or voice note is selected (tapped).
  List<Widget> _selectedNodeButtons(BuildContext context, AminotesSelectedNode node, AminotesStrings strings) => [
    if (node.kind == AminotesNodeKind.image && node.src != null)
      _ToolButton(
        tooltip: strings.viewImage,
        icon: Icons.fullscreen,
        onPressed: () {
          // Captured first: closing the keyboard can hide this toolbar.
          final navigator = Navigator.of(context);
          unawaited(_controller.unfocus());
          AminotesImageViewer.show(
            navigator.context,
            src: node.src!,
            alt: node.alt,
            onDelete: _controller.deleteSelection,
          );
        },
      ),
    if (node.kind == AminotesNodeKind.image)
      for (final (alignment, tooltip, icon) in [
        (AminotesImageAlignment.left, strings.alignImageLeft, Icons.align_horizontal_left),
        (AminotesImageAlignment.center, strings.alignImageCenter, Icons.align_horizontal_center),
        (AminotesImageAlignment.right, strings.alignImageRight, Icons.align_horizontal_right),
      ])
        _ToolButton(
          tooltip: tooltip,
          icon: icon,
          active: node.align == alignment,
          // Tapping the active one goes back to following the text direction.
          onPressed: () => _controller.setImageAlignment(node.align == alignment ? null : alignment),
        ),
    _ToolButton(
      tooltip: node.kind == AminotesNodeKind.image ? strings.deleteImage : strings.deleteVoiceNote,
      icon: Icons.delete_outline,
      onPressed: _controller.deleteSelection,
    ),
  ];

  // Shown first while the cursor is in a table.
  List<Widget> _tableButtons(AminotesStrings strings) => [
    _ToolButton(tooltip: strings.addRowBelow, icon: Icons.table_rows_outlined, onPressed: _controller.addRowAfter),
    _ToolButton(
      tooltip: strings.addColumnAfter,
      icon: Icons.view_column_outlined,
      onPressed: _controller.addColumnAfter,
    ),
    _ToolButton(tooltip: strings.deleteRow, icon: Icons.playlist_remove, onPressed: _controller.deleteRow),
    _ToolButton(tooltip: strings.deleteColumn, icon: Icons.backspace_outlined, onPressed: _controller.deleteColumn),
    _ToolButton(tooltip: strings.headerRow, icon: Icons.title, onPressed: _controller.toggleHeaderRow),
    _ToolButton(tooltip: strings.deleteTable, icon: Icons.grid_off, onPressed: _controller.deleteTable),
  ];

  Future<void> _recordVoiceNote(BuildContext context, AminotesStrings strings) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = switch (await _controller.startVoiceNote()) {
      AminotesRecordResult.started => null,
      AminotesRecordResult.permissionDenied => strings.microphoneDenied,
      AminotesRecordResult.failed => strings.recordingFailed,
    };
    if (message != null) messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addImage(BuildContext context, AminotesStrings strings) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Captured first: closing the keyboard usually hides this toolbar
    // (toolbarVisible), which unmounts it.
    final navigator = Navigator.of(context);
    // The sheet would open behind the keyboard: close it first. The cursor
    // position is kept, and the image goes there.
    unawaited(_controller.unfocus());
    final source = await showModalBottomSheet<AminotesImageSource>(
      context: navigator.context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(strings.imageFromGallery),
              onTap: () => Navigator.pop(context, AminotesImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(strings.imageFromCamera),
              onTap: () => Navigator.pop(context, AminotesImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      await _controller.pickImage(source);
    } catch (error) {
      debugPrint('aminotes: image: $error');
      messenger?.showSnackBar(SnackBar(content: Text(strings.imageFailed)));
    }
  }

  Future<void> _editLink(BuildContext context, AminotesState state, AminotesStrings strings) async {
    final hasLink = state.isActive('link');
    final url = await showUrlDialog(
      context,
      title: hasLink ? strings.editLink : strings.addLink,
      initialUrl: state.linkHref ?? '',
      removable: hasLink,
    );
    // The dialog took focus; put the cursor back where it was.
    if (url == null) return _controller.focus();
    await (url.isEmpty ? _controller.removeLink() : _controller.setLink(url));
  }
}

/// A row of color swatches plus "none".
class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.colors,
    required this.selected,
    required this.noneLabel,
    required this.colorNames,
    required this.onPick,
  });

  final List<Color> colors;
  final Color? selected;
  final String noneLabel;
  final Map<String, String> colorNames;
  final ValueChanged<Color?> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch(Color? color) {
      final isSelected = color == null ? selected == null : selected?.toARGB32() == color.toARGB32();
      final label = color == null ? noneLabel : colorNames[cssHex(color)] ?? cssHex(color);
      return Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: isSelected,
          label: label,
          child: InkResponse(
            onTap: () => onPick(color),
            radius: 22,
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: color ?? scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? scheme.primary : scheme.outlineVariant,
                  width: isSelected ? 3 : 1,
                ),
              ),
              child: color == null ? Icon(Icons.format_color_reset, size: 16, color: scheme.onSurfaceVariant) : null,
            ),
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          children: [swatch(null), for (final color in colors) swatch(color)],
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.open,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color? color;
  final bool open;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: open,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: open ? scheme.secondaryContainer : null,
        foregroundColor: open ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
      ),
      // The current color shows as a bar under the icon.
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          Container(
            width: 18,
            height: 4,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: color ?? Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: color == null ? Border.all(color: scheme.outlineVariant) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    this.icon,
    this.iconWidget,
    this.label,
    this.active = false,
    required this.onPressed,
  });

  final String tooltip;
  final IconData? icon;
  final Widget? iconWidget;
  final String? label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: active,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: active ? colors.secondaryContainer : null,
        foregroundColor: active ? colors.onSecondaryContainer : colors.onSurfaceVariant,
      ),
      icon:
          iconWidget ??
          (icon != null ? Icon(icon) : Text(label!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => const VerticalDivider(width: 12, indent: 14, endIndent: 14);
}
