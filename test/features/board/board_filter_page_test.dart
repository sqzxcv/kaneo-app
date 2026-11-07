import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/test_app.dart';

Future<void> filterMenu(WidgetTester tester, String option) async {
  await tester.tap(find.byIcon(LucideIcons.listFilter));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(option).last);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String query) async {
  if (find.byKey(const ValueKey('board-search')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('board-search-toggle')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(const ValueKey('board-search')), query);
  await tester.pumpAndSettle();
}

Future<void> checkOption(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(CheckboxListTile, label));
  await tester.pump();
  await tester.tap(find.text('Save').last);
  await tester.pumpAndSettle();
}

void main() {
  testBothLayouts('text filters all columns consistently and reset restores every card', (
    tester,
    size,
  ) async {
    final app = await pumpKaneoApp(
      tester,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await search(tester, 'missing task');
    expect(find.text(app.i18n.t('mobile:board.noTasksMatchTheFilters')), findsNWidgets(4));
    expect(find.text(app.i18n.t('mobile:board.noTasksHere')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('filter-count'))).data, '1');
    await tester.tap(find.byTooltip('Reset'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-count')), findsNothing);
    expect(find.text('Set up the project'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('board-search'))).controller!.text,
      isEmpty,
    );
  });

  testBothLayouts('priority, label and overdue conditions filter the same board', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.tasks.first['dueDate'] = '2000-01-01';
    server.addLabel('B-only', taskId: 'task-1');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await filterMenu(tester, 'Priority');
    await checkOption(tester, 'High');
    expect(find.text('Set up the project'), findsOneWidget);
    expect(find.text('Ship the beta'), findsOneWidget);
    expect(find.text('Review the board layout'), findsNothing);
    await filterMenu(tester, 'Labels');
    await checkOption(tester, 'B-only');
    expect(find.text('Ship the beta'), findsNothing);
    await filterMenu(tester, 'Overdue only');
    expect(find.text('Set up the project'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('filter-count'))).data, '3');
  });

  testBothLayouts('one label option matches every per-task copy from the API', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()..relations.clear();
    server.addLabel('B Shared label');
    server.addLabel('B Shared label', taskId: 'task-1');
    server.addLabel('B Shared label', taskId: 'task-3');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await filterMenu(tester, 'Labels');
    expect(find.widgetWithText(CheckboxListTile, 'B Shared label'), findsOneWidget);
    await checkOption(tester, 'B Shared label');
    expect(find.byKey(const ValueKey('board-card-task-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-card-task-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-card-task-2')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('filter-count'))).data, '1');
  });
  testBothLayouts('label picker waits for a delayed API response before opening', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.addLabel('B Delayed label', taskId: 'task-1');
    final gate = server.hold('api/label/workspace/');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await filterMenu(tester, 'Labels');
    await tester.pump(const Duration(seconds: 1));
    gate.release();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'B Delayed label'), findsOneWidget);
  });
  testBothLayouts('reopening cached labels shows a newly created label', (tester, size) async {
    final server = FakeKaneo();
    server.addLabel('B Old label', taskId: 'task-1');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await filterMenu(tester, 'Labels');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    server.addLabel('B New label', taskId: 'task-1');
    final gate = server.hold('api/label/workspace/');
    await filterMenu(tester, 'Labels');
    await tester.pump(const Duration(seconds: 1));
    gate.release();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'B New label'), findsOneWidget);
  });
  testBothLayouts('assignee multi-select includes unassigned and me shortcut', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.tasks[2]['userId'] = 'user-2';
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await filterMenu(tester, 'Assignee');
    await checkOption(tester, 'Unassigned');
    expect(find.text('Celebrate'), findsOneWidget);
    expect(find.text('Set up the project'), findsNothing);
    await filterMenu(tester, 'Me');
    expect(find.text('Set up the project'), findsOneWidget);
    expect(find.text('Celebrate'), findsNothing);
    expect(find.text('Review the board layout'), findsNothing);
  });

  testBothLayouts('planned and archived collections can be shown, filtered, and hidden', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.addTask(title: 'B future', status: statusPlanned);
    server.addTask(title: 'B past', status: statusArchived);
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'B future'), findsNothing);
    await filterMenu(tester, 'Show planned');
    await filterMenu(tester, 'Show archived');
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'B future'), findsOneWidget);
    expect(find.text('B past'), findsOneWidget);
    await search(tester, 'B future');
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'B future'), findsOneWidget);
    expect(find.text('B past'), findsNothing);
    await filterMenu(tester, 'Hide planned');
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'B future'), findsNothing);
    await filterMenu(tester, 'Hide archived');
    expect(find.byKey(const ValueKey('column-header-__archived')), findsNothing);
  });

  testBothLayouts('switching projects clears text, conditions and collection visibility', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.addTask(
      projectId: FakeKaneo.secondProjectId,
      title: 'B other project',
      assigneeId: null,
    );
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await filterMenu(tester, 'Me');
    await filterMenu(tester, 'Show planned');
    await search(tester, 'setup');
    if (size == narrowSize) {
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
    }
    await tester.tap(inPage(find.text('Demo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second project').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-count')), findsNothing);
    expect(find.text('B other project'), findsOneWidget);
    expect(find.byKey(const ValueKey('column-header-__planned')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testBothLayouts('dragging a filtered card preserves the hidden cards around its destination', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()..tasks.clear();
    final hidden = server.addTask(title: 'hidden first');
    final shown = server.addTask(title: 'shown first');
    server.addTask(title: 'hidden middle');
    server.addTask(title: 'shown middle');
    final last = server.addTask(title: 'shown last');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await search(tester, 'shown');
    final target = tester.getRect(find.byKey(ValueKey('drop-card-${shown['id']}')));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('drag-handle-${last['id']}'))),
    );
    await gesture.moveBy(const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(target.topLeft + const Offset(100, 12));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final sorted = [...server.tasks]
      ..sort((a, b) => (a['position'] as num).compareTo(b['position'] as num));
    expect(sorted.take(3).map((t) => t['id']), [hidden['id'], last['id'], shown['id']]);
  });

  testBothLayouts('a planned card can move into a normal column without duplicate cache entries', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final task = server.addTask(title: 'B planned movement', status: statusPlanned);
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await filterMenu(tester, 'Show planned');
    await tester.longPress(find.text('B planned movement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('To Do').last);
    await tester.pumpAndSettle();
    final board = app.container.read(boardQuery(FakeKaneo.projectId)).requireValue;
    expect(board.plannedTasks, isEmpty);
    expect(board.columns.first.tasks!.where((t) => t.id == task['id']).length, 1);
    expect(server.tasks.firstWhere((t) => t['id'] == task['id'])['status'], 'to-do');
  });
  testBothLayouts('switching board and list preserves text and selected filters', (
    tester,
    size,
  ) async {
    await pumpKaneoApp(tester, size: size, location: AppRoutes.board(FakeKaneo.projectId));
    await filterMenu(tester, 'Priority');
    await checkOption(tester, 'High');
    await search(tester, 'Set up');
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list-task-task-1')), findsOneWidget);
    expect(find.text('Ship the beta'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('filter-count'))).data, '2');
    await tester.tap(find.byTooltip('Board view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-card-task-1')), findsOneWidget);
    expect(find.text('Ship the beta'), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('board-search'))).controller!.text,
      'Set up',
    );
  });
}
