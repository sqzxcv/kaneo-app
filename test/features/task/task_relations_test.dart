import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/task_panel.dart';
import 'package:kaneo_app/features/task/task_relations.dart';
import 'package:kaneo_app/features/task/task_relations_view.dart';

import '../../support/test_app.dart';

final _parent = find.byKey(const ValueKey('task-parent'));
final _add = find.byKey(const ValueKey('task-add-subtask'));
final _box = find.byKey(const ValueKey('subtask-title'));
final _create = find.byKey(const ValueKey('subtask-create'));
final _cancel = find.byKey(const ValueKey('subtask-cancel'));
final _progress = find.byKey(const ValueKey('task-subtask-progress'));
final _title = find.byKey(const ValueKey('task-title'));
final _status = find.byKey(const ValueKey('task-status'));

const _createPath = 'api/task/${FakeKaneo.projectId}';

Finder _row(String id) => find.byKey(ValueKey('task-subtask-$id'));
Finder _check(String id) => find.byKey(ValueKey('task-subtask-check-$id'));
Finder _link(TaskLinkKind kind, String id) => find.byKey(ValueKey('task-link-${kind.name}-$id'));
Finder _card(String id) => find.byKey(ValueKey('board-card-$id'));
Finder _in(Finder parent, Finder child) => find.descendant(of: parent, matching: child);

/// The task on top, which on a narrow window is the only one that finds anything.
Finder _top(String id, Finder child) => _in(taskOpen(id), child);

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

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Back to whatever the task on top was opened from.
Future<void> _back(WidgetTester tester, Size size) async {
  await tester.tap(find.byTooltip(size == wideSize ? 'Close' : 'Back').last);
  await tester.pumpAndSettle();
}

Future<void> _addSubtask(WidgetTester tester, String title) async {
  await _press(tester, _add);
  await tester.enterText(_box, title);
  await tester.pump();
}

Map<String, dynamic> _task(FakeKaneo server, String id) =>
    server.tasks.firstWhere((t) => t['id'] == id);

bool _ticked(WidgetTester tester, String id) => tester.widget<Checkbox>(_check(id)).value == true;

void _expectProgress(String text) => expect(_in(_progress, find.text(text)), findsOneWidget);

RelatedTask _related(String id, {bool? done}) =>
    RelatedTask(id: id, title: id, status: 'to-do', isCompleted: done, projectId: 'p');

TaskRelation _relation(String source, String target, String type, {bool summaries = true}) =>
    TaskRelation(
      id: '$source-$target',
      sourceTaskId: source,
      targetTaskId: target,
      relationType: type,
      sourceTask: summaries ? _related(source) : null,
      targetTask: summaries ? _related(target) : null,
    );

ProjectColumn _column(String slug, int position, {bool isFinal = false}) => ProjectColumn(
  id: slug,
  projectId: 'p',
  name: slug,
  slug: slug,
  position: position,
  isFinal: isFinal,
);

