import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aminotes/aminotes.dart';
import 'package:aminotes/src/bridge/tiptap_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

void main() {
  late Directory root;
  late FakeHost host;
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

  setUp(() {
    root = Directory.systemTemp.createTempSync('aminotes_images');
    AminotesMedia.store = MediaStore(rootDir: root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  AminotesController controllerWith({PickedImage? picked}) {
    final controller = AminotesController(
      hostFactory: (onMessage) => host = FakeHost(onMessage),
      imagePicker: (source) async => picked,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  // Real file I/O completes outside the test's fake clock: alternate real
  // waiting with pumps until [done] or a timeout.
  Future<void> settleIo(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  Future<void> pumpEditing(WidgetTester tester, AminotesController controller) async {
    await tester.pumpWidget(
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
    await tester.pump();
    host.postFromPage('{"type":"ready"}');
    await tester.pump();
    await tester.pump();
    host.postFromPage('{"type":"state","focused":true}');
    await tester.pump();
  }

  testWidgets('toolbar → gallery stores the photo and inserts it at the cursor', (tester) async {
    final controller = controllerWith(
      picked: PickedImage(bytes: jpeg, name: 'IMG_1.JPG'),
    );
    await pumpEditing(tester, controller);
    await tester.scrollUntilVisible(find.byTooltip('Image'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await settleIo(tester, () => host.calls('command').isNotEmpty);

    final insert = host.calls('command').last;
    final src = RegExp(r'"src":"(local:images/[0-9]+\.jpg)"').firstMatch(insert)?.group(1);
    expect(src, isNotNull, reason: insert);
    final file = File('${root.path}/${src!.substring('local:'.length)}');
    expect(file.readAsBytesSync(), jpeg);
  });

  testWidgets('the sheet still opens when closing the keyboard hides the toolbar', (tester) async {
    final controller = controllerWith(
      picked: PickedImage(bytes: jpeg, name: 'a.png'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: AminotesEditor(controller: controller)),
              ValueListenableBuilder(
                valueListenable: controller.toolbarVisible,
                builder: (context, visible, _) =>
                    visible ? AminotesToolbar(controller: controller) : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    host.postFromPage('{"type":"ready"}');
    await tester.pump();
    await tester.pump();
    host.postFromPage('{"type":"state","focused":true}');
    await tester.pump();
    await tester.scrollUntilVisible(find.byTooltip('Image'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('Image'));
    // The page reports the blur: the toolbar goes away.
    host.postFromPage('{"type":"state","focused":false}');
    await tester.pumpAndSettle();
    expect(find.byType(AminotesToolbar), findsNothing);
    await tester.tap(find.text('Choose from gallery'));
    await settleIo(tester, () => host.calls('command').isNotEmpty);
    expect(host.calls('command').last, contains('"src":"local:images/'));
  });

  testWidgets('cancelling the picker inserts nothing', (tester) async {
    final controller = controllerWith();
    await pumpEditing(tester, controller);
    expect(await tester.runAsync(() => controller.pickImage(AminotesImageSource.camera)), isNull);
    expect(host.calls('command'), isEmpty);
  });

  testWidgets('the page gets a data: URL for a local image, or null if missing', (tester) async {
    final controller = controllerWith();
    await pumpEditing(tester, controller);
    Directory('${root.path}/images').createSync();
    File('${root.path}/images/a.png').writeAsBytesSync([1, 2, 3]);

    host.postFromPage('{"type":"resolveMedia","src":"local:images/a.png"}');
    host.postFromPage('{"type":"resolveMedia","src":"local:images/gone.jpg"}');
    await settleIo(tester, () => host.calls('mediaResolved').length == 2);

    final answers = host.calls('mediaResolved').toList();
    expect(
      answers,
      contains(
        'window.tiptap && window.tiptap.mediaResolved("local:images/a.png", "data:image/png;base64,${base64Encode([1, 2, 3])}");',
      ),
    );
    expect(answers, contains('window.tiptap && window.tiptap.mediaResolved("local:images/gone.jpg", null);'));
  });

  test('images are listed for upload with their MIME type', () async {
    Directory('${root.path}/images').createSync();
    File('${root.path}/images/p.png').writeAsBytesSync([9]);
    final doc = {
      'type': 'doc',
      'content': [
        {
          'type': 'image',
          'attrs': {'src': 'local:images/p.png', 'alt': null},
        },
        {
          'type': 'image',
          'attrs': {'src': 'https://cdn/x.jpg'},
        },
      ],
    };
    final pending = await AminotesMedia.pendingUploads(doc);
    expect(pending.single.kind, 'image');
    expect(pending.single.mimeType, 'image/png');
    final replaced = AminotesMedia.replaceSources(doc, {'local:images/p.png': 'https://cdn/p.png'});
    expect(AminotesMedia.sources(replaced), {'https://cdn/p.png', 'https://cdn/x.jpg'});
  });

  test('bridge parses resolveMedia', () {
    expect(
      (TiptapMessage.parse('{"type":"resolveMedia","src":"local:images/a.png"}')! as TiptapResolveMedia).src,
      'local:images/a.png',
    );
  });
}
