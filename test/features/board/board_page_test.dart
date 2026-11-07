import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_card.dart';
import 'package:kaneo_app/features/board/board_orientation.dart';

import '../../support/test_app.dart';

Finder lane(FakeKaneo server, int index) =>
    find.byKey(PageStorageKey('column-tasks-${server.columns[index]['slug']}'));

void main() {
  test('only mobile platforms on a display under 600dp lock orientation', () {
    for (final platform in TargetPlatform.values) {
      expect(
        isPhoneDisplay(platform, const Size(1170, 2532), 3),
        platform == TargetPlatform.iOS || platform == TargetPlatform.android,
      );
      expect(isPhoneDisplay(platform, const Size(1800, 2400), 3), isFalse);
      expect(isPhoneDisplay(platform, const Size(2400, 1800), 3), isFalse);
    }
  });

  testBothLayouts('columns stay side by side, with fixed headers and custom columns', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.columns.first['name'] = '需求池';
    server.columns.first['icon'] = 'Inbox';
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    final firstHeader = find.byKey(ValueKey('column-header-${server.columns[0]['slug']}'));
    final nextHeader = find.byKey(ValueKey('column-header-${server.columns[1]['slug']}'));
    final before = tester.getTopLeft(firstHeader);
    expect(tester.getTopLeft(nextHeader).dy, before.dy);
    expect(tester.getTopLeft(nextHeader).dx, greaterThan(before.dx + 250));
    await tester.drag(lane(server, 0), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstHeader), before);
    await tester.drag(find.byKey(const ValueKey('board-horizontal')), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstHeader).dx, lessThan(before.dx));
    expect(find.text('需求池'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('card shows id, title, assignee, priority, date, labels and subtasks', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    server.tasks.first['dueDate'] = '2027-01-18';
    server.addLabel('B-visual', taskId: 'task-1');
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    final card = find.byKey(const ValueKey('board-card-task-1'));
    for (final text in [
      'DEMO-1',
      'Set up the project',
      'B-visual',
      '0/1',
      app.i18n.t('mobile:meta.priority.high'),
      formatDueShort(app.i18n, '2027-01-18'),
    ]) {
      expect(find.descendant(of: card, matching: find.text(text)), findsOneWidget);
    }
    expect(find.descendant(of: card, matching: find.byTooltip('Test User')), findsOneWidget);
    await tester.tap(find.text('Set up the project'));
    await tester.pumpAndSettle();
    expect(taskOpen('task-1'), findsOneWidget);
  });

  testBothLayouts('one pull refresh keeps all columns and card positions', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    final first = find.byKey(const ValueKey('board-card-task-1'));
    final before = tester.getTopLeft(first);
    final gate = server.hold('api/task/tasks/');
    await tester.drag(lane(server, 0), const Offset(0, 350));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.getTopLeft(first), before);
    gate.release();
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(tester.getTopLeft(first), before);
  });

  testBothLayouts('refresh failure keeps cards and explains the error', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    server.fail('api/task/tasks/', status: 500, body: {'message': 'Refresh unavailable'});
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Refresh unavailable'), findsOneWidget);
    expect(find.text('Set up the project'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testBothLayouts('100 cards are lazy and reachable without moving the column header', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()..tasks.clear();
    server.boardPageSize = 30;
    for (var index = 0; index < 100; index++) {
      server.addTask(title: 'Card $index');
    }
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    expect(find.byType(BoardCard).evaluate().length, lessThan(25));
    expect(find.text('100 tasks'), findsOneWidget);
    final header = find.byKey(ValueKey('column-header-${server.columns.first['slug']}'));
    final before = tester.getTopLeft(header);
    await tester.dragUntilVisible(
      find.text('Card 99'),
      lane(server, 0),
      const Offset(0, -650),
      maxIteration: 30,
    );
    await tester.pumpAndSettle();
    expect(find.text('Card 99'), findsOneWidget);
    expect(tester.getTopLeft(header).dy, before.dy);
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('board loading, empty columns and zero columns are readable', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()..tasks.clear();
    final gate = server.hold('api/task/tasks/');
    final app = await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
      settle: false,
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.release();
    await tester.pumpAndSettle();
    expect(find.text(app.i18n.t('mobile:board.noTasksHere')), findsNWidgets(4));
    server.columns.clear();
    final refresh = app.container.read(boardQuery(FakeKaneo.projectId).notifier).refresh();
    await tester.pumpAndSettle();
    await refresh;
    expect(find.text(app.i18n.t('mobile:board.noTasksHere')), findsOneWidget);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS]) {
    for (final display in [const Size(390, 844), const Size(1024, 1366)]) {
      testWidgets(
        '$platform $display uses display size and releases orientation on task navigation',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.display.size = display;
          tester.view.display.devicePixelRatio = 1;
          addTearDown(tester.view.display.reset);
          final calls = <List<dynamic>>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              calls.add(call.arguments as List<dynamic>);
            }
            return null;
          });
          addTearDown(
            () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            ),
          );
          final app = await pumpKaneoApp(
            tester,
            size: narrowSize.flipped,
            location: AppRoutes.board(FakeKaneo.projectId),
          );
          final phone = display.shortestSide < 600 && platform != TargetPlatform.macOS;
          expect(
            calls,
            phone
                ? [
                    ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
                  ]
                : isEmpty,
          );
          expect(find.byType(NavigationBar), findsNothing);
          expect(tester.getSize(find.byType(AppBar)).height, 48);
          await tester.tap(find.text('Set up the project'));
          await tester.pumpAndSettle();
          if (phone) expect(calls.last, isEmpty);
          app.container.read(routerProvider).pop();
          await tester.pumpAndSettle();
          if (phone) expect(calls.last.length, 2);
          app.container.read(routerProvider).go(AppRoutes.home);
          await tester.pumpAndSettle();
          if (phone) expect(calls.last, isEmpty);
          if (!phone) expect(calls, isEmpty);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  testWidgets('list mode releases orientation', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.display.size = narrowSize;
    tester.view.display.devicePixelRatio = 1;
    addTearDown(tester.view.display.reset);
    final calls = <List<dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        calls.add(call.arguments as List<dynamic>);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpKaneoApp(
      tester,
      size: narrowSize.flipped,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    expect(calls.single.length, 2);
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(calls.last, isEmpty);
    await tester.tap(find.byTooltip('Board view'));
    await tester.pumpAndSettle();
    expect(calls.last.length, 2);
    debugDefaultTargetPlatformOverride = null;
  });
}
