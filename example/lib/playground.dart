import 'package:aminotes/aminotes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design a note: pick a style, the text settings and the toolbar buttons,
/// see the result live, then copy the code for your app.
class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

/// A complete design for the playground: the box (a plain Flutter widget, anything goes) and the
/// note's text (AminotesTheme).
@immutable
class PlaygroundDesign {
  const PlaygroundDesign({
    required this.name,
    required this.boxColor,
    this.radius = 12,
    this.border = false,
    this.shadow = false,
    this.tilt = 0,
    this.handwriting = false,
    this.fontSize = 16,
    this.lineHeight = 1.5,
    this.padding = 16,
    this.textColor,
    required this.accentColor,
    this.dark = false,
    this.css = '',
  });

  final String name;
  final Color boxColor;
  final double radius;
  final bool border;
  final bool shadow;

  /// Degrees.
  final double tilt;
  final bool handwriting;
  final double fontSize;
  final double lineHeight;
  final double padding;
  final Color? textColor;
  final Color accentColor;
  final bool dark;
  final String css;

  PlaygroundDesign copyWith({
    Color? boxColor,
    double? radius,
    bool? border,
    bool? shadow,
    double? tilt,
    bool? handwriting,
    double? fontSize,
    double? lineHeight,
    double? padding,
    Color? textColor,
    bool clearTextColor = false,
    Color? accentColor,
    String? css,
  }) => PlaygroundDesign(
    name: 'Custom',
    boxColor: boxColor ?? this.boxColor,
    radius: radius ?? this.radius,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
    tilt: tilt ?? this.tilt,
    handwriting: handwriting ?? this.handwriting,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    padding: padding ?? this.padding,
    textColor: clearTextColor ? null : textColor ?? this.textColor,
    accentColor: accentColor ?? this.accentColor,
    dark: dark,
    css: css ?? this.css,
  );

  AminotesTheme get theme => AminotesTheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    textColor: textColor,
    accentColor: accentColor,
    fontFamily: handwriting ? 'Caveat' : null,
    fonts: handwriting ? const [AminotesFont('Caveat', 'assets/fonts/Caveat.ttf')] : const [],
    fontSize: fontSize,
    lineHeight: lineHeight,
    padding: EdgeInsets.all(padding),
    css: css.trim().isEmpty ? null : css,
  );
}

// Round checkboxes, for the sticky note: something AminotesTheme alone can't do.
const _roundCheckboxes = '''
.ProseMirror input[type='checkbox'] {
  appearance: none; width: 22px; height: 22px; border-radius: 50%;
  border: 2px solid var(--primary); display: grid; place-content: center;
}
.ProseMirror input[type='checkbox']:checked { background: var(--primary); }
.ProseMirror input[type='checkbox']:checked::after { content: '✓'; color: white; font-size: 14px; }
.ProseMirror h1 { font-size: 1.5em; }''';

// Big headings and tight spacing.
const _notionStyle = '''
.ProseMirror h1 { font-size: 2.4em; font-weight: 700; margin: 0.4em 0 0.1em; }
.ProseMirror > * + * { margin-top: 0.25em; }
.ProseMirror blockquote { border-inline-start-color: currentColor; }
.voice-note button { border-radius: 6px; }''';