void main() {
  group('reading relations', () {
    final relations = [
      _relation('a', 'me', 'subtask'),
      _relation('me', 'b', 'subtask'),
      _relation('me', 'c', 'subtask'),
      _relation('me', 'd', 'related'),
      _relation('e', 'me', 'related'),
      _relation('me', 'f', 'blocks'),
      _relation('g', 'me', 'blocks'),
    ];

    test('the parent is the source of a subtask link, and the subtasks its targets', () {
      expect(parentTaskOf('me', relations)?.id, 'a');
      expect(parentTaskOf('a', relations), isNull);
      expect(subtasksOf('me', relations).map((t) => t.id), ['b', 'c']);
      expect(subtasksOf('b', relations), isEmpty);
    });

    test('other links are in the order blocked by, blocks, related, in either direction', () {
      expect(linkedTasksOf('me', relations).map((l) => (l.kind, l.task.id)), [
        (TaskLinkKind.blockedBy, 'g'),
        (TaskLinkKind.blocks, 'f'),
        (TaskLinkKind.related, 'd'),
        (TaskLinkKind.related, 'e'),
      ]);
    });

    test('a task the server left out is not shown', () {
      final missing = [
        _relation('me', 'b', 'subtask', summaries: false),
        _relation('a', 'me', 'subtask', summaries: false),
        _relation('me', 'c', 'related', summaries: false),
      ];
      expect(subtasksOf('me', missing), isEmpty);
      expect(parentTaskOf('me', missing), isNull);
      expect(linkedTasksOf('me', missing), isEmpty);
    });

    test('ticking off goes to the first final column, and back to the first open one', () {
      final columns = [
        _column('shipped', 3, isFinal: true),
        _column('review', 2),
        _column('closed', 4, isFinal: true),
        _column('backlog', 1),
      ];
      expect(completionStatus(columns, done: true), 'shipped');
      expect(completionStatus(columns, done: false), 'backlog');
    });

    test('a project without such a column has nowhere to go', () {
      expect(completionStatus([_column('a', 1)], done: true), isNull);
      expect(completionStatus([_column('a', 1, isFinal: true)], done: false), isNull);
      expect(completionStatus(const [], done: true), isNull);
    });

    test('showing a task as done leaves every other task as it was', () {
      final updated = relationsWithDone(relations, 'b', true);
      expect(updated.map((r) => r.id), relations.map((r) => r.id));
      expect(subtasksOf('me', updated).map((t) => t.isCompleted), [true, null]);
      expect(parentTaskOf('me', updated)?.isCompleted, isNull);
    });
  });

  group('subtask progress', () {
    FakeKaneo withSubtasks() {
      final server = FakeKaneo();
      server.addTask(id: 'sub-open', title: 'Still open', status: 'in-progress');
      server.addTask(id: 'sub-done', title: 'All finished', status: 'done');
      server.addRelation('task-1', 'sub-open');
      server.addRelation('task-1', 'sub-done');
      return server;
    }

    testBothLayouts('shows how many are done, and each one', (tester, size) async {
      final server = withSubtasks();
      await _openFromBoard(tester, size, server: server);
      _expectProgress('1/3');
      expect(_in(_row('task-2'), find.text('Write the first description')), findsOneWidget);
      expect(_ticked(tester, 'task-2'), isFalse);
      expect(_ticked(tester, 'sub-open'), isFalse);
      expect(_ticked(tester, 'sub-done'), isTrue);
      final finished = tester.widget<Text>(_in(_row('sub-done'), find.text('All finished')));
      expect(finished.style!.decoration, TextDecoration.lineThrough);
    });

    testBothLayouts('all done shows as complete', (tester, size) async {
      final server = FakeKaneo();
      _task(server, 'task-2')['status'] = 'done';
      await _openFromBoard(tester, size, server: server);
      _expectProgress('1/1');
    });

    testWidgets('wide rows show the ticket id, and narrow ones leave it out', (tester) async {
      final server = FakeKaneo();
      final number = _task(server, 'task-2')['number'];
      await _openFromBoard(tester, wideSize, server: server);
      expect(_in(_row('task-2'), find.text('DEMO-$number')), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();
      await tester.tap(_card('task-1'));
      await tester.pumpAndSettle();
      expect(_in(_row('task-2'), find.text('DEMO-$number')), findsNothing);
    });

    testBothLayouts('a task with no relations says so', (tester, size) async {
      final app = await _openFromBoard(tester, size, id: 'task-3');
      expect(_progress, findsNothing);
      expect(find.text(app.i18n.t('mobile:taskDetail.subtasks.empty')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.relations.empty')), findsOneWidget);
      expect(_parent, findsNothing);
    });
  });

  group('adding a subtask', () {
    testBothLayouts('creates it under the task and shows it, and the board follows', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, 'A new step');
      await tester.tap(_create);
      await tester.pumpAndSettle();

      final created = server.tasks.singleWhere((t) => t['title'] == 'A new step');
      expect(created['projectId'], FakeKaneo.projectId);
      expect(created['status'], 'to-do');
      expect(created['priority'], 'no-priority');
      expect(created['userId'], isNull);
      final id = created['id'] as String;
      expect(
        server.relations.where(
          (r) =>
              r['sourceTaskId'] == 'task-1' &&
              r['targetTaskId'] == id &&
              r['relationType'] == 'subtask',
        ),
        hasLength(1),
      );

      expect(_in(_row(id), find.text('A new step')), findsOneWidget);
      _expectProgress('0/2');
      expect(_box, findsNothing);

      final board = app.container.read(boardQuery(FakeKaneo.projectId)).value!;
      final columns = board.columns;
      expect(columns.expand((c) => c.tasks!).map((t) => t.id), contains(id));
      final card = columns.expand((c) => c.tasks!).firstWhere((t) => t.id == 'task-1');
      expect(card.subtaskCounts?.total, 2);
      final relations = app.container.read(projectRelationsQuery(FakeKaneo.projectId)).value!;
      expect(relations.map((r) => r.targetTaskId), contains(id));
    });

    testBothLayouts('Enter adds it too', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, 'By the keyboard');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(server.tasks.where((t) => t['title'] == 'By the keyboard'), hasLength(1));
      expect(_box, findsNothing);
    });

    testBothLayouts('a title takes one line, without spaces around it', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, '  Pasted\nin two  ');
      await tester.tap(_create);
      await tester.pumpAndSettle();
      expect(server.tasks.where((t) => t['title'] == 'Pasted in two'), hasLength(1));
    });

    testBothLayouts('a blank title adds nothing', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, '   ');
      expect(tester.widget<FilledButton>(_create).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(server.requestsTo(_createPath, method: 'POST'), isEmpty);
      expect(_box, findsOneWidget);
    });

    testBothLayouts('cancelling adds nothing and forgets what was typed', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, 'Changed my mind');
      await tester.tap(_cancel);
      await tester.pumpAndSettle();
      expect(_box, findsNothing);
      expect(server.requestsTo(_createPath, method: 'POST'), isEmpty);

      await _press(tester, _add);
      expect(tester.widget<TextField>(_box).controller!.text, isEmpty);
    });

    testBothLayouts('under a planned task it starts planned', (tester, size) async {
      final server = FakeKaneo();
      _task(server, 'task-3')['status'] = 'planned';
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('task-3'));
      await _addSubtask(tester, 'Later');
      await tester.tap(_create);
      await tester.pumpAndSettle();
      expect(server.tasks.singleWhere((t) => t['title'] == 'Later')['status'], 'planned');
    });

    testBothLayouts('a task that is done still adds to the first open column', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('task-6'));
      await _addSubtask(tester, 'One more thing');
      await tester.tap(_create);
      await tester.pumpAndSettle();
      expect(server.tasks.singleWhere((t) => t['title'] == 'One more thing')['status'], 'to-do');
    });

    testBothLayouts('when it fails it says why, keeps the text and can try again', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, 'Try twice');
      server.failNext(_createPath, method: 'POST', body: {'message': 'Not today'});
      await tester.tap(_create);
      await tester.pumpAndSettle();
      expect(find.text('Not today'), findsOneWidget);
      expect(tester.widget<TextField>(_box).controller!.text, 'Try twice');
      expect(server.tasks.where((t) => t['title'] == 'Try twice'), isEmpty);
      expect(server.requestsTo('api/task-relation', method: 'POST'), isEmpty);

      await tester.tap(_create);
      await tester.pumpAndSettle();
      expect(server.tasks.where((t) => t['title'] == 'Try twice'), hasLength(1));
      expect(_box, findsNothing);
    });

    testBothLayouts('a task that could not be linked is not created again', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, 'Stray');
      server.failNext('api/task-relation', method: 'POST');
      await tester.tap(_create);
      await tester.pumpAndSettle();
      expect(find.text(app.i18n.t('mobile:taskNew.parentFailed')), findsOneWidget);
      expect(server.tasks.where((t) => t['title'] == 'Stray'), hasLength(1));
      expect(_box, findsNothing);
      _expectProgress('0/1');
    });

    testBothLayouts('it finishes even if the task closes meanwhile', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, 'Left behind');
      final gate = server.hold(_createPath, method: 'POST');
      await tester.tap(_create);
      await tester.pump();
      await _back(tester, size);
      gate.release();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final id = server.tasks.singleWhere((t) => t['title'] == 'Left behind')['id'];
      expect(server.relations.where((r) => r['targetTaskId'] == id), hasLength(1));
    });

    testWidgets('turning narrow keeps what is being typed', (tester) async {
      await _openFromBoard(tester, wideSize);
      await _addSubtask(tester, 'Half a title');

      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_box).controller!.text, 'Half a title');

      setWindowSize(tester, wideSize);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_box).controller!.text, 'Half a title');
    });
  });

  group('ticking off a subtask', () {
    testBothLayouts('moves it to the done column, and the list and the board follow', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _check('task-2'));
      expect(_task(server, 'task-2')['status'], 'done');
      expect(_ticked(tester, 'task-2'), isTrue);
      _expectProgress('1/1');
      expect(taskOpen('task-2'), findsNothing);

      final board = app.container.read(boardQuery(FakeKaneo.projectId)).value!;
      final done = board.columns.firstWhere((c) => c.slug == 'done').tasks!;
      expect(done.map((t) => t.id), contains('task-2'));
      final parent = board.columns.expand((c) => c.tasks!).firstWhere((t) => t.id == 'task-1');
      expect(parent.subtaskCounts?.completed, 1);
    });

    testBothLayouts('undoing moves it back to the first open column', (tester, size) async {
      final server = FakeKaneo();
      _task(server, 'task-2')['status'] = 'done';
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _check('task-2'));
      expect(_task(server, 'task-2')['status'], 'to-do');
      expect(_ticked(tester, 'task-2'), isFalse);
      _expectProgress('0/1');
    });

    testBothLayouts('it shows at once, and a second press is ignored until the first has settled', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await tester.ensureVisible(_check('task-2'));
      await tester.pumpAndSettle();
      final gate = server.hold('api/task/status/task-2');
      await tester.tap(_check('task-2'));
      await tester.pump();
      expect(_ticked(tester, 'task-2'), isTrue);
      _expectProgress('1/1');
      await tester.pump(const Duration(milliseconds: 50));
      expect(_task(server, 'task-2')['status'], 'to-do');

      await tester.tap(_check('task-2'));
      await tester.pump();
      expect(_ticked(tester, 'task-2'), isTrue);

      gate.release();
      await tester.pumpAndSettle();
      expect(_task(server, 'task-2')['status'], 'done');
      expect(server.requestsTo('api/task/status/task-2', method: 'PUT'), hasLength(1));
    });

    testBothLayouts('when the server refuses it goes back and says why', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      server.failNext('api/task/status/task-2', body: {'message': 'Nope'});
      await _press(tester, _check('task-2'));
      expect(find.text('Nope'), findsOneWidget);
      expect(_ticked(tester, 'task-2'), isFalse);
      expect(_task(server, 'task-2')['status'], 'to-do');
      _expectProgress('0/1');

      await _press(tester, _check('task-2'));
      expect(_task(server, 'task-2')['status'], 'done');
      expect(_ticked(tester, 'task-2'), isTrue);
    });

    testBothLayouts('when the columns will not load it goes back too', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      server.failNext('api/column/', body: {'message': 'No columns today'});
      await _press(tester, _check('task-2'));
      expect(find.text('No columns today'), findsOneWidget);
      expect(_ticked(tester, 'task-2'), isFalse);
      expect(server.requestsTo('api/task/status/task-2', method: 'PUT'), isEmpty);
    });

    testBothLayouts('a project with no final column says so', (tester, size) async {
      final server = FakeKaneo();
      for (final column in server.columns) {
        column['isFinal'] = false;
      }
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _check('task-2'));
      expect(find.text(app.i18n.t('tasks:subtasks.noCompletionColumn')), findsOneWidget);
      expect(_ticked(tester, 'task-2'), isFalse);
      expect(server.requestsTo('api/task/status/task-2', method: 'PUT'), isEmpty);
    });

    testBothLayouts('a subtask in another project uses the columns of its own project', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      for (final column in server.columns) {
        if (column['projectId'] == FakeKaneo.secondProjectId && column['isFinal'] == true) {
          column['slug'] = 'shipped';
        }
      }
      server.addTask(id: 'far', title: 'Over there', projectId: FakeKaneo.secondProjectId);
      server.addRelation('task-1', 'far');
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _check('far'));
      expect(_task(server, 'far')['status'], 'shipped');
      expect(_ticked(tester, 'far'), isTrue);
    });

    testBothLayouts('a subtask open below follows', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('task-2'));
      await _press(tester, _parent);
      expect(taskOpen('task-1'), findsOneWidget);
      await _press(tester, _top('task-1', _check('task-2')));
      await _back(tester, size);
      expect(_top('task-2', _in(_status, find.text('Done'))), findsOneWidget);
    });
  });

  group('without permission', () {
    testBothLayouts('nothing can be added or ticked, and everything can be opened', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.capabilities['updateTasks'] = false;
      await _openFromBoard(tester, size, server: server);
      expect(_add, findsNothing);
      expect(tester.widget<Checkbox>(_check('task-2')).onChanged, isNull);
      await tester.ensureVisible(_check('task-2'));
      await tester.pumpAndSettle();
      await _press(tester, _row('task-2'));
      expect(taskOpen('task-2'), findsOneWidget);
      expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    testBothLayouts('adding takes permission to create as well', (tester, size) async {
      final server = FakeKaneo();
      server.capabilities['createTasks'] = false;
      await _openFromBoard(tester, size, server: server);
      expect(_add, findsNothing);
      await _press(tester, _check('task-2'));
      expect(_task(server, 'task-2')['status'], 'done');
    });

    testBothLayouts('permission going away closes the box', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _addSubtask(tester, 'Too late');
      server.capabilities['createTasks'] = false;
      unawaited(app.container.read(capabilitiesQuery(FakeKaneo.workspaceId).notifier).refresh());
      await tester.pumpAndSettle();
      expect(_box, findsNothing);
      expect(_add, findsNothing);
    });
  });

  group('going to other tasks and back', () {
    testBothLayouts('a subtask opens, and back returns to its parent', (tester, size) async {
      await _openFromBoard(tester, size);
      await _press(tester, _row('task-2'));
      expect(taskOpen('task-2'), findsOneWidget);
      expect(
        tester.widget<TextField>(_top('task-2', _title)).controller!.text,
        'Write the first description',
      );

      await _back(tester, size);
      expect(taskOpen('task-2'), findsNothing);
      expect(taskOpen('task-1'), findsOneWidget);
      await tester.ensureVisible(_row('task-2'));
    });

    testBothLayouts('a subtask leads up to its parent, and back returns to it', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final number = _task(server, 'task-1')['number'];
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-2'),
      );
      expect(_in(_parent, find.text(app.i18n.t('tasks:detail.subtaskOf'))), findsOneWidget);
      expect(_in(_parent, find.text('DEMO-$number')), findsOneWidget);
      expect(_in(_parent, find.text('Set up the project')), findsOneWidget);

      await _press(tester, _parent);
      expect(taskOpen('task-1'), findsOneWidget);
      expect(_top('task-1', _parent), findsNothing);

      await _back(tester, size);
      expect(taskOpen('task-1'), findsNothing);
      expect(taskOpen('task-2'), findsOneWidget);
    });

    testBothLayouts('linked tasks are labelled by how they are linked, and open', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.addRelation('task-1', 'task-3', 'related');
      server.addRelation('task-1', 'task-4', 'blocks');
      server.addRelation('task-5', 'task-1', 'blocks');
      server.addRelation('task-6', 'task-1', 'related');
      final app = await _openFromBoard(tester, size, server: server);
      final rows = {
        _link(TaskLinkKind.blockedBy, 'task-5'): ('blockedBy', 'Ship the beta', 'task-5'),
        _link(TaskLinkKind.blocks, 'task-4'): ('blocks', 'Fix the drag preview', 'task-4'),
        _link(TaskLinkKind.related, 'task-3'): ('related', 'Review the board layout', 'task-3'),
        _link(TaskLinkKind.related, 'task-6'): ('related', 'Celebrate', 'task-6'),
      };
      final tops = [for (final row in rows.keys) tester.getTopLeft(row).dy];
      expect(tops, [...tops]..sort());
      for (final MapEntry(key: row, value: (kind, title, id)) in rows.entries) {
        final label = app.i18n.t('mobile:taskDetail.relations.$kind');
        expect(_in(row, find.text(label)), findsOneWidget);
        expect(_in(row, find.text(title)), findsOneWidget);

        await _press(tester, row);
        expect(taskOpen(id), findsOneWidget);
        await _back(tester, size);
        expect(taskOpen(id), findsNothing);
        expect(taskOpen('task-1'), findsOneWidget);
      }
      expect(find.byType(Checkbox), findsNWidgets(1));
    });

    testBothLayouts('going down and up and back retraces every step', (tester, size) async {
      await _openFromBoard(tester, size);
      await _press(tester, _row('task-2'));
      await _press(tester, _top('task-2', _parent));
      await _press(tester, _top('task-1', _row('task-2')).last);
      expect(taskOpen('task-2'), findsWidgets);

      await _back(tester, size);
      await _back(tester, size);
      await _back(tester, size);
      expect(taskOpen('task-2'), findsNothing);
      expect(taskOpen('task-1'), findsOneWidget);
      await _back(tester, size);
      expect(find.byKey(taskPanelKey), findsNothing);
      expect(_card('task-1'), findsOneWidget);
    });

    testWidgets('from a page of its own on a wide window it opens over the page', (tester) async {
      await pumpKaneoApp(tester, location: AppRoutes.task('task-1'));
      await _press(tester, _row('task-2'));
      expect(find.byKey(taskPanelKey), findsOneWidget);
      await _back(tester, wideSize);
      expect(find.byKey(taskPanelKey), findsNothing);
      expect(taskOpen('task-1'), findsOneWidget);
    });

    testWidgets('a panel that turned narrow opens a page, and comes back', (tester) async {
      await _openFromBoard(tester, wideSize);
      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();
      await _press(tester, _row('task-2'));
      expect(taskOpen('task-2'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(taskOpen('task-2'), findsNothing);
      expect(find.byKey(taskPanelKey), findsOneWidget);
      expect(taskOpen('task-1'), findsOneWidget);
    });
  });

  group('changes made elsewhere', () {
    testBothLayouts('a status changed on the subtask shows on its parent', (tester, size) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _row('task-2'));
      await _press(tester, _top('task-2', _status));
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await _back(tester, size);
      expect(_ticked(tester, 'task-2'), isTrue);
      _expectProgress('1/1');
    });

    testBothLayouts('a title saved on leaving the subtask shows on its parent', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      await _press(tester, _row('task-2'));
      await tester.enterText(_top('task-2', _title), 'Renamed while leaving');
      await _back(tester, size);
      expect(_task(server, 'task-2')['title'], 'Renamed while leaving');
      expect(_in(_row('task-2'), find.text('Renamed while leaving')), findsOneWidget);
    });

    testBothLayouts('a title changed on the parent shows on the subtask', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('task-2'));
      await _press(tester, _parent);
      await tester.enterText(_top('task-1', _title), 'A new parent name');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await _back(tester, size);
      expect(_in(_parent, find.text('A new parent name')), findsOneWidget);
    });

    testBothLayouts('a change to the task itself does not read its relations again', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openFromBoard(tester, size, server: server);
      final before = server.requestsTo('api/task-relation/task-1').length;
      await tester.enterText(_title, 'Only the title');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_task(server, 'task-1')['title'], 'Only the title');
      expect(server.requestsTo('api/task-relation/task-1'), hasLength(before));
    });

    testBothLayouts('a change to an unrelated task does not either', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final before = server.requestsTo('api/task-relation/task-1').length;
      app.container.read(savedTaskProvider.notifier).saved('task-5');
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/task-relation/task-1'), hasLength(before));
    });
  });

  group('while loading and when it fails', () {
    testBothLayouts('the task shows while its relations load', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold('api/task-relation/task-1');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final spinner = _in(
        find.byType(TaskRelationSections),
        find.byType(CircularProgressIndicator),
      );
      expect(_title, findsOneWidget);
      expect(spinner, findsOneWidget);
      expect(_row('task-2'), findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(spinner, findsNothing);
      expect(_row('task-2'), findsOneWidget);
    });

    testBothLayouts('a failure leaves the task, says so and can be retried', (tester, size) async {
      final server = FakeKaneo()..fail('api/task-relation/task-1', status: 500);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
      );
      expect(_title, findsOneWidget);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      expect(_add, findsNothing);

      server.clearOverrides();
      await _press(tester, find.text(app.i18n.t('mobile:common.retry')));
      expect(_row('task-2'), findsOneWidget);
      expect(_add, findsOneWidget);
    });

    testBothLayouts('no permission says so, with nothing to retry', (tester, size) async {
      final server = FakeKaneo()..fail('api/task-relation/task-1', status: 403);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
      );
      expect(_title, findsOneWidget);
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
    });

    testBothLayouts('a failed refresh keeps the list on screen', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('task-2'));
      await _press(tester, _parent);
      expect(_top('task-1', _row('task-2')), findsOneWidget);
      server.fail('api/task-relation/task-1');
      await _press(tester, _top('task-1', _check('task-2')));
      expect(_ticked(tester, 'task-2'), isTrue);
      _expectProgress('1/1');
    });
  });
}
