import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aminotes/aminotes.dart';
import 'package:aminotes/src/media/voice_notes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

Map<String, dynamic> _note(List<Map<String, dynamic>> inline) => {
  'type': 'doc',
  'content': [
    {'type': 'paragraph', 'content': inline},
  ],
};

Map<String, dynamic> _text(String text) => {'type': 'text', 'text': text};

Map<String, dynamic> _voice(String src, [int duration = 3]) => {
  'type': 'voiceNote',
  'attrs': {'src': src, 'duration': duration},
};

void main() {
  late Directory root;
  late FakeHost host;
  late _FakeRecorder recorder;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aminotes_media');
    AminotesMedia.store = MediaStore(rootDir: root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  AminotesController controllerWith({Map<String, dynamic>? doc, bool allowMic = true, Duration? max}) {
    final controller = AminotesController(
      initialContent: AminotesContent.json(doc ?? _note([_text('Hi')])),
      maxVoiceNoteDuration: max ?? const Duration(minutes: 10),
      hostFactory: (onMessage) => host = FakeHost(onMessage),
      recorderFactory: (store) => recorder = _FakeRecorder(allowed: allowMic),
    );
    addTearDown(controller.dispose);
    return controller;
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

  Future<void> tapRecord(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.byTooltip('Record voice note'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('Record voice note'));
    await tester.pump();
  }

  group('recording', () {
    testWidgets('mic → recording bar → Done inserts the voice note at the cursor', (tester) async {
      final controller = controllerWith();
      await pumpEditing(tester, controller);
      await tapRecord(tester);
      expect(recorder.started, isTrue);
      expect(controller.recording.value, isNotNull);
      expect(find.byType(AminotesRecordingBar), findsOneWidget);
      expect(find.byTooltip('Bold'), findsNothing, reason: 'the bar replaces the toolbar');

      recorder.fakeElapsed = const Duration(seconds: 7);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('0:07'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(controller.recording.value, isNull);
      expect(find.byType(AminotesRecordingBar), findsNothing);
      expect(
        host.calls('command').last,
        'window.tiptap && window.tiptap.command("insertVoiceNote", {"src":"local:voice_notes/test.m4a","duration":7});',
      );
    });

    testWidgets('Cancel throws the recording away', (tester) async {
      final controller = controllerWith();
      await pumpEditing(tester, controller);
      await tapRecord(tester);
      await tester.tap(find.byTooltip('Cancel recording'));
      await tester.pump();
      expect(recorder.cancelled, isTrue);
      expect(controller.recording.value, isNull);
      expect(host.calls('command').where((s) => s.contains('insertVoiceNote')), isEmpty);
    });

    testWidgets('a refused microphone shows a message', (tester) async {
      final controller = controllerWith(allowMic: false);
      await pumpEditing(tester, controller);
      await tapRecord(tester);
      expect(controller.recording.value, isNull);
      expect(find.text('Allow microphone access to record voice notes.'), findsOneWidget);
    });

    testWidgets('toolbarVisible stays true while recording, even without focus', (tester) async {
      final controller = controllerWith();
      await pumpEditing(tester, controller);
      expect(controller.toolbarVisible.value, isTrue);
      await controller.startVoiceNote();
      // E.g. Android's permission dialog took focus from the note.
      host.postFromPage('{"type":"state","focused":false}');
      await tester.pump();
      expect(controller.toolbarVisible.value, isTrue);
      await controller.cancelVoiceNote();
      expect(controller.toolbarVisible.value, isFalse);
    });

    testWidgets('a recording stops and is inserted at the time limit', (tester) async {
      final controller = controllerWith(max: const Duration(seconds: 30));
      await pumpEditing(tester, controller);
      expect(await controller.startVoiceNote(), AminotesRecordResult.started);
      recorder.fakeElapsed = const Duration(seconds: 30);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(controller.recording.value, isNull);
      expect(host.calls('command').last, contains('"duration":30'));
    });
  });

  group('AminotesMedia', () {
    test('sources and replaceSources', () {
      final doc = _note([_voice('local:voice_notes/a.m4a'), _text(' and '), _voice('https://cdn/b.m4a')]);
      expect(AminotesMedia.sources(doc), {'local:voice_notes/a.m4a', 'https://cdn/b.m4a'});
      final replaced = AminotesMedia.replaceSources(doc, {'local:voice_notes/a.m4a': 'https://cdn/a.m4a'});
      expect(AminotesMedia.sources(replaced), {'https://cdn/a.m4a', 'https://cdn/b.m4a'});
      expect(AminotesMedia.sources(doc), contains('local:voice_notes/a.m4a'), reason: 'the input is untouched');
    });

    test('pendingUploads lists local files once, with their bytes', () async {
      Directory('${root.path}/voice_notes').createSync();
      File('${root.path}/voice_notes/a.m4a').writeAsBytesSync([1, 2, 3]);
      final doc = _note([
        _voice('local:voice_notes/a.m4a'),
        _voice('local:voice_notes/a.m4a'),
        _voice('https://x/y.m4a'),
      ]);
      final pending = await AminotesMedia.pendingUploads(doc);
      expect(pending, hasLength(1));
      expect(pending.single.kind, 'voiceNote');
      expect(pending.single.mimeType, 'audio/mp4');
      expect(pending.single.fileName, 'a.m4a');
      expect(await pending.single.read(), Uint8List.fromList([1, 2, 3]));
    });

    test('unusedLocalFiles finds recordings no note uses', () async {
      Directory('${root.path}/voice_notes').createSync();
      for (final name in ['used.m4a', 'orphan.m4a']) {
        File('${root.path}/voice_notes/$name').writeAsStringSync('x');
      }
      final unused = await AminotesMedia.unusedLocalFiles([
        _note([_voice('local:voice_notes/used.m4a')]),
      ]);
      expect(unused, ['${root.path}/voice_notes/orphan.m4a']);
    });

    test('local paths never escape the store', () async {
      expect(await AminotesMedia.store.fileFor('local:../secret'), isNull);
    });
  });

  group('uploads', () {
    testWidgets('uploadPendingMedia uploads, swaps the URLs, and keeps failures local', (tester) async {
      Directory('${root.path}/voice_notes').createSync();
      File('${root.path}/voice_notes/ok.m4a').writeAsStringSync('ok');
      File('${root.path}/voice_notes/bad.m4a').writeAsStringSync('bad');
      final doc = _note([_voice('local:voice_notes/ok.m4a'), _voice('local:voice_notes/bad.m4a')]);
      final controller = controllerWith(doc: doc);
      await pumpEditing(tester, controller);
      host.replyDoc = doc;

      Object? error;
      Map<String, dynamic>? result;
      await tester.runAsync(() async {
        try {
          result = await controller.uploadPendingMedia((upload) async {
            if (upload.fileName == 'bad.m4a') throw const SocketException('offline');
            return 'https://cdn/${upload.fileName}';
          });
        } catch (e) {
          error = e;
        }
      });
      expect(error, isA<SocketException>(), reason: 'the failure is reported');
      expect(result, isNull);
      final swap = host.calls('replaceSources').single;
      expect(jsonDecode(swap.substring(swap.indexOf('(') + 1, swap.lastIndexOf(')'))), {
        'local:voice_notes/ok.m4a': 'https://cdn/ok.m4a',
      });
    });

    test('before an editor is shown, replaceMediaSources updates the stored note', () async {
      final controller = controllerWith(doc: _note([_voice('local:voice_notes/a.m4a')]));
      controller.replaceMediaSources({'local:voice_notes/a.m4a': 'https://cdn/a.m4a'});
      expect(AminotesMedia.sources(await controller.getJson()), {'https://cdn/a.m4a'});
    });
  });
}

/// Stands in for the microphone.
class _FakeRecorder implements VoiceNoteRecorder {
  @override
  void Function(Object error)? onFailed;
  _FakeRecorder({required this.allowed});

  final bool allowed;
  bool started = false;
  bool cancelled = false;
  Duration fakeElapsed = Duration.zero;

  @override
  MediaStore get store => throw UnimplementedError();

  @override
  bool get isRecording => started && !cancelled;

  @override
  Duration get elapsed => fakeElapsed;

  @override
  Stream<double> levels() => const Stream.empty();

  @override
  Future<bool> start() async => started = allowed;

  @override
  Future<({String src, int duration})?> stop() async =>
      (src: 'local:voice_notes/test.m4a', duration: fakeElapsed.inSeconds);

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  void dispose() {}
}
