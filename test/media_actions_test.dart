import 'dart:async';
import 'dart:convert';

import 'package:aminotes/aminotes.dart';
import 'package:aminotes/src/media/voice_notes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;
  late _FakeAudio audio;

  Future<AminotesController> pumpEditing(WidgetTester tester) async {
    final controller = AminotesController(
      hostFactory: (onMessage) => host = FakeHost(onMessage),
      audioFactory: () => audio = _FakeAudio(),
    );
    addTearDown(controller.dispose);
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
    return controller;
  }

  Iterable<String> commands() => host.calls('command').map((s) => RegExp(r'command\("(\w+)"').firstMatch(s)!.group(1)!);

  Future<void> tapPill(WidgetTester tester, {String key = 'vn0', int duration = 12}) async {
    host.postFromPage(
      jsonEncode({'type': 'voiceNoteToggle', 'key': key, 'src': 'local:voice_notes/a.m4a', 'duration': duration}),
    );
    await tester.pump();
  }

  group('voice note playback', () {
    testWidgets('tapping a pill plays it and shows the playback bar', (tester) async {
      final controller = await pumpEditing(tester);
      expect(controller.toolbarVisible.value, isFalse);
      await tapPill(tester);
      expect(audio.played, ['local:voice_notes/a.m4a']);
      expect(controller.playback.value?.playing, isTrue);
      expect(controller.playback.value?.duration, const Duration(seconds: 12));
      expect(controller.toolbarVisible.value, isTrue, reason: 'the player shows even when not editing');
      expect(find.byType(AminotesPlaybackBar), findsOneWidget);
      expect(host.calls('voiceNotePlayback').last, contains('("vn0", true, 0.0)'));

      audio.position(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('0:03'), findsOneWidget);
      expect(host.calls('voiceNotePlayback').last, contains('("vn0", true, 3.0)'), reason: 'the pill shows the time');

      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(audio.log.last, 'pause');
      expect(controller.playback.value?.playing, isFalse);
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(audio.log.last, 'resume');
    });

    testWidgets('seeking is clamped to the note, and finishing hides the bar', (tester) async {
      final controller = await pumpEditing(tester);
      await tapPill(tester, duration: 10);
      await controller.seekVoiceNote(const Duration(seconds: 30));
      expect(audio.log.last, 'seek 0:00:10.000000');
      await controller.seekVoiceNote(const Duration(seconds: -2));
      expect(audio.log.last, 'seek 0:00:00.000000');

      audio.complete();
      await tester.pump();
      expect(controller.playback.value, isNull);
      expect(find.byType(AminotesPlaybackBar), findsNothing);
      expect(host.calls('voiceNotePlayback').last, contains('("vn0", false, null)'));
    });

    testWidgets('dragging the slider seeks once, on release', (tester) async {
      await pumpEditing(tester);
      await tapPill(tester, duration: 10);
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pump();
      expect(audio.log.where((entry) => entry.startsWith('seek')), hasLength(1));
    });

    testWidgets('playing another note stops the first one', (tester) async {
      final controller = await pumpEditing(tester);
      await tapPill(tester);
      await tapPill(tester, key: 'vn1');
      expect(controller.playback.value?.key, 'vn1');
      expect(host.calls('voiceNotePlayback').map((s) => s.contains('("vn0", false')).contains(true), isTrue);
    });

    testWidgets('Delete removes the playing voice note from the note', (tester) async {
      final controller = await pumpEditing(tester);
      await tapPill(tester);
      await tester.tap(find.byTooltip('Delete voice note'));
      await tester.pump();
      expect(controller.playback.value, isNull);
      expect(host.calls('command').last, contains('"deleteVoiceNote", {"key":"vn0"}'));
    });
  });

  group('selected image', () {
    testWidgets('a tapped image gets View and Delete buttons first', (tester) async {
      await pumpEditing(tester);
      host.postFromPage('{"type":"state","focused":true}');
      await tester.pump();
      expect(find.byTooltip('View image'), findsNothing);

      host.postFromPage(
        '{"type":"state","focused":true,"selectedNode":{"type":"image","src":"https://example.com/a.jpg","alt":"A cat"}}',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Delete image'));
      expect(commands().last, 'deleteSelection');

      await tester.tap(find.byTooltip('View image'));
      await tester.pumpAndSettle();
      final viewer = tester.widget<AminotesImageViewer>(find.byType(AminotesImageViewer));
      expect(viewer.src, 'https://example.com/a.jpg');
      expect(viewer.alt, 'A cat');
      expect(host.calls('blur'), isNotEmpty, reason: 'the keyboard closes for the viewer');
      final deletes = commands().where((c) => c == 'deleteSelection').length;
      await tester.tap(find.byTooltip('Delete image'));
      await tester.pumpAndSettle();
      expect(find.byType(AminotesImageViewer), findsNothing, reason: 'Delete closes the viewer');
      expect(commands().where((c) => c == 'deleteSelection').length, deletes + 1);
    });

    testWidgets('a tapped image can be aligned left, center or right', (tester) async {
      await pumpEditing(tester);
      host.postFromPage(
        '{"type":"state","focused":true,"selectedNode":{"type":"image","src":"https://example.com/a.jpg","align":"center"}}',
      );
      await tester.pump();
      IconButton button(String tooltip) => tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)).first,
      );
      expect(button('Center').isSelected, isTrue, reason: 'shows the current alignment');
      expect(button('Align left').isSelected, isFalse);

      await tester.tap(find.byTooltip('Align right'));
      expect(host.calls('command').last, contains('"setImageAlign", {"align":"right"}'));
      await tester.tap(find.byTooltip('Center'));
      expect(host.calls('command').last, contains('"setImageAlign", {"align":null}'), reason: 'tapping the active one resets');
    });

    testWidgets('a selected voice note can be deleted from the toolbar', (tester) async {
      await pumpEditing(tester);
      host.postFromPage(
        '{"type":"state","focused":true,"selectedNode":{"type":"voiceNote","src":"local:voice_notes/a.m4a","duration":4}}',
      );
      await tester.pump();
      expect(find.byTooltip('View image'), findsNothing);
      await tester.tap(find.byTooltip('Delete voice note'));
      expect(commands().last, 'deleteSelection');
    });
  });

  group('word count', () {
    // The same note as the JS test 'words and characters' (tiptap/scripts/test_note.mjs).
    const note = {
      'type': 'doc',
      'content': [
        {
          'type': 'heading',
          'attrs': {'level': 1},
          'content': [
            {'type': 'text', 'text': 'Shopping'},
          ],
        },
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'bo'},
            {
              'type': 'text',
              'text': 'ld',
              'marks': [
                {'type': 'bold'},
              ],
            },
            {'type': 'text', 'text': ' milk'},
            {'type': 'hardBreak'},
            {'type': 'text', 'text': 'eggs'},
          ],
        },
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'مرحبا بكم'},
            {
              'type': 'voiceNote',
              'attrs': {'src': 'local:voice_notes/a.m4a', 'duration': 3},
            },
            {'type': 'text', 'text': 'end'},
          ],
        },
      ],
    };

    test('counts a saved note like the editor does', () {
      expect(AminotesStats.of(note), const AminotesStats(words: 7, characters: 33));
      expect(AminotesStats.of(const {'type': 'doc'}), const AminotesStats());
    });

    testWidgets('live counts arrive in the state', (tester) async {
      final controller = await pumpEditing(tester);
      host.postFromPage('{"type":"state","stats":{"words":3,"characters":15}}');
      await tester.pump();
      expect(controller.state.value.stats, const AminotesStats(words: 3, characters: 15));
    });
  });
}

class _FakeAudio implements VoiceNoteAudio {
  final played = <String>[];
  final log = <String>[];
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _durations = StreamController<Duration>.broadcast(sync: true);
  final _completions = StreamController<void>.broadcast(sync: true);

  void position(Duration value) => _positions.add(value);
  void complete() => _completions.add(null);

  @override
  Future<void> play(String src) async {
    played.add(src);
    log.add('play');
  }

  @override
  Future<void> pause() async => log.add('pause');
  @override
  Future<void> resume() async => log.add('resume');
  @override
  Future<void> seek(Duration position) async => log.add('seek $position');
  @override
  Future<void> stop() async => log.add('stop');
  @override
  Stream<Duration> get positions => _positions.stream;
  @override
  Stream<Duration> get durations => _durations.stream;
  @override
  Stream<void> get completions => _completions.stream;
  @override
  void dispose() {}
}
