import 'package:aminotes/aminotes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;

  Future<AminotesController> pumpEditing(WidgetTester tester, {List<AminotesToolbarItem>? items}) async {
    final controller = AminotesController(hostFactory: (onMessage) => host = FakeHost(onMessage));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: AminotesEditor(controller: controller)),
              AminotesToolbar(controller: controller, items: items ?? AminotesToolbarItem.full),
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

  testWidgets('controller table commands', (tester) async {
    final controller = await pumpEditing(tester);
    await controller.insertTable(rows: 2, columns: 4, withHeaderRow: false);
    await controller.addRowBefore();
    await controller.addColumnAfter();
    await controller.deleteTable();
    expect(host.calls('command').first, contains('"insertTable", {"rows":2,"cols":4,"withHeaderRow":false}'));
    expect(commands().skip(1), ['addRowBefore', 'addColumnAfter', 'deleteTable']);
  });

  testWidgets('table buttons appear only while the cursor is in a table', (tester) async {
    await pumpEditing(tester);
    host.postFromPage('{"type":"state","focused":true}');
    await tester.pump();
    expect(find.byTooltip('Add row below'), findsNothing);
    await tester.scrollUntilVisible(find.byTooltip('Insert table'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('Insert table'));
    expect(commands().last, 'insertTable');

    host.postFromPage('{"type":"state","focused":true,"active":{"table":true}}');
    await tester.pump();
    // The bar scrolls lazily: bring the insert button into view to check it.
    await tester.scrollUntilVisible(find.byTooltip('Insert table'), 200, scrollable: find.byType(Scrollable).last);
    final insert = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.table_chart_outlined));
    expect(insert.onPressed, isNull, reason: 'no tables inside tables');
    // Back to the start of the bar, where the table buttons are.
    await tester.fling(find.byType(Scrollable).last, const Offset(2000, 0), 5000);
    await tester.pumpAndSettle();
    for (final tooltip in [
      'Add row below',
      'Add column after',
      'Delete row',
      'Delete column',
      'Header row',
      'Delete table',
    ]) {
      await tester.tap(find.byTooltip(tooltip));
    }
    expect(commands().skip(1), [
      'addRowAfter',
      'addColumnAfter',
      'deleteRow',
      'deleteColumn',
      'toggleHeaderRow',
      'deleteTable',
    ]);
  });

  testWidgets('a toolbar without the table item shows no table buttons', (tester) async {
    await pumpEditing(tester, items: AminotesToolbarItem.compact);
    host.postFromPage('{"type":"state","focused":true,"active":{"table":true}}');
    await tester.pump();
    expect(find.byTooltip('Add row below'), findsNothing);
  });
}
