import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_card.dart';

import '../../support/test_app.dart';

Finder card(String id) => find.byKey(ValueKey('board-card-$id'));
Finder column(String slug) => find.byKey(ValueKey('drop-column-$slug'));

Future<void> goTo(WidgetTester tester, TestGesture gesture, Offset point) async {
  await gesture.moveTo(point);
  await tester.pump(const Duration(milliseconds: 30));
}

/// The middle of a card's title, away from its handle.
Offset cardBody(WidgetTester tester, String id) => tester.getCenter(
  find.descendant(of: card(id), matching: find.text(tester.widget<BoardCard>(card(id)).task.title)),
);

/// Long enough for a press to pick a card up.
const held = Duration(milliseconds: 600);

/// On iPhone and iPad a finger could only move a card by its handle, and a mouse not at all (KAN-69).
void onIOS(String description, Future<void> Function(WidgetTester tester, Size size) body) {
  testBothLayouts('on iOS, $description', (tester, size) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body(tester, size);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<TestApp> pumpBoard(WidgetTester tester, FakeKaneo server, Size size) => pumpKaneoApp(
  tester,
  server: server,
  size: size,
  location: AppRoutes.board(FakeKaneo.projectId),
);

Offset inProgress(WidgetTester tester) {
  final header = tester.getRect(find.byKey(const ValueKey('column-header-in-progress')));
  return Offset(header.left + 20, header.center.dy);
}

String? statusOf(FakeKaneo server, String id) =>
    server.tasks.firstWhere((t) => t['id'] == id)['status'] as String?;

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
      final gesture = await pickUpCard(tester, 'task-1', kind: kind);
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
      final gesture = await pickUpCard(tester, 'task-2', kind: kind);
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
    final gesture = await pickUpCard(tester, 'task-1');
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
    final gesture = await pickUpCard(tester, 'task-1');
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

  onIOS('a mouse drags the card itself to another column', (tester, size) async {
    final server = FakeKaneo();
    await pumpBoard(tester, server, size);
    final gesture = await tester.startGesture(
      cardBody(tester, 'task-1'),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(5, 5));
    await tester.pump();
    await goTo(tester, gesture, inProgress(tester));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(statusOf(server, 'task-1'), 'in-progress');
    expect(taskOpen('task-1'), findsNothing);
  });

  // A trackpad on an iPad is a mouse, and people often rest on the card before moving it.
  onIOS('a mouse held still on the card drags it, and only a right click opens the menu', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final app = await pumpBoard(tester, server, size);
    final gesture = await tester.startGesture(
      cardBody(tester, 'task-1'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(held);
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsNothing);
    await gesture.moveBy(const Offset(5, 5));
    await tester.pump();
    await goTo(tester, gesture, inProgress(tester));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(statusOf(server, 'task-1'), 'in-progress');
  });

  onIOS('a finger picks the card itself up with a long press and moves it', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpBoard(tester, server, size);
    final cards = find.byType(BoardCard).evaluate().length;
    final gesture = await tester.startGesture(cardBody(tester, 'task-1'));
    await tester.pump(held);
    expect(find.byType(BoardCard), findsNWidgets(cards + 1), reason: 'The card was not picked up');
    await goTo(tester, gesture, inProgress(tester));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(statusOf(server, 'task-1'), 'in-progress');
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsNothing);
    expect(taskOpen('task-1'), findsNothing);
  });

  onIOS('a long press let go of in place opens the menu and moves nothing', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpBoard(tester, server, size);
    final gesture = await tester.startGesture(cardBody(tester, 'task-1'));
    await tester.pump(held);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsOneWidget);
    expect(server.requestsTo('api/task/reorder'), isEmpty);
    expect(statusOf(server, 'task-1'), 'to-do');
    expect(taskOpen('task-1'), findsNothing);
  });

  onIOS('a finger that moves at once scrolls the board and leaves the card', (tester, size) async {
    final server = FakeKaneo();
    await pumpBoard(tester, server, size);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const ValueKey('board-horizontal')))
        .controller!;
    final gesture = await tester.startGesture(cardBody(tester, 'task-1'));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(server.requestsTo('api/task/reorder'), isEmpty);
    expect(statusOf(server, 'task-1'), 'to-do');
  });

  // A move takes a moment to save on a distant server. A long press on the next card used to open
  // its menu meanwhile, and a card dropped meanwhile went back where it was.
  onIOS('while a move saves, a finger picks the next card up, and its drop lands after', (
    tester,
    size,
  ) async {
    final server = FakeKaneo()..relations.clear();
    final app = await pumpBoard(tester, server, size);
    final gate = server.hold('api/task/reorder');
    final first = await pickUpCard(tester, 'task-1');
    await goTo(tester, first, inProgress(tester));
    await first.up();
    await tester.pump();
    final second = await tester.startGesture(cardBody(tester, 'task-2'));
    await tester.pump(held);
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsNothing);
    await goTo(tester, second, inProgress(tester));
    await second.up();
    await tester.pump();
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsNothing);
    gate.release();
    await tester.pumpAndSettle();
    expect(statusOf(server, 'task-1'), 'in-progress');
    expect(statusOf(server, 'task-2'), 'in-progress');
    expect(find.descendant(of: column('in-progress'), matching: card('task-2')), findsOneWidget);
  });

  // A palm or another finger on the board used to stand in for the finger carrying the card.
  onIOS('another finger on the board neither undoes a drag nor opens the menu', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final app = await pumpBoard(tester, server, size);
    final carrying = await tester.startGesture(cardBody(tester, 'task-1'));
    await tester.pump(held);
    await goTo(tester, carrying, inProgress(tester));
    final other = await tester.startGesture(cardBody(tester, 'task-3'), pointer: 7);
    await tester.pump(const Duration(milliseconds: 50));
    await carrying.up();
    await other.up();
    await tester.pumpAndSettle();
    expect(statusOf(server, 'task-1'), 'in-progress');
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsNothing);
  });

  onIOS('a card carried away and brought back is put down without the menu', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpBoard(tester, server, size);
    final start = cardBody(tester, 'task-1');
    final gesture = await tester.startGesture(start);
    await tester.pump(held);
    await goTo(tester, gesture, start + const Offset(0, 120));
    await goTo(tester, gesture, start);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsNothing);
    expect(server.requestsTo('api/task/reorder'), isEmpty);
  });

  // Tooltips answer a long press too, and used to take it from the card.
  for (final (part, finder) in [
    ('assignee', find.descendant(of: card('task-1'), matching: find.byType(CircleAvatar))),
    ('expand arrow', find.byKey(const ValueKey('expand-task-task-1'))),
  ]) {
    onIOS('a long press on the $part picks the card up as well', (tester, size) async {
      final server = FakeKaneo();
      await pumpBoard(tester, server, size);
      final gesture = await tester.startGesture(tester.getCenter(finder));
      await tester.pump(held);
      await goTo(tester, gesture, inProgress(tester));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(statusOf(server, 'task-1'), 'in-progress');
      expect(find.byType(Tooltip), findsWidgets);
    });
  }
}
