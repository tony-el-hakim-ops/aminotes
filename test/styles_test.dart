import 'package:aminotes/aminotes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;

  Future<AminotesController> pumpEditor(
    WidgetTester tester,
    AminotesTheme theme, {
    ValueChanged<AminotesError>? onError,
  }) async {
    final controller = AminotesController(onError: onError, hostFactory: (onMessage) => host = FakeHost(onMessage));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AminotesEditor(controller: controller, theme: theme),
        ),
      ),
    );
    await tester.pump();
    host.postFromPage('{"type":"ready"}');
    // Font files are read asynchronously before being sent.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();
    return controller;
  }

  testWidgets('custom CSS and app fonts reach the page', (tester) async {
    await pumpEditor(
      tester,
      const AminotesTheme(
        fontFamily: 'Brand',
        // Any asset will do for the test: it is sent as the font file.
        fonts: [AminotesFont('Brand', 'packages/aminotes/assets/editor/compat.js', weight: FontWeight.w700)],
        css: '.ProseMirror h1 { font-size: 3em; }',
      ),
    );
    final styles = host.calls('setStyles').single;
    expect(styles, contains('.ProseMirror h1 { font-size: 3em; }'));
    expect(styles, contains('"family":"Brand"'));
    expect(styles, contains('"weight":700'));
    expect(styles, contains('data:font/ttf;base64,'));
    expect(host.calls('setTheme').last, contains("'Brand', sans-serif"));
  });

  testWidgets('no CSS or fonts: nothing extra is sent', (tester) async {
    await pumpEditor(tester, const AminotesTheme());
    expect(host.calls('setStyles'), isEmpty);
  });

  testWidgets('a missing font file is reported, and the CSS still applies', (tester) async {
    final errors = <AminotesError>[];
    await pumpEditor(
      tester,
      const AminotesTheme(fonts: [AminotesFont('Nope', 'assets/fonts/missing.ttf')], css: 'p { color: red; }'),
      onError: errors.add,
    );
    expect(errors.single.message, contains('assets/fonts/missing.ttf'));
    expect(host.calls('setStyles').single, contains('p { color: red; }'));
  });
}
