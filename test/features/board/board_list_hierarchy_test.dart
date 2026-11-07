import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_expansion.dart';

import '../../support/test_app.dart';

FakeKaneo tree() {
  final server = FakeKaneo()
    ..tasks.clear()
    ..relations.clear();
  server.addTask(id: 'parent', title: 'B Parent');
  server.addTask(id: 'child', title: 'B Child');
  server.addTask(id: 'grandchild', title: 'B Grandchild');
  server.addTask(id: 'cross', title: 'B Other column', status: 'in-progress');
  server.addRelation('parent', 'child');
  server.addRelation('child', 'grandchild');
  server.addRelation('parent', 'cross');
  return server;
}

Finder row(String id) => find.byKey(ValueKey('list-task-$id'));
Future<void> toggle(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('expand-task-$id')));
  await tester.pumpAndSettle();
}

Future<TestApp> open(
  WidgetTester tester,
  Size size,
  FakeKaneo server, {
  Map<String, Object> preferences = const {},
}) async {
  final app = await pumpKaneoApp(
    tester,
    server: server,
    size: size,
    preferences: preferences,
    location: AppRoutes.board(FakeKaneo.projectId),
  );
  await tester.tap(find.byTooltip('List view'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testBothLayouts(
    'same-group hierarchy defaults closed, expands each level and keeps total count',
    (tester, size) async {
      await open(tester, size, tree());
      expect(row('parent'), findsOneWidget);
      expect(row('child'), findsNothing);
      expect(inPage(find.text('3 tasks')), findsOneWidget);
      await toggle(tester, 'parent');
      expect(row('child'), findsOneWidget);
      expect(row('grandchild'), findsNothing);
      final parentTitle = tester.getTopLeft(find.text('B Parent'));
      final childTitle = tester.getTopLeft(find.text('B Child'));
      expect(childTitle.dx, greaterThan(parentTitle.dx));
      await toggle(tester, 'child');
      expect(row('grandchild'), findsOneWidget);
      expect(tester.getTopLeft(find.text('B Grandchild')).dx, greaterThan(childTitle.dx));
      await toggle(tester, 'parent');
      expect(row('child'), findsNothing);
      expect(row('grandchild'), findsNothing);
      expect(inPage(find.text('3 tasks')), findsOneWidget);
    },
  );
  testBothLayouts('other-group children stay visible with the parent title', (tester, size) async {
    await open(tester, size, tree());
    expect(row('cross'), findsOneWidget);
    expect(
      find.descendant(of: row('cross'), matching: find.text('Parent task: B Parent')),
      findsOneWidget,
    );
  });
  testBothLayouts('a filter matching only a child shows it as a root', (tester, size) async {
    await open(tester, size, tree());
    if (size == narrowSize) {
      await tester.tap(find.byKey(const ValueKey('board-search-toggle')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byKey(const ValueKey('board-search')), 'B Child');
    await tester.pumpAndSettle();
    expect(row('parent'), findsNothing);
    expect(row('child'), findsOneWidget);
    expect(find.text('Parent task: B Parent'), findsOneWidget);
  });
  testBothLayouts('expansion survives a fresh app and stays scoped to its project', (
    tester,
    size,
  ) async {
    final server = tree();
    final app = await open(tester, size, server);
    await toggle(tester, 'parent');
    final key = boardExpansionKey(FakeKaneo.projectId);
    final saved = app.container.read(prefsProvider).getStringList(key)!;
    expect(saved, ['parent']);
    await tester.pumpWidget(const SizedBox());
    await open(tester, size, server, preferences: {key: saved});
    expect(row('child'), findsOneWidget);
    expect(row('grandchild'), findsNothing);
    expect(saved, isNot(contains('grandchild')));
  });
  testBothLayouts('switching projects keeps separate expansion choices', (tester, size) async {
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
    if (find.byTooltip('List view').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
    }
    expect(row('other-parent'), findsOneWidget);
    expect(row('other-child'), findsNothing);
    await tester.tap(inPage(find.text('Second project')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo').last);
    await tester.pumpAndSettle();
    if (find.byTooltip('List view').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
    }
    expect(row('child'), findsOneWidget);
  });
  testBothLayouts('deep overdue subtasks fit without overflowing', (tester, size) async {
    final server = tree();
    server.addTask(id: 'deep', title: 'B Deep task with a long title', dueDate: '2000-01-01');
    server.addRelation('grandchild', 'deep');
    await open(tester, size, server);
    await toggle(tester, 'parent');
    await toggle(tester, 'child');
    await toggle(tester, 'grandchild');
    expect(row('deep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testBothLayouts('refresh updates the hierarchy when relations change', (tester, size) async {
    final server = tree();
    await open(tester, size, server);
    server.relations.clear();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(row('child'), findsOneWidget);
    expect(row('grandchild'), findsOneWidget);
  });
  testBothLayouts('cycles and multiple parents render each task once', (tester, size) async {
    final server = tree()..relations.clear();
    server.addRelation('parent', 'child');
    server.addRelation('child', 'grandchild');
    server.addRelation('grandchild', 'parent');
    server.addRelation('parent', 'grandchild');
    await open(tester, size, server);
    expect(row('parent'), findsOneWidget);
    await toggle(tester, 'parent');
    expect(row('child'), findsOneWidget);
    expect(row('grandchild'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testBothLayouts('relations loading has one indicator and then shows the collapsed list', (
    tester,
    size,
  ) async {
    final server = tree();
    final gate = server.hold('api/task-relation/project/');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      settle: false,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.byTooltip('List view'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.release();
    await tester.pumpAndSettle();
    expect(row('parent'), findsOneWidget);
    expect(row('child'), findsNothing);
  });
  for (final status in [403, 500]) {
    testBothLayouts('relations $status reports the error instead of silently flattening tasks', (
      tester,
      size,
    ) async {
      final server = tree()..fail('api/task-relation/project/', status: status);
      final app = await open(tester, size, server);
      expect(
        find.text(app.i18n.t(status == 403 ? 'mobile:errors.forbidden' : 'mobile:ui.loadFailed')),
        findsOneWidget,
      );
      expect(row('parent'), findsNothing);
    });
  }
}
