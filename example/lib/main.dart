import 'dart:convert';

import 'package:aminotes/aminotes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'playground.dart';

void main() {
  // The Caveat font's license (SIL OFL) on the app's license page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Caveat font'], await rootBundle.loadString('assets/fonts/Caveat-OFL.txt'));
  });
  runApp(const ExampleApp());
}

/// Shows how a host app uses aminotes: its own note box, its own full-screen
/// page, the package's toolbar above the keyboard, and saving on change.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  var _dark = false;
  var _rtl = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'aminotes example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      // Arabic switches the layout to right-to-left and the package's texts
      // (toolbar, dialogs) to Arabic.
      locale: _rtl ? const Locale('ar') : const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: NoteScreen(
        dark: _dark,
        rtl: _rtl,
        onDarkChanged: (value) => setState(() => _dark = value),
        onRtlChanged: (value) => setState(() => _rtl = value),
      ),
    );
  }
}

class NoteScreen extends StatefulWidget {
  const NoteScreen({
    super.key,
    required this.dark,
    required this.rtl,
    required this.onDarkChanged,
    required this.onRtlChanged,
  });

  final bool dark;
  final bool rtl;
  final ValueChanged<bool> onDarkChanged;
  final ValueChanged<bool> onRtlChanged;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  // A host app would save to its database in onChanged; here we just count.
  var _saves = 0;

  late final _controller = AminotesController(
    initialContent: const AminotesContent.text('Tap here to write.\nThis note started as plain text.'),
    onChanged: (json) {
      // Edits flushed on dispose can arrive after this screen is gone.
      if (!mounted) return;
      setState(() => _saves++);
    },
    onLinkTap: _openLink,
    onError: (error) => debugPrint('aminotes ${error.kind.name}: ${error.message}'),
  );

  @override
  void initState() {
    super.initState();
    // Start the editor page now so the box is ready by the time it's tapped.
    _controller.preload();
  }

  /// A real app would use url_launcher; the demo just shows the link.
  void _openLink(String href) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open link?'),
        content: SelectableText(href),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSample() async {
    final json = jsonDecode(await rootBundle.loadString('assets/sample_note.json')) as Map<String, dynamic>;
    await _controller.load(AminotesContent.json(json));
  }

  Future<void> _showJson() async {
    final json = await _controller.getJson();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current JSON'),
        content: SingleChildScrollView(
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(json),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  /// What a host app does when it's online: upload recordings, get URLs back.
  /// This demo pretends: no server, so the URLs don't play.
  Future<void> _uploadVoiceNotes() async {
    final messenger = ScaffoldMessenger.of(context);
    var uploaded = 0;
    try {
      await _controller.uploadPendingMedia((upload) async {
        final bytes = await upload.read();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        uploaded++;
        return 'https://files.example.com/${upload.fileName}?size=${bytes.length}';
      });
      messenger.showSnackBar(
        SnackBar(content: Text(uploaded == 0 ? 'Nothing to upload' : 'Uploaded $uploaded (simulated)')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Upload failed: $error')));
    }
  }

  void _openFullScreen() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FullScreenNote(controller: _controller)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('aminotes'),
        actions: [
          IconButton(
            tooltip: 'Playground',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlaygroundScreen())),
          ),
          IconButton(
            tooltip: 'Notes list',
            icon: const Icon(Icons.view_list_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotesListScreen())),
          ),
          IconButton(
            tooltip: 'Dark mode',
            isSelected: widget.dark,
            icon: const Icon(Icons.dark_mode_outlined),
            onPressed: () => widget.onDarkChanged(!widget.dark),
          ),
          IconButton(
            tooltip: 'Arabic',
            isSelected: widget.rtl,
            icon: const Icon(Icons.format_textdirection_r_to_l),
            onPressed: () => widget.onRtlChanged(!widget.rtl),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Note', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                // A note this app version can't edit safely is read-only.
                ValueListenableBuilder(
                  valueListenable: _controller.state,
                  builder: (context, state, _) => state.loadFailed
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                "This note can't be edited in this version of the app. It's shown read-only and kept unchanged.",
                                style: TextStyle(color: colors.onErrorContainer),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // The host app's own note box; aminotes only fills it.
                Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      AminotesEditor(
                        controller: _controller,
                        placeholder: 'Write a note…',
                        // The box grows with the note, then scrolls inside.
                        autoHeight: true,
                        minHeight: 120,
                        maxHeight: 320,
                        theme: const AminotesTheme(padding: EdgeInsetsDirectional.fromSTEB(12, 10, 44, 10)),
                        inactiveChild: const Center(child: Text('Open in full screen')),
                      ),
                      PositionedDirectional(
                        top: 4,
                        end: 4,
                        // On the web the editor is an iframe, which would take
                        // the click: shield buttons drawn over it.
                        child: PointerInterceptor(
                          child: IconButton(
                            tooltip: 'Full screen',
                            icon: const Icon(Icons.open_in_full),
                            onPressed: _openFullScreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Live counts from the editor.
                ValueListenableBuilder(
                  valueListenable: _controller.state,
                  builder: (context, state, _) => Text(
                    '${state.stats.words} words · ${state.stats.characters} characters · '
                    '${_saves == 0 ? 'no changes saved yet' : 'saved $_saves times'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(onPressed: _loadSample, child: const Text('Load sample note')),
                    OutlinedButton(
                      onPressed: () =>
                          _controller.load(const AminotesContent.text('First line\n\nAfter an empty line')),
                      child: const Text('Load plain text'),
                    ),
                    OutlinedButton(
                      onPressed: () => _controller.load(
                        const AminotesContent.html('<h2>From HTML</h2><p><b>Bold</b> and <i>italic</i></p>'),
                      ),
                      child: const Text('Load HTML'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          _controller.load(const AminotesContent.text('مرحبا، هذه ملاحظة باللغة العربية.')),
                      child: const Text('Load Arabic'),
                    ),
                    OutlinedButton(
                      onPressed: () => _controller.load(AminotesContent.empty),
                      child: const Text('Clear'),
                    ),
                    OutlinedButton(
                      onPressed: () => _controller.load(const AminotesContent.json(_webOnlyNote)),
                      child: const Text('Load web-only content'),
                    ),
                    OutlinedButton(
                      onPressed: () => _controller.load(const AminotesContent.json(_brokenNote)),
                      child: const Text('Load broken note'),
                    ),
                    OutlinedButton(onPressed: _uploadVoiceNotes, child: const Text('Upload media')),
                    FilledButton.tonal(onPressed: _showJson, child: const Text('Show JSON')),
                  ],
                ),
              ],
            ),
          ),
          // Compact toolbar for the box, with a pinned "full screen" button.
          _KeyboardToolbar(
            controller: _controller,
            items: AminotesToolbarItem.compact,
            trailing: IconButton(
              tooltip: 'Full screen',
              icon: const Icon(Icons.open_in_full),
              onPressed: _openFullScreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// A list of notes as cheap previews (no WebView per note). Tapping one opens
/// it in the editor; its saved JSON updates the preview.
class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key});

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final _notes = <Map<String, dynamic>>[
    _textNote('Groceries', ['Milk', 'Eggs', 'Bread']),
    _textNote('ملاحظة', ['مرحبا، هذه ملاحظة باللغة العربية.']),
    _webOnlyNote,
  ];

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/sample_note.json').then((text) {
      if (mounted) setState(() => _notes.insert(0, jsonDecode(text) as Map<String, dynamic>));
    });
  }

  Future<void> _open(int index) async {
    final controller = AminotesController(
      initialContent: AminotesContent.json(_notes[index]),
      onChanged: (json) => setState(() => _notes[index] = json),
    );
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FullScreenNote(controller: controller)));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      // Counted from the saved JSON, without opening an editor.
      appBar: AppBar(
        title: Text(
          '${_notes.length} notes · ${_notes.fold(0, (sum, note) => sum + AminotesStats.of(note).words)} words',
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => Material(
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(index),
            // Only the start of each note, faded out at the bottom.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.75, 1],
                ).createShader(bounds),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: AminotesPreview(json: _notes[index], maxBlocks: 6, imageHeight: 100),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Map<String, dynamic> _textNote(String title, List<String> lines) => {
    'type': 'doc',
    'content': [
      {
        'type': 'heading',
        'attrs': {'level': 2},
        'content': [
          {'type': 'text', 'text': title},
        ],
      },
      for (final line in lines)
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': line},
          ],
        },
    ],
  };
}

/// The same note, full screen. Same controller: text, cursor and undo history
/// carry over both ways.
class FullScreenNote extends StatelessWidget {
  const FullScreenNote({super.key, required this.controller});