const playgroundPresets = [
  PlaygroundDesign(name: 'Plain', boxColor: Color(0xFFF4F5F7), border: true, accentColor: Color(0xFF00696B)),
  PlaygroundDesign(
    name: 'Card',
    boxColor: Color(0xFFFFFFFF),
    radius: 20,
    shadow: true,
    fontSize: 17,
    padding: 20,
    textColor: Color(0xFF1C1B1F),
    accentColor: Color(0xFF3F51B5),
  ),
  PlaygroundDesign(
    name: 'Sticky note',
    boxColor: Color(0xFFFFF59D),
    radius: 2,
    shadow: true,
    tilt: -1.5,
    handwriting: true,
    fontSize: 24,
    lineHeight: 1.3,
    padding: 18,
    textColor: Color(0xFF3E2723),
    accentColor: Color(0xFF8D6E63),
    css: _roundCheckboxes,
  ),
  PlaygroundDesign(
    name: 'Notion style',
    boxColor: Color(0xFFFFFFFF),
    radius: 8,
    border: true,
    lineHeight: 1.6,
    padding: 24,
    textColor: Color(0xFF37352F),
    accentColor: Color(0xFF2383E2),
    css: _notionStyle,
  ),
  PlaygroundDesign(
    name: 'Dark',
    boxColor: Color(0xFF1E1F22),
    radius: 16,
    textColor: Color(0xFFE6E6E6),
    accentColor: Color(0xFF8AB4F8),
    dark: true,
  ),
];

const _swatches = [
  Color(0xFFFFFFFF),
  Color(0xFFF4F5F7),
  Color(0xFFFFF59D),
  Color(0xFFC8E6C9),
  Color(0xFFBBDEFB),
  Color(0xFFF8BBD0),
  Color(0xFF1E1F22),
];

const _accents = [
  Color(0xFF00696B),
  Color(0xFF3F51B5),
  Color(0xFF2383E2),
  Color(0xFFE53935),
  Color(0xFF8D6E63),
  Color(0xFF8AB4F8),
];

const _textColors = [Color(0xFF1C1B1F), Color(0xFF37352F), Color(0xFF3E2723), Color(0xFFE6E6E6)];

/// Every built-in button, in the order of the full toolbar.
const _allItems = [
  AminotesToolbarItem.undo,
  AminotesToolbarItem.redo,
  AminotesToolbarItem.bold,
  AminotesToolbarItem.italic,
  AminotesToolbarItem.underline,
  AminotesToolbarItem.strikethrough,
  AminotesToolbarItem.textColor,
  AminotesToolbarItem.highlight,
  AminotesToolbarItem.link,
  AminotesToolbarItem.heading1,
  AminotesToolbarItem.heading2,
  AminotesToolbarItem.heading3,
  AminotesToolbarItem.bulletList,
  AminotesToolbarItem.numberedList,
  AminotesToolbarItem.checklist,
  AminotesToolbarItem.indent,
  AminotesToolbarItem.outdent,
  AminotesToolbarItem.quote,
  AminotesToolbarItem.inlineCode,
  AminotesToolbarItem.codeBlock,
  AminotesToolbarItem.divider,
  AminotesToolbarItem.table,
  AminotesToolbarItem.voiceNote,
  AminotesToolbarItem.image,
];

