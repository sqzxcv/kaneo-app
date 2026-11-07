import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/new_task.dart';
import 'package:kaneo_app/features/task/new_task_page.dart';
import 'package:kaneo_app/features/task/open_task.dart';
import 'package:kaneo_app/features/task/task_edits.dart';

import '../../support/test_app.dart';

final _form = find.byType(NewTaskForm);
final _title = find.byKey(const ValueKey('new-task-title'));
final _description = find.descendant(
  of: find.byKey(const ValueKey('new-task-description')),
  matching: find.byType(TextField),
);
final _create = find.byKey(const ValueKey('new-task-create'));
final _cancel = find.byKey(const ValueKey('new-task-cancel'));
final _project = find.byKey(const ValueKey('new-task-project'));
final _status = find.byKey(const ValueKey('new-task-status'));
final _priority = find.byKey(const ValueKey('new-task-priority'));
final _assignee = find.byKey(const ValueKey('new-task-assignee'));
final _startDate = find.byKey(const ValueKey('new-task-start-date'));
final _dueDate = find.byKey(const ValueKey('new-task-due-date'));
final _labels = find.byKey(const ValueKey('new-task-labels'));
final _notice = find.byKey(const ValueKey('new-task-notice'));
final _error = find.byKey(const ValueKey('new-task-error'));

final _labelSearch = find.descendant(
  of: find.byType(PopoverBody),
  matching: find.byType(TextField),
);

const _createPath = 'api/task/${FakeKaneo.projectId}';

Finder _inColumn(String slug, String text) =>
    find.descendant(of: find.byKey(ValueKey('drop-column-$slug')), matching: find.text(text));

Finder _shown(Finder field, String text) => find.descendant(of: field, matching: find.text(text));

Map<String, dynamic> _newTask(FakeKaneo server, String title) =>
    server.tasks.singleWhere((t) => t['title'] == title);

List<FakeRequest> _posts(FakeKaneo server) => server.requestsTo(_createPath, method: 'POST');

/// Opens the form from a board, the way a column's "add task" does when given a [status].
Future<TestApp> _openFromBoard(
  WidgetTester tester,
  Size size, {
  FakeKaneo? server,
  String? status,
}) async {
  final app = await pumpKaneoApp(
    tester,
    server: server,
    size: size,
    location: AppRoutes.board(FakeKaneo.projectId),
  );
  openNewTask(
    tester.element(find.byType(Scaffold).last),
    projectId: FakeKaneo.projectId,
    status: status,
  );
  await tester.pumpAndSettle();
  return app;
}

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Picks day 15 of the month on show.
Future<void> _pickDay(WidgetTester tester) async {
  await tester.tap(find.text('15').last);
  await tester.pumpAndSettle();
}

String _day15() {
  final now = DateTime.now();
  return toApiDate(DateTime(now.year, now.month, 15));
}

bool _enabled(WidgetTester tester) => tester.widget<FilledButton>(_create).onPressed != null;

ProjectColumn _column(String slug, {num? position, bool? isFinal}) => ProjectColumn(
  id: slug,
  projectId: 'p',
  name: slug,
  slug: slug,
  position: position,
  isFinal: isFinal,
);

