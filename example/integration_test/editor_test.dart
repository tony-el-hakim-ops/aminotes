// Integration tests: the package with the real Tiptap editor page, in a real
// WebView (Android/iOS) or iframe (Chrome). Unlike the package's widget tests
// (a fake page), these catch problems between Dart and the page.
//
// Android: tool/integration_android.sh [device]  (grants the microphone)
// iOS:     flutter test integration_test -d <device>
// Chrome:  tool/integration_web.sh               (fake microphone, chromedriver)
import 'dart:async';
import 'dart:convert';

import 'package:aminotes/aminotes.dart';
// ignore: implementation_imports
import 'package:aminotes/src/media/playable_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  // Draw frames as the app would (by default a test only draws when it
  // pumps): moving the editor between widgets takes a few frames on its own.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('Loading', () {
    testWidgets('a JSON note loads and comes back unchanged', (tester) async {
      final sample = jsonDecode(await rootBundle.loadString('assets/sample_note.json')) as Map<String, dynamic>;
      final controller = await openEditor(tester, content: AminotesContent.json(sample));

      expect(await controller.getJson(), sample);
      // The page counts words the same way as AminotesStats in Dart, and the
      // count is there from the start.
      await waitFor(tester, () => controller.state.value.stats == AminotesStats.of(sample), 'stats');
    });

    testWidgets('text and HTML notes are converted', (tester) async {
      final controller = await openEditor(tester, content: const AminotesContent.text('One\nTwo'));
      expect(paragraphs(await controller.getJson()), ['One', 'Two']);

      await controller.load(const AminotesContent.html('<p><strong>Hi</strong> there</p>'));
      final doc = await controller.getJson();
      expect(paragraphs(doc), ['Hi there']);
      expect(marksOf(doc, 'Hi'), ['bold']);
    });

    testWidgets('content from a newer web app survives an edit', (tester) async {
      final controller = await openEditor(tester, content: const AminotesContent.json(webOnlyNote));
      await controller.insertText('Edited ');
      final doc = await controller.getJson();

      final content = doc['content'] as List;
      expect(content[1], (webOnlyNote['content'] as List)[1], reason: 'the unknown callout block is untouched');
      final first = content[0] as Map;
      expect(first['attrs'], {'textAlign': 'center'}, reason: 'the unknown attribute is kept');
      expect((first['content'] as List).first, {'type': 'text', 'text': 'Edited Hi '});
      expect(jsonEncode(first), contains('"mention"'));
      expect(jsonEncode(first), contains('"superscript"'));
    });

    testWidgets('a note that breaks the schema is read-only and kept unchanged', (tester) async {
      final errors = <AminotesError>[];
      final controller = await openEditor(tester, content: const AminotesContent.json(brokenNote), onError: errors.add);
      await waitFor(tester, () => controller.state.value.loadFailed, 'loadFailed');
      await controller.insertText('nope');
      expect(await controller.getJson(), brokenNote);
      expect(errors.map((e) => e.kind), contains(AminotesErrorKind.load));
    });
  });

  group('Editing', () {
    testWidgets('formatting commands change the real document, and undo works', (tester) async {
      final controller = await openEditor(tester);
      await controller.toggleBold();
      await controller.insertText('Bold');
      await waitFor(tester, () => controller.state.value.isActive('bold'), 'bold active');
      await controller.toggleBold();
      await controller.insertText(' plain');

      var doc = await controller.getJson();
      expect(marksOf(doc, 'Bold'), ['bold']);
      expect(marksOf(doc, ' plain'), isEmpty);

      await waitFor(tester, () => controller.state.value.canUndo, 'canUndo');
      await controller.undo();
      doc = await controller.getJson();
      expect(paragraphs(doc).single, isNot(contains('plain')));
    });

    testWidgets('lists, checklists, headings and tables', (tester) async {
      final controller = await openEditor(tester);
      await controller.toggleHeading(2);
      await controller.insertText('Title');
      await controller.insertTable(rows: 2, columns: 2);
      await controller.addRowAfter();
      final doc = await controller.getJson();
      final types = (doc['content'] as List).map((n) => (n as Map)['type']).toList();
      expect(types, containsAllInOrder(['heading', 'table']));
      expect(await controller.debugEvaluate("document.querySelectorAll('.ProseMirror tr').length"), 3);
    });

    testWidgets('links are added, and taps on them reach onLinkTap', (tester) async {
      final links = <String>[];
      final controller = await openEditor(tester, onLinkTap: links.add);
      await controller.setLink('https://flutter.dev');
      expect(marksOf(await controller.getJson(), 'https://flutter.dev'), ['link']);

      await controller.debugEvaluate("document.querySelector('.ProseMirror a').click()");
      await waitFor(tester, () => links.isNotEmpty, 'onLinkTap');
      expect(links.single, 'https://flutter.dev');
    });

    testWidgets('a javascript: link is neutralized and never reported', (tester) async {
      final links = <String>[];
      final controller = await openEditor(
        tester,
        onLinkTap: links.add,
        content: const AminotesContent.json({
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {
                  'type': 'text',
                  'text': 'evil',
                  'marks': [
                    {
                      'type': 'link',
                      'attrs': {'href': 'javascript:alert(1)'},
                    },
                  ],
                },
              ],
            },
          ],
        }),
      );
      expect(await controller.debugEvaluate("document.querySelector('.ProseMirror a').getAttribute('href')"), '');
      await controller.debugEvaluate("document.querySelector('.ProseMirror a').click()");
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(links, isEmpty);
    });
  });

  group('Saving', () {
    testWidgets('edits reach onChanged; flush and close return the latest text', (tester) async {
      final changes = <Map<String, dynamic>>[];
      final controller = await openEditor(tester, onChanged: changes.add, dispose: false);
      await controller.insertText('Hello');
      await waitFor(tester, () => changes.isNotEmpty, 'onChanged after typing pauses');

      await controller.insertText(' now');
      await controller.flush();
      await waitFor(tester, () => paragraphs(changes.last).first == 'Hello now', 'flushed change');

      await controller.insertText('!');
      final saved = await controller.close();
      expect(paragraphs(saved).first, 'Hello now!');
    });

    testWidgets('going to the background saves edits right away', (tester) async {
      final changes = <Map<String, dynamic>>[];
      // Long typing pause: a change arriving early can only come from the flush.
      final controller = await openEditor(tester, onChanged: changes.add, changeDelay: const Duration(seconds: 30));
      await controller.insertText('Before the call');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await waitFor(tester, () => changes.isNotEmpty, 'flush on hide', timeout: const Duration(seconds: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(paragraphs(changes.last).first, 'Before the call');
    });

    testWidgets('typing, saving and dialogs never reload the editor page', (tester) async {
      final changes = <Map<String, dynamic>>[];
      // A text note turns into JSON on the first save: that once reloaded the
      // web iframe mid-typing.
      final controller = await openEditor(tester, content: const AminotesContent.text('Plain'), onChanged: changes.add);
      await controller.insertText('More ');
      await waitFor(tester, () => changes.isNotEmpty, 'first save');
      await openAndCloseDialog(tester);
      await controller.insertText('and more ');
      await controller.flush();
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(controller.debugPageLoads, 1);
    });
  });

  group('Box and full screen', () {
    testWidgets('full screen and back keep the text (and, off the web, undo)', (tester) async {
      final controller = await openEditor(tester, content: const AminotesContent.text('Start'));
      await controller.insertText('Box ');

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: AminotesEditor(controller: controller)),
          ),
        ),
      );
      await settle(tester);
      await controller.insertText('Full ');
      navigator.pop();
      await settle(tester);

      // The cursor stays where it was (on the web the page reloads, and the
      // controller puts the cursor back).
      expect(paragraphs(await controller.getJson()).first, 'Box Full Start');
      if (!kIsWeb) {
        // On Android/iOS the same WebView moves between the editors.
        expect(controller.debugPageLoads, 1);
        await controller.undo();
        expect(paragraphs(await controller.getJson()).first, 'Box Start');
      }
    });

    testWidgets('a note taller than its box scrolls inside it, even in a scrolling list', (tester) async {
      final controller = AminotesController(
        initialContent: AminotesContent.text(List.generate(40, (i) => 'Line ${i + 1}').join('\n')),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AminotesEditor(controller: controller, autoHeight: true, minHeight: 100, maxHeight: 250),
                // Enough below it for the list itself to scroll.
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await waitFor(tester, () => controller.state.value.ready, 'editor ready', timeout: const Duration(seconds: 30));
      await waitFor(tester, () => (controller.contentHeight.value ?? 0) > 250, 'content taller than the box');
      await settle(tester);
      final page = await controller.debugEvaluate(
        '[document.scrollingElement.scrollHeight, document.scrollingElement.clientHeight, window.innerHeight]',
      );
      expect((page! as List)[0] as num, greaterThan((page as List)[1] as num), reason: 'the page overflows: $page');

      await tester.drag(find.byType(AminotesEditor), const Offset(0, -150));
      await settle(tester);
      final scrollTop = await controller.debugEvaluate('document.scrollingElement.scrollTop');
      expect(scrollTop as num, greaterThan(0), reason: 'the note scrolled inside its box (page: $page)');
      expect(tester.getTopLeft(find.byType(AminotesEditor)).dy, 16, reason: 'the list did not scroll');
      // On the web the browser scrolls the iframe itself (finger or wheel);
      // Flutter's simulated drags never reach inside it, so this is for
      // Android/iOS, where the package routes the drags.
    }, skip: kIsWeb);

    testWidgets('autoHeight sizes the editor to the note', (tester) async {
      final controller = await openEditor(
        tester,
        content: const AminotesContent.text('One\nTwo\nThree\nFour'),
        autoHeight: true,
      );
      await waitFor(tester, () => controller.contentHeight.value != null, 'contentHeight');
      await settle(tester);
      final height = tester.getSize(find.byType(AminotesEditor)).height;
      expect(height, closeTo(controller.contentHeight.value!, 1));
      expect(height, greaterThan(60), reason: 'four lines are taller than the minimum');
    });

    testWidgets('a dialog over the editor turns off the page clicks while open', (tester) async {
      final controller = await openEditor(tester);
      Future<Object?> pointerEvents() => controller.debugEvaluate('window.frameElement.style.pointerEvents');
      await openAndCloseDialog(tester, whileOpen: () async => expect(await pointerEvents(), 'none'));
      expect(await pointerEvents(), 'auto');
    }, skip: !kIsWeb); // Only the web's iframe takes clicks meant for Flutter.
  });

  group('Look', () {
    testWidgets('Arabic direction and dark mode reach the page', (tester) async {
      final controller = await openEditor(
        tester,
        content: const AminotesContent.text('مرحبا بكم'),
        rtl: true,
        dark: true,
      );
      Future<Object?> look() =>
          controller.debugEvaluate('[document.documentElement.dir, document.documentElement.dataset.brightness]');
      await waitForAsync(tester, () async => listEquals(await look() as List?, ['rtl', 'dark']), 'rtl + dark');
    });
  });

  group('Design', () {
    testWidgets('custom CSS and an app font apply in the page', (tester) async {
      final controller = await openEditor(
        tester,
        content: const AminotesContent.html('<h1>Big</h1><p>Handwritten</p>'),
        theme: const AminotesTheme(
          fontFamily: 'Caveat',
          fontSize: 20,
          fonts: [AminotesFont('Caveat', 'assets/fonts/Caveat.ttf')],
          css: '.ProseMirror h1 { font-size: 3em; }',
        ),
      );
      await waitForAsync(
        tester,
        () async =>
            await controller.debugEvaluate("document.fonts.ready.then(() => document.fonts.check('20px Caveat'))") ==
            true,
        'Caveat loaded in the page',
      );
      final h1 = await controller.debugEvaluate(
        "[getComputedStyle(document.querySelector('.ProseMirror h1')).fontSize, "
        "getComputedStyle(document.querySelector('.ProseMirror p')).fontFamily]",
      );
      expect(h1, ['60px', contains('Caveat')]);
    });
  });

  group('Media', () {
    testWidgets('an image shows in the page', (tester) async {
      final controller = await openEditor(tester);
      if (kIsWeb) {
        await controller.insertImage('data:image/png;base64,$redPixelPng');
      } else {
        // Stored on the device (local:) and handed to the page for display.
        final src = await controller.insertImageBytes(base64Decode(redPixelPng), extension: 'png');
        expect(src, startsWith('local:images/'));
      }
      await waitForAsync(
        tester,
        () async =>
            await controller.debugEvaluate(
              "(() => { const img = document.querySelector('.ProseMirror img'); return !!img && img.complete && img.naturalWidth > 0; })()",
            ) ==
            true,
        'image rendered',
      );
    });

    testWidgets('an image can be resized with a corner handle, by touch', (tester) async {
      final controller = await openEditor(tester);
      // A 400 x 200 picture, made in the page.
      final png = await controller.debugEvaluate(
        "(() => { const c = document.createElement('canvas'); c.width = 400; c.height = 200; "
        "const g = c.getContext('2d'); g.fillStyle = '#3f51b5'; g.fillRect(0, 0, 400, 200); return c.toDataURL(); })()",
      );
      await controller.insertImage(png! as String);
      await waitForAsync(
        tester,
        () async =>
            await controller.debugEvaluate("document.querySelector('.ProseMirror img')?.complete === true") == true,
        'image loaded',
      );
      final before = await controller.debugEvaluate("document.querySelector('.ProseMirror img').offsetWidth") as num;

      // Drag the bottom-right handle 100 px to the left with a finger (the
      // browser's mouse where touch events don't exist).
      await controller.debugEvaluate('''(() => {
        const handle = document.querySelector("[data-resize-handle='bottom-right']");
        const box = handle.getBoundingClientRect();
        const x = box.left + box.width / 2, y = box.top + box.height / 2;
        if (typeof TouchEvent === 'function' && typeof Touch === 'function') {
          const touch = (target, dx) => new Touch({ identifier: 1, target, clientX: x + dx, clientY: y });
          handle.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, cancelable: true, touches: [touch(handle, 0)] }));
          document.dispatchEvent(new TouchEvent('touchmove', { bubbles: true, cancelable: true, touches: [touch(document.body, -100)] }));
          document.dispatchEvent(new TouchEvent('touchend', { bubbles: true, cancelable: true, touches: [] }));
          return 'touch';
        }
        handle.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, clientX: x, clientY: y }));
        document.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: x - 100, clientY: y }));
        document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, clientX: x - 100, clientY: y }));
        return 'mouse';
      })()''');

      final image = ((await controller.getJson())['content'] as List).cast<Map>().firstWhere(
        (n) => n['type'] == 'image',
      );
      final attrs = image['attrs'] as Map;
      expect(attrs['width'], closeTo(before - 100, 2), reason: 'saved in the note');
      expect(attrs['height'], closeTo((before - 100) / 2, 2), reason: 'keeps the proportions');
      // Saved sizes survive reopening the note.
      await controller.load(AminotesContent.json(await controller.getJson()));
      await waitForAsync(
        tester,
        () async =>
            await controller.debugEvaluate("document.querySelector('.ProseMirror img')?.offsetWidth") == attrs['width'],
        'size restored',
      );
    });

    testWidgets('an image can be aligned right, in the JSON and on screen', (tester) async {
      final controller = await openEditor(tester);
      // A small picture (narrower than the note), between two paragraphs.
      final png = await controller.debugEvaluate(
        "(() => { const c = document.createElement('canvas'); c.width = 100; c.height = 50; "
        "c.getContext('2d').fillRect(0, 0, 100, 50); return c.toDataURL(); })()",
      );
      await controller.load(
        AminotesContent.json({
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'A'},
              ],
            },
            {
              'type': 'image',
              'attrs': {'src': png},
            },
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'B'},
              ],
            },
          ],
        }),
      );
      await waitForAsync(
        tester,
        () async =>
            await controller.debugEvaluate("document.querySelector('.ProseMirror img')?.complete === true") == true,
        'image loaded',
      );
      // Select across the image, as tapping it would, and align it.
      await controller.debugEvaluate('window.tiptap.setSelection({from: 1, to: 6})');
      await controller.setImageAlignment(AminotesImageAlignment.right);

      final image = ((await controller.getJson())['content'] as List).cast<Map>()[1];
      expect((image['attrs'] as Map)['align'], 'right');
      final gap = await controller.debugEvaluate(
        "document.querySelector('.ProseMirror').getBoundingClientRect().right - "
        "document.querySelector('.ProseMirror img').getBoundingClientRect().right",
      );
      expect(gap as num, lessThan(2), reason: 'against the right edge of the note');
    });

    testWidgets('tapping a voice note plays it through the app, to the end', (tester) async {
      final controller = await openEditor(tester);
      final wav = silentWav(const Duration(milliseconds: 1200));
      final src = kIsWeb
          ? 'data:audio/wav;base64,${base64Encode(wav)}'
          : await AminotesMedia.store.saveBytes('voice_notes', 'wav', wav);
      await controller.execute('insertVoiceNote', {'src': src, 'duration': 1});

      await controller.debugEvaluate("document.querySelector('.voice-note button').click()");
      await waitFor(tester, () => controller.playback.value?.playing == true, 'playing');
      expect(controller.toolbarVisible.value, isTrue, reason: 'the player bar shows');
      await waitFor(tester, () => controller.playback.value == null, 'played to the end');
    });

    testWidgets('recording inserts a voice note', (tester) async {
      final errors = <AminotesError>[];
      final controller = await openEditor(tester, onError: errors.add);
      final result = await controller.startVoiceNote();
      expect(
        result,
        AminotesRecordResult.started,
        reason: 'grant the microphone first (tool/integration_android.sh does)',
      );
      await pumpFor(tester, const Duration(milliseconds: 1500));
      final src = await controller.finishVoiceNote();
      expect(src, isNotNull, reason: 'errors: $errors');
      expect(jsonEncode(await controller.getJson()), contains('"voiceNote"'));
      if (kIsWeb) {
        // Whatever this browser recorded, the note now holds a format every
        // device plays.
        final info = await decodeInPage(controller, src!);
        expect(info[0], anyOf('audio/mp4', 'audio/wav'), reason: 'errors: $errors');
      }
    });

    testWidgets('web recordings are converted to AAC, or WAV, that decode', (tester) async {
      final controller = await openEditor(tester);
      // A 1.2 s Opus clip in WebM, recorded in the page: what Firefox makes,
      // and what iPhones can't play.
      Future<String> opusClip() async => await controller.debugEvaluate(
        '(async () => { const ctx = new AudioContext(); const dest = ctx.createMediaStreamDestination(); '
        'const osc = ctx.createOscillator(); osc.connect(dest); osc.start(); '
        'const rec = new MediaRecorder(dest.stream, {mimeType: "audio/webm;codecs=opus"}); const parts = []; '
        'rec.ondataavailable = (e) => parts.push(e.data); rec.start(); '
        'await new Promise((r) => setTimeout(r, 1200)); rec.stop(); await new Promise((r) => (rec.onstop = r)); '
        'osc.stop(); ctx.close(); return URL.createObjectURL(new Blob(parts, {type: "audio/webm"})); })()',
      ) as String;

      final best = await makePlayableEverywhere(await opusClip());
      expect(best, isNotNull);
      expect(best!.mimeType, anyOf('audio/mp4', 'audio/wav'));
      // Which path this browser took, saved by the driver to
      // build/integration_response_data.json.
      IntegrationTestWidgetsFlutterBinding.instance.reportData = {'webRecordingFormat': best.mimeType};
      var info = await decodeInPage(controller, best.src);
      expect(info[0], best.mimeType);
      expect(info[1] as num, closeTo(1.2, 0.4), reason: 'about as long as the recording');

      // The fallback, which browsers without an AAC encoder (Firefox) use.
      final wav = await makePlayableEverywhere(await opusClip(), fallback: true);
      expect(wav!.mimeType, 'audio/wav');
      info = await decodeInPage(controller, wav.src);
      expect(info[1] as num, closeTo(1.2, 0.4));

      // Audio that already plays everywhere is left alone.
      expect(await makePlayableEverywhere(wav.src), isNull);
    }, skip: !kIsWeb);
  });
}

