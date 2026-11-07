import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_expansion.dart';

import '../../support/test_app.dart';
import 'board_drag_test.dart' show goTo;
import 'board_filter_page_test.dart' show search;

FakeKaneo tree() {
  final server = FakeKaneo()
    ..tasks.clear()
    ..relations.clear();
  server.addTask(id: 'parent', title: 'B Parent');
  server.addTask(id: 'child', title: 'B Child');
  server.addTask(id: 'grandchild', title: 'B Grandchild');
  server.addTask(id: 'cross', title: 'B Other column', status: 'in-progress');
  server.addTask(id: 'complete', title: 'B Completed', status: 'done');
  server.addRelation('parent', 'child');
  server.addRelation('child', 'grandchild');
  server.addRelation('parent', 'cross');
  server.addRelation('parent', 'complete');
  return server;
}

Finder card(String id) => find.byKey(ValueKey('board-card-$id'));
Future<void> toggle(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('expand-task-$id')));
  await tester.pumpAndSettle();
}

Future<TestApp> open(
  WidgetTester tester,
  Size size,
  FakeKaneo server, {
  Map<String, Object> preferences = const {},
}) => pumpKaneoApp(
  tester,
  server: server,
  size: size,
  location: AppRoutes.board(FakeKaneo.projectId),
  preferences: preferences,
);

