import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_page.dart';
import 'package:kaneo_app/features/inbox/my_tasks_page.dart';
import 'package:kaneo_app/features/markdown/markdown_field.dart';
import 'package:kaneo_app/features/shell/app_shell.dart' show shellPageKey;
import 'package:kaneo_app/features/shell/app_sidebar.dart';
import 'package:kaneo_app/features/task/description_autosave.dart';
import 'package:kaneo_app/features/task/open_task.dart';
import 'package:kaneo_app/features/task/task_description.dart';
import 'package:kaneo_app/features/task/task_page.dart';
import 'package:kaneo_app/features/task/task_panel.dart';
import 'package:kaneo_app/features/task/task_properties.dart';

import '../../support/test_app.dart';

final _panel = find.byKey(taskPanelKey);
final _title = find.byKey(const ValueKey('task-title'));
Finder _card(String id) => find.byKey(ValueKey('board-card-$id'));

Future<TestApp> _openBoard(WidgetTester tester, Size size, {FakeKaneo? server}) => pumpKaneoApp(
  tester,
  server: server,
  size: size,
  location: AppRoutes.board(FakeKaneo.projectId),
);

Future<void> _openCard(WidgetTester tester, String id) async {
  await tester.ensureVisible(_card(id));
  await tester.pumpAndSettle();
  await tester.tap(_card(id));
  await tester.pumpAndSettle();
}

Future<void> _resize(WidgetTester tester, Size size) async {
  setWindowSize(tester, size);
  await tester.pumpAndSettle();
}

void _expectTwoColumns(WidgetTester tester) {
  final title = tester.getRect(_title);
  final properties = tester.getRect(find.byType(TaskProperties));
  final description = tester.getRect(find.byType(TaskDescription));
  expect(properties.left, greaterThan(title.right));
  expect(properties.top, lessThan(title.bottom));
  expect(description.top, greaterThanOrEqualTo(title.bottom));
  expect(description.right, lessThan(properties.left));
}

void _expectOneColumn(WidgetTester tester) {
  final title = tester.getRect(_title);
  final properties = tester.getRect(find.byType(TaskProperties));
  final description = tester.getRect(find.byType(TaskDescription));
  expect(properties.top, greaterThanOrEqualTo(title.bottom));
  expect(description.top, greaterThanOrEqualTo(properties.bottom));
  expect(properties.left, title.left);
  expect(description.left, title.left);
}

