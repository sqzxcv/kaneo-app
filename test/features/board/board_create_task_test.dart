import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/test_app.dart';

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> createFrom(WidgetTester tester, FakeKaneo server, Finder entry, String status) async {
  await press(tester, entry);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('new-task-project')),
      matching: find.text('Demo'),
    ),
    findsOneWidget,
  );
  final title = 'B Added to $status';
  await tester.enterText(find.byKey(const ValueKey('new-task-title')), title);
  await press(tester, find.byKey(const ValueKey('new-task-create')));
  final task = server.tasks.singleWhere((task) => task['title'] == title);
  expect(task['projectId'], FakeKaneo.projectId);
  expect(task['status'], status);
  expect(find.byKey(const ValueKey('new-task-title')), findsNothing);
  expect(
    find.descendant(of: find.byKey(ValueKey('drop-column-$status')), matching: find.text(title)),
    findsOneWidget,
  );
}

void main() {
  testBothLayouts('the column header creates a task in that column', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await createFrom(
      tester,
      server,
      find.byKey(const ValueKey('add-task-column-in-progress')),
      'in-progress',
    );
  });

  testBothLayouts('an empty project explains the empty columns and can create its first task', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()..tasks.clear();
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    expect(find.text(app.i18n.t('mobile:board.noTasksHere')), findsNWidgets(4));
    await createFrom(tester, server, find.byKey(const ValueKey('add-task-empty-to-do')), 'to-do');
  });

  testBothLayouts('custom columns pass their slug to the new-task form', (tester, size) async {
    final server = FakeKaneo()..tasks.clear();
    server.columns[1]['slug'] = 'b-review';
    server.columns[1]['name'] = 'B Review';
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await createFrom(
      tester,
      server,
      find.byKey(const ValueKey('add-task-column-b-review')),
      'b-review',
    );
  });

  for (final (status, menu) in [
    (statusPlanned, 'Show planned'),
    (statusArchived, 'Show archived'),
  ]) {
    testBothLayouts('$status collection can create a task with that status', (tester, size) async {
      final server = FakeKaneo()..tasks.clear();
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      await press(tester, find.byIcon(LucideIcons.listFilter));
      await press(tester, find.text(menu));
      await createFrom(tester, server, find.byKey(ValueKey('add-task-column-$status')), status);
    });
  }

  testBothLayouts('the no-column empty state still opens the new-task form', (tester, size) async {
    final server = FakeKaneo()
      ..tasks.clear()
      ..columns.clear();
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await press(tester, find.byKey(const ValueKey('board-empty-add-task')));
    expect(find.byKey(const ValueKey('new-task-title')), findsOneWidget);
  });

  testBothLayouts('column creation controls wait until the board has loaded', (tester, size) async {
    final server = FakeKaneo();
    final gate = server.hold('api/task/tasks/');
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
      settle: false,
    );
    expect(find.byTooltip('Add task'), findsNothing);
    gate.release();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-task-column-to-do')), findsOneWidget);
  });

  for (final status in [403, 500]) {
    testBothLayouts('board HTTP $status does not offer a column creation control', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..fail('api/task/tasks/', status: status);
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      expect(find.byTooltip('Add task'), findsNothing);
      expect(find.byKey(const ValueKey('board-empty-add-task')), findsNothing);
    });
  }
}
