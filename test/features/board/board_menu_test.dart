import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_card.dart';

import '../../support/test_app.dart';

Finder card(String id) => find.byKey(ValueKey('board-card-$id'));
Future<void> menu(WidgetTester tester, String id, {bool mouse = false}) async {
  final title = find.descendant(
    of: card(id),
    matching: find.text(tester.widget<BoardCard>(card(id)).task.title),
  );
  if (mouse) {
    final gesture = await tester.startGesture(
      tester.getCenter(title),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
  } else {
    await tester.longPress(title);
  }
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final mouse in [false, true]) {
    testBothLayouts('${mouse ? 'right click' : 'long press'} opens all actions and opens task', (
      tester,
      size,
    ) async {
      final app = await pumpKaneoApp(
        tester,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      await menu(tester, 'task-1', mouse: mouse);
      for (final key in [
        'moveTo',
        'assignee',
        'priority',
        'sendToTopOfColumn',
        'sendToBottomOfColumn',
        'openTask',
      ]) {
        expect(find.text(app.i18n.t('mobile:board.$key')), findsOneWidget);
      }
      await choose(tester, app.i18n.t('mobile:board.openTask'));
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.task('task-1'));
    });
  }

  testBothLayouts('menu moves to a custom status and updates the card immediately', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.columns[1]['name'] = '已计划';
    server.columns[1]['slug'] = 'custom';
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.moveTo'));
    final gate = server.hold('api/task/reorder');
    await tester.tap(find.text('已计划').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('drop-column-custom')),
        matching: card('task-1'),
      ),
      findsOneWidget,
    );
    gate.release();
    await tester.pumpAndSettle();
    expect(server.tasks.first['status'], 'custom');
  });

  testBothLayouts('menu changes priority immediately then persists it', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.priority'));
    final gate = server.hold('api/task/priority/');
    await choose(tester, app.i18n.t('mobile:meta.priority.urgent'));
    expect(
      find.descendant(
        of: card('task-1'),
        matching: find.text(app.i18n.t('mobile:meta.priority.urgent')),
      ),
      findsOneWidget,
    );
    gate.release();
    await tester.pumpAndSettle();
    expect(server.tasks.first['priority'], 'urgent');
  });

  testBothLayouts('menu sets and clears assignee', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.assignee'));
    final gate = server.hold('api/task/assignee/');
    await choose(tester, 'Second User');
    expect(
      find.descendant(of: card('task-1'), matching: find.byTooltip('Second User')),
      findsOneWidget,
    );
    gate.release();
    await tester.pumpAndSettle();
    expect(server.tasks.first['userId'], 'user-2');
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.assignee'));
    await choose(tester, app.i18n.t('mobile:taskFields.unassigned'));
    expect(find.descendant(of: card('task-1'), matching: find.byType(CircleAvatar)), findsNothing);
    expect(server.tasks.first['userId'], isNull);
  });

  testBothLayouts('menu sends task to bottom and top without reopening the board', (
    tester,
    size,
  ) async {
    final app = await pumpKaneoApp(
      tester,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.sendToBottomOfColumn'));
    expect(tester.getTopLeft(card('task-1')).dy, greaterThan(tester.getTopLeft(card('task-2')).dy));
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.sendToTopOfColumn'));
    expect(tester.getTopLeft(card('task-1')).dy, lessThan(tester.getTopLeft(card('task-2')).dy));
  });

  testBothLayouts('rejected edit restores priority and shows server reason', (tester, size) async {
    final server = FakeKaneo()
      ..fail('api/task/priority/', status: 403, body: {'message': 'Cannot edit'});
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.priority'));
    await tester.tap(find.text(app.i18n.t('mobile:meta.priority.urgent')).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Cannot edit'), findsWidgets);
    expect(
      find.descendant(
        of: card('task-1'),
        matching: find.text(app.i18n.t('mobile:meta.priority.high')),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  testBothLayouts('dismissed menu and priority picker make no writes', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await menu(tester, 'task-1');
    await choose(tester, app.i18n.t('mobile:board.priority'));
    app.container.read(routerProvider).pop();
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testBothLayouts('assignee lookup failure explains the error and keeps the card', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()
      ..fail(
        'api/workspace/${FakeKaneo.workspaceId}/members',
        status: 403,
        body: {'message': 'Members unavailable'},
      );
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    await menu(tester, 'task-1');
    await tester.tap(find.text(app.i18n.t('mobile:board.assignee')));
    await tester.pumpAndSettle();
    expect(find.text('Members unavailable'), findsWidgets);
    expect(card('task-1'), findsOneWidget);
    expect(server.requestsTo('api/task/assignee/'), isEmpty);
  });
}