void main() {
  group('where it opens', () {
    testWidgets('a wide window shows a centered dialog, with the board in view behind it', (
      tester,
    ) async {
      final app = await pumpKaneoApp(tester, location: AppRoutes.board(FakeKaneo.projectId));
      final router = app.container.read(routerProvider);
      await tester.tap(find.byTooltip('New task'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('New task'), findsWidgets);
      // A dialog widget fills the window to center what it holds, which is the first material.
      final dialog = tester.getRect(
        find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first,
      );
      expect(dialog.width, newTaskFormWidth);
      expect(dialog.center.dx, closeTo(wideSize.width / 2, 1));
      expect(dialog.center.dy, closeTo(wideSize.height / 2, 1));
      expect(router.state.uri.toString(), AppRoutes.board(FakeKaneo.projectId));
      // The board is still laid out and painted beside the dialog.
      final card = tester.getRect(find.byKey(const ValueKey('board-card-task-1')));
      expect(card.left, lessThan(dialog.left));
    });

    testWidgets('a narrow window fills the window with a page', (tester) async {
      final app = await pumpKaneoApp(
        tester,
        size: narrowSize,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      await tester.tap(find.byTooltip('New task'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(tester.getSize(_form).width, narrowSize.width);
      expect(find.text('New task'), findsOneWidget);
      expect(
        app.container.read(routerProvider).state.uri.toString(),
        AppRoutes.newTask(projectId: FakeKaneo.projectId),
      );
      // The buttons stay at the bottom of the page, under however little there is to fill in.
      expect(tester.getBottomLeft(_create).dy, greaterThan(narrowSize.height - 80));
    });

    testWidgets('a link on a wide window keeps the form from stretching across', (tester) async {
      await pumpKaneoApp(tester, location: AppRoutes.newTask(projectId: FakeKaneo.projectId));
      expect(tester.getSize(_form).width, newTaskFormWidth);
    });

    testBothLayouts('cancelling goes back without creating anything', (tester, size) async {
      final server = FakeKaneo();
      final count = server.tasks.length;
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Never mind');
      await _press(tester, _cancel);

      expect(_form, findsNothing);
      expect(find.byKey(const ValueKey('board-card-task-1')), findsOneWidget);
      expect(server.tasks, hasLength(count));
    });

    testWidgets('a phone on its side still fits everything, by scrolling', (tester) async {
      await pumpKaneoApp(
        tester,
        size: const Size(844, 390),
        location: AppRoutes.newTask(projectId: FakeKaneo.projectId),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_labels);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(_labels).dy, lessThan(tester.getTopLeft(_create).dy));
    });

    testWidgets('a short wide window keeps the dialog inside it', (tester) async {
      await pumpKaneoApp(
        tester,
        size: const Size(800, 600),
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      await tester.tap(find.byTooltip('New task'));
      await tester.pumpAndSettle();
      await tester.enterText(_description, List.filled(60, 'A long line').join('\n'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getBottomLeft(_create).dy, lessThan(600));
    });

    testWidgets('what was typed survives the window crossing the breakpoint', (tester) async {
      await _openFromBoard(tester, wideSize);
      await tester.enterText(_title, 'Still here');
      await tester.enterText(_description, 'Me too');
      await _press(tester, _priority);
      await _choose(tester, 'High');

      setWindowSize(tester, const Size(500, 500));
      await tester.pumpAndSettle();
      expect(find.text('Still here'), findsOneWidget);
      expect(find.text('Me too'), findsOneWidget);
      expect(_shown(_priority, 'High'), findsOneWidget);

      setWindowSize(tester, wideSize);
      await tester.pumpAndSettle();
      expect(find.text('Still here'), findsOneWidget);
      expect(find.text('Me too'), findsOneWidget);
      expect(_shown(_priority, 'High'), findsOneWidget);
    });
  });

  group('status', () {
    testBothLayouts('starting from a column defaults to that column', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server, status: 'in-review');
      expect(_shown(_status, 'In Review'), findsOneWidget);

      await tester.enterText(_title, 'From the column');
      await _press(tester, _create);
      expect(_newTask(server, 'From the column')['status'], 'in-review');
    });

    testBothLayouts('otherwise it starts in the first open column', (tester, size) async {
      await _openFromBoard(tester, size);
      expect(_shown(_status, 'To Do'), findsOneWidget);
    });

    testBothLayouts('it can be changed, and the choice is what gets created', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server, status: 'in-review');
      await _press(tester, _status);
      await _choose(tester, 'Done');
      expect(_shown(_status, 'Done'), findsOneWidget);

      await tester.enterText(_title, 'Already done');
      await _press(tester, _create);
      expect(_newTask(server, 'Already done')['status'], 'done');
    });

    testBothLayouts('a column the project no longer has falls back', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server, status: 'gone');
      expect(_shown(_status, 'To Do'), findsOneWidget);

      await tester.enterText(_title, 'Not lost');
      await _press(tester, _create);
      expect(_newTask(server, 'Not lost')['status'], 'to-do');
    });

    test('the status a task starts in', () {
      final columns = [
        _column('done', position: 2, isFinal: true),
        _column('doing', position: 1),
        _column('backlog', position: 0),
      ];
      expect(initialTaskStatus(columns, 'doing'), 'doing');
      expect(initialTaskStatus(columns, null), 'backlog');
      expect(initialTaskStatus(columns, 'gone'), 'backlog');
      expect(initialTaskStatus(columns, statusPlanned), statusPlanned);
      expect(initialTaskStatus(columns, statusArchived), statusArchived);
      expect(initialTaskStatus(const [], null), statusPlanned);
      expect(initialTaskStatus([_column('done', isFinal: true)], null), statusPlanned);
      // A slug two columns share can't pick a column.
      expect(
        initialTaskStatus([
          _column('same', position: 0),
          _column('same', position: 1),
          _column('next', position: 2),
        ], null),
        'next',
      );
    });

    test('what can be picked', () {
      final statuses = newTaskStatuses(
        [_column('b', position: 1), _column('a', position: 0)],
        projectId: 'p',
        plannedName: 'Planned',
      );
      expect([for (final s in statuses) s.slug], [statusPlanned, 'a', 'b']);
      expect(statuses.first.name, 'Planned');
      final own = newTaskStatuses([_column(statusPlanned)], projectId: 'p', plannedName: 'Planned');
      expect([for (final s in own) s.slug], [statusPlanned]);
    });
  });

  group('a title is required', () {
    testBothLayouts('without one the button does nothing', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      expect(_enabled(tester), isFalse);
      await tester.tap(_create, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_form, findsOneWidget);
      expect(_posts(server), isEmpty);

      await tester.enterText(_title, '   \n ');
      await tester.pump();
      expect(_enabled(tester), isFalse);

      await tester.enterText(_title, 'Enough');
      await tester.pump();
      expect(_enabled(tester), isTrue);

      await tester.enterText(_title, '');
      await tester.pump();
      expect(_enabled(tester), isFalse);
    });

    testWidgets('Enter creates the task on a wide window, once there is a title', (tester) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, wideSize, server: server);
      await tester.showKeyboard(_title);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_form, findsOneWidget);
      expect(_posts(server), isEmpty);

      await tester.enterText(_title, 'By Enter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_form, findsNothing);
      expect(_newTask(server, 'By Enter')['status'], 'to-do');
    });

    testWidgets('a narrow window moves on to the description instead', (tester) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, narrowSize, server: server);
      await tester.enterText(_title, 'Not yet');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(_form, findsOneWidget);
      expect(_posts(server), isEmpty);
      expect(tester.widget<TextField>(_description).focusNode!.hasFocus, isTrue);
    });
  });

  group('when creating fails', () {
    testBothLayouts('everything filled in stays, and trying again sends the same', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..addLabel('ui', color: 'blue');
      final count = server.tasks.length;
      await _openFromBoard(tester, size, server: server, status: 'in-progress');
      await tester.enterText(_title, 'Worth keeping');
      await tester.enterText(_description, '# Keep\n\n* me  \n');
      await _press(tester, _priority);
      await _choose(tester, 'High');
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      await _press(tester, _dueDate);
      await _pickDay(tester);
      await _press(tester, _labels);
      await tester.tap(find.text('ui').last);
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      server.failNext(
        _createPath,
        method: 'POST',
        status: 500,
        body: {'message': 'The server fell over'},
      );
      await _press(tester, _create);

      expect(_form, findsOneWidget);
      expect(_shown(_error, 'The server fell over'), findsOneWidget);
      expect(find.text('Worth keeping'), findsOneWidget);
      expect(find.text('# Keep\n\n* me  \n'), findsOneWidget);
      expect(_shown(_status, 'In Progress'), findsOneWidget);
      expect(_shown(_priority, 'High'), findsOneWidget);
      expect(_shown(_assignee, 'Second User'), findsOneWidget);
      expect(_shown(_labels, 'ui'), findsOneWidget);
      expect(_enabled(tester), isTrue);
      expect(server.tasks, hasLength(count));

      await _press(tester, _create);
      expect(_form, findsNothing);
      expect(_error, findsNothing);
      final task = _newTask(server, 'Worth keeping');
      expect(task['description'], '# Keep\n\n* me  \n');
      expect(task['status'], 'in-progress');
      expect(task['priority'], 'high');
      expect(task['userId'], 'user-2');
      expect(task['dueDate'], _day15());
      expect(server.tasks, hasLength(count + 1));
    });

    testBothLayouts('with no connection everything stays too', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Offline');
      await tester.enterText(_description, 'Typed offline');
      server.unreachable = true;
      await _press(tester, _create);

      expect(_form, findsOneWidget);
      expect(_error, findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Typed offline'), findsOneWidget);
    });

    testBothLayouts('being refused says so, and stays', (tester, size) async {
      final server = FakeKaneo()
        ..failNext(_createPath, method: 'POST', status: 403, body: {'message': 'Not allowed'});
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Refused');
      await _press(tester, _create);

      expect(_shown(_error, 'Not allowed'), findsOneWidget);
      expect(find.text('Refused'), findsOneWidget);
    });

    testBothLayouts('a label that can\'t be added doesn\'t create the task twice', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..addLabel('ui', color: 'blue');
      final count = server.tasks.length;
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Labelled');
      await _press(tester, _labels);
      await tester.tap(find.text('ui').last);
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      server.failNext(RegExp(r'api/label/[^/]+/task$'), method: 'PUT', status: 500);
      await _press(tester, _create);

      expect(_form, findsNothing);
      expect(find.text("Task created, but some labels couldn't be added."), findsOneWidget);
      expect(server.tasks, hasLength(count + 1));
      expect(_inColumn('to-do', 'Labelled'), findsOneWidget);
    });
  });

  group('when it is created', () {
    testBothLayouts('the card is in its column at once, before the board reloads', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server, status: 'in-review');
      await tester.enterText(_title, 'Right away');
      final gate = server.hold('api/task/tasks/');
      await _pressHolding(tester, _create);

      expect(_form, findsNothing);
      final board = app.container.read(boardQuery(FakeKaneo.projectId)).value!;
      final column = board.columns.firstWhere((c) => c.slug == 'in-review');
      expect(column.tasks!.last.title, 'Right away');
      expect(_inColumn('in-review', 'Right away'), findsOneWidget);
      expect(_inColumn('to-do', 'Right away'), findsNothing);
      expect(find.text('Task created successfully'), findsOneWidget);

      gate.release();
      await tester.pumpAndSettle();
      expect(_inColumn('in-review', 'Right away'), findsOneWidget);
    });

    testBothLayouts('the labels reach the card with the reload', (tester, size) async {
      final server = FakeKaneo()..addLabel('ui', color: 'blue');
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'With a label');
      await _press(tester, _labels);
      await tester.tap(find.text('ui').last);
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await _press(tester, _create);

      final task = _newTask(server, 'With a label');
      expect(server.labels.where((l) => l['taskId'] == task['id']), hasLength(1));
      expect(
        find.descendant(
          of: find.byKey(ValueKey('board-card-${task['id']}')),
          matching: find.text('ui'),
        ),
        findsOneWidget,
      );
    });

    testBothLayouts('pressing twice creates one task', (tester, size) async {
      final server = FakeKaneo();
      final count = server.tasks.length;
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Once');
      await tester.pump();
      final gate = server.hold(_createPath, method: 'POST');
      await tester.ensureVisible(_create);
      await tester.pump();
      tester.widget<FilledButton>(_create).onPressed!();
      await tester.pump();
      // Busy now: nothing to press, and no way out.
      expect(_enabled(tester), isFalse);
      expect(tester.widget<OutlinedButton>(_cancel).onPressed, isNull);
      gate.release();
      await tester.pumpAndSettle();

      expect(_form, findsNothing);
      expect(server.tasks, hasLength(count + 1));
      expect(_posts(server), hasLength(1));
    });

    testWidgets('closing the dialog while it is on its way still gets the card to the board', (
      tester,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, wideSize, server: server, status: 'in-review');
      await tester.enterText(_title, 'Left behind');
      await tester.pump();
      final gate = server.hold(_createPath, method: 'POST');
      await _pressHolding(tester, _create);
      await tester.tap(find.byTooltip('Close'));
      await _settle(tester);
      expect(_form, findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(_inColumn('in-review', 'Left behind'), findsOneWidget);
      expect(find.text('Task created successfully'), findsOneWidget);
    });

    testWidgets('a failure after the dialog was closed is still reported', (tester) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, wideSize, server: server);
      await tester.enterText(_title, 'Left behind');
      await tester.pump();
      final gate = server.hold(_createPath, method: 'POST');
      await _pressHolding(tester, _create);
      await tester.tap(find.byTooltip('Close'));
      await _settle(tester);

      server.failNext(_createPath, method: 'POST', status: 500);
      gate.release();
      await tester.pumpAndSettle();
      expect(find.text(app.i18n.t('common:modals.createTask.createError')), findsOneWidget);
    });

    testBothLayouts('the title is one line, and the description is sent exactly as typed', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, '  Pasted\n  in  ');
      await tester.enterText(_description, '  # As typed\n\n* me  \n\n');
      await _press(tester, _create);

      final task = _newTask(server, 'Pasted in');
      expect(task['description'], '  # As typed\n\n* me  \n\n');
    });

    testBothLayouts('every field is sent', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Everything');
      await _press(tester, _priority);
      await _choose(tester, 'Urgent');
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      await _press(tester, _startDate);
      await _pickDay(tester);
      await _press(tester, _dueDate);
      await _pickDay(tester);
      await _press(tester, _create);

      final task = _newTask(server, 'Everything');
      expect(task['priority'], 'urgent');
      expect(task['userId'], 'user-2');
      expect(task['startDate'], _day15());
      expect(task['dueDate'], _day15());
      expect(task['projectId'], FakeKaneo.projectId);
    });

    testBothLayouts('a date can be cleared again', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'No date after all');
      await _press(tester, _dueDate);
      await _pickDay(tester);
      await _press(tester, _dueDate);
      await _choose(tester, 'Clear');
      await _press(tester, _create);
      expect(_newTask(server, 'No date after all')['dueDate'], isNull);
    });

    testBothLayouts('a task nobody is assigned to stays that way', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Nobody yet');
      await _press(tester, _create);
      final task = _newTask(server, 'Nobody yet');
      expect(task['userId'], isNull);
      expect(_posts(server).single.body, isNot(contains('userId')));
    });
  });

  group('labels', () {
    testBothLayouts('one made on the spot is created, selected and added', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'With a new label');
      await _press(tester, _labels);
      await tester.enterText(_labelSearch, 'fresh');
      await tester.pump();
      await tester.tap(find.text('Create label “fresh”'));
      await tester.pumpAndSettle();
      expect(server.labels.where((l) => l['name'] == 'fresh'), hasLength(1));
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(_shown(_labels, 'fresh'), findsOneWidget);

      await _press(tester, _create);
      final task = _newTask(server, 'With a new label');
      expect(
        server.labels.where((l) => l['name'] == 'fresh' && l['taskId'] == task['id']),
        hasLength(1),
      );
    });

    // KAN-66: a label only other tasks had wasn't offered.
    testBothLayouts('one only another task has is offered, and stays on that task', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..labels.clear();
      server.addLabel('theirs', color: 'teal', taskId: 'task-3');
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Borrowing a label');
      await _press(tester, _labels);
      await tester.tap(find.text('theirs').last);
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(_shown(_labels, 'theirs'), findsOneWidget);

      await _press(tester, _create);
      final task = _newTask(server, 'Borrowing a label');
      expect(
        server.labels.where((l) => l['name'] == 'theirs' && l['taskId'] == task['id']),
        hasLength(1),
      );
      expect(server.labels.where((l) => l['taskId'] == 'task-3'), hasLength(1));
      expect(server.labels.where((l) => l['taskId'] == null), isEmpty);
    });

    testBothLayouts('making one has its own permission', (tester, size) async {
      final server = FakeKaneo()..capabilities['createLabels'] = false;
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _labels);
      await tester.enterText(_labelSearch, 'fresh');
      await tester.pump();
      expect(find.text('Create label “fresh”'), findsNothing);
    });

    testBothLayouts('one can be taken off again', (tester, size) async {
      final server = FakeKaneo()..addLabel('ui', color: 'blue');
      await _openFromBoard(tester, size, server: server);
      await tester.enterText(_title, 'Changed my mind');
      for (var i = 0; i < 2; i++) {
        await _press(tester, _labels);
        await tester.tap(find.text('ui').last);
        await tester.pump();
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();
      }
      expect(_shown(_labels, 'ui'), findsNothing);
      await _press(tester, _create);
      final task = _newTask(server, 'Changed my mind');
      expect(server.labels.where((l) => l['taskId'] == task['id']), isEmpty);
    });
  });

  group('choosing a project', () {
    FakeKaneo twoProjects() {
      final server = FakeKaneo();
      server.addProject(id: 'other', name: 'Other', slug: 'OTH');
      server.columns.removeWhere((c) => c['projectId'] == 'other' && c['slug'] == 'in-review');
      return server;
    }

    testBothLayouts('the task goes to the project chosen, in one of its columns', (
      tester,
      size,
    ) async {
      final server = twoProjects();
      await _openFromBoard(tester, size, server: server, status: 'in-review');
      await _press(tester, _project);
      await _choose(tester, 'Other');
      expect(_shown(_project, 'Other'), findsOneWidget);
      expect(_shown(_status, 'To Do'), findsOneWidget);

      await tester.enterText(_title, 'Elsewhere');
      await _press(tester, _create);
      final task = _newTask(server, 'Elsewhere');
      expect(task['projectId'], 'other');
      expect(task['status'], 'to-do');
      // The board behind is another project's, and doesn't get the card.
      expect(_form, findsNothing);
      expect(find.text('Elsewhere'), findsNothing);
    });

    testBothLayouts('without a project there is nothing to create in, until one is picked', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.newTask());
      await tester.enterText(_title, 'Where to?');
      await tester.pumpAndSettle();
      expect(_enabled(tester), isFalse);
      expect(server.requestsTo('api/task/new'), isEmpty);

      await _press(tester, _project);
      await _choose(tester, 'Demo');
      expect(_enabled(tester), isTrue);
    });

    testBothLayouts('an assignee who isn\'t in the next project doesn\'t follow', (
      tester,
      size,
    ) async {
      final server = twoProjects();
      server.on(RegExp(r'members'), (request) {
        final inOther = request.query['projectId'] == 'other';
        return FakeResponse(
          200,
          inOther
              ? server.members.where((m) => m['id'] == FakeKaneo.userId).toList()
              : server.members,
        );
      }, method: 'GET');
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _assignee);
      await _choose(tester, 'Second User');
      expect(_shown(_assignee, 'Second User'), findsOneWidget);

      await _press(tester, _project);
      await _choose(tester, 'Other');
      expect(_shown(_assignee, 'Second User'), findsNothing);

      await tester.enterText(_title, 'Without them');
      await _press(tester, _create);
      expect(_newTask(server, 'Without them')['userId'], isNull);
    });
  });

  group('required custom fields', () {
    testBothLayouts('the task is created, and the server fills them in', (tester, size) async {
      final server = FakeKaneo();
      server.customFields.add({
        'id': 'field-1',
        'projectId': FakeKaneo.projectId,
        'name': 'Team',
        'type': 'dropdown',
        'required': true,
        'defaultValue': 'Core',
        'options': ['Core', 'Web'],
        'position': 0,
      });
      await _openFromBoard(tester, size, server: server, status: 'to-do');
      await tester.enterText(_title, 'Has a required field');
      await tester.pump();
      expect(_enabled(tester), isTrue);
      await _press(tester, _create);

      expect(_form, findsNothing);
      final task = _newTask(server, 'Has a required field');
      expect(_posts(server).single.body, isNot(contains('customFields')));
      expect(
        server.customFieldValues.singleWhere((v) => v['taskId'] == task['id'])['value'],
        'Core',
      );
      expect(_inColumn('to-do', 'Has a required field'), findsOneWidget);
    });
  });

  group('while it can\'t be used yet', () {
    testBothLayouts('loading: what is typed stays, and the button waits for the columns', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final gate = server.hold('api/column/');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.newTask(projectId: FakeKaneo.projectId),
        settle: false,
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.enterText(_title, 'Typed early');
      await tester.pump();
      expect(_enabled(tester), isFalse);

      gate.release();
      await tester.pumpAndSettle();
      expect(find.text('Typed early'), findsOneWidget);
      expect(_shown(_status, 'To Do'), findsOneWidget);
      expect(_enabled(tester), isTrue);
    });

    testBothLayouts('columns that fail to load say so, and can be tried again', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()
        ..fail('api/column/', status: 500, body: {'message': 'No columns today'});
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.newTask(projectId: FakeKaneo.projectId),
      );
      await tester.enterText(_title, 'Kept through the retry');
      await tester.pump();
      expect(_shown(_notice, 'No columns today'), findsOneWidget);
      expect(_enabled(tester), isFalse);

      server.clearOverrides();
      await _press(tester, find.descendant(of: _notice, matching: find.text('Try again')));
      expect(_notice, findsNothing);
      expect(find.text('Kept through the retry'), findsOneWidget);
      expect(_enabled(tester), isTrue);
    });

    testBothLayouts('projects that fail to load say so too', (tester, size) async {
      final server = FakeKaneo()
        ..fail(RegExp(r'api/project'), status: 500, body: {'message': 'No projects today'});
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.newTask(projectId: FakeKaneo.projectId),
      );
      expect(_shown(_notice, 'No projects today'), findsOneWidget);
      await tester.enterText(_title, 'Nowhere to go');
      await tester.pump();
      expect(_enabled(tester), isFalse);
    });

    testBothLayouts('a workspace with no projects says so', (tester, size) async {
      await pumpKaneoApp(
        tester,
        server: FakeKaneo.empty(),
        size: size,
        location: AppRoutes.newTask(),
      );
      expect(_shown(_notice, 'No projects'), findsOneWidget);
      await tester.enterText(_title, 'Nowhere to go');
      await tester.pump();
      expect(_enabled(tester), isFalse);
      await tester.tap(_project, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(PopoverBody), findsNothing);
    });

    testBothLayouts('someone who may not create tasks is told, and can\'t', (tester, size) async {
      final server = FakeKaneo()..capabilities['createTasks'] = false;
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.newTask(projectId: FakeKaneo.projectId),
      );
      expect(_shown(_notice, app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      await tester.enterText(_title, 'Not allowed');
      await tester.pump();
      expect(_enabled(tester), isFalse);
    });

    testBothLayouts('a field they may not set can\'t be opened', (tester, size) async {
      final server = FakeKaneo()
        ..capabilities['assignTasks'] = false
        ..capabilities['updateLabels'] = false;
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.newTask(projectId: FakeKaneo.projectId),
      );
      await tester.tap(_assignee, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Second User'), findsNothing);
      await tester.tap(_labels, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);

      await tester.enterText(_title, 'Still possible');
      await tester.pump();
      expect(_enabled(tester), isTrue);
    });

    testBothLayouts('permissions that fail to load count as allowed', (tester, size) async {
      final server = FakeKaneo()..fail('capabilities', status: 500);
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.newTask(projectId: FakeKaneo.projectId),
      );
      await tester.enterText(_title, 'Let the server decide');
      await tester.pump();
      expect(_enabled(tester), isTrue);
    });
  });

  group('boardWithNewCard', () {
    BoardData board() => BoardData.fromJson({
      'id': 'p',
      'name': 'P',
      'slug': 'P',
      'workspaceId': 'w',
      'columns': [
        {
          'id': 'c1',
          'name': 'One',
          'slug': 'one',
          'tasks': [
            {'id': 'a', 'title': 'A', 'status': 'one', 'position': 1, 'projectId': 'p'},
            {'id': 'b', 'title': 'B', 'status': 'one', 'position': 3, 'projectId': 'p'},
          ],
        },
        {'id': 'c2', 'name': 'Two', 'slug': 'two', 'tasks': <Object>[]},
      ],
      'plannedTasks': <Object>[],
      'archivedTasks': <Object>[],
    });

    BoardTask card(String status, {String id = 'new', num? position}) =>
        BoardTask(id: id, title: 'New', status: status, projectId: 'p', position: position);

    List<String> ids(List<BoardTask>? tasks) => [for (final t in tasks!) t.id];

    test('goes to the column of its status, by position', () {
      final result = boardWithNewCard(board(), card('one', position: 2));
      expect(ids(result.columns[0].tasks), ['a', 'new', 'b']);
      expect(result.columns[1].tasks, isEmpty);
      expect(ids(boardWithNewCard(board(), card('two')).columns[1].tasks), ['new']);
    });

    test('goes last when it has no position', () {
      expect(ids(boardWithNewCard(board(), card('one')).columns[0].tasks), ['a', 'b', 'new']);
    });

    test('goes to planned and archived, which aren\'t columns', () {
      expect(ids(boardWithNewCard(board(), card(statusPlanned)).plannedTasks), ['new']);
      expect(ids(boardWithNewCard(board(), card(statusArchived)).archivedTasks), ['new']);
    });

    test('a card already there stays as it is', () {
      final result = boardWithNewCard(board(), card('two', id: 'a'));
      expect(ids(result.columns[0].tasks), ['a', 'b']);
      expect(result.columns[1].tasks, isEmpty);
    });

    test('a status with nowhere to show changes nothing', () {
      final result = boardWithNewCard(board(), card('elsewhere'));
      expect(ids(result.columns[0].tasks), ['a', 'b']);
      expect(result.plannedTasks, isEmpty);
    });
  });
}

/// Lets animations finish while a request is held back.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Presses [target] with a request held back, where waiting for everything to settle wouldn't end.
Future<void> _pressHolding(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _settle(tester);
}
