import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_data.dart';
import 'package:kaneo_app/features/board/board_page.dart';
import 'package:kaneo_app/features/markdown/markdown_field.dart';
import 'package:kaneo_app/features/task/task_actions.dart';
import 'package:kaneo_app/features/task/task_description.dart';
import 'package:kaneo_app/features/task/task_properties.dart';
import 'package:kaneo_app/features/task/task_relations.dart';

import '../../support/test_app.dart';

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const _link =
    '${FakeKaneo.serverUrl}/dashboard/workspace/${FakeKaneo.workspaceId}'
    '/project/${FakeKaneo.projectId}/task/task-1';

// The last, because a task can be open on top of another.
final _copyLinks = find.byKey(const ValueKey('task-copy-link'));
final _mores = find.byKey(const ValueKey('task-more'));
final _copyLink = _copyLinks.last;
final _more = _mores.last;

/// The one in the picker. On a wide window, the sidebar lists the projects too.
final _secondProject = find.text('Second project').last;
Finder _card(String id) => find.byKey(ValueKey('board-card-$id'));
Finder _subtask(String id) => find.byKey(ValueKey('task-subtask-$id'));

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<TestApp> _openTask(
  WidgetTester tester,
  Size size, {
  FakeKaneo? server,
  String id = 'task-1',
}) => pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task(id));

/// A card opened from its board, as a panel on a wide window and a page on a narrow one.
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
  await _press(tester, _card(id));
  expect(taskOpen(id), findsOneWidget);
  return app;
}

Future<void> _choose(WidgetTester tester, TestApp app, String item) async {
  await _press(tester, _more);
  await _press(tester, find.text(app.i18n.t('mobile:taskDetail.menu.$item')));
}

Future<void> _confirmDelete(WidgetTester tester, TestApp app) async {
  await _choose(tester, app, 'delete');
  await _press(tester, find.text(app.i18n.t('mobile:common.delete')));
}

/// Leaves the description's text box open, with [text] not yet saved.
Future<void> _typeDescription(WidgetTester tester, String text) async {
  await _press(tester, find.byType(TaskDescription));
  await tester.enterText(
    find.descendant(of: find.byType(MarkdownField), matching: find.byType(TextField)).first,
    text,
  );
  await tester.pump();
}

String _location(TestApp app) => app.container.read(routerProvider).state.uri.path;

List<String> _boardCards(TestApp app, String projectId) => [
  for (final task in boardTasks(app.container.read(boardQuery(projectId)).requireValue)) task.id,
];

/// What the app puts on the clipboard.
List<String> _watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// What the app hands to the system's share sheet. [fail] makes the system refuse.
List<Map<Object?, Object?>> _watchShares(WidgetTester tester, {bool fail = false}) {
  final shared = <Map<Object?, Object?>>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_shareChannel, (call) async {
    if (fail) throw PlatformException(code: 'share', message: 'No share sheet');
    shared.add(call.arguments as Map<Object?, Object?>);
    return 'dev.fluttercommunity.plus/share/success';
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_shareChannel, null));
  return shared;
}