  final AminotesController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        leading: IconButton(
          tooltip: 'Exit full screen',
          icon: const Icon(Icons.close_fullscreen),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AminotesEditor(controller: controller, placeholder: 'Write a note…', autofocus: true),
          ),
          // The full toolbar plus a custom button of the host app.
          _KeyboardToolbar(
            controller: controller,
            items: [
              ...AminotesToolbarItem.full,
              AminotesToolbarItem.custom(
                icon: const Icon(Icons.today_outlined),
                tooltip: 'Insert date',
                onPressed: (c) => c.insertText(MaterialLocalizations.of(context).formatMediumDate(DateTime.now())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows the package's toolbar while the note is being edited. The Scaffold
/// shrinks its body for the keyboard, so this sits right above it.
class _KeyboardToolbar extends StatelessWidget {
  const _KeyboardToolbar({required this.controller, required this.items, this.trailing});

  final AminotesController controller;
  final List<AminotesToolbarItem> items;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.toolbarVisible,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: AminotesToolbar(controller: controller, items: items, trailing: trailing),
        );
      },
    );
  }
}

/// A note written by a (future) web app with extensions this package doesn't
/// have: a callout block, a mention, a superscript mark and a text-align
/// attribute. All are kept and saved back unchanged.
const _webOnlyNote = <String, dynamic>{
  'type': 'doc',
  'content': [
    {
      'type': 'paragraph',
      'attrs': {'textAlign': 'center'},
      'content': [
        {'type': 'text', 'text': 'Hi '},
        {
          'type': 'mention',
          'attrs': {'id': '42', 'label': 'Sam'},
        },
        {'type': 'text', 'text': ', E=mc'},
        {
          'type': 'text',
          'text': '2',
          'marks': [
            {'type': 'superscript'},
          ],
        },
      ],
    },
    {
      'type': 'callout',
      'attrs': {'emoji': '💡'},
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'A web-only callout'},
          ],
        },
      ],
    },
    {
      'type': 'paragraph',
      'content': [
        {'type': 'text', 'text': 'Edit this line, then Show JSON: the rest is unchanged.'},
      ],
    },
  ],
};

/// Structurally invalid (a paragraph directly inside a list): opened
/// read-only and never overwritten.
const _brokenNote = <String, dynamic>{
  'type': 'doc',
  'content': [
    {
      'type': 'bulletList',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'Broken list'},
          ],
        },
      ],
    },
  ],
};
