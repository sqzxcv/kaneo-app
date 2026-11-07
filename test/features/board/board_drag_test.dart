import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../../support/test_app.dart';

Finder card(String id) => find.byKey(ValueKey('board-card-$id'));
Finder column(String slug) => find.byKey(ValueKey('drop-column-$slug'));

Future<TestGesture> startDrag(WidgetTester tester, String id, PointerDeviceKind kind) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey('drag-handle-$id'))),
    kind: kind,
  );
  await gesture.moveBy(const Offset(4, 4));
  await tester.pump();
  return gesture;
}

Future<void> goTo(WidgetTester tester, TestGesture gesture, Offset point) async {
  await gesture.moveTo(point);
  await tester.pump(const Duration(milliseconds: 30));
}

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testBothLayouts('$kind moves to a custom column immediately, saves without refetching', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.columns[1]['name'] = '已计划';
      server.columns[1]['slug'] = 'custom-plan';
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      final gate = server.hold('api/task/reorder');
      final boardReads = server.requestsTo('api/task/tasks/').length;
      final gesture = await startDrag(tester, 'task-1', kind);
      final header = tester.getRect(find.byKey(const ValueKey('column-header-custom-plan')));
      await goTo(tester, gesture, Offset(header.left + 20, header.center.dy));
      await gesture.up();
      await tester.pump();
      expect(find.descendant(of: column('custom-plan'), matching: card('task-1')), findsOneWidget);
      expect(find.descendant(of: column('to-do'), matching: card('task-1')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(server.requestsTo('api/task/tasks/').length, boardReads);
      gate.release();
      await tester.pumpAndSettle();
      expect(server.tasks.firstWhere((t) => t['id'] == 'task-1')['status'], 'custom-plan');
      final reload = app.container.read(boardQuery(FakeKaneo.projectId).notifier).refresh();
      await tester.pumpAndSettle();
      await reload;
      expect(find.descendant(of: column('custom-plan'), matching: card('task-1')), findsOneWidget);
    });

    testBothLayouts('$kind reorders within a column', (tester, size) async {
      final server = FakeKaneo()..relations.clear();
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      final target = tester.getRect(find.byKey(const ValueKey('drop-card-task-1')));
      final gesture = await startDrag(tester, 'task-2', kind);
      await goTo(tester, gesture, target.topLeft + const Offset(100, 12));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(card('task-2')).dy, lessThan(tester.getTopLeft(card('task-1')).dy));
      expect(server.tasks.firstWhere((t) => t['id'] == 'task-2')['position'], 0);
    });
  }

  testBothLayouts('failed move restores original position and keeps other columns stable', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()
      ..fail('api/task/reorder', status: 403, body: {'message': 'Read only'});
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    final before = tester.getTopLeft(card('task-1'));
    final other = tester.getTopLeft(card('task-5'));
    final gesture = await startDrag(tester, 'task-1', PointerDeviceKind.touch);
    final header = tester.getRect(find.byKey(const ValueKey('column-header-in-progress')));
    await goTo(tester, gesture, Offset(header.left + 20, header.center.dy));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Read only'), findsWidgets);
    expect(tester.getTopLeft(card('task-1')), before);
    expect(tester.getTopLeft(card('task-5')), other);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  });

  testBothLayouts('holding a dragged card at the edge scrolls the board, then stops on cancel', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const ValueKey('board-horizontal')))
        .controller!;
    final gesture = await startDrag(tester, 'task-1', PointerDeviceKind.touch);
    await goTo(tester, gesture, Offset(size.width - 4, 150));
    await tester.pump(const Duration(milliseconds: 400));
    expect(scroll.offset, greaterThan(0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    final stopped = scroll.offset;
    await tester.pump(const Duration(milliseconds: 400));
    expect(scroll.offset, stopped);
    expect(server.requestsTo('api/task/reorder'), isEmpty);
  });

  testWidgets('desktop mouse drags the card body', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, location: AppRoutes.board(FakeKaneo.projectId));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Set up the project')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(5, 5));
      await tester.pump();
      await goTo(
        tester,
        gesture,
        // Next to the sidebar the last column runs off the page, so aim for the start of its header.
        tester.getTopLeft(find.byKey(const ValueKey('column-header-done'))) + const Offset(20, 20),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(server.tasks.firstWhere((t) => t['id'] == 'task-1')['status'], 'done');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