const _demoNote =
    '<h1>Weekend</h1>'
    '<p>Pick up <strong>flowers</strong> and <mark>call Maya</mark>. Ideas in '
    '<a href="https://example.com">this list</a>.</p>'
    '<ul data-type="taskList">'
    '<li data-type="taskItem" data-checked="true"><p>Book the table</p></li>'
    '<li data-type="taskItem" data-checked="false"><p>Buy a gift</p></li>'
    '</ul>'
    '<blockquote><p>Leave by 6 pm.</p></blockquote>';

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  final _controller = AminotesController(initialContent: const AminotesContent.html(_demoNote));
  PlaygroundDesign _design = playgroundPresets.first;
  Set<AminotesToolbarItem> _items = {...AminotesToolbarItem.compact.where((i) => i != AminotesToolbarItem.separator)};
  late final _css = TextEditingController(text: _design.css);

  @override
  void dispose() {
    _controller.dispose();
    _css.dispose();
    super.dispose();
  }

  void _apply(PlaygroundDesign design) => setState(() {
    _design = design;
    if (_css.text != design.css) _css.text = design.css;
  });

  /// The chosen buttons in toolbar order, with a separator between groups.
  List<AminotesToolbarItem> get _toolbarItems {
    final out = <AminotesToolbarItem>[];
    var lastWasSeparator = true;
    for (final item in AminotesToolbarItem.full) {
      if (item == AminotesToolbarItem.separator) {
        if (!lastWasSeparator) out.add(item);
        lastWasSeparator = true;
      } else if (_items.contains(item)) {
        out.add(item);
        lastWasSeparator = false;
      }
    }
    while (out.isNotEmpty && out.last == AminotesToolbarItem.separator) {
      out.removeLast();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final d = _design;
    Widget box = Container(
      height: 230,
      decoration: BoxDecoration(
        color: d.boxColor,
        borderRadius: BorderRadius.circular(d.radius),
        border: d.border ? Border.all(color: Colors.black12) : null,
        boxShadow: d.shadow ? const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: AminotesEditor(controller: _controller, theme: d.theme, previewWhileLoading: false),
    );
    if (d.tilt != 0) box = Transform.rotate(angle: d.tilt * 3.14159 / 180, child: box);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Playground'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Style'),
              Tab(text: 'Text'),
              Tab(text: 'Toolbar'),
              Tab(text: 'Code'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), child: box),
            if (_toolbarItems.isNotEmpty) AminotesToolbar(controller: _controller, items: _toolbarItems),
            const Divider(height: 1),
            Expanded(child: TabBarView(children: [_styleTab(), _textTab(), _toolbarTab(), _codeTab()])),
          ],
        ),
      ),
    );
  }

  Widget _styleTab() {
    final d = _design;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in playgroundPresets)
              ChoiceChip(
                label: Text(preset.name),
                showCheckmark: false,
                selected: d.name == preset.name,
                onSelected: (_) => _apply(preset),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _label('Box color'),
        _swatchRow(_swatches, d.boxColor, (c) => _apply(d.copyWith(boxColor: c))),
        _slider('Corner radius', d.radius, 0, 32, (v) => _apply(d.copyWith(radius: v))),
        _slider('Tilt (degrees)', d.tilt, -4, 4, (v) => _apply(d.copyWith(tilt: v)), decimals: 1),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Shadow'),
          value: d.shadow,
          onChanged: (v) => _apply(d.copyWith(shadow: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Border'),
          value: d.border,
          onChanged: (v) => _apply(d.copyWith(border: v)),
        ),
        const Text('The box is your own widget: any shape, color, image or animation works.'),
      ],
    );
  }

  Widget _textTab() {
    final d = _design;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _label('Font'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text("Phone's font")),
            ButtonSegment(value: true, label: Text('Caveat (app asset)')),
          ],
          selected: {d.handwriting},
          onSelectionChanged: (v) => _apply(d.copyWith(handwriting: v.single)),
        ),
        _slider('Font size', d.fontSize, 12, 32, (v) => _apply(d.copyWith(fontSize: v))),
        _slider('Line height', d.lineHeight, 1, 2, (v) => _apply(d.copyWith(lineHeight: v)), decimals: 1),
        _slider('Padding', d.padding, 4, 32, (v) => _apply(d.copyWith(padding: v))),
        _label('Text color'),
        Row(
          children: [
            ChoiceChip(
              label: const Text('From app theme'),
              selected: d.textColor == null,
              onSelected: (_) => _apply(d.copyWith(clearTextColor: true)),
            ),
            const SizedBox(width: 8),
            Expanded(child: _swatchRow(_textColors, d.textColor, (c) => _apply(d.copyWith(textColor: c)))),
          ],
        ),
        _label('Accent (links, checkboxes, quote bar)'),
        _swatchRow(_accents, d.accentColor, (c) => _apply(d.copyWith(accentColor: c))),
        _label('Custom CSS (anything the settings above can\'t do)'),
        TextField(
          controller: _css,
          maxLines: 8,
          minLines: 3,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '.ProseMirror h1 { font-size: 2em; }',
          ),
          onChanged: (css) => setState(() => _design = d.copyWith(css: css)),
        ),
      ],
    );
  }

  Widget _toolbarTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => setState(
                () => _items = {...AminotesToolbarItem.compact.where((i) => i != AminotesToolbarItem.separator)},
              ),
              child: const Text('Compact'),
            ),
            OutlinedButton(onPressed: () => setState(() => _items = {..._allItems}), child: const Text('Full')),
            OutlinedButton(onPressed: () => setState(() => _items = {}), child: const Text('None')),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in _allItems)
              FilterChip(
                label: Text(item.name),
                selected: _items.contains(item),
                onSelected: (on) => setState(() => on ? _items.add(item) : _items.remove(item)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Order follows the full toolbar; separators are added between groups.'),
      ],
    );
  }

  Widget _codeTab() {
    final code = generatePlaygroundCode(_design, _toolbarItems);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy code'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int decimals = 0,
  }) => Row(
    children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) * (decimals == 0 ? 1 : 10)).round(),
          label: value.toStringAsFixed(decimals),
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 36, child: Text(value.toStringAsFixed(decimals))),
    ],
  );

  Widget _swatchRow(List<Color> colors, Color? selected, ValueChanged<Color> onPick) => Wrap(
    spacing: 8,
    children: [
      for (final color in colors)
        GestureDetector(
          onTap: () => onPick(color),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected?.toARGB32() == color.toARGB32() ? Colors.teal : Colors.black26,
                width: selected?.toARGB32() == color.toARGB32() ? 3 : 1,
              ),
            ),
          ),
        ),
    ],
  );
}