void main() {
  group('the menu and the link', () {
    final task = Task(id: 't', projectId: 'p', workspaceId: 'w', title: 'A task', status: 'to-do');
    const everything = WorkspaceCapabilities(
      createTasks: true,
      updateTasks: true,
      deleteTasks: true,
    );

    List<TaskMenuItem> items({
      WorkspaceCapabilities? can = everything,
      bool hasLink = true,
      bool isSubtask = false,
      bool hasDestination = true,
    }) => taskMenuItems(
      can: can,
      hasLink: hasLink,
      isSubtask: isSubtask,
      hasDestination: hasDestination,
    );

    test('the link is the one the web app has for the task', () {
      expect(
        taskWebLink('https://kaneo.example.com', task),
        'https://kaneo.example.com/dashboard/workspace/w/project/p/task/t',
      );
      expect(
        taskWebLink('https://kaneo.example.com/', task),
        'https://kaneo.example.com/dashboard/workspace/w/project/p/task/t',
      );
    });

    test('there is no link without a server or a workspace', () {
      expect(taskWebLink(null, task), isNull);
      expect(
        taskWebLink(
          'https://kaneo.example.com',
          Task(id: 't', projectId: 'p', title: 'A task', status: 'to-do'),
        ),
        isNull,
      );
    });

    test('sharing says which task it is, even before its project has loaded', () {
      expect(taskShareText('DEMO-1', 'A task', 'https://l'), 'DEMO-1 A task\nhttps://l');
      expect(taskShareText('', 'A task', 'https://l'), 'A task\nhttps://l');
    });

    test('a task moves to another project that is still in use', () {
      const here = Project(id: 'p', workspaceId: 'w', slug: 'P', name: 'Here');
      const there = Project(id: 'q', workspaceId: 'w', slug: 'Q', name: 'There');
      const old = Project(id: 'r', workspaceId: 'w', slug: 'R', name: 'Old', archivedAt: 'then');
      expect(taskMoveDestinations(const [here, there, old], task), [there]);
    });

    test('someone allowed everything is offered everything', () {
      expect(items(), TaskMenuItem.values);
    });

    test('permissions that have not loaded count as allowed', () {
      expect(items(can: null), TaskMenuItem.values);
    });

    test('each action needs its own permission', () {
      const noCreate = WorkspaceCapabilities(updateTasks: true, deleteTasks: true);
      const noUpdate = WorkspaceCapabilities(createTasks: true, deleteTasks: true);
      const noDelete = WorkspaceCapabilities(createTasks: true, updateTasks: true);
      expect(items(can: noCreate), isNot(contains(TaskMenuItem.duplicate)));
      expect(items(can: noUpdate), isNot(contains(TaskMenuItem.move)));
      expect(items(can: noDelete), isNot(contains(TaskMenuItem.delete)));
      expect(items(can: const WorkspaceCapabilities()), [TaskMenuItem.share]);
    });

    test('copying a subtask also takes permission to change tasks', () {
      const noUpdate = WorkspaceCapabilities(createTasks: true);
      expect(items(can: noUpdate), contains(TaskMenuItem.duplicate));
      expect(items(can: noUpdate, isSubtask: true), isNot(contains(TaskMenuItem.duplicate)));
    });

    test('moving takes somewhere to go, and sharing a link', () {
      expect(items(hasDestination: false), isNot(contains(TaskMenuItem.move)));
      expect(items(hasLink: false), isNot(contains(TaskMenuItem.share)));
    });
  });

  group('copying the link', () {
    testBothLayouts('puts it on the clipboard and says so', (tester, size) async {
      final copied = _watchClipboard(tester);
      final app = await _openTask(tester, size);
      await _press(tester, _copyLink);
      expect(copied, [_link]);
      expect(find.text(app.i18n.t('mobile:taskDetail.screen.linkCopied')), findsOneWidget);
    });

    testBothLayouts('follows the task to another project', (tester, size) async {
      final copied = _watchClipboard(tester);
      final app = await _openTask(tester, size);
      await _choose(tester, app, 'move');
      await _press(tester, _secondProject);
      await _press(tester, _copyLink);
      expect(copied.single, contains('/project/${FakeKaneo.secondProjectId}/task/task-1'));
    });
  });

  group('sharing', () {
    testBothLayouts('sends the ticket, the title and the link to the share sheet', (
      tester,
      size,
    ) async {
      final shared = _watchShares(tester);
      final app = await _openTask(tester, size);
      await _choose(tester, app, 'share');
      expect(shared.single['text'], 'DEMO-1 Set up the project\n$_link');
    });

    testBothLayouts('points the share sheet at the button', (tester, size) async {
      final shared = _watchShares(tester);
      final app = await _openTask(tester, size);
      final button = tester.getRect(_more);
      await _choose(tester, app, 'share');
      expect(shared.single['originX'], button.left);
      expect(shared.single['originY'], button.top);
      expect(shared.single['originWidth'], button.width);
      expect(shared.single['originHeight'], button.height);
    });

    testBothLayouts('says so when the system refuses', (tester, size) async {
      _watchShares(tester, fail: true);
      final app = await _openTask(tester, size);
      await _choose(tester, app, 'share');
      expect(find.text(app.i18n.t('mobile:common.somethingWrong')), findsOneWidget);
    });
  });

  group('copying the task', () {
    testBothLayouts('opens the copy, and the board has it too', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _choose(tester, app, 'duplicate');

      final copy = server.tasks.last;
      expect(server.requestsTo('api/task/duplicate/task-1', method: 'POST'), hasLength(1));
      expect(copy['id'], isNot('task-1'));
      expect(copy['title'], 'Set up the project');
      expect(taskOpen(copy['id'] as String), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.duplicated')), findsOneWidget);
      expect(_boardCards(app, FakeKaneo.projectId), containsAll(['task-1', copy['id']]));
    });

    testBothLayouts('a subtask shows up in the list of its open parent', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openTask(tester, size, server: server);
      await _press(tester, _subtask('task-2'));
      await _choose(tester, app, 'duplicate');

      final subtasks = subtasksOf(
        'task-1',
        app.container.read(taskRelationsQuery('task-1')).requireValue,
      );
      expect(subtasks.map((t) => t.id), ['task-2', server.tasks.last['id']]);
    });

    testBothLayouts('text still being typed goes along', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openTask(tester, size, server: server);
      await _typeDescription(tester, 'Typed just now');
      await _choose(tester, app, 'duplicate');
      expect(server.tasks.last['description'], 'Typed just now');
    });

    testBothLayouts('stays on the task and says why when it fails', (tester, size) async {
      final server = FakeKaneo()
        ..failNext(
          'api/task/duplicate/task-1',
          status: 500,
          body: {'message': 'Could not copy', 'code': 'ERROR'},
        );
      final app = await _openFromBoard(tester, size, server: server);
      final before = server.tasks.length;
      await _choose(tester, app, 'duplicate');
      expect(server.tasks, hasLength(before));
      expect(taskOpen('task-1'), findsOneWidget);
      expect(find.text('Could not copy'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.duplicated')), findsNothing);
    });

    testBothLayouts('asking twice while it is under way copies once', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold('api/task/duplicate/task-1', method: 'POST');
      final app = await _openTask(tester, size, server: server);
      await _choose(tester, app, 'duplicate');
      expect(tester.widget<IconButton>(_more).onPressed, isNull);
      gate.release();
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/task/duplicate/task-1', method: 'POST'), hasLength(1));
      expect(tester.widget<IconButton>(_more).onPressed, isNotNull);
    });
  });

  group('moving the task', () {
    testBothLayouts('offers the other projects, and not this one or an archived one', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.addProject(id: 'old', name: 'Old project', slug: 'OLD')['archivedAt'] = '2026-01-01';
      server.addProject(id: 'third', name: 'Third project', slug: 'THD');
      final app = await _openTask(tester, size, server: server);
      await _choose(tester, app, 'move');
      // Only the picker shows these, as the sidebar lists the projects by name.
      expect(find.text('SEC'), findsOneWidget);
      expect(find.text('THD'), findsOneWidget);
      expect(find.text('OLD'), findsNothing);
      expect(find.text('DEMO'), findsNothing);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.moveTitle')), findsWidgets);
    });

    testBothLayouts('shows the new project and number, and leaves the board', (tester, size) async {
      final server = FakeKaneo();
      server.addTask(projectId: FakeKaneo.secondProjectId, title: 'Already there');
      final app = await _openFromBoard(tester, size, server: server);
      await _choose(tester, app, 'move');
      await _press(tester, _secondProject);

      final request = server.requestsTo('api/task/move/task-1', method: 'PUT').single;
      expect((request.body as Map)['destinationProjectId'], FakeKaneo.secondProjectId);
      expect(
        server.tasks.firstWhere((t) => t['id'] == 'task-1')['projectId'],
        FakeKaneo.secondProjectId,
      );
      final bar = find.descendant(of: taskOpen('task-1'), matching: find.byType(AppBar));
      expect(find.descendant(of: bar, matching: find.text('Second project')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('SEC-2')), findsOneWidget);
      expect(taskOpen('task-1'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.moved')), findsOneWidget);
      expect(_boardCards(app, FakeKaneo.projectId), isNot(contains('task-1')));
      expect(_card('task-1'), findsNothing);
    });

    testBothLayouts('goes to the first column where its own does not exist', (tester, size) async {
      final server = FakeKaneo();
      server.columns.add({
        'id': 'column-blocked',
        'projectId': FakeKaneo.projectId,
        'name': 'Blocked',
        'slug': 'blocked',
        'position': 9,
        'icon': null,
        'color': null,
        'isFinal': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
      });
      server.addTask(id: 'task-b', title: 'Stuck', status: 'blocked');
      final app = await _openTask(tester, size, server: server, id: 'task-b');
      final properties = find.byType(TaskProperties);
      expect(find.descendant(of: properties, matching: find.text('Blocked')), findsOneWidget);
      await _choose(tester, app, 'move');
      await _press(tester, _secondProject);
      expect(find.descendant(of: properties, matching: find.text('To Do')), findsOneWidget);
    });

    testBothLayouts('a board open on the other project gets the card', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openTask(tester, size, server: server);
      // Keeps the destination's board open, as it is when it lies below the task.
      final keepOpen = app.container.listen(boardQuery(FakeKaneo.secondProjectId), (_, _) {});
      addTearDown(keepOpen.close);
      await tester.pumpAndSettle();
      expect(_boardCards(app, FakeKaneo.secondProjectId), isEmpty);
      await _choose(tester, app, 'move');
      await _press(tester, _secondProject);
      expect(_boardCards(app, FakeKaneo.secondProjectId), ['task-1']);
    });

    testBothLayouts('a subtask shows its new number in the list of its open parent', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.addTask(projectId: FakeKaneo.secondProjectId, title: 'Already there');
      final app = await _openTask(tester, size, server: server);
      await _press(tester, _subtask('task-2'));
      await _choose(tester, app, 'move');
      await _press(tester, _secondProject);

      final subtask = subtasksOf(
        'task-1',
        app.container.read(taskRelationsQuery('task-1')).requireValue,
      ).single;
      expect(subtask.projectId, FakeKaneo.secondProjectId);
      expect(subtask.number, 2);
    });

    testBothLayouts('changes nothing and says why when it fails', (tester, size) async {
      final server = FakeKaneo()
        ..failNext(
          'api/task/move/task-1',
          status: 403,
          body: {'message': 'No access to that project', 'code': 'FORBIDDEN'},
        );
      final app = await _openFromBoard(tester, size, server: server);
      await _choose(tester, app, 'move');
      await _press(tester, _secondProject);
      expect(find.text('No access to that project'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.moved')), findsNothing);
      expect(_boardCards(app, FakeKaneo.projectId), contains('task-1'));
      final bar = find.descendant(of: taskOpen('task-1'), matching: find.byType(AppBar));
      expect(find.descendant(of: bar, matching: find.text('DEMO-1')), findsOneWidget);
    });

    testBothLayouts('dismissing the choice moves nothing', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openTask(tester, size, server: server);
      await _choose(tester, app, 'move');
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/task/move/task-1'), isEmpty);
    });

    testBothLayouts('the lists below catch up', (tester, size) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.myTasks,
      );
      await _press(tester, find.text('Set up the project'));
      final assigned = server.requestsTo('api/task/assigned').length;
      await _choose(tester, app, 'move');
      await _press(tester, _secondProject);
      expect(server.requestsTo('api/task/assigned').length, greaterThan(assigned));
      final mine = app.container.read(assignedTasksQuery(FakeKaneo.workspaceId)).requireValue.tasks;
      expect(mine.firstWhere((t) => t.id == 'task-1').projectId, FakeKaneo.secondProjectId);
    });

    testBothLayouts('says so if it turns out there is nowhere to go', (tester, size) async {
      final server = FakeKaneo()..failNext('api/project', method: 'GET');
      server.projects.removeWhere((p) => p['id'] == FakeKaneo.secondProjectId);
      final app = await _openTask(tester, size, server: server);
      await _choose(tester, app, 'move');
      expect(find.text(app.i18n.t('app:shell.noProjects')), findsWidgets);
      expect(server.requestsTo('api/task/move/task-1'), isEmpty);
    });

    testBothLayouts('is not offered when there is nowhere to go', (tester, size) async {
      final server = FakeKaneo();
      server.projects.removeWhere((p) => p['id'] == FakeKaneo.secondProjectId);
      final app = await _openTask(tester, size, server: server);
      await _press(tester, _more);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.move')), findsNothing);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.delete')), findsOneWidget);
    });

    testBothLayouts('loads the projects if they have not arrived yet', (tester, size) async {
      final server = FakeKaneo()..failNext('api/project', method: 'GET', times: 1);
      final app = await _openTask(tester, size, server: server);
      await _choose(tester, app, 'move');
      expect(find.text('SEC'), findsOneWidget);
    });
  });

  group('deleting the task', () {
    testBothLayouts('asks first, and cancelling changes nothing', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _choose(tester, app, 'delete');
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.deleteTitle')), findsOneWidget);
      expect(
        find.text(
          app.i18n.t('mobile:taskDetail.menu.deleteMessage', {'title': 'Set up the project'}),
        ),
        findsOneWidget,
      );
      expect(server.requestsTo('api/task/task-1', method: 'DELETE'), isEmpty);

      await _press(tester, find.text(app.i18n.t('mobile:common.cancel')));
      expect(server.requestsTo('api/task/task-1', method: 'DELETE'), isEmpty);
      expect(taskOpen('task-1'), findsOneWidget);
    });

    testBothLayouts('comes back to the board without its card, as it was left', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final board = tester.state(find.byType(BoardPage, skipOffstage: false));
      await _confirmDelete(tester, app);

      expect(server.requestsTo('api/task/task-1', method: 'DELETE'), hasLength(1));
      expect(server.tasks.where((t) => t['id'] == 'task-1'), isEmpty);
      expect(taskOpen('task-1'), findsNothing);
      expect(_location(app), AppRoutes.board(FakeKaneo.projectId));
      expect(find.byType(BoardPage), findsOneWidget);
      expect(_card('task-1'), findsNothing);
      expect(_card('task-3'), findsOneWidget);
      expect(tester.state(find.byType(BoardPage)), same(board));
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.deleted')), findsOneWidget);
    });

    testBothLayouts('comes back to a board opened from the home page, as it was left', (
      tester,
      size,
    ) async {
      final app = await pumpKaneoApp(tester, size: size);
      unawaited(app.container.read(routerProvider).push(AppRoutes.board(FakeKaneo.projectId)));
      await tester.pumpAndSettle();
      final board = tester.state(find.byType(BoardPage));
      await _press(tester, _card('task-1'));
      await _confirmDelete(tester, app);
      expect(taskOpen('task-1'), findsNothing);
      expect(tester.state(find.byType(BoardPage)), same(board));
    });

    testBothLayouts('from a link, goes to the board of the task', (tester, size) async {
      final server = FakeKaneo();
      final app = await _openTask(tester, size, server: server);
      await _confirmDelete(tester, app);
      expect(taskOpen('task-1'), findsNothing);
      expect(_location(app), AppRoutes.board(FakeKaneo.projectId));
      expect(find.byType(BoardPage), findsOneWidget);
      expect(_card('task-3'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.deleted')), findsOneWidget);
    });

    testBothLayouts('from another page, goes to the board of the task', (tester, size) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.myTasks,
      );
      await _press(tester, find.text('Set up the project'));
      await _confirmDelete(tester, app);
      expect(taskOpen('task-1'), findsNothing);
      expect(_location(app), AppRoutes.board(FakeKaneo.projectId));
      expect(find.byType(BoardPage), findsOneWidget);
    });

    testBothLayouts('of a task in another project, goes to that board', (tester, size) async {
      final server = FakeKaneo();
      server.addTask(id: 'elsewhere', projectId: FakeKaneo.secondProjectId, title: 'Elsewhere');
      final app = await _openTask(tester, size, server: server, id: 'elsewhere');
      await _confirmDelete(tester, app);
      expect(_location(app), AppRoutes.board(FakeKaneo.secondProjectId));
    });

    testBothLayouts('a subtask opened from its parent closes both, for the board', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      await _press(tester, _subtask('task-2'));
      await _confirmDelete(tester, app);
      expect(server.tasks.where((t) => t['id'] == 'task-2'), isEmpty);
      expect(taskOpen('task-2'), findsNothing);
      expect(taskOpen('task-1'), findsNothing);
      expect(_location(app), AppRoutes.board(FakeKaneo.projectId));
      expect(_card('task-1'), findsOneWidget);
    });

    testBothLayouts('after the person has left it, they stay where they went', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final gate = server.hold('api/task/task-2', method: 'DELETE');
      final app = await _openTask(tester, size, server: server);
      await _press(tester, _subtask('task-2'));
      await _confirmDelete(tester, app);
      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(taskOpen('task-2'), findsNothing);
      expect(_subtask('task-2'), findsOneWidget);

      gate.release();
      await tester.pumpAndSettle();
      expect(taskOpen('task-1'), findsOneWidget);
      expect(_subtask('task-2'), findsNothing);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.deleted')), findsOneWidget);
    });

    testBothLayouts('stays on the task and says why when it fails', (tester, size) async {
      final server = FakeKaneo()
        ..failNext(
          'api/task/task-1',
          method: 'DELETE',
          status: 403,
          body: {'message': 'Not allowed to delete', 'code': 'FORBIDDEN'},
        );
      final app = await _openFromBoard(tester, size, server: server);
      await _confirmDelete(tester, app);
      expect(find.text('Not allowed to delete'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.deleted')), findsNothing);
      expect(taskOpen('task-1'), findsOneWidget);
      expect(_boardCards(app, FakeKaneo.projectId), contains('task-1'));
    });

    testBothLayouts('is not remembered, so that it cannot show again from the cache', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _openFromBoard(tester, size, server: server);
      final cache = app.container.read(cacheStoreProvider);
      expect(cache.peek('task/task-1'), isNotNull);
      await _confirmDelete(tester, app);
      expect(cache.peek('task/task-1'), isNull);

      app.container.read(routerProvider).push(AppRoutes.task('task-1'));
      await tester.pumpAndSettle();
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      expect(find.text('Set up the project'), findsNothing);
    });

    testBothLayouts('text that could not be saved is dropped with it', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/description/task-1', method: 'PUT');
      final app = await _openTask(tester, size, server: server);
      await _typeDescription(tester, 'Never saved');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(app.i18n.t('app:description.notSaved')), findsOneWidget);

      await _choose(tester, app, 'delete');
      // Leaving the text box is one more try.
      final tries = server.requestsTo('api/task/description/task-1', method: 'PUT').length;
      await _press(tester, find.text(app.i18n.t('mobile:common.delete')));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/task/description/task-1', method: 'PUT'), hasLength(tries));
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.deleted')), findsOneWidget);
    });
  });

  group('without permission', () {
    testBothLayouts('someone who can only read can copy the link and share', (tester, size) async {
      final server = FakeKaneo();
      server.capabilities.updateAll((_, _) => false);
      final app = await _openTask(tester, size, server: server);
      expect(_copyLink, findsOneWidget);
      await _press(tester, _more);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.share')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.duplicate')), findsNothing);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.move')), findsNothing);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.delete')), findsNothing);
    });

    for (final (capability, item) in const [
      ('createTasks', 'duplicate'),
      ('updateTasks', 'move'),
      ('deleteTasks', 'delete'),
    ]) {
      testBothLayouts('without $capability there is no $item, and the rest stays', (
        tester,
        size,
      ) async {
        final server = FakeKaneo()..capabilities[capability] = false;
        final app = await _openTask(tester, size, server: server);
        await _press(tester, _more);
        for (final other in const ['share', 'duplicate', 'move', 'delete']) {
          expect(
            find.text(app.i18n.t('mobile:taskDetail.menu.$other')),
            other == item ? findsNothing : findsOneWidget,
            reason: other,
          );
        }
      });
    }

    testBothLayouts('a subtask cannot be copied without permission to change tasks', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..capabilities['updateTasks'] = false;
      final app = await _openTask(tester, size, server: server, id: 'task-2');
      await _press(tester, _more);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.duplicate')), findsNothing);
    });

    testBothLayouts('everything is offered until the permissions arrive', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold('capabilities');
      final app = await _openTask(tester, size, server: server);
      await _press(tester, _more);
      expect(find.text(app.i18n.t('mobile:taskDetail.menu.delete')), findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
    });
  });

  group('while there is no task', () {
    testBothLayouts('nothing is offered while it loads', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold('api/task/task-1');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
        settle: false,
      );
      await tester.pump();
      expect(_copyLinks, findsNothing);
      expect(_mores, findsNothing);
      gate.release();
      await tester.pumpAndSettle();
      expect(_copyLinks, findsOneWidget);
      expect(_mores, findsOneWidget);
    });

    testBothLayouts('nothing is offered when it fails to load', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/task-1');
      await _openTask(tester, size, server: server);
      expect(_copyLinks, findsNothing);
      expect(_mores, findsNothing);
    });
  });
}