void main() {
  group('on a wide window', () {
    testWidgets('a card slides out a panel from the right, and the board stays in view', (
      tester,
    ) async {
      await _openBoard(tester, wideSize);
      await tester.ensureVisible(_card('task-1'));
      await tester.pumpAndSettle();
      await tester.tap(_card('task-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final page = tester.getRect(find.byKey(shellPageKey));
      final sliding = tester.getRect(_panel).left;
      await tester.pumpAndSettle();
      final panel = tester.getRect(_panel);
      expect(sliding, greaterThan(panel.left));
      expect(panel.right, page.right);
      expect(panel.width, lessThan(page.width));

      // The board is still there next to it, and it is the same page as before.
      expect(find.byType(BoardPage), findsOneWidget);
      expect(tester.getTopLeft(_card('task-1')).dx, lessThan(panel.left));
      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.byType(TaskPage), findsNothing);
      expect(taskOpen('task-1'), findsOneWidget);
      _expectTwoColumns(tester);
    });

    testWidgets('closing returns to the same scroll position', (tester) async {
      final server = FakeKaneo();
      for (var i = 0; i < 30; i++) {
        server.addTask(id: 'extra-$i', title: 'Extra $i');
      }
      await _openBoard(tester, wideSize, server: server);
      final lane = find.byKey(PageStorageKey('column-tasks-${server.columns.first['slug']}'));
      await tester.drag(lane, const Offset(0, -900));
      await tester.pumpAndSettle();
      final card = _card('extra-12');
      final before = tester.getTopLeft(card);
      expect(before.dy, lessThan(800));

      // By the close button.
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(taskOpen('extra-12'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(tester.getTopLeft(card), before);

      // By a tap beside the panel.
      await tester.tap(card);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(_panel) + const Offset(-40, 300));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(tester.getTopLeft(card), before);
    });

    testWidgets('a list view row opens the panel and keeps its place too', (tester) async {
      final server = FakeKaneo();
      for (var i = 0; i < 30; i++) {
        server.addTask(id: 'extra-$i', title: 'Extra $i');
      }
      await _openBoard(tester, wideSize, server: server);
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      await tester.drag(inPage(find.byType(Scrollable)).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('list-task-extra-15'));
      final before = tester.getTopLeft(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(taskOpen('extra-15'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(row), before);
    });

    testWidgets('a list on another page opens the panel over that page', (tester) async {
      await pumpKaneoApp(tester, size: wideSize, location: AppRoutes.myTasks);
      await tester.tap(find.text('Set up the project'));
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
      expect(find.byType(MyTasksPage), findsOneWidget);
    });

    testWidgets('the panel stays one column where two would not fit', (tester) async {
      await pumpKaneoApp(tester, size: const Size(800, 1000), location: AppRoutes.myTasks);
      await tester.tap(find.text('Set up the project'));
      await tester.pumpAndSettle();
      _expectOneColumn(tester);
      final panel = tester.getRect(_panel);
      expect(panel.left, greaterThan(tester.getRect(find.byKey(shellPageKey)).left));
    });

    testWidgets('back closes the panel and leaves the board', (tester) async {
      final app = await _openBoard(tester, wideSize);
      final router = app.container.read(routerProvider);
      await _openCard(tester, 'task-1');
      router.pop();
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(router.state.uri.path, AppRoutes.board(FakeKaneo.projectId));
    });

    testWidgets('going elsewhere from the sidebar closes the panel', (tester) async {
      await _openBoard(tester, wideSize);
      await _openCard(tester, 'task-1');
      await tester.tap(find.descendant(of: find.byType(AppSidebar), matching: find.text('Inbox')));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
    });

    testWidgets('a task opened from the panel opens over it, and closes back to it', (
      tester,
    ) async {
      await _openBoard(tester, wideSize);
      await _openCard(tester, 'task-1');
      openTask(tester.element(_title), 'task-2');
      await tester.pumpAndSettle();
      expect(taskOpen('task-2'), findsOneWidget);
      expect(taskOpen('task-1'), findsOneWidget);
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      expect(taskOpen('task-2'), findsNothing);
      expect(taskOpen('task-1'), findsOneWidget);
    });

    testWidgets('turning narrow fills the window and keeps what is being typed', (tester) async {
      await _openBoard(tester, wideSize);
      await _openCard(tester, 'task-1');
      await tester.enterText(_title, 'Half a thought');
      await tester.tapAt(tester.getTopLeft(find.byType(TaskDescription)) + const Offset(8, 8));
      await tester.pumpAndSettle();
      final box = find.descendant(
        of: find.descendant(of: find.byType(TaskDescription), matching: find.byType(MarkdownField)),
        matching: find.byType(TextField),
      );
      await tester.enterText(box, 'Half a sentence');

      await _resize(tester, narrowSize);
      expect(tester.getSize(_panel).width, narrowSize.width);
      _expectOneColumn(tester);
      expect(tester.widget<TextField>(box).controller!.text, 'Half a sentence');

      await _resize(tester, wideSize);
      expect(tester.getSize(_panel).width, lessThan(wideSize.width));
      _expectTwoColumns(tester);
      expect(tester.widget<TextField>(box).controller!.text, 'Half a sentence');

      await tester.pump(descriptionSaveDelay);
      await tester.pumpAndSettle();
    });
  });

  group('on a narrow window', () {
    testWidgets('a card opens a full page with one column', (tester) async {
      final app = await _openBoard(tester, narrowSize);
      await _openCard(tester, 'task-1');
      expect(find.byType(TaskPage), findsOneWidget);
      expect(_panel, findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.task('task-1'));
      expect(tester.getSize(find.byType(TaskPage)), narrowSize);
      _expectOneColumn(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        app.container.read(routerProvider).state.uri.path,
        AppRoutes.board(FakeKaneo.projectId),
      );
    });

    testWidgets('a list on a tab opens a full page without the tabs', (tester) async {
      await pumpKaneoApp(tester, size: narrowSize, location: AppRoutes.myTasks);
      await tester.tap(find.text('Set up the project'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.getSize(find.byType(TaskPage)), narrowSize);
    });

    testWidgets('a landscape phone is still one column', (tester) async {
      await _openBoard(tester, const Size(844, 390));
      await _openCard(tester, 'task-1');
      expect(find.byType(TaskPage), findsOneWidget);
    });
  });

  group('from a link or a notification', () {
    testBothLayouts('a link shows the full page', (tester, size) async {
      await pumpKaneoApp(tester, size: size, location: AppRoutes.task('task-1'));
      expect(find.byType(TaskPage), findsOneWidget);
      expect(_panel, findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      size == wideSize ? _expectTwoColumns(tester) : _expectOneColumn(tester);
    });

    testBothLayouts('a notification opens the full page, and back returns to where it was', (
      tester,
      size,
    ) async {
      final app = await pumpKaneoApp(tester, size: size, location: AppRoutes.inbox);
      final router = app.container.read(routerProvider);
      openTaskPage(tester.element(find.byType(Scaffold).last), 'task-1');
      await tester.pumpAndSettle();
      expect(find.byType(TaskPage), findsOneWidget);
      expect(_panel, findsNothing);
      expect(router.state.uri.path, AppRoutes.task('task-1'));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.inbox);
    });

    testBothLayouts('a desktop notification, with no page to open from, opens the full page', (
      tester,
      size,
    ) async {
      final app = await pumpKaneoApp(tester, size: size, location: AppRoutes.inbox);
      final router = app.container.read(routerProvider);
      openTask(router.routerDelegate.navigatorKey.currentContext!, 'task-1');
      await tester.pumpAndSettle();
      expect(find.byType(TaskPage), findsOneWidget);
      expect(_panel, findsNothing);
      expect(router.state.uri.path, AppRoutes.task('task-1'));
    });

    testBothLayouts('a link to another task shows that task', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size, location: AppRoutes.task('task-1'));
      app.container.read(routerProvider).go(AppRoutes.task('task-3'));
      await tester.pumpAndSettle();
      expect(taskOpen('task-3'), findsOneWidget);
      expect(tester.widget<TextField>(_title).controller!.text, 'Review the board layout');
    });
  });

  group('while loading and when it fails', () {
    testBothLayouts('shows a spinner, with a way out, until the task arrives', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final gate = server.hold('api/task/task-1');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(_title, findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_title, findsOneWidget);
    });

    testWidgets('the panel shows a spinner and can be closed before the task arrives', (
      tester,
    ) async {
      final server = FakeKaneo();
      await _openBoard(tester, wideSize, server: server);
      final gate = server.hold('api/task/task-1');
      await tester.ensureVisible(_card('task-1'));
      await tester.pumpAndSettle();
      await tester.tap(_card('task-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(of: _panel, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_panel, findsNothing);
      gate.release();
      await tester.pumpAndSettle();
    });

    testBothLayouts('a failure says so and can be retried', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/task-1', status: 500);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
      );
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      expect(_title, findsNothing);

      server.clearOverrides();
      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(_title, findsOneWidget);
    });

    testBothLayouts('no permission says so, with nothing to retry', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/task-1', status: 403);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
      );
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
    });

    testBothLayouts('the task shows while its other parts have failed', (tester, size) async {
      final server = FakeKaneo()
        ..fail('api/column/')
        ..fail('api/label/')
        ..fail('capabilities')
        ..fail('members');
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('task-1'));
      expect(_title, findsOneWidget);
      expect(find.byType(TaskProperties), findsOneWidget);
      expect(find.text('to-do'), findsOneWidget);
    });
  });
}