/// The Dart code for a design and toolbar, ready to paste into an app.
String generatePlaygroundCode(PlaygroundDesign d, List<AminotesToolbarItem> items) {
  String hex(Color c) => 'Color(0x${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';
  String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  final theme = [
    if (d.dark) 'brightness: Brightness.dark,',
    if (d.textColor != null) 'textColor: ${hex(d.textColor!)},',
    'accentColor: ${hex(d.accentColor)},',
    if (d.handwriting) ...[
      "fontFamily: 'Caveat',",
      '// Declare the file under `fonts:` (or `assets:`) in your pubspec.',
      "fonts: [AminotesFont('Caveat', 'assets/fonts/Caveat.ttf')],",
    ],
    'fontSize: ${n(d.fontSize)},',
    'lineHeight: ${n(d.lineHeight)},',
    'padding: EdgeInsets.all(${n(d.padding)}),',
    if (d.css.trim().isNotEmpty) "css: r'''\n${d.css.trim()}\n''',",
  ];
  final decoration = [
    'color: ${hex(d.boxColor)},',
    'borderRadius: BorderRadius.circular(${n(d.radius)}),',
    if (d.border) 'border: Border.all(color: Colors.black12),',
    if (d.shadow) 'boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],',
  ];
  String indent(List<String> lines, int spaces) =>
      lines.expand((line) => line.split('\n')).map((line) => line.isEmpty ? line : '${' ' * spaces}$line').join('\n');

  var box =
      '''Container(
  height: 230,
  decoration: BoxDecoration(
${indent(decoration, 4)}
  ),
  clipBehavior: Clip.antiAlias,
  child: AminotesEditor(
    controller: controller,
    theme: AminotesTheme(
${indent(theme, 6)}
    ),
  ),
)''';
  if (d.tilt != 0) {
    box =
        'Transform.rotate(\n  angle: ${n(d.tilt)} * pi / 180, // import dart:math\n  child: ${box.replaceAll('\n', '\n  ')},\n)';
  }
  final toolbar = items.isEmpty
      ? '// No toolbar: call controller.toggleBold() etc. from your own buttons.'
      : '''AminotesToolbar(
  controller: controller,
  items: const [
${items.map((i) => '    AminotesToolbarItem.${i.name},').join('\n')}
  ],
)''';
  return '// The note box (show the toolbar above the keyboard while\n'
      '// controller.toolbarVisible is true).\n$box,\n\n$toolbar,\n';
}
