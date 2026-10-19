import 'dart:convert';

import 'package:aminotes/aminotes.dart';
import 'package:aminotes/src/media/voice_notes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

const _doc = {
  'type': 'doc',
  'content': [
    {
      'type': 'paragraph',
      'content': [
        {'type': 'text', 'text': 'Preview me'},
      ],
    },
  ],
};

void main() {
  late FakeHost host;
  late _FakeRecorder recorder;

  AminotesController controllerWith({
    ValueChanged<Map<String, dynamic>>? onChanged,
    ValueChanged<String>? onLinkTap,
    ValueChanged<AminotesError>? onError,
    bool saveRecording = true,
  }) => AminotesController(
    initialContent: const AminotesContent.json(_doc),
    onChanged: onChanged,
    onLinkTap: onLinkTap,
    onError: onError,
    saveRecordingWhenInterrupted: saveRecording,
    hostFactory: (onMessage) => host = FakeHost(onMessage),
    recorderFactory: (_) => recorder = _FakeRecorder(),
  );

  Future<void> pumpEditor(WidgetTester tester, AminotesController controller, {Widget Function(Widget)? wrap}) async {
    final editor = AminotesEditor(controller: controller, autoHeight: true, minHeight: 60, maxHeight: 300);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topCenter, child: wrap?.call(editor) ?? editor),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> ready(WidgetTester tester) async {
    host.postFromPage('{"type":"ready"}');
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the note shows as a preview until the editor page is ready', (tester) async {
    final controller = controllerWith();
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    expect(find.byType(AminotesPreview), findsOneWidget);
    expect(find.textContaining('Preview me', findRichText: true), findsOneWidget);
    await ready(tester);
    expect(find.byType(AminotesPreview), findsNothing);
  });

  testWidgets('the editor view survives the note turning into JSON', (tester) async {
    // A text note becomes JSON after the first edit. If that changed the
    // widgets around the view, the web iframe would reload mid-typing.
    final controller = AminotesController(
      initialContent: const AminotesContent.text('Plain'),
      onChanged: (_) {},
      hostFactory: (onMessage) => host = FakeHost(onMessage),
    );
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);
    final view = tester.element(find.byKey(const ValueKey('fake-webview')));
    host.postFromPage(jsonEncode({'type': 'change', 'doc': _doc}));
    await tester.pump();
    expect(tester.element(find.byKey(const ValueKey('fake-webview'))), same(view));
  });

  testWidgets('state sent just before the page counts as ready is kept', (tester) async {
    final controller = controllerWith();
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    host.postFromPage('{"type":"state","stats":{"words":5,"characters":20}}');
    expect(controller.state.value.ready, isFalse);
    await ready(tester);
    expect(controller.state.value.ready, isTrue);
    expect(controller.state.value.stats, const AminotesStats(words: 5, characters: 20));
  });

  testWidgets('the note takes vertical drags only when taller than its box, or while editing', (tester) async {
    // In a scrolling list the list takes vertical drags; the note must get
    // them to scroll (or resize an image) but leave them otherwise.
    final controller = controllerWith();
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);
    host.postFromPage('{"type":"height","value":200}');
    await tester.pumpAndSettle();
    expect(host.claimVerticalDrags, isFalse, reason: 'fits in its box (max 300)');

    host.postFromPage('{"type":"height","value":900}');
    await tester.pumpAndSettle();
    expect(host.claimVerticalDrags, isTrue, reason: 'taller than its box: scrolls inside');

    host.postFromPage('{"type":"height","value":200}');
    host.postFromPage('{"type":"state","focused":true}');
    await tester.pumpAndSettle();
    expect(host.claimVerticalDrags, isTrue, reason: 'being edited');
  });

  testWidgets('autoHeight follows the content between min and max', (tester) async {
    final controller = controllerWith();
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);
    Size size() => tester.getSize(find.byType(AminotesEditor));
    expect(size().height, 60, reason: 'minHeight before the page reports');
    host.postFromPage('{"type":"height","value":140}');
    await tester.pumpAndSettle();
    expect(size().height, 140);
    expect(controller.contentHeight.value, 140);
    host.postFromPage('{"type":"height","value":900}');
    await tester.pumpAndSettle();
    expect(size().height, 300, reason: 'maxHeight; it scrolls inside');
  });

  testWidgets('an autoHeight box keeps its size while another editor shows the note', (tester) async {
    final controller = controllerWith();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              AminotesEditor(controller: controller, autoHeight: true, minHeight: 60, maxHeight: 300),
              SizedBox(height: 400, child: AminotesEditor(controller: controller)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    host.postFromPage('{"type":"height","value":150}');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AminotesEditor).first).height, 150);
  });

  testWidgets('the page takes no clicks while a dialog covers the editor', (tester) async {
    // In a browser the editor is an iframe: it would swallow taps meant for
    // the dialog (e.g. tapping outside it to close it).
    final controller = controllerWith();
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);
    expect(host.interactiveValue, isTrue);

    final context = tester.element(find.byType(AminotesEditor));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Over the note')),
    );
    await tester.pumpAndSettle();
    expect(host.interactiveValue, isFalse);

    await tester.tapAt(const Offset(5, 5)); // outside the dialog
    await tester.pumpAndSettle();
    expect(find.text('Over the note'), findsNothing);
    expect(host.interactiveValue, isTrue);
  });

  testWidgets('link taps reach onLinkTap; page errors reach onError', (tester) async {
    final links = <String>[];
    final errors = <AminotesError>[];
    final controller = controllerWith(onLinkTap: links.add, onError: errors.add);
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);
    host.postFromPage('{"type":"linkTap","href":"https://flutter.dev"}');
    host.postFromPage('{"type":"error","message":"load: Invalid content"}');
    host.postFromPage('{"type":"error","message":"boom"}');
    host.postFromPage('{"type":"error","message":"unsupported-webview: Chrome/52"}');
    expect(links, ['https://flutter.dev']);
    expect(errors.map((e) => e.kind), [AminotesErrorKind.load, AminotesErrorKind.editor, AminotesErrorKind.webView]);
  });

  testWidgets('going to the background flushes edits and saves a recording', (tester) async {
    final controller = controllerWith();
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);
    await controller.startVoiceNote();
    recorder.fakeElapsed = const Duration(seconds: 4);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(host.calls('flush'), isNotEmpty);
    expect(controller.recording.value, isNull);
    expect(
      host.calls('command').last,
      contains('"insertVoiceNote", {"src":"local:voice_notes/test.m4a","duration":4}'),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('an interrupted recording can be discarded instead', (tester) async {
    final controller = controllerWith(saveRecording: false);
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);
    await controller.startVoiceNote();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(recorder.cancelled, isTrue);
    expect(host.calls('command').where((s) => s.contains('insertVoiceNote')), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a recording that fails is ended and reported, never silently lost', (tester) async {
    final errors = <AminotesError>[];
    final controller = controllerWith(onError: errors.add);
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);
    await ready(tester);

    await controller.startVoiceNote();
    recorder.onFailed!(StateError('EncodingError'));
    expect(controller.recording.value, isNull, reason: 'the bar stops counting');
    expect(errors.single.kind, AminotesErrorKind.recording);

    await controller.startVoiceNote();
    recorder.recordedNothing = true;
    expect(await controller.finishVoiceNote(), isNull);
    expect(errors.last.message, 'Nothing was recorded');
    expect(host.calls('command').where((s) => s.contains('insertVoiceNote')), isEmpty);
  });

  testWidgets('dispose flushes, and the last edits still reach onChanged', (tester) async {
    final changes = <Map<String, dynamic>>[];
    final controller = controllerWith(onChanged: changes.add);
    await pumpEditor(tester, controller);
    await ready(tester);
    controller.dispose();
    expect(host.calls('flush'), isNotEmpty);
    expect(host.disposed, isFalse, reason: 'the page gets a moment to answer');
    host.postFromPage(jsonEncode({'type': 'change', 'doc': _doc}));
    expect(changes.single, _doc);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(host.disposed, isTrue);
  });

  testWidgets('close returns the final JSON', (tester) async {
    final controller = controllerWith();
    await pumpEditor(tester, controller);
    await ready(tester);
    host.replyDoc = _doc;
    final json = await tester.runAsync(controller.close);
    expect(json, _doc);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('preload starts the editor page before it is shown', (tester) async {
    final controller = controllerWith();
    addTearDown(controller.dispose);
    controller.preload();
    expect(host, isNotNull);
    host.postFromPage('{"type":"ready"}');
    await tester.pump();
    expect(host.calls('setContent'), isNotEmpty);
  });
}

class _FakeRecorder implements VoiceNoteRecorder {
  @override
  void Function(Object error)? onFailed;
  bool started = false;
  bool cancelled = false;
  Duration fakeElapsed = Duration.zero;
  bool recordedNothing = false;

  @override
  MediaStore get store => throw UnimplementedError();
  @override
  bool get isRecording => started;
  @override
  Duration get elapsed => fakeElapsed;
  @override
  Stream<double> levels() => const Stream.empty();
  @override
  Future<bool> start() async => started = true;
  @override
  Future<({String src, int duration})?> stop() async =>
      recordedNothing ? null : (src: 'local:voice_notes/test.m4a', duration: fakeElapsed.inSeconds);
  @override
  Future<void> cancel() async => cancelled = true;
  @override
  void dispose() {}
}
