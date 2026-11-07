import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../../support/test_app.dart';

const _api = 'api/search';
const _lookup = 'api/task/by-ticket-id/';
const _field = ValueKey('search-field');
const _taskTitle = 'Rocket fuel';
const _projectName = 'Rocket launch';
const _commentPreview = 'Talk about the rocket with @Ann';

/// Something of each kind for `rocket`, and an activity entry for that new task on top.
FakeKaneo _server() {
  final server = FakeKaneo();
  server.addProject(id: 'project-rocket', name: _projectName, slug: 'RKT');
  server.addTask(id: 'task-rocket', projectId: 'project-rocket', title: _taskTitle);
  server.addComment(
    'task-2',
    'Talk about the **rocket** with <kaneo-mention user-id="u" label="Ann">@Ann</kaneo-mention>',
  );
  return server;
}

Future<TestApp> _open(WidgetTester tester, FakeKaneo server, Size size) =>
    pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.search);

void _go(TestApp app, String location) => app.container.read(routerProvider).go(location);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_field)).controller!.text;

/// Types [text], and waits for the pause that starts the search.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_field), text);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _search(WidgetTester tester, String text) async {
  await _type(tester, text);
  await tester.pumpAndSettle();
}

/// Lets requests that aren't held through, without waiting for anything else to finish.
Future<void> _letRequestsThrough(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('finding things', () {
    testBothLayouts('asks for something to look for first', (tester, size) async {
      final server = _server();
      final app = await _open(tester, server, size);
      expect(find.text(app.i18n.t('mobile:search.empty.title')), findsOneWidget);
      expect(server.requestsTo(_api), isEmpty);
    });

    testBothLayouts('finds tasks, projects and comments, under their kinds', (tester, size) async {
      final app = await _open(tester, _server(), size);
      await _search(tester, 'rocket');

      expect(inPage(find.text(_taskTitle)), findsOneWidget);
      expect(inPage(find.text('RKT-1')), findsWidgets);
      expect(inPage(find.text(_projectName)), findsWidgets);
      expect(inPage(find.text('RKT')), findsOneWidget);
      expect(inPage(find.text(_commentPreview)), findsOneWidget);
      for (final kind in ['tasks', 'projects', 'comments']) {
        expect(inPage(find.text(app.i18n.t('mobile:search.kinds.$kind'))), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('leaves out what it is not looking for', (tester, size) async {
      final server = _server();
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      final answer = server.requestsTo(_api).single;
      expect(answer.query['type'], 'all');
      expect(answer.query['workspaceId'], FakeKaneo.workspaceId);
      expect(inPage(find.text('created on $_taskTitle')), findsNothing);
      expect(inPage(find.text(app.i18n.t('mobile:search.kinds.activity'))), findsNothing);
    });

    testBothLayouts('leaving out everything found is no results', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      await _search(tester, 'test workspace');
      expect(
        find.text(app.i18n.t('mobile:search.noResults', {'query': 'test workspace'})),
        findsOneWidget,
      );
    });

    testBothLayouts('a comment shows who wrote it and when', (tester, size) async {
      final app = await pumpKaneoApp(
        tester,
        server: _server(),
        size: size,
        location: AppRoutes.search,
        overrides: [nowProvider.overrideWithValue(() => DateTime.utc(2026, 11, 6, 15))],
      );
      await _search(tester, 'rocket');
      final when = app.i18n.t('mobile:time.hoursAgo', {'count': 3});
      expect(
        inPage(
          find.text(app.i18n.t('mobile:search.commentMeta', {'name': 'Test User', 'when': when})),
        ),
        findsOneWidget,
      );
    });

    testWidgets('stays a reading column on a wide window', (tester) async {
      await _open(tester, _server(), wideSize);
      await _search(tester, 'rocket');
      expect(tester.getSize(inPage(find.byType(ListView))).width, contentMaxWidth);
    });

    testWidgets('keeps the search when the window crosses the breakpoint', (tester) async {
      await _open(tester, _server(), wideSize);
      await _search(tester, 'rocket');

      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'rocket');
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
    });
  });

  group('when it searches', () {
    testBothLayouts('typing waits for a pause', (tester, size) async {
      final server = _server();
      await _open(tester, server, size);
      for (final text in ['r', 'ro', 'roc']) {
        await tester.enterText(find.byKey(_field), text);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(server.requestsTo(_api), isEmpty);

      await _search(tester, 'rocket');
      expect(server.requestsTo(_api).single.query['q'], 'rocket');
    });

    testBothLayouts('the search key does not wait, or search twice', (tester, size) async {
      final server = _server();
      await _open(tester, server, size);
      await tester.enterText(find.byKey(_field), 'rocket');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _letRequestsThrough(tester); // Shorter than the pause.
      expect(server.requestsTo(_api).single.query['q'], 'rocket');

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(server.requestsTo(_api), hasLength(1));
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
    });

    testBothLayouts('spaces around the words change nothing', (tester, size) async {
      final server = _server();
      await _open(tester, server, size);
      await _search(tester, '  rocket ');
      await _search(tester, 'rocket');
      expect(server.requestsTo(_api).single.query['q'], 'rocket');
    });

    testBothLayouts('only spaces are nothing to search for', (tester, size) async {
      final server = _server();
      final app = await _open(tester, server, size);
      await _search(tester, '   ');
      expect(server.requestsTo(_api), isEmpty);
      expect(find.text(app.i18n.t('mobile:search.empty.title')), findsOneWidget);
    });

    testBothLayouts('waits for an input method to finish composing', (tester, size) async {
      final server = _server();
      server.addTask(title: '火箭燃料');
      await _open(tester, server, size);
      await tester.showKeyboard(find.byKey(_field));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'huojian',
          selection: TextSelection.collapsed(offset: 7),
          composing: TextRange(start: 0, end: 7),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(server.requestsTo(_api), isEmpty);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '火箭', selection: TextSelection.collapsed(offset: 2)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(server.requestsTo(_api).single.query['q'], '火箭');
      expect(inPage(find.text('火箭燃料')), findsOneWidget);
    });

    testBothLayouts('a slow answer to an older search does not replace a newer one', (
      tester,
      size,
    ) async {
      final server = _server();
      await _open(tester, server, size);
      final gate = server.hold(_api);
      await _type(tester, 'rocket');
      await _type(tester, 'board');
      await _letRequestsThrough(tester);
      expect(inPage(find.byType(CircularProgressIndicator)), findsOneWidget);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text('Review the board layout')), findsOneWidget);
      expect(inPage(find.text(_taskTitle)), findsNothing);
    });

    testBothLayouts('looking for something else clears the old results', (tester, size) async {
      final server = _server();
      await _open(tester, server, size);
      await _search(tester, 'rocket');
      final gate = server.hold(_api);
      await _type(tester, 'board');
      await _letRequestsThrough(tester);
      expect(inPage(find.text(_taskTitle)), findsNothing);
      expect(inPage(find.byType(CircularProgressIndicator)), findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
    });
  });

  group('opening a result', () {
    testBothLayouts('a task opens', (tester, size) async {
      await _open(tester, _server(), size);
      await _search(tester, 'rocket');
      await tester.tap(inPage(find.text(_taskTitle)));
      await tester.pumpAndSettle();
      expect(taskOpen('task-rocket'), findsOneWidget);
    });

    testBothLayouts('a project opens its board', (tester, size) async {
      final app = await _open(tester, _server(), size);
      await _search(tester, 'rocket');
      await tester.tap(inPage(find.text('RKT')));
      await tester.pumpAndSettle();
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.board('project-rocket'));
    });

    testBothLayouts('a comment opens the task it is on', (tester, size) async {
      final server = _server();
      await _open(tester, server, size);
      await _search(tester, 'rocket');
      await tester.tap(inPage(find.text(_commentPreview)));
      await tester.pumpAndSettle();
      expect(taskOpen('task-2'), findsOneWidget);

      final lookup = server.requestsTo(_lookup).single;
      expect(Uri.decodeComponent(lookup.path), contains('DEMO-2'));
      expect(lookup.query['workspaceId'], FakeKaneo.workspaceId);
    });

    testBothLayouts('tapping a comment twice while it looks up opens one task', (
      tester,
      size,
    ) async {
      final server = _server();
      await _open(tester, server, size);
      await _search(tester, 'rocket');
      final gate = server.hold(_lookup);
      await tester.tap(inPage(find.text(_commentPreview)));
      await tester.pump();
      await tester.tap(inPage(find.text(_commentPreview)));
      await tester.pump();
      gate.release();
      await tester.pumpAndSettle();
      expect(server.requestsTo(_lookup), hasLength(1));
      expect(taskOpen('task-2'), findsOneWidget);
    });

    testBothLayouts('when the task of a comment is gone it says why and stays', (
      tester,
      size,
    ) async {
      final server = _server();
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      server.failNext(_lookup, status: 404, body: {'message': 'The task is gone'});
      await tester.tap(inPage(find.text(_commentPreview)));
      await tester.pumpAndSettle();
      expect(find.text('The task is gone'), findsOneWidget);
      expect(taskOpen('task-2'), findsNothing);
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.search);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.tap(inPage(find.text(_commentPreview)));
      await tester.pumpAndSettle();
      expect(taskOpen('task-2'), findsOneWidget);
    });

    testBothLayouts('a comment with no ticket id opens its project', (tester, size) async {
      final server = FakeKaneo();
      server.on(
        _api,
        (_) => FakeResponse(200, {
          'results': [
            {
              'id': 'comment-1',
              'type': 'comment',
              'title': 'Comment on a task',
              'content': 'No ticket here',
              'projectId': FakeKaneo.projectId,
            },
          ],
          'totalCount': 1,
          'searchQuery': 'ticket',
        }),
      );
      final app = await _open(tester, server, size);
      await _search(tester, 'ticket');
      await tester.tap(inPage(find.text('No ticket here')));
      await tester.pumpAndSettle();
      expect(
        app.container.read(routerProvider).state.uri.path,
        AppRoutes.board(FakeKaneo.projectId),
      );
      expect(server.requestsTo(_lookup), isEmpty);
    });

    testBothLayouts('closing what opened looks again, with the results still there', (
      tester,
      size,
    ) async {
      final server = _server();
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      await tester.tap(inPage(find.text(_taskTitle)));
      await tester.pumpAndSettle();

      server.addTask(title: 'Rocket nose');
      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'rocket');
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
      expect(inPage(find.text('Rocket nose')), findsOneWidget);
      expect(server.requestsTo(_api), hasLength(2));
    });
  });

  group('coming back to the page', () {
    testBothLayouts('shows the last search at once, then what is new', (tester, size) async {
      final server = _server();
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      _go(app, AppRoutes.home);
      await tester.pumpAndSettle();

      server.addTask(title: 'Rocket nose');
      final gate = server.hold(_api);
      _go(app, AppRoutes.search);
      await tester.pump();
      expect(_fieldText(tester), 'rocket');
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _letRequestsThrough(tester);
      expect(inPage(find.text('Rocket nose')), findsNothing);
      expect(server.requestsTo(_api), hasLength(2));

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text('Rocket nose')), findsOneWidget);
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
    });

    testBothLayouts('keeps the results when looking again fails', (tester, size) async {
      final server = _server();
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      _go(app, AppRoutes.home);
      await tester.pumpAndSettle();

      server.fail(_api, status: 500);
      _go(app, AppRoutes.search);
      await tester.pumpAndSettle();
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsNothing);
    });

    testBothLayouts('clearing the search forgets it', (tester, size) async {
      final server = _server();
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      await tester.tap(find.byTooltip(app.i18n.t('mobile:search.clear')));
      await tester.pumpAndSettle();
      expect(_fieldText(tester), isEmpty);
      expect(find.text(app.i18n.t('mobile:search.empty.title')), findsOneWidget);
      expect(find.byTooltip(app.i18n.t('mobile:search.clear')), findsNothing);

      _go(app, AppRoutes.home);
      await tester.pumpAndSettle();
      _go(app, AppRoutes.search);
      await tester.pumpAndSettle();
      expect(_fieldText(tester), isEmpty);
      expect(server.requestsTo(_api), hasLength(1));
    });

    testBothLayouts('each workspace has its own last search', (tester, size) async {
      final server = _server();
      server.workspaces.add({...server.workspaces.first, 'id': 'ws-other', 'name': 'Other'});
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');

      await app.container.read(selectedWorkspaceIdProvider.notifier).select('ws-other');
      await tester.pumpAndSettle();
      expect(_fieldText(tester), isEmpty);
      expect(inPage(find.text(_taskTitle)), findsNothing);

      await app.container.read(selectedWorkspaceIdProvider.notifier).select(FakeKaneo.workspaceId);
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'rocket');
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
    });
  });

  group('the other states', () {
    testBothLayouts('waiting for the answer', (tester, size) async {
      final server = _server();
      await _open(tester, server, size);
      final gate = server.hold(_api);
      await _type(tester, 'rocket');
      await _letRequestsThrough(tester);
      expect(inPage(find.byType(CircularProgressIndicator)), findsOneWidget);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
    });

    testBothLayouts('a failure says so, and retrying gets the results', (tester, size) async {
      final server = _server()..failNext(_api, status: 500);
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);

      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(inPage(find.text(_taskTitle)), findsOneWidget);
    });

    testBothLayouts('no permission says so, with nothing to retry', (tester, size) async {
      final server = _server()..fail(_api, status: 403);
      final app = await _open(tester, server, size);
      await _search(tester, 'rocket');
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
    });

    testBothLayouts('nothing found says what was looked for', (tester, size) async {
      final app = await _open(tester, _server(), size);
      await _search(tester, 'nothing like this');
      expect(
        find.text(app.i18n.t('mobile:search.noResults', {'query': 'nothing like this'})),
        findsOneWidget,
      );
    });
  });
}
