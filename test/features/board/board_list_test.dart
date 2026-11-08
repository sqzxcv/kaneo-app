import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_list_row.dart';

import '../../support/test_app.dart';

Finder row(String id) => find.byKey(ValueKey('list-task-$id'));
Future<TestApp> openList(WidgetTester tester, Size size, {FakeKaneo? server}) async {
  final app = await pumpKaneoApp(
    tester,
    server: server,
    size: size,
    location: AppRoutes.board(FakeKaneo.projectId),
  );
  await tester.tap(find.byTooltip('List view'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testBothLayouts('list groups tasks by status and switches back to the board', (
    tester,
    size,
  ) async {
    await openList(tester, size);
    final headers = ['to-do', 'in-progress', 'in-review', 'done'];
    for (var index = 1; index < headers.length; index++) {
      expect(
        tester.getTopLeft(find.byKey(ValueKey('list-group-${headers[index]}'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(ValueKey('list-group-${headers[index - 1]}'))).dy),
      );
    }
    expect(
      tester.getTopLeft(row('task-1')).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('list-group-in-progress'))).dy),
    );
    expect(
      tester.getTopLeft(row('task-3')).dy,
      greaterThan(tester.getTopLeft(find.byKey(const ValueKey('list-group-in-progress'))).dy),
    );
    await tester.tap(find.byTooltip('Board view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-card-task-1')), findsOneWidget);
    expect(find.byType(BoardListRow), findsNothing);
  });

  testBothLayouts('rows show id, title and assignee, plus the proper date and wide metadata', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.tasks.first['dueDate'] = '2000-01-01';
    server.tasks[1]['dueDate'] = '2099-01-01';
    server.addLabel('B Label', taskId: 'task-1');
    final app = await openList(tester, size, server: server);
    await tester.tap(find.byKey(const ValueKey('expand-task-task-1')));
    await tester.pumpAndSettle();
    final first = row('task-1');
    for (final text in ['DEMO-1', 'Set up the project', formatDueShort(app.i18n, '2000-01-01')]) {
      expect(find.descendant(of: first, matching: find.text(text)), findsOneWidget);
    }
    expect(find.descendant(of: first, matching: find.byTooltip('Test User')), findsOneWidget);
    expect(
      find.descendant(of: row('task-6'), matching: find.byTooltip('Unassigned')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.byTooltip('High')),
      size == wideSize ? findsOneWidget : findsNothing,
    );
    expect(
      find.descendant(of: first, matching: find.text('B Label')),
      size == wideSize ? findsOneWidget : findsNothing,
    );
    expect(
      find.descendant(
        of: row('task-2'),
        matching: find.text(formatDueShort(app.i18n, '2099-01-01')),
      ),
      size == wideSize ? findsOneWidget : findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  // KAN-68: a phone's list showed no progress. The owner decided it should, as the board does.
  testBothLayouts('a parent row shows its subtask progress, and other rows show none', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.addTask(id: 'task-7', title: 'Second child');
    server.addRelation('task-1', 'task-7');
    server.tasks.firstWhere((t) => t['id'] == 'task-2')['status'] = 'done';
    await openList(tester, size, server: server);
    final progress = find.descendant(of: row('task-1'), matching: find.text('1/2'));
    expect(progress, findsOneWidget);
    expect(
      find.descendant(of: row('task-1'), matching: find.byTooltip('Subtasks')),
      findsOneWidget,
    );
    // Beside the title, inside the row.
    final title = tester.getRect(
      find.descendant(of: row('task-1'), matching: find.text('Set up the project')),
    );
    expect(tester.getRect(progress).left, greaterThanOrEqualTo(title.right));
    expect(tester.getRect(row('task-1')).contains(tester.getCenter(progress)), isTrue);
    for (final id in ['task-3', 'task-4', 'task-5', 'task-6']) {
      expect(
        find.descendant(of: row(id), matching: find.textContaining(RegExp(r'^\d+/\d+$'))),
        findsNothing,
        reason: id,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('clicking a list row opens the shared task route', (tester, size) async {
    await openList(tester, size);
    await tester.tap(find.descendant(of: row('task-1'), matching: find.text('Set up the project')));
    await tester.pumpAndSettle();
    expect(taskOpen('task-1'), findsOneWidget);
  });

  testBothLayouts('empty list keeps status headers and consistent empty messages', (
    tester,
    size,
  ) async {
    final app = await openList(tester, size, server: FakeKaneo()..tasks.clear());
    expect(find.text(app.i18n.t('mobile:board.noTasksHere')), findsNWidgets(4));
    expect(find.byType(BoardListRow), findsNothing);
    expect(find.byKey(const ValueKey('list-group-to-do')), findsOneWidget);
  });

  for (final status in [403, 500]) {
    testBothLayouts('list mode preserves the $status error state', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/tasks/', status: status);
      final app = await openList(tester, size, server: server);
      expect(
        find.text(app.i18n.t(status == 403 ? 'mobile:errors.forbidden' : 'mobile:ui.loadFailed')),
        findsOneWidget,
      );
      expect(find.byType(BoardListRow), findsNothing);
    });
  }

  testBothLayouts('list can be chosen while loading and renders when the request completes', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final gate = server.hold('api/task/tasks/');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
      settle: false,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('List view'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.release();
    await tester.pumpAndSettle();
    expect(row('task-1'), findsOneWidget);
  });

  testBothLayouts('long titles and many labels fit and 100 rows stay lazy', (tester, size) async {
    final server = FakeKaneo()..tasks.clear();
    for (var i = 0; i < 100; i++) {
      final task = server.addTask(title: 'B list $i ${'很长的任务标题 ' * 10}');
      if (i == 0) {
        for (var label = 0; label < 6; label++) {
          server.addLabel('long label $label ${'标签' * 10}', taskId: task['id'] as String);
        }
      }
    }
    await openList(tester, size, server: server);
    expect(find.byType(BoardListRow).evaluate().length, lessThan(40));
    final list = find.byKey(const PageStorageKey('board-list-${FakeKaneo.projectId}'));
    await tester.scrollUntilVisible(
      row(server.tasks.last['id'] as String),
      600,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    expect(row(server.tasks.last['id'] as String), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testBothLayouts("the assignee's picture shows on the card and in the list, as on the web", (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.members.first['image'] = '/api/user/avatar/a1';
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    Finder picture(Finder of) => find.descendant(
      of: of,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is NetworkImage &&
            (w.image as NetworkImage).url == '${FakeKaneo.serverUrl}/api/user/avatar/a1',
      ),
    );
    expect(picture(find.byKey(const ValueKey('board-card-task-1'))), findsOneWidget);
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(picture(row('task-1')), findsOneWidget);
  });
}
