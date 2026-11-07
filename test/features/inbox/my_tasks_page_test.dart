import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/task_panel.dart';

import '../../support/test_app.dart';

const _late = 'Late task';
const _dueToday = 'Due today';
const _dueSoon = 'Due soon';
const _dueLater = 'Due later';
const _noDate = 'No date';
const _elsewhere = 'In the other project';

final DateTime _now = DateTime(2026, 11, 6, 9);

String _day(int month, int day) => DateTime(2026, month, day).toUtc().toIso8601String();

/// A task for each due-date group, across two projects and three statuses.
FakeKaneo _server() {
  final server = FakeKaneo.empty();
  server.addProject(id: 'p1', name: 'Alpha', slug: 'ALP');
  server.addProject(id: 'p2', name: 'Beta', slug: 'BET');
  server.addTask(id: 'late', projectId: 'p1', title: _late, dueDate: _day(11, 1));
  server.addTask(
    id: 'today',
    projectId: 'p2',
    title: _dueToday,
    status: 'in-progress',
    dueDate: _day(11, 6),
  );
  server.addTask(id: 'soon', projectId: 'p1', title: _dueSoon, dueDate: _day(11, 10));
  server.addTask(
    id: 'later',
    projectId: 'p1',
    title: _dueLater,
    status: 'in-review',
    dueDate: _day(12, 1),
  );
  server.addTask(id: 'none', projectId: 'p1', title: _noDate);
  server.addTask(id: 'elsewhere', projectId: 'p2', title: _elsewhere);
  server.addTask(id: 'theirs', projectId: 'p2', title: 'Not mine', assigneeId: 'user-2');
  return server;
}

Future<TestApp> _pump(
  WidgetTester tester,
  Size size, {
  FakeKaneo? server,
  String locale = defaultLocale,
  bool settle = true,
}) => pumpKaneoApp(
  tester,
  server: server ?? _server(),
  size: size,
  location: AppRoutes.myTasks,
  locale: locale,
  settle: settle,
  overrides: [nowProvider.overrideWithValue(() => _now)],
);

void _go(TestApp app, String location) => app.container.read(routerProvider).go(location);

/// What is on screen in the page, in order, out of [texts].
List<String> _order(WidgetTester tester, List<String> texts) {
  final found = [
    for (final text in texts)
      if (inPage(find.text(text)).evaluate().isNotEmpty)
        (text, tester.getTopLeft(inPage(find.text(text)).first).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (text, _) in found) text];
}

Future<void> _groupBy(WidgetTester tester, TestApp app, String key) async {
  await tester.tap(inPage(find.text(app.i18n.t(key))));
  await tester.pumpAndSettle();
}

