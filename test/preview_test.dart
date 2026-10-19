import 'dart:convert';
import 'dart:io';

import 'package:aminotes/aminotes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _doc(List<Map<String, dynamic>> content) => {'type': 'doc', 'content': content};
Map<String, dynamic> _p(List<Map<String, dynamic>> inline) => {'type': 'paragraph', 'content': inline};
Map<String, dynamic> _t(String text, [List<Map<String, dynamic>>? marks]) => {
  'type': 'text',
  'text': text,
  'marks': ?marks,
};

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  final sample = jsonDecode(File('example/assets/sample_note.json').readAsStringSync()) as Map<String, dynamic>;

  testWidgets('draws the whole sample note without a WebView', (tester) async {
    await _pump(tester, AminotesPreview(json: sample));
    await tester.pump();
    expect(find.textContaining('Tiptap round-trip test', findRichText: true), findsOneWidget);
    expect(find.textContaining('Nested item', findRichText: true), findsOneWidget);
    expect(find.textContaining('Numbered list starting at 3', findRichText: true), findsOneWidget);
    expect(find.text('3.'), findsOneWidget, reason: 'ordered lists keep their start');
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget, reason: 'the voice note pill');
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resized image keeps its size and proportions; others fill the width', (tester) async {
    Map<String, dynamic> image(Map<String, Object> size) => {
      'type': 'image',
      'attrs': {'src': 'https://example.com/a.png', ...size},
    };
    await _pump(
      tester,
      AminotesPreview(
        imageHeight: 160,
        json: _doc([
          image({'width': 120, 'height': 60}),
          image({'width': 400, 'height': 400}),
          image({}),
        ]),
      ),
    );
    final sizes = tester.widgetList<Image>(find.byType(Image)).map((i) => tester.getSize(find.byWidget(i))).toList();
    expect(sizes[0], const Size(120, 60), reason: 'its resized size');
    expect(sizes[1], const Size(160, 160), reason: 'never taller than imageHeight, same proportions');
    expect(sizes[2].width, 768, reason: 'not resized: the full width (800 minus the padding)');
  });

  testWidgets('a resized image follows its alignment', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 400,
        child: AminotesPreview(
          json: _doc([
            {
              'type': 'image',
              'attrs': {'src': 'https://example.com/a.png', 'width': 100, 'height': 50, 'align': 'right'},
            },
          ]),
        ),
      ),
    );
    final box = tester.getRect(find.byType(Image));
    final preview = tester.getRect(find.byType(AminotesPreview));
    expect(preview.right - box.right, lessThan(20), reason: 'against the right edge');
  });

  testWidgets('marks become text styles', (tester) async {
    await _pump(
      tester,
      AminotesPreview(
        json: _doc([
          _p([
            _t('b', [
              {'type': 'bold'},
            ]),
            _t('red', [
              {
                'type': 'textStyle',
                'attrs': {'color': '#e53935'},
              },
            ]),
          ]),
        ]),
      ),
    );
    final rich = tester.widget<RichText>(find.byType(RichText).first).text as TextSpan;
    final spans = (rich.children!.single as TextSpan).children!.cast<TextSpan>();
    expect(spans[0].style!.fontWeight, FontWeight.w700);
    expect(spans[1].style!.color, const Color(0xFFE53935));
  });

  testWidgets('unknown content shows the placeholder; maxBlocks limits the blocks', (tester) async {
    final doc = _doc([
      _p([_t('one')]),
      {'type': 'callout'},
      _p([_t('three')]),
    ]);
    await _pump(tester, AminotesPreview(json: doc));
    expect(find.text('Unsupported content (callout), kept unchanged'), findsOneWidget);
    await _pump(tester, AminotesPreview(json: doc, maxBlocks: 1));
    expect(find.textContaining('three', findRichText: true), findsNothing);
  });

  testWidgets('Arabic paragraphs read right to left inside an English app', (tester) async {
    await _pump(
      tester,
      AminotesPreview(
        json: _doc([
          _p([_t('مرحبا')]),
          _p([_t('Hello')]),
        ]),
      ),
    );
    final texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
    expect(texts[0].textDirection, TextDirection.rtl);
    expect(texts[1].textDirection, TextDirection.ltr);
  });

  testWidgets('taps reach the host app', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      InkWell(
        onTap: () => taps++,
        child: AminotesPreview(
          json: _doc([
            {
              'type': 'taskList',
              'content': [
                {
                  'type': 'taskItem',
                  'attrs': {'checked': false},
                  'content': [
                    _p([_t('task')]),
                  ],
                },
              ],
            },
          ]),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    expect(taps, 1);
  });

  test('plainText', () {
    expect(
      AminotesPreview.plainText(
        _doc([
          _p([_t('Hi '), _t('there')]),
          _p([_t('Second')]),
        ]),
      ),
      'Hi there\nSecond',
    );
  });
}
