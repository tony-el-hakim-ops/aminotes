import 'package:aminotes/aminotes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;

  Future<AminotesController> pumpToolbar(
    WidgetTester tester,
    AminotesToolbar Function(AminotesController) build,
  ) async {
    final controller = AminotesController(hostFactory: (onMessage) => host = FakeHost(onMessage));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: AminotesEditor(controller: controller)),
              build(controller),
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

  testWidgets('custom buttons run with the controller and can show as active', (tester) async {
    AminotesController? pressedWith;
    final controller = await pumpToolbar(
      tester,
      (controller) => AminotesToolbar(
        controller: controller,
        items: [
          AminotesToolbarItem.bold,
          AminotesToolbarItem.custom(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Template',
            onPressed: (c) => pressedWith = c,
            isActive: (state) => state.isActive('bold'),
          ),
        ],
      ),
    );
    await tester.tap(find.byTooltip('Template'));
    expect(pressedWith, same(controller));

    host.postFromPage('{"type":"state","active":{"bold":true}}');
    await tester.pump();
    final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.auto_awesome));
    expect(button.isSelected, isTrue);
  });

  testWidgets('icons can be replaced, headings included', (tester) async {
    await pumpToolbar(
      tester,
      (controller) => AminotesToolbar(
        controller: controller,
        items: const [AminotesToolbarItem.bold, AminotesToolbarItem.heading1],
        icons: const {AminotesToolbarItem.bold: Icons.star, AminotesToolbarItem.heading1: Icons.title},
      ),
    );
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.format_bold), findsNothing);
    expect(find.byIcon(Icons.title), findsOneWidget);
    expect(find.text('H1'), findsNothing);
    await tester.tap(find.byTooltip('Bold'));
    expect(host.calls('command').single, contains('toggleBold'));
  });

  test('built-in items keep their names and presets', () {
    expect(AminotesToolbarItem.bold.name, 'bold');
    expect(AminotesToolbarItem.full, contains(AminotesToolbarItem.table));
    expect(AminotesToolbarItem.compact, isNot(contains(AminotesToolbarItem.table)));
  });
}
