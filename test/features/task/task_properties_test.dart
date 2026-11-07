import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/core/ui/calendar.dart';
import 'package:kaneo_app/features/auth/login_page.dart';
import 'package:kaneo_app/features/markdown/markdown_field.dart';
import 'package:kaneo_app/features/task/task_description.dart';

import '../../support/test_app.dart';

final _title = find.byKey(const ValueKey('task-title'));
final _status = find.byKey(const ValueKey('task-status'));
final _priority = find.byKey(const ValueKey('task-priority'));
final _assignee = find.byKey(const ValueKey('task-assignee'));
final _labels = find.byKey(const ValueKey('task-labels'));
final _startDate = find.byKey(const ValueKey('task-start-date'));
final _dueDate = find.byKey(const ValueKey('task-due-date'));

Finder _card(String id) => find.byKey(ValueKey('board-card-$id'));
Finder _inCard(String id, Finder finder) => find.descendant(of: _card(id), matching: finder);

/// Opens [id] from its board, the way a person would, as a panel or a page.
Future<TestApp> _openFromBoard(
  WidgetTester tester,
  Size size, {
  FakeKaneo? server,
  String id = 'task-1',
}) async {
  final app = await pumpKaneoApp(
    tester,
    server: server,
    size: size,
    location: AppRoutes.board(FakeKaneo.projectId),
  );
  await tester.ensureVisible(_card(id));
  await tester.pumpAndSettle();
  await tester.tap(_card(id));
  await tester.pumpAndSettle();
  return app;
}

