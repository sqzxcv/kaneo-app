import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/open_task.dart' show openTask;
import 'package:kaneo_app/features/task/task_edits.dart';

import '../../support/test_app.dart';

final _socket = FakeKaneo.projectSocket(FakeKaneo.projectId);
final _otherSocket = FakeKaneo.projectSocket(FakeKaneo.secondProjectId);

Map<String, dynamic> _task(FakeKaneo server, String id) =>
    server.tasks.firstWhere((t) => t['id'] == id);

int _boardReads(FakeKaneo server) => server.requestsTo('api/task/tasks/').length;

int _taskReads(FakeKaneo server, String id) => server.requestsTo('api/task/$id').length;

String _title(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const ValueKey('task-title'))).controller!.text;

/// A task from a link, the way a search result or the home page gets there: nothing of its project
/// is open below it.
Future<TestApp> _openAlone(WidgetTester tester, FakeKaneo server, Size size, [String? id]) =>
    pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task(id ?? 'task-1'));

/// Time for an event to be handled, and no more than the five seconds it is allowed.
Future<void> _within5Seconds(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

/// KAN-59: nothing else keeps a task up to date when its board isn't open below it.
void main() {
  group('a task opened away from its board', () {
    testBothLayouts('from the inbox, follows a change made elsewhere without reading a board', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      await tester.tap(find.text('Fix the drag preview'));
      await tester.pumpAndSettle();
      expect(taskOpen('task-4'), findsOneWidget);
      expect(server.openSockets(_socket), hasLength(1));

      _task(server, 'task-4')['title'] = 'Renamed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-4', 'taskTitleChanged': true});
      await _within5Seconds(tester);

      expect(_title(tester), 'Renamed on the web');
      expect(_boardReads(server), 0, reason: 'There is no board on screen to read for.');
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('from my tasks, as a panel or a page, does too', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.myTasks);
      await tester.tap(find.byKey(const ValueKey('task-1')));
      await tester.pumpAndSettle();
      expect(taskOpen('task-1'), findsOneWidget);

      _task(server, 'task-1')['title'] = 'Renamed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);

      expect(_title(tester), 'Renamed on the web');
      expect(_boardReads(server), 0);
    });

    testBothLayouts('from a link, does too', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      _task(server, 'task-1')['title'] = 'Renamed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_title(tester), 'Renamed on the web');
      expect(_boardReads(server), 0);
    });

    testBothLayouts('keeps a title being typed', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      final field = find.byKey(const ValueKey('task-title'));
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'Being typed');
      _task(server, 'task-1')['title'] = 'Renamed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_title(tester), 'Being typed');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(_task(server, 'task-1')['title'], 'Being typed');
    });

    testBothLayouts('holds back the read while an edit is being saved', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openAlone(tester, server, size);
      final gate = server.hold('api/task/title/task-1');
      app.container.read(taskEditsProvider('task-1')).setTitle('Saving this');
      await tester.pump();
      final reads = _taskReads(server, 'task-1');
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), reads);
      expect(app.container.read(taskQuery('task-1')).requireValue.title, 'Saving this');
      gate.release();
      await _within5Seconds(tester);
      expect(_taskReads(server, 'task-1'), greaterThan(reads));
      expect(app.container.read(taskQuery('task-1')).requireValue.title, 'Saving this');
    });

    testBothLayouts('shows a comment made elsewhere', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
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

    testBothLayouts('reads its labels and links as they change', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
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
      expect(_boardReads(server), 0);
    });

    testBothLayouts('reads its list again when a subtask on it changes', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      final reads = server.requestsTo('api/task-relation/task-1').length;
      _task(server, 'task-2')['status'] = 'done';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-2'});
      await _within5Seconds(tester);
      expect(server.requestsTo('api/task-relation/task-1').length, reads + 1);
    });

    testBothLayouts('reads nothing of itself for a task that has nothing to do with it', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      final requests = server.requests.length;
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-5'});
      server.emit(_socket, 'TASKS_REORDERED', {
        'tasks': [
          {'id': 'task-5', 'position': 1, 'status': 'done'},
        ],
      });
      server.emit(_socket, 'TASK_CREATED', {'taskId': 'task-6'});
      await _within5Seconds(tester);
      expect(server.requests, hasLength(requests));
    });

    testBothLayouts('shows what a change to the project brings, without reading a board', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      final columns = server.requestsTo('api/column/${FakeKaneo.projectId}').length;
      final projects = server.requestsTo('api/project', method: 'GET').length;
      server.emit(_socket, 'PROJECT_UPDATED', {'projectId': FakeKaneo.projectId});
      await _within5Seconds(tester);
      expect(
        server.requestsTo('api/project', method: 'GET').length,
        greaterThan(projects),
        reason: "The bar shows the project's name.",
      );
      expect(server.requestsTo('api/column/${FakeKaneo.projectId}').length, greaterThan(columns));
      expect(_boardReads(server), 0);
    });

    testBothLayouts('stays as it was when deleted elsewhere, as it does over a board', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      final title = _title(tester);
      final requests = server.requests.length;
      server.tasks.removeWhere((t) => t['id'] == 'task-1');
      server.emit(_socket, 'TASK_DELETED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_title(tester), title);
      expect(server.requests, hasLength(requests));
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('moves with its task to the socket of another project', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      expect(server.openSockets(_socket), hasLength(1));
      _task(server, 'task-1')['projectId'] = FakeKaneo.secondProjectId;
      server.emit(_socket, 'TASK_MOVED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(server.openSockets(_socket), isEmpty);
      expect(server.openSockets(_otherSocket), hasLength(1));

      _task(server, 'task-1')['title'] = 'Renamed over there';
      server.emit(_otherSocket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_title(tester), 'Renamed over there');
    });
  });

  group('after time without a socket', () {
    testBothLayouts('it comes back by itself and the task catches up', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      server.unreachable = true;
      server.dropSockets();
      _task(server, 'task-1')['title'] = 'Changed while offline';
      await tester.pump(const Duration(seconds: 30));
      expect(_title(tester), isNot('Changed while offline'));

      server.unreachable = false;
      await tester.pump(RealtimeConnection.maxRetryDelay);
      await tester.pump();
      await _within5Seconds(tester);
      expect(server.openSockets(_socket), hasLength(1));
      expect(_title(tester), 'Changed while offline');
      expect(_boardReads(server), 0);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('the project alone losing its socket is noticed too', (tester, size) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      final reads = _taskReads(server, 'task-1');
      server.dropSockets(path: _socket);
      _task(server, 'task-1')['title'] = 'Changed meanwhile';
      await tester.pump(RealtimeConnection.maxRetryDelay);
      await tester.pump();
      await _within5Seconds(tester);
      expect(server.openSockets(_socket), hasLength(1));
      expect(_taskReads(server, 'task-1'), greaterThan(reads));
      expect(_title(tester), 'Changed meanwhile');
    });

    testBothLayouts('a server that refuses sockets leaves the task working', (tester, size) async {
      final server = FakeKaneo()..refuseSockets = true;
      await _openAlone(tester, server, size);
      await tester.pump(const Duration(minutes: 1));
      expect(find.byKey(const ValueKey('task-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('the app in the background gives it up, and catches up back in front', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _openAlone(tester, server, size);
      await _lifecycle(tester, const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(server.openSockets(_socket), isEmpty);
      _task(server, 'task-1')['title'] = 'Changed in the background';
      await tester.pump(const Duration(minutes: 1));
      await _lifecycle(tester, const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await _within5Seconds(tester);
      expect(server.openSockets(_socket), hasLength(1));
      expect(_title(tester), 'Changed in the background');
    });
  });

  group('one socket for a project', () {
    testBothLayouts('only once the task says which project, and gone on leaving it', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final gate = server.hold('api/task/task-1');
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        settle: false,
        location: AppRoutes.task('task-1'),
      );
      await tester.pump();
      expect(server.openSockets(_socket), isEmpty, reason: 'No telling which project yet.');
      gate.release();
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), hasLength(1));

      app.container.read(routerProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), isEmpty);
      expect(server.openSockets(FakeKaneo.userSocket), hasLength(1));
    });

    testBothLayouts('a task that fails to load has none', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/task-1', status: 500);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
      );
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      expect(server.openSockets(_socket), isEmpty);
    });

    testBothLayouts('a task over its board uses the board\'s', (tester, size) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      final socket = server.openSockets(_socket).single;
      final card = find.byKey(const ValueKey('board-card-task-1'));
      openTask(tester.element(card), 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      expect(taskOpen('task-1'), findsOneWidget);
      expect(server.openSockets(_socket), [socket]);
      expect(server.sockets.where((s) => s.path == _socket), hasLength(1), reason: 'Not even once');

      // One read per change, not one for each who is listening.
      final reads = _taskReads(server, 'task-1');
      _task(server, 'task-1')['title'] = 'Renamed on the web';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_title(tester), 'Renamed on the web');
      expect(
        _taskReads(server, 'task-1'),
        reads + 2,
        reason: 'One for the card, one for the task.',
      );

      await Navigator.of(tester.element(taskOpen('task-1'))).maybePop();
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), [socket], reason: 'The board is still open.');
      expect(tester.takeException(), isNull);

      app.container.read(routerProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), isEmpty);
    });

    testBothLayouts('two tasks of a project share it', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openAlone(tester, server, size);
      final socket = server.openSockets(_socket).single;
      app.container.read(routerProvider).push(AppRoutes.task('task-3'));
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), [socket]);

      // The one that's covered keeps up as well, for when it shows again.
      _task(server, 'task-1')['title'] = 'Renamed under the page';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(_title(tester), 'Renamed under the page');
      expect(server.openSockets(_socket), [socket]);
    });

    testBothLayouts('a board opened from the task uses the same, and leaves it behind', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openAlone(tester, server, size);
      final socket = server.openSockets(_socket).single;
      final router = app.container.read(routerProvider);

      router.push(AppRoutes.board(FakeKaneo.projectId));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('board-card-task-3')), findsOneWidget);
      expect(server.openSockets(_socket), [socket]);

      // The board keeps up from the socket that was already there.
      _task(server, 'task-3')['title'] = 'Renamed for the board';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-3'});
      await _within5Seconds(tester);
      expect(find.text('Renamed for the board'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), [socket], reason: 'The task is still open.');

      // And the task carries on without it, however the board's page left things.
      final boardReads = _boardReads(server);
      _task(server, 'task-1')['title'] = 'Renamed after the board';
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      await _within5Seconds(tester);
      expect(_title(tester), 'Renamed after the board');
      expect(_boardReads(server), boardReads, reason: 'Nobody is looking at the board any more.');

      router.go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(server.openSockets(_socket), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('a board that closes while a read is on its way is no trouble', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openAlone(tester, server, size);
      final router = app.container.read(routerProvider);
      router.push(AppRoutes.board(FakeKaneo.projectId));
      await tester.pumpAndSettle();

      final gate = server.hold('api/task/task-3');
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-1'});
      server.emit(_socket, 'TASK_UPDATED', {'taskId': 'task-3'});
      await tester.pump(const Duration(seconds: 1));
      router.pop();
      await tester.pumpAndSettle();
      _task(server, 'task-1')['title'] = 'Read after the board went';
      gate.release();
      await _within5Seconds(tester);
      expect(tester.takeException(), isNull);
      expect(_title(tester), 'Read after the board went');
    });
  });
}
