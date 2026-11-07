import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../../support/test_app.dart';

Finder card(String id) => find.byKey(ValueKey('board-card-$id'));

/// Long-presses [id]'s card and returns what its menu offers.
Future<List<String>> menuOf(WidgetTester tester, I18n i18n, String id) async {
  await tester.longPress(find.descendant(of: card(id), matching: find.text('Set up the project')));
  await tester.pumpAndSettle();
  final offered = [
    for (final key in [
      'moveTo',
      'assignee',
      'priority',
      'sendToTopOfColumn',
      'sendToBottomOfColumn',
      'openTask',
    ])
      if (find.text(i18n.t('mobile:board.$key')).evaluate().isNotEmpty) key,
  ];
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
  return offered;
}

Future<TestApp> pumpBoard(WidgetTester tester, FakeKaneo server, Size size) => pumpKaneoApp(
  tester,
  server: server,
  size: size,
  location: AppRoutes.board(FakeKaneo.projectId),
);

/// What a viewer gets from the server: seeing, and nothing else.
FakeKaneo viewer() => FakeKaneo()..capabilities.updateAll((_, _) => false);

void main() {
  testBothLayouts('a viewer is not offered new tasks anywhere on the board', (tester, size) async {
    final server = viewer();
    await pumpBoard(tester, server, size);
    expect(find.byTooltip('New task'), findsNothing);
    expect(find.byTooltip('Add task'), findsNothing);
    expect(find.byKey(const ValueKey('add-task-column-to-do')), findsNothing);
    // The board itself still shows.
    expect(card('task-1'), findsOneWidget);
  });

  testBothLayouts('a viewer is not offered a task in an empty column', (tester, size) async {
    final server = viewer()..tasks.clear();
    await pumpBoard(tester, server, size);
    expect(find.byKey(const ValueKey('add-task-empty-to-do')), findsNothing);
    expect(find.text('Add task'), findsNothing);
  });

  testBothLayouts('a viewer is not offered a task on a board without columns', (
    tester,
    size,
  ) async {
    final server = viewer()
      ..tasks.clear()
      ..columns.clear();
    await pumpBoard(tester, server, size);
    expect(find.byKey(const ValueKey('board-empty-add-task')), findsNothing);
  });

  testBothLayouts('a viewer\'s card menu only opens the task', (tester, size) async {
    final server = viewer();
    final app = await pumpBoard(tester, server, size);
    expect(await menuOf(tester, app.i18n, 'task-1'), ['openTask']);
  });

  // Desktops pick a card up by its body as well as by its grip.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testBothLayouts('a viewer cannot pick a card up on ${platform.name}', (tester, size) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final server = viewer();
        await pumpBoard(tester, server, size);
        expect(card('task-1'), findsOneWidget);
        expect(find.byKey(const ValueKey('drag-handle-task-1')), findsNothing);
        expect(find.byType(Draggable<String>), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testBothLayouts('each permission brings back its own actions', (tester, size) async {
    final server = viewer()..capabilities['assignTasks'] = true;
    final app = await pumpBoard(tester, server, size);
    expect(await menuOf(tester, app.i18n, 'task-1'), ['assignee', 'openTask']);
    expect(find.byTooltip('New task'), findsNothing);

    server.capabilities
      ..['assignTasks'] = false
      ..['updateTasks'] = true;
    await tester.pumpWidget(const SizedBox());
    final again = await pumpBoard(tester, server, size);
    expect(await menuOf(tester, again.i18n, 'task-1'), [
      'moveTo',
      'priority',
      'sendToTopOfColumn',
      'sendToBottomOfColumn',
      'openTask',
    ]);
    expect(find.byKey(const ValueKey('drag-handle-task-1')), findsOneWidget);
    expect(find.byTooltip('New task'), findsNothing);
  });

  testBothLayouts('creating tasks brings back every way to start one', (tester, size) async {
    final server = viewer()..capabilities['createTasks'] = true;
    await pumpBoard(tester, server, size);
    expect(find.byTooltip('New task'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-task-column-to-do')), findsOneWidget);
  });

  testBothLayouts('the list view\'s menu follows the same permissions', (tester, size) async {
    final server = viewer();
    final app = await pumpBoard(tester, server, size);
    await tester.tap(find.byTooltip(app.i18n.t('mobile:board.listView')));
    await tester.pumpAndSettle();
    await tester.longPress(
      find.descendant(
        of: find.byKey(const ValueKey('list-task-task-1')),
        matching: find.text('Set up the project'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(app.i18n.t('mobile:board.openTask')), findsOneWidget);
    expect(find.text(app.i18n.t('mobile:board.moveTo')), findsNothing);
  });

  testBothLayouts('until permissions load, the board offers everything', (tester, size) async {
    final server = viewer();
    final gate = server.hold('capabilities');
    await pumpBoard(tester, server, size);
    expect(find.byTooltip('New task'), findsOneWidget);
    gate.release();
    await tester.pumpAndSettle();
    expect(find.byTooltip('New task'), findsNothing);
  });
}