/// Back to the board, which on a narrow window was behind the task's page.
Future<void> _close(WidgetTester tester, Size size) async {
  await tester.tap(find.byTooltip(size == wideSize ? 'Close' : 'Back'));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, Finder row) async {
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String _shown(WidgetTester tester, Finder row, String text) {
  expect(find.descendant(of: row, matching: find.text(text)), findsOneWidget);
  return text;
}

Map<String, dynamic> _task(FakeKaneo server, [String id = 'task-1']) =>
    server.tasks.firstWhere((t) => t['id'] == id);

BoardData _board(TestApp app) => app.container.read(boardQuery(FakeKaneo.projectId)).value!;

List<String> _column(TestApp app, String slug) => [
  for (final task in _board(app).columns.firstWhere((c) => c.slug == slug).tasks!) task.id,
];

/// Picks day 15 of the month on show.
Future<void> _pickDay(WidgetTester tester) async {
  await tester.tap(find.text('15').last);
  await tester.pumpAndSettle();
}

String _day15() {
  final now = DateTime.now();
  return toApiDate(DateTime(now.year, now.month, 15));
}

void main() {
  group('title', () {
    testBothLayouts('Enter saves it, and the board and its list show it', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'A better title');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_task(server)['title'], 'A better title');
      expect(server.requestsTo('api/task/title/task-1', method: 'PUT'), hasLength(1));

      await _close(tester, size);
      expect(_inCard('task-1', find.text('A better title')), findsOneWidget);
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(find.text('A better title'), findsOneWidget);
    });

    testBothLayouts('leaving with the back button saves what was typed', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Typed and left');
      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_task(server)['title'], 'Typed and left');
      expect(_inCard('task-1', find.text('Typed and left')), findsOneWidget);
    });

    testBothLayouts('leaving the box saves, and only a change saves', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.tap(_title);
      await tester.pump();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/task/title/task-1', method: 'PUT'), isEmpty);

      await tester.enterText(_title, 'Saved on blur');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(_task(server)['title'], 'Saved on blur');
    });

    testBothLayouts('spaces around an untouched title are not a change', (tester, size) async {
      final server = FakeKaneo();
      _task(server)['title'] = ' Spaced ';
      await _openFromBoard(tester, size, server: server);
      await tester.tap(_title);
      await tester.pump();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/task/title/task-1', method: 'PUT'), isEmpty);
      expect(_task(server)['title'], ' Spaced ');
    });

    testBothLayouts('an empty title is not saved and the old one comes back', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/task/title/task-1', method: 'PUT'), isEmpty);
      expect(tester.widget<TextField>(_title).controller!.text, 'Set up the project');
    });

    testBothLayouts('line breaks pasted in come out', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, ' One\nTwo\r\n ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_task(server)['title'], 'One Two');
      expect(tester.widget<TextField>(_title).controller!.text, 'One Two');
    });

    testBothLayouts('a failed save puts the old title back everywhere and says why', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.failNext('api/task/title/', status: 500, body: {'message': 'Title refused'});
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Not to be');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Title refused'), findsOneWidget);
      expect(tester.widget<TextField>(_title).controller!.text, 'Set up the project');
      await _close(tester, size);
      expect(_inCard('task-1', find.text('Set up the project')), findsOneWidget);
    });

    testBothLayouts('text typed as the session ends is not sent to the next account', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Under the old account');
      unawaited(app.container.read(sessionProvider.notifier).signOut());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(server.requestsTo('api/task/title/', method: 'PUT'), isEmpty);
    });

    testBothLayouts('a change from elsewhere shows, but not over text being typed', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      _task(server)['title'] = 'Changed elsewhere';
      unawaited(app.container.read(taskQuery('task-1').notifier).refresh());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_title).controller!.text, 'Changed elsewhere');

      await tester.enterText(_title, 'Mine');
      _task(server)['title'] = 'Changed again';
      unawaited(app.container.read(taskQuery('task-1').notifier).refresh());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_title).controller!.text, 'Mine');

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
    });
  });

  group('status', () {
    testBothLayouts('moves the card to its new column', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      _shown(tester, _status, 'To Do');
      await _press(tester, _status);
      await _choose(tester, 'In Progress');
      expect(_task(server)['status'], 'in-progress');
      _shown(tester, _status, 'In Progress');
      expect(_column(app, 'in-progress'), contains('task-1'));
      expect(_column(app, 'to-do'), isNot(contains('task-1')));

      await _close(tester, size);
      final column = find.byKey(const ValueKey('drop-column-in-progress'));
      expect(find.descendant(of: column, matching: _card('task-1')), findsOneWidget);
    });

    testBothLayouts('the board moves as soon as it is chosen, before the server answers', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final gate = server.hold('api/task/status/');
      await _press(tester, _status);
      await _choose(tester, 'Done');
      _shown(tester, _status, 'Done');
      expect(_column(app, 'done'), contains('task-1'));
      expect(_task(server)['status'], 'to-do');
      gate.release();
      await tester.pumpAndSettle();
      expect(_task(server)['status'], 'done');
    });

    testBothLayouts('a parent\'s progress on the board follows its child', (tester, size) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      // A child can be folded away under its parent on the board.
      unawaited(app.container.read(routerProvider).push(AppRoutes.task('task-2')));
      await tester.pumpAndSettle();
      expect(boardTaskCounts(app, 'task-1'), 0);
      await _press(tester, _status);
      await _choose(tester, 'Done');
      expect(boardTaskCounts(app, 'task-1'), 1);
    });

    testBothLayouts('a task can be archived and planned, and says so', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final archived = app.i18n.t('mobile:taskFields.archived');
      final planned = app.i18n.t('mobile:taskFields.planned');

      await _press(tester, _status);
      await _choose(tester, archived);
      expect(_task(server)['status'], statusArchived);
      _shown(tester, _status, archived);
      expect([for (final t in _board(app).archivedTasks) t.id], contains('task-1'));
      expect(_column(app, 'to-do'), isNot(contains('task-1')));

      await _press(tester, _status);
      await _choose(tester, planned);
      expect(_task(server)['status'], statusPlanned);
      _shown(tester, _status, planned);
      expect([for (final t in _board(app).plannedTasks) t.id], contains('task-1'));
    });

    testBothLayouts('a failed change goes back to the old column and says why', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      server.failNext('api/task/status/', status: 400, body: {'message': 'Status refused'});
      await _press(tester, _status);
      await _choose(tester, 'Done');
      expect(find.text('Status refused'), findsOneWidget);
      _shown(tester, _status, 'To Do');
      expect(_column(app, 'to-do'), contains('task-1'));
      expect(_column(app, 'done'), isNot(contains('task-1')));
    });
  });

  group('priority', () {
    testBothLayouts('shows on the card', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final urgent = app.i18n.t('mobile:meta.priority.urgent');
      await _press(tester, _priority);
      await _choose(tester, urgent);
      expect(_task(server)['priority'], 'urgent');
      _shown(tester, _priority, urgent);
      await _close(tester, size);
      expect(_inCard('task-1', find.text(urgent)), findsOneWidget);
    });

    testBothLayouts('choosing the same one sends nothing', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _priority);
      await _choose(tester, app.i18n.t('mobile:meta.priority.high'));
      expect(server.requestsTo('api/task/priority/', method: 'PUT'), isEmpty);
    });

    testBothLayouts('a failed change goes back and says why', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      server.failNext('api/task/priority/', status: 500, body: {'message': 'Priority refused'});
      await _press(tester, _priority);
      await _choose(tester, app.i18n.t('mobile:meta.priority.low'));
      expect(find.text('Priority refused'), findsOneWidget);
      _shown(tester, _priority, app.i18n.t('mobile:meta.priority.high'));
      expect(_task(server)['priority'], 'high');
      await _close(tester, size);
      expect(_inCard('task-1', find.text(app.i18n.t('mobile:meta.priority.high'))), findsOneWidget);
    });
  });

  group('assignee', () {
    testBothLayouts('can change, and the card follows', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      _shown(tester, _assignee, 'Test User');
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      expect(_task(server)['userId'], 'user-2');
      _shown(tester, _assignee, 'Second User');
      await _close(tester, size);
      expect(_inCard('task-1', find.byTooltip('Second User')), findsOneWidget);
    });

    testBothLayouts('can be cleared, and the card follows', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final unassigned = app.i18n.t('mobile:taskFields.unassigned');
      await _press(tester, _assignee);
      await _choose(tester, unassigned);
      expect(_task(server)['userId'], isNull);
      _shown(tester, _assignee, unassigned);
      await _close(tester, size);
      expect(_inCard('task-1', find.byTooltip('Test User')), findsNothing);
    });

    testBothLayouts('the people load when they are needed, if they failed before', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.failNext('/members', times: 1);
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      expect(_task(server)['userId'], 'user-2');
    });

    testBothLayouts('says why when the people cannot be loaded', (tester, size) async {
      final server = FakeKaneo();
      server.fail('/members', body: {'message': 'No people today'});
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _assignee);
      expect(find.text('No people today'), findsOneWidget);
      expect(find.text('Second User'), findsNothing);
    });

    testBothLayouts('a failed change puts the old person back', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      server.failNext('api/task/assignee/', status: 403, body: {'message': 'Not allowed'});
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      expect(find.text('Not allowed'), findsOneWidget);
      _shown(tester, _assignee, 'Test User');
      await _close(tester, size);
      expect(_inCard('task-1', find.byTooltip('Test User')), findsOneWidget);
    });
  });

  group('labels', () {
    FakeKaneo labelled() {
      final server = FakeKaneo();
      server.addLabel('ui', color: 'blue');
      server.addLabel('docs', color: 'green');
      return server;
    }

    /// Ticks or unticks in the picker, and saves if it has a button for that.
    Future<void> toggle(WidgetTester tester, TestApp app, List<String> names) async {
      await _press(tester, _labels);
      for (final name in names) {
        await tester.tap(find.text(name).last);
        await tester.pump();
      }
      await tester.tap(find.text(app.i18n.t('mobile:common.save')).last);
      await tester.pumpAndSettle();
    }

    List<String> onTask(FakeKaneo server, String id) => [
      for (final label in server.labels)
        if (label['taskId'] == id) label['name'] as String,
    ];

    testBothLayouts('can be added and show on the card', (tester, size) async {
      final server = labelled();
      final app = await _openFromBoard(tester, size, server: server);
      expect(find.text(app.i18n.t('tasks:properties.addLabels')), findsOneWidget);
      await toggle(tester, app, ['ui', 'docs']);
      expect(onTask(server, 'task-1'), unorderedEquals(['ui', 'docs']));
      _shown(tester, _labels, 'ui');
      _shown(tester, _labels, 'docs');
      await _close(tester, size);
      expect(_inCard('task-1', find.text('ui')), findsOneWidget);
      expect(_inCard('task-1', find.text('docs')), findsOneWidget);
    });

    testBothLayouts('can be removed from the card, by the task\'s own copy', (tester, size) async {
      final server = labelled();
      final copy = server.addLabel('ui', color: 'blue', taskId: 'task-1');
      final app = await _openFromBoard(tester, size, server: server);
      _shown(tester, _labels, 'ui');
      await toggle(tester, app, ['ui']);
      expect(onTask(server, 'task-1'), isEmpty);
      expect(server.requestsTo('api/label/${copy['id']}/task', method: 'DELETE'), hasLength(1));
      expect(find.descendant(of: _labels, matching: find.text('ui')), findsNothing);
      await _close(tester, size);
      expect(_inCard('task-1', find.text('ui')), findsNothing);
    });

    // KAN-66: a label only other tasks had wasn't offered, so the only way was a new one.
    testBothLayouts('a label only another task has can be picked, and stays on that task', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..labels.clear();
      server.addLabel('theirs', color: 'teal', taskId: 'task-3');
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _labels);
      final option = find.descendant(of: find.byType(PopoverBody), matching: find.text('theirs'));
      expect(option, findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskFields.noLabels')), findsNothing);
      await tester.tap(option);
      await tester.pump();
      await tester.tap(find.text(app.i18n.t('mobile:common.save')).last);
      await tester.pumpAndSettle();

      expect(onTask(server, 'task-1'), ['theirs']);
      expect(onTask(server, 'task-3'), ['theirs']);
      expect(server.labels.where((l) => l['taskId'] == null), isEmpty);
      expect(server.labels.firstWhere((l) => l['taskId'] == 'task-1')['color'], 'teal');
      _shown(tester, _labels, 'theirs');
      await _close(tester, size);
      expect(_inCard('task-1', find.text('theirs')), findsOneWidget);
      expect(_inCard('task-3', find.text('theirs')), findsOneWidget);

      // Taking it off again leaves the other task's.
      await _press(tester, _card('task-1'));
      await toggle(tester, app, ['theirs']);
      expect(onTask(server, 'task-1'), isEmpty);
      expect(onTask(server, 'task-3'), ['theirs']);
    });

    testBothLayouts('saving the same selection sends nothing', (tester, size) async {
      final server = labelled();
      final app = await _openFromBoard(tester, size, server: server);
      await toggle(tester, app, const []);
      expect(server.requestsTo('api/label/', method: 'PUT'), isEmpty);
      expect(server.requestsTo('api/label/', method: 'DELETE'), isEmpty);
    });

    testBothLayouts('when one fails it says why and shows what the task really has', (
      tester,
      size,
    ) async {
      final server = labelled();
      final app = await _openFromBoard(tester, size, server: server);
      final docs = server.labels.firstWhere((l) => l['name'] == 'docs');
      server.failNext(
        'api/label/${docs['id']}/task',
        method: 'PUT',
        status: 500,
        body: {'message': 'Label refused'},
      );
      await toggle(tester, app, ['ui', 'docs']);
      expect(find.text('Label refused'), findsOneWidget);
      expect(onTask(server, 'task-1'), ['ui']);
      _shown(tester, _labels, 'ui');
      expect(find.descendant(of: _labels, matching: find.text('docs')), findsNothing);
      await _close(tester, size);
      expect(_inCard('task-1', find.text('ui')), findsOneWidget);
    });

    testBothLayouts('with no labels in the workspace the picker says how to make one', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..labels.clear();
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _labels);
      expect(find.text(app.i18n.t('mobile:taskFields.noLabels')), findsOneWidget);
    });

    testBothLayouts('a label made in the picker goes on the task and the card', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _labels);
      await tester.enterText(
        find.descendant(of: find.byType(PopoverBody), matching: find.byType(TextField)),
        'brand new',
      );
      await tester.pump();
      await tester.tap(
        find.text(app.i18n.t('mobile:taskFields.createLabel', {'name': 'brand new'})),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(app.i18n.t('mobile:common.save')).last);
      await tester.pumpAndSettle();
      expect(onTask(server, 'task-1'), ['brand new']);
      _shown(tester, _labels, 'brand new');
      await _close(tester, size);
      expect(_inCard('task-1', find.text('brand new')), findsOneWidget);
    });

    testBothLayouts('making a label has its own permission', (tester, size) async {
      final server = FakeKaneo()..capabilities['createLabels'] = false;
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _labels);
      await tester.enterText(
        find.descendant(of: find.byType(PopoverBody), matching: find.byType(TextField)),
        'brand new',
      );
      await tester.pump();
      expect(
        find.text(app.i18n.t('mobile:taskFields.createLabel', {'name': 'brand new'})),
        findsNothing,
      );
    });
  });

  group('dates', () {
    testBothLayouts('the start date saves through the whole task and keeps the rest', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      _task(server)
        ..['dueDate'] = '2030-02-03T00:00:00.000Z'
        ..['description'] = 'Keep me';
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _startDate);
      await _pickDay(tester);

      final task = _task(server);
      expect(task['startDate'], _day15());
      expect(task['dueDate'], '2030-02-03T00:00:00.000Z');
      expect(task['title'], 'Set up the project');
      expect(task['userId'], FakeKaneo.userId);
      expect(task['priority'], 'high');
      expect(task['description'], 'Keep me');
      final put = server.requestsTo('api/task/task-1', method: 'PUT').single;
      expect((put.body! as Map).containsKey('description'), isFalse);
      _shown(tester, _startDate, formatDate(app.i18n, _day15()));
      expect(boardCard(app, 'task-1').startDate, _day15());
    });

    testBothLayouts('the start date starts from the server, not from an old copy', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      _task(server)['title'] = 'Changed on the web';
      _task(server)['status'] = 'done';
      await _press(tester, _startDate);
      await _pickDay(tester);
      expect(_task(server)['title'], 'Changed on the web');
      expect(_task(server)['status'], 'done');
      expect(_task(server)['startDate'], _day15());
    });

    testBothLayouts('the start date can be cleared', (tester, size) async {
      final server = FakeKaneo();
      _task(server)['startDate'] = _day15();
      _task(server)['dueDate'] = '2030-02-03T00:00:00.000Z';
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _startDate);
      await tester.tap(find.text(app.i18n.t('mobile:picker.clear')));
      await tester.pumpAndSettle();
      expect(_task(server)['startDate'], isNull);
      expect(_task(server)['dueDate'], '2030-02-03T00:00:00.000Z');
      _shown(tester, _startDate, app.i18n.t('tasks:properties.noDate'));
    });

    testBothLayouts('a start date the server refuses goes back and says why', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      server.failNext(
        'api/task/task-1',
        method: 'PUT',
        status: 400,
        body: {'message': 'Start date cannot be after due date.'},
      );
      await _press(tester, _startDate);
      await _pickDay(tester);
      expect(find.text('Start date cannot be after due date.'), findsOneWidget);
      _shown(tester, _startDate, app.i18n.t('tasks:properties.noDate'));
      expect(boardCard(app, 'task-1').startDate, isNull);
    });

    testBothLayouts('the due date shows on the card', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _dueDate);
      await _pickDay(tester);
      expect(_task(server)['dueDate'], _day15());
      _shown(tester, _dueDate, formatDate(app.i18n, _day15()));
      await _close(tester, size);
      expect(_inCard('task-1', find.text(formatDueShort(app.i18n, _day15()))), findsOneWidget);
    });

    testBothLayouts('the due date can be cleared, and leaves the card', (tester, size) async {
      final server = FakeKaneo();
      _task(server)['dueDate'] = _day15();
      final app = await _openFromBoard(tester, size, server: server);
      final due = formatDueShort(app.i18n, _day15());
      await _press(tester, _dueDate);
      await tester.tap(find.text(app.i18n.t('mobile:picker.clear')));
      await tester.pumpAndSettle();
      expect(_task(server)['dueDate'], isNull);
      _shown(tester, _dueDate, app.i18n.t('tasks:properties.noDate'));
      await _close(tester, size);
      expect(_inCard('task-1', find.text(due)), findsNothing);
    });

    testBothLayouts('a failed due date goes back and says why', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      server.failNext('api/task/due-date/', status: 500, body: {'message': 'Date refused'});
      await _press(tester, _dueDate);
      await _pickDay(tester);
      expect(find.text('Date refused'), findsOneWidget);
      _shown(tester, _dueDate, app.i18n.t('tasks:properties.noDate'));
    });

    testBothLayouts('dismissing the picker changes nothing', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _dueDate);
      expect(find.byType(KaneoCalendar), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(KaneoCalendar), findsNothing);
      expect(server.requestsTo('api/task/due-date/', method: 'PUT'), isEmpty);
    });
  });

  group('pickers', () {
    testWidgets('open next to the value on a wide window', (tester) async {
      await _openFromBoard(tester, wideSize);
      await _press(tester, _status);
      final value = tester.getRect(_status);
      final popover = tester.getRect(find.byType(PopoverBody));
      expect((popover.top - value.bottom).abs(), lessThan(24));
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('open as a bottom sheet on a narrow window', (tester) async {
      await _openFromBoard(tester, narrowSize);
      await _press(tester, _status);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testBothLayouts('a second press while one is opening does not open another', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.columns.clear();
      final gate = server.hold('api/column/');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
        settle: false,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_status);
      await tester.tap(_status);
      gate.release();
      await tester.pumpAndSettle();
      expect(find.byType(PopoverBody), findsOneWidget);
    });
  });

  group('edits in a row', () {
    testBothLayouts('a due date chosen while the start date saves is not undone by it', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      final gate = server.hold('api/task/task-1');
      await _press(tester, _startDate);
      await _pickDay(tester);
      await _press(tester, _dueDate);
      await _pickDay(tester);
      expect(server.requestsTo('api/task/due-date/', method: 'PUT'), isEmpty);
      gate.release();
      await tester.pumpAndSettle();
      expect(_task(server)['startDate'], _day15());
      expect(_task(server)['dueDate'], _day15());
    });

    testBothLayouts('undoing one failed edit keeps the one after it', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final urgent = app.i18n.t('mobile:meta.priority.urgent');
      final gate = server.hold('api/task/priority/');
      server.failNext('api/task/priority/', status: 500, body: {'message': 'Priority refused'});
      await _press(tester, _priority);
      await _choose(tester, urgent);
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      gate.release();
      await tester.pumpAndSettle();
      _shown(tester, _priority, app.i18n.t('mobile:meta.priority.high'));
      _shown(tester, _assignee, 'Second User');
      expect(_task(server)['userId'], 'user-2');
    });

    testBothLayouts('a save still in flight when the page closes reaches the board', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final gate = server.hold('api/task/priority/');
      await _press(tester, _priority);
      await _choose(tester, app.i18n.t('mobile:meta.priority.low'));
      await _close(tester, size);
      gate.release();
      await tester.pumpAndSettle();
      expect(_task(server)['priority'], 'low');
      expect(_inCard('task-1', find.text(app.i18n.t('mobile:meta.priority.low'))), findsOneWidget);
    });

    testBothLayouts('a save that fails after the page closed still corrects the board', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final gate = server.hold('api/task/priority/');
      server.failNext('api/task/priority/', status: 500, body: {'message': 'Priority refused'});
      await _press(tester, _priority);
      await _choose(tester, app.i18n.t('mobile:meta.priority.low'));
      await _close(tester, size);
      gate.release();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Priority refused'), findsOneWidget);
      expect(_inCard('task-1', find.text(app.i18n.t('mobile:meta.priority.high'))), findsOneWidget);
    });
  });

  group('lists elsewhere', () {
    testBothLayouts('my tasks shows a new title', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.myTasks);
      await tester.tap(find.text('Set up the project'));
      await tester.pumpAndSettle();
      await tester.enterText(_title, 'A title for my list');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await _close(tester, size);
      expect(find.text('A title for my list'), findsOneWidget);
    });

    testBothLayouts('my tasks drops a task given to someone else', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.myTasks);
      await tester.tap(find.text('Set up the project'));
      await tester.pumpAndSettle();
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      await _close(tester, size);
      expect(find.text('Set up the project'), findsNothing);
    });

    testBothLayouts('with no board open nothing asks for one', (tester, size) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
      );
      await _press(tester, _priority);
      await _choose(tester, app.i18n.t('mobile:meta.priority.low'));
      expect(_task(server)['priority'], 'low');
      expect(server.requestsTo('api/task/tasks/'), isEmpty);
    });

    testBothLayouts('an edit reaches a board opened afterwards', (tester, size) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
      );
      await _press(tester, _priority);
      await _choose(tester, app.i18n.t('mobile:meta.priority.low'));
      app.container.read(routerProvider).go(AppRoutes.board(FakeKaneo.projectId));
      await tester.pumpAndSettle();
      expect(_inCard('task-1', find.text(app.i18n.t('mobile:meta.priority.low'))), findsOneWidget);
    });
  });

  group('description', () {
    testBothLayouts('shows formatted and can be edited in the panel or page', (tester, size) async {
      final server = FakeKaneo();
      _task(server)['description'] = '**Bold** words';
      await _openFromBoard(tester, size, server: server);
      expect(find.byType(TaskDescription), findsOneWidget);
      expect(find.textContaining('Bold'), findsWidgets);

      await tester.ensureVisible(find.byType(TaskDescription));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(find.byType(TaskDescription)) + const Offset(8, 8));
      await tester.pumpAndSettle();
      final box = find.descendant(
        of: find.descendant(of: find.byType(TaskDescription), matching: find.byType(MarkdownField)),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(box).controller!.text, '**Bold** words');
      await tester.enterText(box, '**Bold** and new');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(_task(server)['description'], '**Bold** and new');
      expect(box, findsNothing);
    });
  });

  group('empty fields', () {
    testBothLayouts('say so instead of leaving a gap', (tester, size) async {
      final server = FakeKaneo();
      server.addTask(
        id: 'bare',
        title: 'Bare',
        assigneeId: null,
        priority: 'no-priority',
        status: 'to-do',
      );
      final app = await _openFromBoard(tester, size, server: server, id: 'bare');
      _shown(tester, _assignee, app.i18n.t('mobile:taskFields.unassigned'));
      _shown(tester, _priority, app.i18n.t('mobile:meta.priority.noPriority'));
      _shown(tester, _labels, app.i18n.t('tasks:properties.addLabels'));
      _shown(tester, _startDate, app.i18n.t('tasks:properties.noDate'));
      _shown(tester, _dueDate, app.i18n.t('tasks:properties.noDate'));
    });
  });

  group('without permission', () {
    FakeKaneo readOnly() {
      final server = FakeKaneo();
      server.capabilities
        ..['updateTasks'] = false
        ..['assignTasks'] = false
        ..['updateLabels'] = false;
      return server;
    }

    testBothLayouts('nothing can be changed, and everything can be read', (tester, size) async {
      final server = readOnly();
      final app = await _openFromBoard(tester, size, server: server);
      expect(tester.widget<TextField>(_title).readOnly, isTrue);
      for (final row in [_status, _priority, _assignee, _labels, _startDate, _dueDate]) {
        await _press(tester, row);
        expect(find.byType(PopoverBody), findsNothing);
      }
      _shown(tester, _status, 'To Do');
      _shown(tester, _assignee, 'Test User');
      _shown(tester, _labels, app.i18n.t('mobile:taskFields.none'));
      expect(server.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    testBothLayouts('assigning has its own permission', (tester, size) async {
      final server = readOnly()..capabilities['assignTasks'] = true;
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      expect(_task(server)['userId'], 'user-2');
    });

    testBothLayouts('labels have their own permission', (tester, size) async {
      final server = readOnly()..capabilities['updateLabels'] = true;
      server.addLabel('ui');
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _labels);
      await tester.tap(find.text('ui').last);
      await tester.pump();
      await tester.tap(find.text(app.i18n.t('mobile:common.save')).last);
      await tester.pumpAndSettle();
      _shown(tester, _labels, 'ui');
    });

    testBothLayouts('a change the server refuses anyway still goes back', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      server.failNext('api/task/priority/', status: 403, body: {'message': 'Forbidden'});
      await _press(tester, _priority);
      await _choose(tester, app.i18n.t('mobile:meta.priority.low'));
      _shown(tester, _priority, app.i18n.t('mobile:meta.priority.high'));
    });
  });
}

BoardTask boardCard(TestApp app, String id) =>
    _board(app).columns.expand((c) => c.tasks ?? const <BoardTask>[]).firstWhere((t) => t.id == id);

num boardTaskCounts(TestApp app, String id) => boardCard(app, id).subtaskCounts?.completed ?? 0;