// ---------------------------------------------------------------------------
// Helpers

Future<AminotesController> openEditor(
  WidgetTester tester, {
  AminotesContent content = AminotesContent.empty,
  ValueChanged<Map<String, dynamic>>? onChanged,
  ValueChanged<String>? onLinkTap,
  ValueChanged<AminotesError>? onError,
  Duration changeDelay = const Duration(milliseconds: 400),
  bool autoHeight = false,
  bool rtl = false,
  bool dark = false,
  bool dispose = true,
  AminotesTheme? theme,
}) async {
  final controller = AminotesController(
    initialContent: content,
    onChanged: onChanged,
    onLinkTap: onLinkTap,
    onError: onError,
    changeDelay: changeDelay,
  );
  if (dispose) addTearDown(controller.dispose);
  final editor = AminotesEditor(
    controller: controller,
    theme: theme,
    autoHeight: autoHeight,
    minHeight: 60,
    maxHeight: 600,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: SafeArea(
            child: autoHeight ? Align(alignment: Alignment.topCenter, child: editor) : editor,
          ),
        ),
      ),
    ),
  );
  await waitFor(tester, () => controller.state.value.ready, 'editor ready', timeout: const Duration(seconds: 30));
  return controller;
}

/// Fetches a `blob:` URL inside the editor page (same origin) and decodes it
/// like a player would: `[mime type, seconds]`.
Future<List<Object?>> decodeInPage(AminotesController controller, String src) async => await controller.debugEvaluate(
  '(async () => { const blob = await (await fetch(${jsonEncode(src)})).blob(); '
  'const audio = await new OfflineAudioContext(1, 1, 44100).decodeAudioData(await blob.arrayBuffer()); '
  'return [blob.type, audio.duration]; })()',
) as List<Object?>;

