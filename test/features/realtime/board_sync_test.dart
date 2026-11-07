import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/open_task.dart' show openTask;
import 'package:kaneo_app/features/task/task_edits.dart';

import '../../support/test_app.dart';

final _socket = FakeKaneo.projectSocket(FakeKaneo.projectId);

Finder _card(String id) => find.byKey(ValueKey('board-card-$id'));

Finder _inColumn(String slug, String id) =>
    find.descendant(of: find.byKey(ValueKey('drop-column-$slug')), matching: _card(id));

/// What an open board reads over the network. Anything in here costs a request per page.
int _boardReads(FakeKaneo server) => server.requestsTo('api/task/tasks/').length;

int _taskReads(FakeKaneo server, String id) => server.requestsTo('api/task/$id').length;

Map<String, dynamic> _task(FakeKaneo server, String id) =>
    server.tasks.firstWhere((t) => t['id'] == id);

Future<TestApp> _open(WidgetTester tester, FakeKaneo server, Size size, {Session? session}) =>
    pumpKaneoApp(
      tester,
      server: server,
      size: size,
      session: session ?? testSession,
      location: AppRoutes.board(FakeKaneo.projectId),
    );

/// Time for an event to be handled, and no more than the five seconds it is allowed.
Future<void> _within5Seconds(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Time that would do for a socket to come back after any failure.
Future<void> _afterRetry(WidgetTester tester) async {
  await tester.pump(RealtimeConnection.maxRetryDelay);
  await tester.pump();
  await _within5Seconds(tester);
}

Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

void main() {
  group('a change made elsewhere', () {
    testBothLayouts('moves the card within five seconds, reading only that task', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      expect(_inColumn('to-do', 'task-1'), findsOneWidget);
      expect(server.openSockets(_socket), hasLength(1));
      final reads = _boardReads(server);
      _task(server, 'task-1')
        ..['status'] = 'in-progress'
        ..['title'] = 'Changed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1', 'projectId': FakeKaneo.projectId});
      await _within5Seconds(tester);
      expect(_inColumn('in-progress', 'task-1'), findsOneWidget);
      expect(_inColumn('to-do', 'task-1'), findsNothing);
      expect(find.text('Changed on the web'), findsOneWidget);
      expect(_boardReads(server), reads, reason: 'A change to one task must not read the board.');
      expect(_taskReads(server, 'task-1'), 1);
      expect(server.requestsTo('api/task/task-1').single.query['view'], 'board');
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('shows in the list view as well', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      _task(server, 'task-1')['title'] = 'Changed for the list';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(find.text('Changed for the list'), findsOneWidget);
    });

    testBothLayouts('a move on the web is applied from the event, without any request', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final requests = server.requests.length;
      server.emit(_socket, 'TASKS_REORDERED', {
        'projectId': FakeKaneo.projectId,
        'tasks': [
          {'id': 'task-3', 'position': -1, 'status': 'to-do'},
        ],
      });
      await _within5Seconds(tester);
      expect(_inColumn('to-do', 'task-3'), findsOneWidget);
      final column = app.container
          .read(boardQuery(FakeKaneo.projectId))
          .requireValue
          .columns
          .firstWhere((c) => c.slug == 'to-do');
      expect(column.tasks!.first.id, 'task-3');
      expect(server.requests.length, requests);
    });

    testBothLayouts('the echo of a change already on screen changes nothing', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final query = boardQuery(FakeKaneo.projectId);
      final before = app.container.read(query).requireValue;
      server.emit(_socket, 'TASKS_REORDERED', {
        'tasks': [
          for (final task in before.columns.first.tasks!)
            {'id': task.id, 'position': task.position, 'status': task.status},
        ],
      });
      await _within5Seconds(tester);
      expect(app.container.read(query).requireValue, same(before));
    });

    testBothLayouts('a new task shows up with its labels', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      final task = server.addTask(id: 'task-new', title: 'From the web', status: 'to-do');
      server.addLabel('from-web', taskId: task['id'] as String);
      server.emit(_socket, 'TASK_CREATED', {'taskId': 'task-new'});
      await _within5Seconds(tester);
      expect(_inColumn('to-do', 'task-new'), findsOneWidget);
      expect(find.text('from-web'), findsOneWidget);
      expect(_boardReads(server), reads);
    });

    testBothLayouts('a deleted task goes, without a request', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      server.tasks.removeWhere((t) => t['id'] == 'task-3');
      server.emit(_socket, 'TASK_DELETED', {'taskId': 'task-3'});
      await _within5Seconds(tester);
      expect(_card('task-3'), findsNothing);
      expect(_boardReads(server), reads);
      expect(_taskReads(server, 'task-3'), 0);
    });

    testBothLayouts('a task moved to another project goes', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      _task(server, 'task-3')['projectId'] = FakeKaneo.secondProjectId;
      server.emit(_socket, 'TASK_MOVED', {'taskId': 'task-3'});
      await _within5Seconds(tester);
      expect(_card('task-3'), findsNothing);
    });

    testBothLayouts('a change of labels reads only the labels', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      server.addLabel('added-on-web', taskId: 'task-1');
      final reads = _boardReads(server);
      server.emit(_socket, 'TASK_LABEL_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(find.text('added-on-web'), findsOneWidget);
      expect(_boardReads(server), reads);
      expect(_taskReads(server, 'task-1'), 0);
    });

    testBothLayouts('a child finished elsewhere brings the progress of its parent', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final query = boardQuery(FakeKaneo.projectId);
      SubtaskCounts? progress() => app.container
          .read(query)
          .requireValue
          .columns
          .expand((c) => c.tasks!)
          .firstWhere((t) => t.id == 'task-1')
          .subtaskCounts;
      expect(progress()!.completed, 0);
      final reads = _boardReads(server);
      _task(server, 'task-2')['status'] = 'done';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-2'});
      // The server sends this with every change of status, with no word on which task it is about.
      server.emit(_socket, 'TASK_RELATION_UPDATED', {'taskId': ''});
      await _within5Seconds(tester);
      expect(progress()!.completed, 1);
      expect(_boardReads(server), reads);
    });

    testBothLayouts('the progress of a parent with a child elsewhere reads the board', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      server.emit(_socket, 'TASK_RELATION_UPDATED', {'taskId': ''});
      await _within5Seconds(tester);
      expect(_boardReads(server), reads + 1);
    });

    testBothLayouts('a new link reads both tasks and the hierarchy', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final relationReads = server.requestsTo('api/task-relation/project/').length;
      server.emit(_socket, 'TASK_RELATION_UPDATED', {
        'sourceTaskId': 'task-1',
        'targetTaskId': 'task-3',
      });
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), 1);
      expect(_taskReads(server, 'task-3'), 1);
      expect(server.requestsTo('api/task-relation/project/').length, relationReads + 1);
    });

    testBothLayouts('a burst reads the board once, instead of each task', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      for (final task in server.tasks) {
        task['title'] = 'Burst ${task['id']}';
        server.emit(_socket, 'TASK_UPDATED', {'taskId': task['id']});
      }
      await _within5Seconds(tester);
      expect(find.text('Burst task-1'), findsOneWidget);
      expect(_boardReads(server), reads + 1);
      expect(server.requests.where((r) => r.query['view'] == 'board'), isEmpty);
    });

    testBothLayouts('events of one moment make one read of a task', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      for (var i = 0; i < 3; i++) {
        server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      }
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), 1);
    });

    testBothLayouts('a change to the project reads the board and the columns', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      server.columns.first['name'] = 'Renamed on the web';
      server.emit(_socket, 'PROJECT_UPDATED', {'projectId': FakeKaneo.projectId});
      await _within5Seconds(tester);
      expect(find.text('Renamed on the web'), findsOneWidget);
      expect(_boardReads(server), reads + 1);
    });

    testBothLayouts('an event it has no use for reads nothing', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final requests = server.requests.length;
      // With no task open, a comment has nothing to show on the board.
      server.emit(_socket, 'COMMENT_UPDATED', {'taskId': 'task-1'});
      server.emit(_socket, 'SOMETHING_NEW');
      server.emitRaw(_socket, 'not json');
      await _within5Seconds(tester);
      expect(server.requests.length, requests);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('a reorder it cannot read reads the board', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      server.emit(_socket, 'TASKS_REORDERED', {'tasks': 'nonsense'});
      await _within5Seconds(tester);
      expect(_boardReads(server), reads + 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('when a read goes wrong', () {
    testBothLayouts('a task that no longer exists goes', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      server.tasks.removeWhere((t) => t['id'] == 'task-3');
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-3'});
      await _within5Seconds(tester);
      expect(_card('task-3'), findsNothing);
    });

    testBothLayouts('any other failure keeps the board, and reads it to find out more', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      server.failNext('api/task/task-1', status: 500);
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_card('task-1'), findsOneWidget);
      expect(_boardReads(server), reads + 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('no access any more keeps the board on screen', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      server.fail('api/task', status: 403);
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_card('task-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('after time without a socket', () {
    testBothLayouts('the socket comes back by itself and the board catches up', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);

      server.unreachable = true;
      server.dropSockets();
      _task(server, 'task-1')['title'] = 'Changed while offline';
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Changed while offline'), findsNothing);
      expect(_card('task-1'), findsOneWidget, reason: 'The board stays on screen meanwhile.');
      expect(find.byType(CircularProgressIndicator), findsNothing);

      server.unreachable = false;
      await _afterRetry(tester);
      expect(server.openSockets(_socket), hasLength(1));
      expect(find.text('Changed while offline'), findsOneWidget);
      // Reads made while offline fail too, and count as requests.
      expect(_boardReads(server), reads + 1);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('a page that failed to load recovers', (tester, size) async {
      final server = FakeKaneo()..unreachable = true;
      final app = await _open(tester, server, size);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      server.unreachable = false;
      await _afterRetry(tester);
      expect(_card('task-1'), findsOneWidget);
    });

    testBothLayouts('a server that refuses sockets leaves the board working', (tester, size) async {
      final server = FakeKaneo()..refuseSockets = true;
      final app = await _open(tester, server, size);
      expect(_card('task-1'), findsOneWidget);
      await _within5Seconds(tester);
      expect(server.openSockets(_socket), isEmpty);
      expect(app.container.read(boardQuery(FakeKaneo.projectId)).value, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      _task(server, 'task-1')['title'] = 'Read once it let the socket in';
      server.refuseSockets = false;
      await _afterRetry(tester);
      expect(server.openSockets(_socket), hasLength(1));
      expect(find.text('Read once it let the socket in'), findsOneWidget);
    });
  });

  group('the app in the background', () {
    testBothLayouts('gives up the socket, and back in front it catches up', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      await _lifecycle(tester, const [AppLifecycleState.inactive]);
      expect(
        server.openSockets(_socket),
        hasLength(1),
        reason: 'A dialog over the app is no reason.',
      );

      await _lifecycle(tester, const [AppLifecycleState.hidden, AppLifecycleState.paused]);
      expect(server.openSockets(_socket), isEmpty);
      final sockets = server.sockets.length;
      final requests = server.requests.length;
      _task(server, 'task-1')['title'] = 'Changed in the background';
      await tester.pump(const Duration(minutes: 5));
      expect(server.sockets, hasLength(sockets), reason: 'No retries in the background.');
      expect(server.requests, hasLength(requests));

      await _lifecycle(tester, const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await _within5Seconds(tester);
      expect(server.openSockets(_socket), hasLength(1));
      expect(find.text('Changed in the background'), findsOneWidget);
    });

    testBothLayouts('coming back with the server unreachable retries until it answers', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      await _lifecycle(tester, const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      server.unreachable = true;
      await _lifecycle(tester, const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pump(const Duration(seconds: 3));
      expect(server.openSockets(_socket), isEmpty);
      _task(server, 'task-1')['title'] = 'Changed meanwhile';
      server.unreachable = false;
      await _afterRetry(tester);
      expect(find.text('Changed meanwhile'), findsOneWidget);
    });
  });

  group('something in progress on this device', () {
    testBothLayouts('a card being saved holds back what comes in, and other columns stay still', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final gesture = await _startDrag(tester, 'task-1');
      final header = tester.getRect(find.byKey(const ValueKey('column-header-in-progress')));
      await gesture.moveTo(Offset(header.left + 20, header.center.dy));
      await tester.pump(const Duration(milliseconds: 30));
      final gate = server.hold('api/task/reorder');
      await gesture.up();
      await tester.pump();
      expect(_inColumn('in-progress', 'task-1'), findsOneWidget);
      final others = tester.getTopLeft(_card('task-5'));

      // Another person's change, and the board as the server still has it.
      _task(server, 'task-5')['title'] = 'Changed by someone else';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-5'});
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), 0);
      expect(_taskReads(server, 'task-5'), 0);
      expect(_inColumn('in-progress', 'task-1'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getTopLeft(_card('task-5')), others);

      gate.release();
      await _within5Seconds(tester);
      expect(find.text('Changed by someone else'), findsOneWidget);
      expect(_inColumn('in-progress', 'task-1'), findsOneWidget);
      expect(tester.getTopLeft(_card('task-5')), others);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testBothLayouts('a card in the air holds back what comes in until it lands', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final gesture = await _startDrag(tester, 'task-1');
      _task(server, 'task-1')['title'] = 'Changed during the drag';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), 0);
      expect(find.text('Changed during the drag'), findsNothing);
      await gesture.cancel();
      await _within5Seconds(tester);
      expect(find.text('Changed during the drag'), findsOneWidget);
    });

    testBothLayouts('a read overtaken by a change here is read again, and undoes nothing', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final gate = server.hold('api/task/task-3');
      _task(server, 'task-3')['title'] = 'Read before the change';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-3'});
      await tester.pump(const Duration(seconds: 1));
      expect(_taskReads(server, 'task-3'), 1);

      // The change on this device, which the read that's under way knows nothing about.
      final query = boardQuery(FakeKaneo.projectId);
      final board = app.container.read(query).requireValue;
      app.container
          .read(query.notifier)
          .setData(
            board.copyWith(
              columns: [
                for (final column in board.columns)
                  column.copyWith(
                    tasks: [
                      for (final task in column.tasks!)
                        task.id == 'task-1' ? task.copyWith(title: 'Changed here') : task,
                    ],
                  ),
              ],
            ),
          );
      await tester.pump();
      _task(server, 'task-3')['title'] = 'Read after the change';
      gate.release();
      await _within5Seconds(tester);
      expect(find.text('Changed here'), findsOneWidget);
      expect(find.text('Read after the change'), findsOneWidget);
      expect(_taskReads(server, 'task-3'), 2);
    });

    testBothLayouts('an edit still being saved holds back the read of that task only', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final context = tester.element(_card('task-1'));
      openTask(context, 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      final gate = server.hold('api/task/title/task-1');
      app.container.read(taskEditsProvider('task-1')).setTitle('Saving this');
      await tester.pump();
      final reads = _taskReads(server, 'task-1');
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-3'});
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), reads);
      expect(_taskReads(server, 'task-3'), 1);
      expect(
        app.container.read(taskQuery('task-1')).requireValue.title,
        'Saving this',
        reason: 'A read from before the save would have undone this.',
      );
      gate.release();
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), greaterThan(reads));
      expect(app.container.read(taskQuery('task-1')).requireValue.title, 'Saving this');
      expect(find.text('Saving this').evaluate(), isNotEmpty);
    });

    testBothLayouts('the board being read waits, then reads again if tasks came or went', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final gate = server.hold('api/task/tasks/');
      final reads = _boardReads(server);
      unawaited(app.container.read(boardQuery(FakeKaneo.projectId).notifier).refresh());
      await tester.pump();
      server.addTask(id: 'task-late', title: 'Came during the read', status: 'to-do');
      server.emit(_socket, 'TASK_CREATED', {'taskId': 'task-late'});
      await _within5Seconds(tester);
      expect(_boardReads(server), reads + 1, reason: 'Nothing new until this read is done.');
      expect(_taskReads(server, 'task-late'), 0);
      gate.release();
      await _within5Seconds(tester);
      expect(_boardReads(server), reads + 2);
      expect(_card('task-late'), findsOneWidget);
    });
  });

  group('a task open over the board', () {
    testBothLayouts('follows what happens to it', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      openTask(tester.element(_card('task-1')), 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      expect(taskOpen('task-1'), findsOneWidget);
      _task(server, 'task-1')['title'] = 'Renamed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1', 'taskTitleChanged': true});
      await _within5Seconds(tester);
      final title = tester.widget<TextField>(find.byKey(const ValueKey('task-title')));
      expect(title.controller!.text, 'Renamed on the web');
    });

    testBothLayouts('keeps a title being typed', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      openTask(tester.element(_card('task-1')), 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('task-title'));
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'Being typed');
      _task(server, 'task-1')['title'] = 'Renamed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(tester.widget<TextField>(field).controller!.text, 'Being typed');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(_task(server, 'task-1')['title'], 'Being typed');
    });

    testBothLayouts('reads its list again when a subtask on it changes', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      openTask(tester.element(_card('task-1')), 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      final reads = server.requestsTo('api/task-relation/task-1').length;
      _task(server, 'task-2')['status'] = 'done';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-2'});
      await _within5Seconds(tester);
      expect(server.requestsTo('api/task-relation/task-1').length, reads + 1);
    });

    testBothLayouts('shows a comment made elsewhere', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      openTask(tester.element(_card('task-1')), 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      server.addComment('task-1', 'Said on the web');
      server.emit(_socket, 'COMMENT_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      await tester.scrollUntilVisible(
        find.text('Said on the web'),
        300,
        scrollable: find
            .descendant(of: taskOpen('task-1'), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Said on the web'), findsOneWidget);
    });

    testBothLayouts('shows its labels and links as they change', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      openTask(tester.element(_card('task-1')), 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      final labelReads = server.requestsTo('api/label/task/task-1').length;
      final linkReads = server.requestsTo('api/task-relation/task-1').length;
      server.emit(_socket, 'TASK_LABEL_UPDATED', {'taskId': 'task-1'});
      server.emit(_socket, 'TASK_RELATION_UPDATED', {
        'sourceTaskId': 'task-1',
        'targetTaskId': 'task-3',
      });
      await _within5Seconds(tester);
      expect(server.requestsTo('api/label/task/task-1').length, greaterThan(labelReads));
      expect(server.requestsTo('api/task-relation/task-1').length, greaterThan(linkReads));
    });
  });

  group('the account', () {
    for (final (type, token) in const [
      (CredentialType.apiKey, FakeKaneo.apiKey),
      (CredentialType.bearer, FakeKaneo.sessionToken),
    ]) {
      testBothLayouts('signing in with $type brings live updates', (tester, size) async {
        final server = FakeKaneo();
        final session = Session(
          serverUrl: FakeKaneo.serverUrl,
          credentialType: type,
          token: token,
          userId: FakeKaneo.userId,
          userName: 'Test User',
          userEmail: FakeKaneo.email,
        );
        await _open(tester, server, size, session: session);
        final socket = server.openSockets(_socket).single;
        expect(socket.session.credentialType, type);
        expect(socket.session.token, token);
        expect(server.openSockets(FakeKaneo.userSocket).single.session.token, token);
        _task(server, 'task-1')['title'] = 'Live with $type';
        server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
        await _within5Seconds(tester);
        expect(find.text('Live with $type'), findsOneWidget);
      });
    }

    testBothLayouts('signing out closes every socket', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      await app.container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      expect(server.sockets.where((s) => s.isOpen), isEmpty);
    });

    testBothLayouts('a new credential gets a new socket, and the old one closes', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final old = server.openSockets(_socket).single;
      await app.container
          .read(sessionProvider.notifier)
          .signIn(
            const Session(
              serverUrl: FakeKaneo.serverUrl,
              credentialType: CredentialType.bearer,
              token: FakeKaneo.sessionToken,
              userId: FakeKaneo.userId,
              userName: 'Test User',
              userEmail: FakeKaneo.email,
            ),
          );
      await tester.pump();
      await tester.pump();
      expect(old.isOpen, isFalse);
      expect(server.openSockets(_socket).single.session.token, FakeKaneo.sessionToken);
      await _within5Seconds(tester);
      expect(server.openSockets(_socket), hasLength(1));
    });

    testBothLayouts('a page covered by another keeps its socket', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      final socket = server.openSockets(_socket).single;
      app.container.read(routerProvider).push(AppRoutes.task('task-3'));
      await tester.pumpAndSettle();
      expect(socket.isOpen, isTrue);
      _task(server, 'task-3')['title'] = 'Renamed under the page';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-3'});
      await _within5Seconds(tester);
      final title = tester.widget<TextField>(find.byKey(const ValueKey('task-title')));
      expect(title.controller!.text, 'Renamed under the page');
      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(
        socket.isOpen,
        isTrue,
        reason: 'Nothing was missed, so there is nothing to read again.',
      );
      expect(find.text('Renamed under the page'), findsOneWidget);
    });

    testBothLayouts('a socket closed for a revoked key leads to the login page', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      server.credentialsRevoked = true;
      server.dropSockets(code: 1008, reason: 'API key revoked');
      await _within5Seconds(tester);
      await tester.pumpAndSettle();
      expect(app.container.read(sessionProvider), isNull);
      expect(server.sockets.where((s) => s.isOpen), isEmpty);
      await tester.pump(const Duration(minutes: 1));
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('a socket closed for lost access keeps the board, and looks at what is left', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _open(tester, server, size);
      final reads = _boardReads(server);
      server.fail('api/task/tasks/', status: 403);
      server.dropSockets(code: 1008, reason: 'Project access revoked');
      await _within5Seconds(tester);
      expect(_boardReads(server), greaterThan(reads));
      expect(_card('task-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('leaving the board closes its socket', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      app.container.read(routerProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), isEmpty);
      expect(server.openSockets(FakeKaneo.userSocket), hasLength(1));
    });

    testBothLayouts('another project gets a socket of its own', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      app.container.read(routerProvider).go(AppRoutes.board(FakeKaneo.secondProjectId));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(server.openSockets(_socket), isEmpty);
      expect(server.openSockets(FakeKaneo.projectSocket(FakeKaneo.secondProjectId)), hasLength(1));
    });
  });
}

Future<TestGesture> _startDrag(WidgetTester tester, String id) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey('drag-handle-$id'))),
    kind: PointerDeviceKind.touch,
  );
  // Past the distance that makes it a drag.
  await gesture.moveBy(const Offset(30, 30));
  await tester.pump();
  return gesture;
}