void main() {
  testBothLayouts('board defaults to parents with progress and expands each nested level', (
    tester,
    size,
  ) async {
    await open(tester, size, tree());
    expect(card('parent'), findsOneWidget);
    expect(card('child'), findsNothing);
    expect(find.descendant(of: card('parent'), matching: find.text('1/3')), findsOneWidget);
    expect(find.text('3 tasks'), findsOneWidget);
    await toggle(tester, 'parent');
    expect(card('child'), findsOneWidget);
    expect(card('grandchild'), findsNothing);
    expect(tester.getTopLeft(card('child')).dx, greaterThan(tester.getTopLeft(card('parent')).dx));
    await toggle(tester, 'child');
    expect(card('grandchild'), findsOneWidget);
    expect(
      tester.getTopLeft(card('grandchild')).dx,
      greaterThan(tester.getTopLeft(card('child')).dx),
    );
    await toggle(tester, 'parent');
    expect(card('child'), findsNothing);
    expect(card('grandchild'), findsNothing);
    expect(find.text('3 tasks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testBothLayouts('cross-column child stays visible and identifies its parent', (
    tester,
    size,
  ) async {
    await open(tester, size, tree());
    expect(card('cross'), findsOneWidget);
    expect(
      find.descendant(of: card('cross'), matching: find.text('Parent task: B Parent')),
      findsOneWidget,
    );
  });
  testBothLayouts('child-only filter cannot hide its matching card', (tester, size) async {
    await open(tester, size, tree());
    await search(tester, 'B Child');
    expect(card('parent'), findsNothing);
    expect(card('child'), findsOneWidget);
    expect(find.text('Parent task: B Parent'), findsOneWidget);
  });
  testBothLayouts('board expansion survives restart and is shared with list view', (
    tester,
    size,
  ) async {
    final server = tree();
    final app = await open(tester, size, server);
    await toggle(tester, 'parent');
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list-task-child')), findsOneWidget);
    final key = boardExpansionKey(FakeKaneo.projectId);
    final saved = app.container.read(prefsProvider).getStringList(key)!;
    await tester.pumpWidget(const SizedBox());
    await open(tester, size, server, preferences: {key: saved});
    expect(card('child'), findsOneWidget);
    expect(card('grandchild'), findsNothing);
  });
  testBothLayouts('project switches preserve separate board expansion choices', (
    tester,
    size,
  ) async {
    final server = tree();
    server.addTask(
      id: 'other-parent',
      title: 'B Second parent',
      projectId: FakeKaneo.secondProjectId,
    );
    server.addTask(
      id: 'other-child',
      title: 'B Second child',
      projectId: FakeKaneo.secondProjectId,
    );
    server.addRelation('other-parent', 'other-child');
    await open(tester, size, server);
    await toggle(tester, 'parent');
    await tester.tap(inPage(find.text('Demo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second project').last);
    await tester.pumpAndSettle();
    expect(card('other-parent'), findsOneWidget);
    expect(card('other-child'), findsNothing);
    await tester.tap(inPage(find.text('Second project')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo').last);
    await tester.pumpAndSettle();
    expect(card('child'), findsOneWidget);
  });
  testBothLayouts('cyclic multi-parent relations have one finite rendering per task', (
    tester,
    size,
  ) async {
    final server = tree();
    server.addRelation('grandchild', 'parent');
    server.addRelation('parent', 'grandchild');
    server.addRelation('child', 'child');
    await open(tester, size, server);
    await toggle(tester, 'parent');
    for (final id in ['parent', 'child', 'grandchild']) {
      expect(card(id), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testBothLayouts('dragging parent moves only parent and reveals children left behind', (
    tester,
    size,
  ) async {
    final server = tree();
    await open(tester, size, server);
    final relations = server.relations.map((r) => Map.of(r)).toList();
    final before = server.tasks.where((t) => t['id'] != 'parent').map((t) => Map.of(t)).toList();
    final gesture = await pickUpCard(tester, 'parent');
    await goTo(
      tester,
      gesture,
      tester.getTopLeft(find.byKey(const ValueKey('column-header-in-progress'))) +
          const Offset(20, 20),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(server.tasks.firstWhere((t) => t['id'] == 'parent')['status'], 'in-progress');
    for (final task in before) {
      final actual = server.tasks.firstWhere((t) => t['id'] == task['id']);
      expect(actual['status'], task['status']);
    }
    expect(server.relations, relations);
    expect(card('child'), findsOneWidget);
    expect(
      find.descendant(of: card('child'), matching: find.text('Parent task: B Parent')),
      findsOneWidget,
    );
    expect(card('cross'), findsNothing);
    expect(card('grandchild'), findsNothing);
  });
  testBothLayouts('reordering around a collapsed subtree uses the complete column position', (
    tester,
    size,
  ) async {
    final server = tree();
    server.addTask(id: 'neighbor', title: 'B Neighbor');
    server.addTask(id: 'moving', title: 'B Moving');
    await open(tester, size, server);
    final target = tester.getRect(find.byKey(const ValueKey('drop-card-neighbor')));
    final gesture = await pickUpCard(tester, 'moving');
    await goTo(tester, gesture, target.topLeft + const Offset(80, 12));
    await gesture.up();
    await tester.pumpAndSettle();
    final tasks = server.tasks.where((t) => t['status'] == 'to-do').toList()
      ..sort((a, b) => (a['position'] as num).compareTo(b['position'] as num));
    expect(tasks.map((t) => t['id']), ['parent', 'child', 'grandchild', 'moving', 'neighbor']);
    expect(card('child'), findsNothing);
  });
  testBothLayouts('board relations loading uses one indicator then reveals collapsed cards', (
    tester,
    size,
  ) async {
    final server = tree();
    final gate = server.hold('api/task-relation/project/');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
      settle: false,
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(card('parent'), findsNothing);
    gate.release();
    await tester.pumpAndSettle();
    expect(card('parent'), findsOneWidget);
    expect(card('child'), findsNothing);
  });
  for (final status in [403, 500]) {
    testBothLayouts('board relations $status shows error without silently flattening', (
      tester,
      size,
    ) async {
      final app = await open(
        tester,
        size,
        tree()..fail('api/task-relation/project/', status: status),
      );
      expect(
        find.text(app.i18n.t(status == 403 ? 'mobile:errors.forbidden' : 'mobile:ui.loadFailed')),
        findsOneWidget,
      );
      expect(card('parent'), findsNothing);
    });
  }
  testBothLayouts('board refresh reloads relations as well as tasks', (tester, size) async {
    final server = tree();
    await open(tester, size, server);
    server.relations.clear();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(card('child'), findsOneWidget);
    expect(card('grandchild'), findsOneWidget);
  });
}