/// Pumps frames until [condition] holds (the page answers asynchronously).
Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await pumpFor(tester, const Duration(milliseconds: 100));
  }
}

Future<void> waitForAsync(
  WidgetTester tester,
  Future<bool> Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await pumpFor(tester, const Duration(milliseconds: 200));
  }
}

Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  await Future<void>.delayed(duration);
  await tester.pump();
}

/// Lets routes animate and the editor move between widgets.
Future<void> settle(WidgetTester tester) => pumpFor(tester, const Duration(milliseconds: 800));

Future<void> openAndCloseDialog(WidgetTester tester, {Future<void> Function()? whileOpen}) async {
  final context = tester.element(find.byType(AminotesEditor).first);
  unawaited(
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Over the note')),
    ),
  );
  await settle(tester);
  await whileOpen?.call();
  Navigator.of(context).pop();
  await settle(tester);
}

/// The text of each top-level paragraph or heading.
List<String> paragraphs(Map<String, dynamic> doc) => [
  for (final node in (doc['content'] as List? ?? const []).cast<Map<String, dynamic>>())
    if (node['type'] == 'paragraph' || node['type'] == 'heading')
      (node['content'] as List? ?? const []).map((t) => (t as Map)['text'] ?? '').join(),
];

/// The mark types on the text node with exactly [text].
List<String> marksOf(Map<String, dynamic> doc, String text) {
  List<String>? found;
  void visit(Object? node) {
    if (node is! Map) return;
    if (node['type'] == 'text' && node['text'] == text) {
      found = [for (final mark in (node['marks'] as List? ?? const [])) (mark as Map)['type'] as String];
    }
    (node['content'] as List?)?.forEach(visit);
  }

  visit(doc);
  if (found == null) fail('No text node "$text" in ${jsonEncode(doc)}');
  return found!;
}

/// A mono 8 kHz 16-bit WAV of silence.
Uint8List silentWav(Duration length) {
  const rate = 8000;
  final samples = rate * length.inMilliseconds ~/ 1000;
  final data = ByteData(44 + samples * 2);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  return data.buffer.asUint8List();
}

const redPixelPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==';

const webOnlyNote = <String, dynamic>{
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
  ],
};

const brokenNote = <String, dynamic>{
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
