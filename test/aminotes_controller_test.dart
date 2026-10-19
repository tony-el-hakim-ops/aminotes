import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aminotes/aminotes.dart';
import 'package:aminotes/src/bridge/tiptap_bridge.dart';
import 'package:aminotes/src/controller/aminotes_state.dart' show cssHex, parseCssColor;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

const _doc = {
  'type': 'doc',
  'content': [
    {
      'type': 'paragraph',
      'content': [
        {'type': 'text', 'text': 'Hello'},
      ],
    },
  ],
};

const _edited = {
  'type': 'doc',
  'content': [
    {
      'type': 'paragraph',
      'content': [
        {'type': 'text', 'text': 'Hello world'},
      ],
    },
  ],
};

void main() {
  late FakeHost host;
  var hostsCreated = 0;

  AminotesController controllerWith({
    AminotesContent content = const AminotesContent.json(_doc),
    ValueChanged<Map<String, dynamic>>? onChanged,
  }) {
    hostsCreated = 0;
    final controller = AminotesController(
      initialContent: content,
      onChanged: onChanged,
      hostFactory: (onMessage) {
        hostsCreated++;
        return host = FakeHost(onMessage);
      },
    );
    addTearDown(controller.dispose);
    return controller;
  }

  // The editor takes the WebView one frame after it's first built.
  Future<void> pumpApp(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.pump();
  }

  Future<void> pumpEditor(WidgetTester tester, AminotesController controller) => pumpApp(
    tester,
    MaterialApp(
      home: Scaffold(
        body: AminotesEditor(controller: controller, placeholder: 'Write a note…'),
      ),
    ),
  );

  group('bundled editor', () {
    test('assets exist and the page loads its script', () {
      for (final name in ['index.html', 'editor.js', 'editor.css']) {
        expect(File('assets/editor/$name').lengthSync(), greaterThan(0), reason: name);
      }
      final html = File('assets/editor/index.html').readAsStringSync();
      expect(html, contains('editor.js'));
      expect(html, contains('editor.css'));
    });

    test('the asset key points into the package', () {
      expect(tiptapEditorAsset, 'packages/aminotes/assets/editor/index.html');
    });
  });

  group('before an editor is shown', () {
    test('no WebView is created and JSON content is returned as is', () async {
      final controller = controllerWith();
      expect(await controller.getJson(), _doc);
      expect(hostsCreated, 0);
      expect(controller.state.value.ready, isFalse);
    });

    test('text and HTML need the editor to convert them', () {
      final controller = controllerWith(content: const AminotesContent.text('Hi'));
      expect(controller.getJson, throwsStateError);
    });
  });

  group('with an editor', () {
    testWidgets('loads the note when the page is ready', (tester) async {
      final controller = controllerWith();
      await pumpEditor(tester, controller);
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);
      expect(controller.state.value.ready, isFalse);

      host.postFromPage('{"type":"ready"}');
      await tester.pump();

      expect(controller.state.value.ready, isTrue);
      final configure = host.calls('configure').single;
      expect(configure, contains('"placeholder":"Write a note…"'));
      expect(configure, contains('"direction":"ltr"'));
      expect(configure, contains('"changeDelay":400'));
      expect(host.calls('setTheme').single, contains('"brightness":"light"'));
      expect(host.calls('setContent').single, contains(jsonEncode({'format': 'json', 'value': _doc})));
    });

    testWidgets('plain text and HTML are sent for Tiptap to convert', (tester) async {
      final controller = controllerWith(content: const AminotesContent.text('Line 1\nLine 2'));
      await pumpEditor(tester, controller);
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      expect(host.calls('setContent').single, contains('"format":"text","value":"Line 1\\nLine 2"'));

      await controller.load(const AminotesContent.html('<p><b>Hi</b></p>'));
      expect(host.calls('setContent').last, contains('"format":"html"'));
    });

    testWidgets('edits reach onChanged and the stream, and survive a page reload', (tester) async {
      final changes = <Map<String, dynamic>>[];
      final controller = controllerWith(onChanged: changes.add);
      final streamed = <Map<String, dynamic>>[];
      final subscription = controller.changes.listen(streamed.add);
      addTearDown(subscription.cancel);
      await pumpEditor(tester, controller);
      host.postFromPage('{"type":"ready"}');
      await tester.pump();

      host.postFromPage(jsonEncode({'type': 'change', 'doc': _edited}));
      await tester.pump();
      expect(changes.single, _edited);
      expect(streamed.single, _edited);

      // On the web, moving the iframe reloads the page: the latest edit comes back.
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      expect(host.calls('setContent').last, contains(jsonEncode({'format': 'json', 'value': _edited})));
    });

    testWidgets('getJson asks the page for the current JSON', (tester) async {
      final controller = controllerWith();
      await pumpEditor(tester, controller);
      host
        ..replyDoc = _edited
        ..postFromPage('{"type":"ready"}');
      await tester.pump();
      expect(await tester.runAsync(controller.getJson), _edited);
    });

    testWidgets('commands become editor page calls', (tester) async {
      final controller = controllerWith();
      await pumpEditor(tester, controller);
      host.postFromPage('{"type":"ready"}');
      await tester.pump();

      await controller.toggleBold();
      await controller.toggleHeading(2);
      await controller.toggleChecklist();
      await controller.setLink('https://example.com');
      await controller.undo();
      expect(host.calls('command').toList(), [
        'window.tiptap && window.tiptap.command("toggleBold", {});',
        'window.tiptap && window.tiptap.command("setHeading", {"level":2});',
        'window.tiptap && window.tiptap.command("toggleTaskList", {});',
        'window.tiptap && window.tiptap.command("setLink", {"href":"https://example.com"});',
        'window.tiptap && window.tiptap.command("undo", {});',
      ]);
    });

    testWidgets('commands sent before the page loads wait for it', (tester) async {
      final controller = controllerWith();
      await pumpEditor(tester, controller);
      final pending = controller.toggleItalic();
      await tester.pump();
      expect(host.calls('command'), isEmpty);
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      await pending;
      expect(host.calls('command').single, contains('toggleItalic'));
    });

    testWidgets('state messages update controller.state', (tester) async {
      final controller = controllerWith();
      await pumpEditor(tester, controller);
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      host.postFromPage(
        '{"type":"state","focused":true,"canUndo":true,"canSink":true,'
        '"active":{"bold":true,"heading2":true},"linkHref":null}',
      );
      final state = controller.state.value;
      expect(state.ready, isTrue);
      expect(state.focused, isTrue);
      expect(state.canUndo, isTrue);
      expect(state.canIndent, isTrue);
      expect(state.isActive('bold'), isTrue);
      expect(state.headingLevel, 2);
    });

    testWidgets('dark theme, Arabic direction and custom theme values reach the page', (tester) async {
      final controller = controllerWith();
      await pumpApp(
        tester,
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AminotesEditor(
              controller: controller,
              theme: const AminotesTheme(fontSize: 18, textColor: Color(0xFF112233), padding: EdgeInsets.all(8)),
            ),
          ),
        ),
      );
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      final theme = host.calls('setTheme').single;
      expect(theme, contains('"brightness":"dark"'));
      expect(theme, contains('"--font-size":"18.0px"'));
      expect(theme, contains('"--text":"rgba(17, 34, 51, 1.000)"'));
      expect(theme, contains('"--pad-top":"8.0px"'));
      expect(host.calls('configure').single, contains('"direction":"rtl"'));
    });

    testWidgets('a second editor (full screen) takes over the note, then gives it back', (tester) async {
      final controller = controllerWith();
      final navigator = GlobalKey<NavigatorState>();
      await pumpApp(
        tester,
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: SizedBox(
              height: 120,
              child: AminotesEditor(controller: controller, inactiveChild: const Text('shown full screen')),
            ),
          ),
        ),
      );
      host.postFromPage('{"type":"ready"}');
      await tester.pump();

      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: AminotesEditor(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(hostsCreated, 1, reason: 'one WebView, moved between editors');
      expect(find.byKey(const ValueKey('fake-webview'), skipOffstage: false), findsOneWidget);
      expect(find.text('shown full screen', skipOffstage: false), findsOneWidget);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('shown full screen'), findsNothing);
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);
      expect(host.calls('setContent'), hasLength(1), reason: 'the note was never reloaded');
    });
  });

  group('toolbar', () {
    testWidgets('buttons run commands without taking focus from the editor', (tester) async {
      final controller = controllerWith();
      final editorFocus = FocusNode();
      addTearDown(editorFocus.dispose);
      await pumpApp(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Focus(
                    focusNode: editorFocus,
                    child: AminotesEditor(controller: controller),
                  ),
                ),
                AminotesToolbar(controller: controller),
              ],
            ),
          ),
        ),
      );
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      host.postFromPage('{"type":"state","focused":true,"canUndo":true,"active":{"bold":true}}');
      editorFocus.requestFocus();
      await tester.pump();

      final bold = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_bold));
      expect(bold.isSelected, isTrue);

      await tester.tap(find.byTooltip('Bold'));
      await tester.tap(find.byTooltip('Heading 1'));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(editorFocus.hasPrimaryFocus, isTrue, reason: 'a toolbar tap would close the Android keyboard');
      expect(host.calls('command').map((s) => RegExp(r'command\("(\w+)"').firstMatch(s)!.group(1)), [
        'toggleBold',
        'setHeading',
        'undo',
      ]);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo)).onPressed, isNull);
    });
  });

  group('M2: colors and safety', () {
    testWidgets('color commands store #rrggbb, null removes', (tester) async {
      final controller = controllerWith();
      await pumpEditor(tester, controller);
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      await controller.setTextColor(const Color(0xFFE53935));
      await controller.setHighlightColor(const Color(0x80FFF59D));
      await controller.setTextColor(null);
      expect(host.calls('command').toList(), [
        'window.tiptap && window.tiptap.command("setTextColor", {"color":"#e53935"});',
        'window.tiptap && window.tiptap.command("setHighlight", {"color":"#fff59d"});',
        'window.tiptap && window.tiptap.command("setTextColor", {"color":null});',
      ]);
    });

    test('state reads colors and the load failure flag', () {
      final state = AminotesState.fromJson({'loadFailed': true, 'textColor': '#E53935', 'highlightColor': '#fff59d'});
      expect(state.loadFailed, isTrue);
      expect(state.textColor, const Color(0xFFE53935));
      expect(state.highlightColor, const Color(0xFFFFF59D));
    });

    test('CSS color parsing', () {
      expect(parseCssColor('#abc'), const Color(0xFFAABBCC));
      expect(parseCssColor('#11223380'), const Color(0x80112233));
      expect(parseCssColor('red'), isNull);
      expect(parseCssColor(null), isNull);
      expect(cssHex(const Color(0xFF0A0B0C)), '#0a0b0c');
    });

    test('the Dart schema version matches the JavaScript one', () {
      final js = File('tiptap/src/extensions.js').readAsStringSync();
      final version = RegExp(r'SCHEMA_VERSION = (\d+)').firstMatch(js)!.group(1);
      expect(aminotesSchemaVersion, int.parse(version!));
    });

    testWidgets('the color swatches apply a color without taking focus', (tester) async {
      final controller = controllerWith();
      final editorFocus = FocusNode();
      addTearDown(editorFocus.dispose);
      await pumpApp(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Focus(
                    focusNode: editorFocus,
                    child: AminotesEditor(controller: controller),
                  ),
                ),
                AminotesToolbar(controller: controller),
              ],
            ),
          ),
        ),
      );
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      host.postFromPage('{"type":"state","focused":true}');
      editorFocus.requestFocus();
      await tester.pump();

      await tester.tap(find.byTooltip('Text color'));
      await tester.pump();
      expect(find.byTooltip('Default color'), findsOneWidget);
      await tester.tap(find.byTooltip('Blue'));
      await tester.pump();
      expect(host.calls('command').single, contains('"setTextColor", {"color":"#1e88e5"}'));
      expect(find.byTooltip('Default color'), findsNothing, reason: 'the palette closes');
      expect(editorFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('a note that failed to load disables the toolbar', (tester) async {
      final controller = controllerWith();
      await pumpApp(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: AminotesEditor(controller: controller)),
                AminotesToolbar(controller: controller),
              ],
            ),
          ),
        ),
      );
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      host.postFromPage('{"type":"state","focused":true,"loadFailed":true}');
      await tester.pump();
      expect(controller.state.value.loadFailed, isTrue);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_bold)).onPressed, isNull);
    });
  });

  group('M3: presets and translations', () {
    Future<void> pumpToolbar(
      WidgetTester tester,
      AminotesController controller, {
      Locale? locale,
      List<AminotesToolbarItem> items = AminotesToolbarItem.full,
      AminotesStrings? strings,
    }) async {
      Widget toolbar = AminotesToolbar(controller: controller, items: items);
      if (strings != null) toolbar = AminotesStringsScope(strings: strings, child: toolbar);
      await pumpApp(
        tester,
        Localizations(
          locale: locale ?? const Locale('en'),
          delegates: const [DefaultWidgetsLocalizations.delegate, DefaultMaterialLocalizations.delegate],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(child: AminotesEditor(controller: controller)),
                  toolbar,
                ],
              ),
            ),
          ),
        ),
      );
      host.postFromPage('{"type":"ready"}');
      // The page setup finishes after a few async calls; then the toolbar rebuilds.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the compact preset shows only its buttons', (tester) async {
      final controller = controllerWith();
      await pumpToolbar(tester, controller, items: AminotesToolbarItem.compact);
      expect(find.byTooltip('Bold'), findsOneWidget);
      expect(find.byTooltip('Checklist'), findsOneWidget);
      expect(find.byTooltip('Heading 1'), findsNothing);
      expect(find.byTooltip('Undo'), findsNothing);
    });

    testWidgets('Arabic locale: Arabic tooltips and page labels', (tester) async {
      final controller = controllerWith();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            // Only the package's widgets need the Arabic locale here.
            builder: (context) => Localizations.override(
              context: context,
              locale: const Locale('ar'),
              child: Scaffold(
                body: Column(
                  children: [
                    Expanded(child: AminotesEditor(controller: controller)),
                    AminotesToolbar(controller: controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      host.postFromPage('{"type":"ready"}');
      await tester.pump();
      expect(find.byTooltip('غامق'), findsOneWidget);
      expect(find.byTooltip('عنوان 2'), findsOneWidget);
      expect(host.calls('configure').single, contains('محتوى غير مدعوم'));
    });

    testWidgets('AminotesStringsScope overrides texts', (tester) async {
      final controller = controllerWith();
      await pumpToolbar(tester, controller, strings: AminotesStrings.english.copyWith(bold: 'Strong'));
      expect(find.byTooltip('Strong'), findsOneWidget);
      expect(find.byTooltip('Bold'), findsNothing);
    });

    testWidgets('the link dialog is translated and adds the link', (tester) async {
      final controller = controllerWith();
      await pumpToolbar(tester, controller, strings: AminotesStrings.arabic);
      await tester.tap(find.byTooltip('رابط'));
      await tester.pumpAndSettle();
      expect(find.text('إضافة رابط'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textDirection, TextDirection.ltr, reason: 'URLs read left to right');
      await tester.enterText(find.byType(TextField), 'https://example.com');
      await tester.tap(find.text('موافق'));
      await tester.pumpAndSettle();
      expect(host.calls('command').last, contains('"setLink", {"href":"https://example.com"}'));
    });
  });

  group('bridge', () {
    test('parses change messages and ignores malformed ones', () {
      expect(TiptapMessage.parse(jsonEncode({'type': 'change', 'doc': _doc})), isA<TiptapChanged>());
      expect(TiptapMessage.parse('{"type":"change"}'), isNull);
      expect(TiptapMessage.parse('not json'), isNull);
    });

    test('state maps the page names to the public ones', () {
      final state = AminotesState.fromJson({'canSink': true, 'canLift': true});
      expect(state.canIndent, isTrue);
      expect(state.canOutdent, isTrue);
    });
  });
}