void main() {
  group('grouping', () {
    testBothLayouts('starts by due date, with the most pressing on top', (tester, size) async {
      final app = await _pump(tester, size);
      String due(String bucket) => app.i18n.t('mobile:myTasks.due.$bucket');
      expect(
        _order(tester, [
          due('overdue'),
          due('today'),
          due('thisWeek'),
          due('later'),
          due('none'),
          _late,
          _dueToday,
          _dueSoon,
          _dueLater,
          _noDate,
        ]),
        [
          due('overdue'),
          _late,
          due('today'),
          _dueToday,
          due('thisWeek'),
          _dueSoon,
          due('later'),
          _dueLater,
          due('none'),
          _noDate,
        ],
      );
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('leaves out what is not assigned to me', (tester, size) async {
      await _pump(tester, size);
      expect(find.text('Not mine'), findsNothing);
    });

    testBothLayouts('leaves out empty groups', (tester, size) async {
      final server = FakeKaneo.empty();
      server.addProject(id: 'p1', name: 'Alpha', slug: 'ALP');
      server.addTask(projectId: 'p1', title: _noDate);
      final app = await _pump(tester, size, server: server);
      expect(find.text(app.i18n.t('mobile:myTasks.due.none')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:myTasks.due.overdue')), findsNothing);
      expect(find.text(app.i18n.t('mobile:myTasks.due.later')), findsNothing);
    });

    testBothLayouts('switches to projects', (tester, size) async {
      final app = await _pump(tester, size);
      await _groupBy(tester, app, 'mobile:myTasks.by.project');

      // Beta has the most pressing work after Alpha's overdue task, so Alpha comes first.
      final order = _order(tester, ['Alpha', _late, _noDate, 'Beta', _dueToday, _elsewhere]);
      expect(order.first, 'Alpha');
      expect(order.indexOf(_late), lessThan(order.indexOf('Beta')));
      expect(order.indexOf(_noDate), lessThan(order.indexOf('Beta')));
      expect(order.indexOf('Beta'), lessThan(order.indexOf(_dueToday)));
      expect(order.indexOf('Beta'), lessThan(order.indexOf(_elsewhere)));
      expect(find.text(app.i18n.t('mobile:myTasks.due.overdue')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('switches to statuses, and back', (tester, size) async {
      final app = await _pump(tester, size);
      await _groupBy(tester, app, 'mobile:myTasks.by.status');

      final toDo = app.i18n.t('tasks:status.to-do');
      final inProgress = app.i18n.t('tasks:status.in-progress');
      final inReview = app.i18n.t('tasks:status.in-review');
      final order = _order(tester, [toDo, _late, inProgress, _dueToday, inReview, _dueLater]);
      expect(order.indexOf(toDo), lessThan(order.indexOf(_late)));
      expect(order.indexOf(inProgress), lessThan(order.indexOf(_dueToday)));
      expect(order.indexOf(inReview), lessThan(order.indexOf(_dueLater)));
      expect(tester.takeException(), isNull);

      await _groupBy(tester, app, 'mobile:myTasks.by.due');
      expect(find.text(app.i18n.t('mobile:myTasks.due.overdue')), findsOneWidget);
    });

    testBothLayouts('every task stays there in every grouping', (tester, size) async {
      final app = await _pump(tester, size);
      for (final key in [
        'mobile:myTasks.by.project',
        'mobile:myTasks.by.status',
        'mobile:myTasks.by.due',
      ]) {
        await _groupBy(tester, app, key);
        for (final title in [_late, _dueToday, _dueSoon, _dueLater, _noDate, _elsewhere]) {
          await tester.scrollUntilVisible(
            inPage(find.text(title)),
            100,
            scrollable: inPage(find.byType(Scrollable)).last,
          );
          expect(inPage(find.text(title)), findsOneWidget, reason: '$title in $key');
        }
        await tester.drag(inPage(find.byType(ListView)), const Offset(0, 2000));
        await tester.pumpAndSettle();
      }
    });

    testBothLayouts('a group header says how many it has', (tester, size) async {
      final server = FakeKaneo.empty();
      server.addProject(id: 'p1', name: 'Alpha', slug: 'ALP');
      server.addTask(projectId: 'p1', title: 'One');
      server.addTask(projectId: 'p1', title: 'Two');
      server.addTask(projectId: 'p1', title: 'Three');
      final app = await _pump(tester, size, server: server);
      expect(find.text('3'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:myTasks.assigned', {'count': 3})), findsOneWidget);
    });

    testWidgets('survives the window crossing the breakpoint', (tester) async {
      final app = await _pump(tester, wideSize);
      await _groupBy(tester, app, 'mobile:myTasks.by.project');
      expect(inPage(find.text('Alpha')), findsOneWidget);

      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();

      expect(inPage(find.text('Alpha')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:myTasks.due.overdue')), findsNothing);
    });

    testBothLayouts('default columns follow the language', (tester, size) async {
      final app = await _pump(tester, size, locale: 'zh-CN');
      await _groupBy(tester, app, 'mobile:myTasks.by.status');
      expect(inPage(find.text(app.i18n.t('tasks:status.to-do'))), findsOneWidget);
      expect(find.text('To Do'), findsNothing);
    });

    testBothLayouts('a renamed column keeps its name', (tester, size) async {
      final server = _server();
      for (final column in server.columns) {
        if (column['slug'] == 'to-do') column['name'] = 'Backlog';
      }
      final app = await _pump(tester, size, server: server);
      await _groupBy(tester, app, 'mobile:myTasks.by.status');
      expect(inPage(find.text('Backlog')), findsOneWidget);
    });
  });

  group('the rows', () {
    testBothLayouts('show the ticket and the project', (tester, size) async {
      await _pump(tester, size);
      expect(inPage(find.text('ALP-1')), findsOneWidget);
      expect(inPage(find.text('Alpha')), findsWidgets);
    });

    testBothLayouts('leave out the project when grouped by it', (tester, size) async {
      final app = await _pump(tester, size);
      await _groupBy(tester, app, 'mobile:myTasks.by.project');
      // Only the group header.
      expect(inPage(find.text('Alpha')), findsOneWidget);
      expect(inPage(find.text('Beta')), findsOneWidget);
    });

    testBothLayouts('say when a task is due', (tester, size) async {
      final app = await _pump(tester, size);
      expect(find.text(app.i18n.t('mobile:time.today')), findsWidgets);
      expect(find.text(formatDueShort(app.i18n, _day(11, 1), now: _now)), findsOneWidget);
    });

    testBothLayouts('a long title and many labels fit', (tester, size) async {
      final server = _server();
      final task = server.addTask(projectId: 'p1', title: 'A very long title ' * 10);
      for (final name in ['first label', 'second label', 'third label']) {
        server.addLabel(name, taskId: task['id'] as String);
      }
      await _pump(tester, size, server: server);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stay on one line next to a wide sidebar, and stack when it leaves no room', (
      tester,
    ) async {
      await _pump(tester, wideSize);
      final title = tester.getTopLeft(inPage(find.text(_late)));
      final ticket = tester.getTopLeft(inPage(find.text('ALP-1')));
      expect(ticket.dx, lessThan(title.dx));

      setWindowSize(tester, const Size(600, 600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final stackedTitle = tester.getTopLeft(inPage(find.text(_late)));
      final stackedTicket = tester.getTopLeft(inPage(find.text('ALP-1')));
      expect(stackedTicket.dy, greaterThan(stackedTitle.dy));
    });

    testWidgets('the due date stays next to the task on a big window', (tester) async {
      final app = await pumpKaneoApp(
        tester,
        server: _server(),
        size: const Size(1920, 1080),
        location: AppRoutes.myTasks,
        overrides: [nowProvider.overrideWithValue(() => _now)],
      );
      final due = find.text(formatDueShort(app.i18n, _day(11, 1), now: _now));
      final column = tester.getRect(
        find.descendant(of: find.byType(ContentWidth), matching: find.byType(ConstrainedBox)).first,
      );
      expect(column.width, contentMaxWidth);
      expect(tester.getTopRight(due).dx, lessThanOrEqualTo(column.right));
    });
  });

  group('tapping a task', () {
    testWidgets('opens it in a panel over the list on a wide window', (tester) async {
      final app = await _pump(tester, wideSize);
      await tester.tap(inPage(find.text(_late)));
      await tester.pumpAndSettle();
      expect(taskOpen('late'), findsOneWidget);
      expect(find.byKey(taskPanelKey), findsOneWidget);
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.myTasks);
    });

    testWidgets('opens it as a page on a narrow window', (tester) async {
      final app = await _pump(tester, narrowSize);
      await tester.tap(inPage(find.text(_late)));
      await tester.pumpAndSettle();
      expect(taskOpen('late'), findsOneWidget);
      expect(find.byKey(taskPanelKey), findsNothing);
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.task('late'));
    });

    testBothLayouts('works from every grouping', (tester, size) async {
      final app = await _pump(tester, size);
      await _groupBy(tester, app, 'mobile:myTasks.by.status');
      await tester.tap(inPage(find.text(_dueToday)));
      await tester.pumpAndSettle();
      expect(taskOpen('today'), findsOneWidget);
    });
  });

  group('coming back to the page', () {
    testBothLayouts('shows what it had at once, then what is new', (tester, size) async {
      final server = _server();
      final app = await _pump(tester, size, server: server);
      _go(app, AppRoutes.home);
      await tester.pumpAndSettle();

      server.addTask(projectId: 'p1', title: 'New task');
      final gate = server.hold('api/task/assigned');
      _go(app, AppRoutes.myTasks);
      await tester.pump();
      await tester.pump();

      expect(inPage(find.text(_late)), findsOneWidget);
      expect(find.text('New task'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text('New task')), findsOneWidget);
    });

    testBothLayouts('keeps what it had when the refresh fails', (tester, size) async {
      final server = _server();
      final app = await _pump(tester, size, server: server);
      _go(app, AppRoutes.home);
      await tester.pumpAndSettle();

      server.fail('api/task/assigned', status: 500);
      _go(app, AppRoutes.myTasks);
      await tester.pumpAndSettle();

      expect(inPage(find.text(_late)), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsNothing);
    });

    testBothLayouts('keeps the grouping while the refresh is out', (tester, size) async {
      final server = _server();
      final app = await _pump(tester, size, server: server);
      await _groupBy(tester, app, 'mobile:myTasks.by.project');

      await tester.fling(inPage(find.byType(ListView)), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(inPage(find.text('Alpha')), findsOneWidget);
    });
  });

  group('states', () {
    testBothLayouts('shows progress while it first loads', (tester, size) async {
      final server = _server();
      final gate = server.hold('api/task/assigned');
      await _pump(tester, size, server: server, settle: false);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(inPage(find.byType(CircularProgressIndicator)), findsOneWidget);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.byType(CircularProgressIndicator)), findsNothing);
      expect(inPage(find.text(_late)), findsOneWidget);
    });

    testBothLayouts('says why it failed, and tries again', (tester, size) async {
      final server = _server()
        ..failNext('api/task/assigned', status: 500, body: {'message': 'Not today'});
      final app = await _pump(tester, size, server: server);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      expect(find.text('Not today'), findsOneWidget);

      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(inPage(find.text(_late)), findsOneWidget);
    });

    testBothLayouts('without permission says so, with no way to retry', (tester, size) async {
      final server = _server()..fail('api/task/assigned', status: 403);
      final app = await _pump(tester, size, server: server);
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
    });

    testBothLayouts('empty says what will appear here', (tester, size) async {
      final app = await _pump(tester, size, server: FakeKaneo.empty());
      expect(find.text(app.i18n.t('mobile:myTasks.empty.title')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:myTasks.empty.message')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:myTasks.by.due')), findsNothing);
    });

    testBothLayouts('with no workspace it points to the web app', (tester, size) async {
      final server = _server()..workspaces.clear();
      final app = await _pump(tester, size, server: server);
      expect(find.text(app.i18n.t('mobile:home.noWorkspace.title')), findsOneWidget);
    });

    testBothLayouts('says when the server has more than it sends', (tester, size) async {
      final server = _server();
      server.on('api/task/assigned', (request) {
        return FakeResponse(200, {
          'tasks': [
            {
              'id': 'late',
              'projectId': 'p1',
              'title': _late,
              'status': 'to-do',
              'projectName': 'Alpha',
              'projectSlug': 'ALP',
            },
          ],
          'total': 150,
        });
      });
      final app = await _pump(tester, size, server: server);
      expect(
        find.text(app.i18n.t('mobile:myTasks.showing', {'shown': 1, 'total': 150})),
        findsOneWidget,
      );
    });
  });

  group('every language fits', () {
    for (final locale in supportedLocales.keys) {
      for (final size in const [narrowSize, Size(600, 600)]) {
        testWidgets('$locale at ${size.width.toInt()}', (tester) async {
          await _pump(tester, size, locale: locale);
          expect(tester.takeException(), isNull);
          expect(find.textContaining('mobile:'), findsNothing);
          expect(find.textContaining('tasks:'), findsNothing);
        });
      }
    }
  });
}
