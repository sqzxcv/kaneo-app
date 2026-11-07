import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/home/home_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/test_app.dart';

const _otherWorkspace = 'ws-other';
const _otherProject = 'project-other';

/// A second workspace with a project, a task assigned to the user and something in the inbox.
FakeKaneo _twoWorkspaces() {
  final server = FakeKaneo();
  server.workspaces.add({...server.workspaces.first, 'id': _otherWorkspace, 'name': 'Other'});
  server.addProject(id: _otherProject, name: 'Other project', slug: 'OTH')['workspaceId'] =
      _otherWorkspace;
  final task = server.addTask(projectId: _otherProject, title: 'Other task');
  server.addNotification(title: 'Other notice', resourceId: task['id'] as String);
  return server;
}

/// A workspace with just these projects.
FakeKaneo _withProjects(List<String> names) {
  final server = FakeKaneo.empty();
  for (final (index, name) in names.indexed) {
    server.addProject(id: 'p$index', name: name, slug: 'P$index');
  }
  return server;
}

FakeKaneo _withArchived() {
  final server = FakeKaneo();
  server.addProject(id: 'old', name: 'Old project', slug: 'OLD')['archivedAt'] =
      '2026-01-01T00:00:00.000Z';
  return server;
}

/// The workspace name is on the sidebar in wide windows and in the home page's bar in narrow ones.
Future<void> _switchWorkspace(WidgetTester tester, {String from = 'Test Workspace'}) async {
  await tester.tap(find.text(from));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Other'));
  await tester.pumpAndSettle();
}

Future<void> _toggleArchived(WidgetTester tester, TestApp app, {bool shown = false}) async {
  final key = shown ? 'mobile:home.hideArchived' : 'mobile:home.showArchived';
  await tester.tap(find.text(app.i18n.t(key)));
  await tester.pumpAndSettle();
}

void _goToBackground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _returnToForeground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Finder _inProject(String projectId, Finder finder) =>
    find.descendant(of: find.byKey(homeProjectKey(projectId)), matching: finder);

void main() {
  group('the project list on a wide window', () {
    testWidgets('a single project is a card of the grid, not the whole width', (tester) async {
      await pumpKaneoApp(tester, server: _withProjects(['Only']), size: wideSize);
      final card = tester.getSize(find.byKey(homeProjectKey('p0')));
      // The web app's max-w-5xl, less px-10, in three columns with 12 between them.
      expect(card.width, moreOrLessEquals((1024 - 80 - 24) / 3, epsilon: 0.1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sits in three columns and goes on in the next row, like the web app', (
      tester,
    ) async {
      await pumpKaneoApp(tester, server: _withProjects(['A', 'B', 'C', 'D']), size: wideSize);
      final rects = [for (var i = 0; i < 4; i++) tester.getRect(find.byKey(homeProjectKey('p$i')))];
      expect(rects[1].top, rects[0].top);
      expect(rects[2].top, rects[0].top);
      expect(rects[1].left, moreOrLessEquals(rects[0].right + 12, epsilon: 0.1));
      expect(rects[2].left, moreOrLessEquals(rects[1].right + 12, epsilon: 0.1));
      expect(rects[3].left, rects[0].left);
      expect(rects[3].top, moreOrLessEquals(rects[0].bottom + 12, epsilon: 0.1));
    });

    testWidgets('stays centered at the web app\'s width', (tester) async {
      await pumpKaneoApp(
        tester,
        server: _withProjects(['A', 'B', 'C']),
        size: const Size(2560, 1440),
      );
      final first = tester.getRect(find.byKey(homeProjectKey('p0')));
      final last = tester.getRect(find.byKey(homeProjectKey('p2')));
      final page = tester.getRect(inPage(find.byType(ListView)));
      expect(last.right - first.left, lessThanOrEqualTo(1024 - 80));
      expect((first.left - page.left) - (page.right - last.right), moreOrLessEquals(0, epsilon: 3));
    });

    const columns = {
      'iPad Pro 13 upright': (Size(1024, 1366), 3),
      'iPad mini upright': (Size(744, 1133), 2),
      'the smallest wide window': (Size(600, 1000), 1),
    };
    columns.forEach((name, setup) {
      final (size, count) = setup;
      testWidgets('$name fits $count columns', (tester) async {
        final server = _withProjects(['A long project name for a small card', 'B', 'C', 'D']);
        await pumpKaneoApp(tester, server: server, size: size);
        final firstRow = [
          for (var i = 0; i < 4; i++) tester.getRect(find.byKey(homeProjectKey('p$i'))).top,
        ].where((top) => top == tester.getRect(find.byKey(homeProjectKey('p0'))).top);
        expect(firstRow, hasLength(count));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('the project list on a narrow window', () {
    testWidgets('is rows across the width, one below the other', (tester) async {
      await pumpKaneoApp(tester, server: _withProjects(['A', 'B']), size: narrowSize);
      final first = tester.getRect(find.byKey(homeProjectKey('p0')));
      final second = tester.getRect(find.byKey(homeProjectKey('p1')));
      expect(first.width, moreOrLessEquals(narrowSize.width - 32, epsilon: 2));
      expect(second.width, first.width);
      expect(second.top, greaterThanOrEqualTo(first.bottom));
    });

    testWidgets('says how far along a project is, or when it is due', (tester) async {
      final server = _withProjects(['Started', 'Empty']);
      server.addTask(projectId: 'p0', title: 'Open');
      server.addTask(projectId: 'p0', title: 'Finished', status: 'done');
      final app = await pumpKaneoApp(tester, server: server, size: narrowSize);
      expect(_inProject('p0', find.text('1 of 2')), findsOneWidget);
      expect(_inProject('p1', find.text(app.i18n.t('mobile:home.noTasks'))), findsOneWidget);

      server.on(
        'api/project',
        (request) => const FakeResponse(200, [
          {
            'id': 'p0',
            'workspaceId': FakeKaneo.workspaceId,
            'slug': 'P0',
            'name': 'Started',
            'statistics': {'completionPercentage': 50, 'totalTasks': 2, 'dueDate': '2026-03-09'},
          },
        ]),
      );
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(_inProject('p0', find.textContaining('Due Mar 9')), findsOneWidget);
    });

    testWidgets('fits on a phone on its side, and with a very long name', (tester) async {
      final server = _withProjects(['A very long project name ' * 10]);
      await pumpKaneoApp(tester, server: server, size: const Size(844, 390));
      expect(tester.takeException(), isNull);
    });
  });

  group('every project', () {
    testBothLayouts('shows its progress', (tester, size) async {
      final server = _withProjects(['Half']);
      server.addTask(projectId: 'p0', title: 'Open');
      server.addTask(projectId: 'p0', title: 'Finished', status: 'done');
      await pumpKaneoApp(tester, server: server, size: size);

      expect(_inProject('p0', find.text('Half')), findsOneWidget);
      expect(_inProject('p0', find.text('50%')), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        _inProject('p0', find.byType(LinearProgressIndicator)),
      );
      expect(bar.value, 0.5);
      if (size == wideSize) expect(_inProject('p0', find.text('2 tasks')), findsOneWidget);
    });

    testBothLayouts('shows a project without any tasks', (tester, size) async {
      await pumpKaneoApp(tester, server: _withProjects(['New']), size: size);
      expect(_inProject('p0', find.text('0%')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('copes with a server that sends no statistics', (tester, size) async {
      final server = FakeKaneo.empty()
        ..on(
          'api/project',
          (request) => const FakeResponse(200, [
            {'id': 'bare', 'workspaceId': FakeKaneo.workspaceId, 'slug': 'B', 'name': 'Bare'},
          ]),
        );
      await pumpKaneoApp(tester, server: server, size: size);
      expect(_inProject('bare', find.text('0%')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('opens its board', (tester, size) async {
      final app = await pumpKaneoApp(tester, server: _withProjects(['Open me']), size: size);
      await tester.tap(find.byKey(homeProjectKey('p0')));
      await tester.pumpAndSettle();
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.board('p0'));
    });

    // KAN-48: the page stays open under a board, so on a phone nothing read the progress again.
    testBothLayouts('come back up to date from a page opened over them', (tester, size) async {
      final server = _withProjects(['First']);
      final app = await pumpKaneoApp(tester, server: server, size: size);
      final router = app.container.read(routerProvider);
      router.push(AppRoutes.account);
      await tester.pumpAndSettle();
      server.addProject(id: 'later', name: 'Added on the web', slug: 'LATER');
      final reads = server.requestsTo('api/project', method: 'GET').length;

      router.pop();
      await tester.pumpAndSettle();

      expect(inPage(find.text('Added on the web')), findsOneWidget);
      expect(
        server.requestsTo('api/project', method: 'GET').length,
        reads + 1,
        reason: 'Once, whether the page or the sidebar asks.',
      );
    });

    testBothLayouts('uses the language of the app', (tester, size) async {
      final server = _withProjects(['项目']);
      final app = await pumpKaneoApp(tester, server: server, size: size, locale: 'zh-CN');
      expect(find.text(app.i18n.t('workspace:home.projects.title')), findsOneWidget);
      expect(app.i18n.t('workspace:home.projects.title'), '你的项目');
      if (size == wideSize) expect(_inProject('p0', find.text('0 个任务')), findsOneWidget);
    });

    testBothLayouts('comes back fresh when pulled down', (tester, size) async {
      final server = _withProjects(['First']);
      await pumpKaneoApp(tester, server: server, size: size);
      server.addProject(id: 'later', name: 'Added on the web', slug: 'LATER');

      await tester.fling(inPage(find.byType(ListView)), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(inPage(find.text('Added on the web')), findsOneWidget);
    });
  });

  group('archived projects', () {
    testBothLayouts('are hidden until asked for, then marked, and hide again', (
      tester,
      size,
    ) async {
      final server = _withArchived();
      final app = await pumpKaneoApp(tester, server: server, size: size);
      expect(inPage(find.text('Demo')), findsOneWidget);
      expect(inPage(find.text('Old project')), findsNothing);

      await _toggleArchived(tester, app);
      expect(inPage(find.text('Demo')), findsOneWidget);
      expect(inPage(find.text('Old project')), findsOneWidget);
      expect(_inProject('old', find.text(app.i18n.t('mobile:home.archived'))), findsOneWidget);
      expect(
        server.requestsTo('api/project', method: 'GET').map((r) => r.query['includeArchived']),
        contains('true'),
      );
      final dimmed = tester.widget<Opacity>(
        find.ancestor(of: find.text('Old project'), matching: find.byType(Opacity)).first,
      );
      expect(dimmed.opacity, 0.6);

      await _toggleArchived(tester, app, shown: true);
      expect(inPage(find.text('Old project')), findsNothing);
      expect(inPage(find.text('Demo')), findsOneWidget);
    });

    testBothLayouts('keep the list on screen while they load', (tester, size) async {
      final server = _withArchived();
      final app = await pumpKaneoApp(tester, server: server, size: size);
      final gate = server.hold('api/project');

      await tester.tap(find.text(app.i18n.t('mobile:home.showArchived')));
      await tester.pump();
      expect(inPage(find.text('Demo')), findsOneWidget);
      expect(inPage(find.byType(CircularProgressIndicator)), findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text('Old project')), findsOneWidget);
    });

    testBothLayouts('say so when they fail to load, and retry gets them', (tester, size) async {
      final server = _withArchived();
      final app = await pumpKaneoApp(tester, server: server, size: size);

      server.fail('api/project', status: 500);
      await _toggleArchived(tester, app);
      expect(inPage(find.text(app.i18n.t('mobile:ui.loadFailed'))), findsOneWidget);

      server.clearOverrides();
      await tester.tap(inPage(find.text(app.i18n.t('mobile:common.retry'))));
      await tester.pumpAndSettle();
      expect(inPage(find.text('Old project')), findsOneWidget);
    });

    testBothLayouts('can be found when a workspace has nothing else', (tester, size) async {
      final server = FakeKaneo.empty();
      server.addProject(id: 'old', name: 'Old project', slug: 'OLD')['archivedAt'] =
          '2026-01-01T00:00:00.000Z';
      final app = await pumpKaneoApp(tester, server: server, size: size);
      expect(find.text(app.i18n.t('mobile:home.empty.title')), findsOneWidget);

      await _toggleArchived(tester, app);
      expect(find.text(app.i18n.t('mobile:home.empty.title')), findsNothing);
      expect(inPage(find.text('Old project')), findsOneWidget);
    });

    testWidgets('stay shown when the window crosses the breakpoint', (tester) async {
      final app = await pumpKaneoApp(tester, server: _withArchived(), size: wideSize);
      await _toggleArchived(tester, app);
      expect(inPage(find.text('Old project')), findsOneWidget);

      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();
      expect(inPage(find.text('Old project')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:home.hideArchived')), findsOneWidget);

      setWindowSize(tester, wideSize);
      await tester.pumpAndSettle();
      expect(inPage(find.text('Old project')), findsOneWidget);
    });
  });

  group('the date and greeting', () {
    testBothLayouts('show today', (tester, size) async {
      final app = await pumpKaneoApp(
        tester,
        size: size,
        overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 11, 6, 9))],
      );
      expect(find.text('Friday, November 6'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:time.goodMorning')), findsOneWidget);
    });

    testBothLayouts('show today in Chinese', (tester, size) async {
      final app = await pumpKaneoApp(
        tester,
        size: size,
        locale: 'zh-CN',
        overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 11, 6, 15))],
      );
      expect(find.text('11月6日星期五'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:time.goodAfternoon')), findsOneWidget);
    });

    testBothLayouts('update at once when the app returns after midnight', (tester, size) async {
      var now = DateTime(2026, 11, 6, 23, 59);
      final app = await pumpKaneoApp(
        tester,
        size: size,
        overrides: [nowProvider.overrideWithValue(() => now)],
      );
      expect(find.text('Friday, November 6'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:time.goodEvening')), findsOneWidget);

      _goToBackground(tester);
      await tester.pump();
      now = DateTime(2026, 11, 7, 8);
      _returnToForeground(tester);
      await tester.pump();

      expect(find.text('Saturday, November 7'), findsOneWidget);
      expect(find.text('Friday, November 6'), findsNothing);
      expect(find.text(app.i18n.t('mobile:time.goodMorning')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:time.goodEvening')), findsNothing);
      // Back in front, the app also reads again what is open.
      await tester.pumpAndSettle();
    });

    testBothLayouts('also update when another page was open meanwhile', (tester, size) async {
      var now = DateTime(2026, 11, 6, 23, 59);
      final app = await pumpKaneoApp(
        tester,
        size: size,
        overrides: [nowProvider.overrideWithValue(() => now)],
      );
      final router = app.container.read(routerProvider);
      unawaited(router.push(AppRoutes.account));
      await tester.pumpAndSettle();

      _goToBackground(tester);
      now = DateTime(2026, 11, 7, 8);
      _returnToForeground(tester);
      await tester.pump();
      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('Saturday, November 7'), findsOneWidget);
      expect(find.text('Friday, November 6'), findsNothing);
    });

    testBothLayouts('update by themselves at midnight with the app open', (tester, size) async {
      var now = DateTime(2026, 11, 6, 23, 59, 30);
      await pumpKaneoApp(tester, size: size, overrides: [nowProvider.overrideWithValue(() => now)]);
      expect(find.text('Friday, November 6'), findsOneWidget);

      now = DateTime(2026, 11, 7);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Saturday, November 7'), findsOneWidget);
      expect(find.text('Friday, November 6'), findsNothing);
    });

    testBothLayouts('keep up with the time of day with the app open', (tester, size) async {
      var now = DateTime(2026, 11, 6, 11, 59);
      final app = await pumpKaneoApp(
        tester,
        size: size,
        overrides: [nowProvider.overrideWithValue(() => now)],
      );
      expect(find.text(app.i18n.t('mobile:time.goodMorning')), findsOneWidget);

      now = DateTime(2026, 11, 6, 12);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text(app.i18n.t('mobile:time.goodAfternoon')), findsOneWidget);

      now = DateTime(2026, 11, 6, 18);
      await tester.pump(const Duration(hours: 6));
      expect(find.text(app.i18n.t('mobile:time.goodEvening')), findsOneWidget);
    });

    testBothLayouts('leave no timer behind when the page closes', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size);
      app.container.read(routerProvider).go(AppRoutes.inbox);
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsNothing);
      // The test framework fails the test if a timer is still pending when it ends.
    });
  });

  group('switching workspace', () {
    testBothLayouts('moves the projects, tasks and inbox to the new workspace', (
      tester,
      size,
    ) async {
      final server = _twoWorkspaces();
      final app = await pumpKaneoApp(tester, server: server, size: size);
      final router = app.container.read(routerProvider);
      expect(inPage(find.text('Demo')), findsOneWidget);
      expect(inPage(find.text('Other project')), findsNothing);

      await _switchWorkspace(tester);
      expect(inPage(find.text('Other project')), findsOneWidget);
      expect(inPage(find.text('Demo')), findsNothing);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Test Workspace'), findsNothing);

      router.go(AppRoutes.myTasks);
      await tester.pumpAndSettle();
      expect(inPage(find.text('Other task')), findsOneWidget);
      expect(inPage(find.text('Set up the project')), findsNothing);
      expect(server.requestsTo('api/task/assigned').last.query['workspaceId'], _otherWorkspace);

      router.go(AppRoutes.inbox);
      await tester.pumpAndSettle();
      expect(inPage(find.text('Other notice')), findsOneWidget);
      expect(inPage(find.text('Assigned to you')), findsNothing);
      expect(server.requestsTo('api/notification').last.query['workspaceId'], _otherWorkspace);
    });

    testBothLayouts('and back again', (tester, size) async {
      final app = await pumpKaneoApp(tester, server: _twoWorkspaces(), size: size);
      await _switchWorkspace(tester);
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Workspace'));
      await tester.pumpAndSettle();
      expect(inPage(find.text('Demo')), findsOneWidget);
      expect(inPage(find.text('Other project')), findsNothing);
      expect(app.container.read(selectedWorkspaceIdProvider), FakeKaneo.workspaceId);
    });

    testBothLayouts('stays on the archived setting, with the new workspace\'s projects', (
      tester,
      size,
    ) async {
      final server = _twoWorkspaces();
      server.addProject(id: 'old', name: 'Old project', slug: 'OLD')
        ..['workspaceId'] = _otherWorkspace
        ..['archivedAt'] = '2026-01-01T00:00:00.000Z';
      final app = await pumpKaneoApp(tester, server: server, size: size);
      await _toggleArchived(tester, app);
      await _switchWorkspace(tester);
      expect(inPage(find.text('Old project')), findsOneWidget);
      expect(inPage(find.text('Other project')), findsOneWidget);
      expect(inPage(find.text('Demo')), findsNothing);
    });

    testBothLayouts('tells the server, as the web app expects', (tester, size) async {
      final server = _twoWorkspaces();
      await pumpKaneoApp(tester, server: server, size: size);
      await _switchWorkspace(tester);
      final sent = server.requestsTo('organization/set-active', method: 'POST');
      expect(sent, hasLength(1));
      expect((sent.single.body! as Map)['organizationId'], _otherWorkspace);
    });

    testBothLayouts('works even if the server refuses to hear about it', (tester, size) async {
      final server = _twoWorkspaces()..fail('organization/set-active', status: 500);
      final app = await pumpKaneoApp(tester, server: server, size: size);
      await _switchWorkspace(tester);
      expect(tester.takeException(), isNull);
      expect(inPage(find.text('Other project')), findsOneWidget);
      expect(app.container.read(sessionProvider), isNotNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testBothLayouts('picking the same workspace changes nothing', (tester, size) async {
      final server = _twoWorkspaces();
      final app = await pumpKaneoApp(tester, server: server, size: size);
      await tester.tap(find.text('Test Workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Workspace').last);
      await tester.pumpAndSettle();
      expect(app.container.read(selectedWorkspaceIdProvider), isNull);
      expect(server.requestsTo('organization/set-active'), isEmpty);
      expect(inPage(find.text('Demo')), findsOneWidget);
    });

    testWidgets('narrow windows have it in the bar, named for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpKaneoApp(tester, server: _twoWorkspaces(), size: narrowSize);
      final bar = find.byType(AppBar);
      expect(find.descendant(of: bar, matching: find.text('Test Workspace')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.byIcon(LucideIcons.chevronDown)), findsOne);
      expect(
        find.bySemanticsLabel(RegExp(app.i18n.t('mobile:home.switchWorkspace'))),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('narrow windows fit a very long workspace name', (tester) async {
      final server = FakeKaneo();
      server.workspaces.first['name'] = 'A very long workspace name ' * 10;
      await pumpKaneoApp(tester, server: server, size: narrowSize);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('Account'), findsOneWidget);
    });

    testWidgets('narrow windows reach search and the account from the bar', (tester) async {
      final app = await pumpKaneoApp(tester, size: narrowSize);
      final router = app.container.read(routerProvider);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.search);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.account);
    });

    testWidgets('survives a window turning wide with the list open', (tester) async {
      final app = await pumpKaneoApp(tester, server: _twoWorkspaces(), size: narrowSize);
      await tester.tap(find.text('Test Workspace'));
      await tester.pumpAndSettle();

      setWindowSize(tester, wideSize);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(app.container.read(selectedWorkspaceIdProvider), _otherWorkspace);
      expect(inPage(find.text('Other project')), findsOneWidget);
    });
  });

  group('the next time the app opens', () {
    testBothLayouts('it is on the workspace used last', (tester, size) async {
      final first = await pumpKaneoApp(tester, server: _twoWorkspaces(), size: size);
      await _switchWorkspace(tester);
      final remembered = first.container.read(prefsProvider).getString('kaneo.lastWorkspaceId');
      expect(remembered, _otherWorkspace);

      // A new app, starting from what the last one saved.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final server = _twoWorkspaces();
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        preferences: {'kaneo.lastWorkspaceId': remembered!},
      );
      expect(find.text('Other'), findsOneWidget);
      expect(inPage(find.text('Other project')), findsOneWidget);
      expect(inPage(find.text('Demo')), findsNothing);
      expect(server.requestsTo('api/project').first.query['workspaceId'], _otherWorkspace);
      // Remembered here, so there is nothing to tell the server.
      expect(server.requestsTo('organization/set-active'), isEmpty);
    });

    testBothLayouts('it falls back to the first workspace if that one is gone', (
      tester,
      size,
    ) async {
      await pumpKaneoApp(
        tester,
        size: size,
        preferences: {'kaneo.lastWorkspaceId': 'deleted-workspace'},
      );
      expect(find.text('Test Workspace'), findsOneWidget);
      expect(inPage(find.text('Demo')), findsOneWidget);
    });
  });

  group('while data is on its way or missing', () {
    testBothLayouts('the date stays up while the projects load', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold('api/project');
      final app = await pumpKaneoApp(tester, server: server, size: size, settle: false);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(inPage(find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text(app.i18n.t('workspace:home.projects.title')), findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.byType(CircularProgressIndicator)), findsNothing);
      expect(inPage(find.text('Demo')), findsOneWidget);
    });

    testBothLayouts('a failure says why, and retry loads the projects', (tester, size) async {
      final server = FakeKaneo()..fail('api/project', status: 500);
      final app = await pumpKaneoApp(tester, server: server, size: size);
      expect(inPage(find.text(app.i18n.t('mobile:ui.loadFailed'))), findsOneWidget);

      server.clearOverrides();
      await tester.tap(inPage(find.text(app.i18n.t('mobile:common.retry'))));
      await tester.pumpAndSettle();
      expect(inPage(find.text('Demo')), findsOneWidget);
    });

    testBothLayouts('no permission reads as that, with no retry', (tester, size) async {
      final server = FakeKaneo()..fail('api/project', status: 403);
      final app = await pumpKaneoApp(tester, server: server, size: size);
      expect(inPage(find.text(app.i18n.t('mobile:errors.forbidden'))), findsOneWidget);
      expect(inPage(find.text(app.i18n.t('mobile:common.retry'))), findsNothing);
    });

    testBothLayouts('a workspace with no projects says so', (tester, size) async {
      final app = await pumpKaneoApp(tester, server: FakeKaneo.empty(), size: size);
      expect(inPage(find.text(app.i18n.t('mobile:home.empty.title'))), findsOneWidget);
      expect(inPage(find.text(app.i18n.t('mobile:home.empty.message'))), findsOneWidget);
    });

    for (final locale in const ['en-US', 'zh-CN', 'zh-TW']) {
      testBothLayouts('no workspace points to the web app, in $locale', (tester, size) async {
        final server = FakeKaneo()..workspaces.clear();
        final app = await pumpKaneoApp(tester, server: server, size: size, locale: locale);
        final message = app.i18n.t('app:home.noWorkspaceOnWeb');
        expect(message, isNot(contains('noWorkspaceOnWeb')));
        expect(inPage(find.text(app.i18n.t('mobile:home.noWorkspace.title'))), findsOneWidget);
        expect(inPage(find.text(message)), findsOneWidget);
      });
    }

    testBothLayouts('no workspace says the same on the other pages', (tester, size) async {
      final server = FakeKaneo()..workspaces.clear();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      expect(inPage(find.text(app.i18n.t('app:home.noWorkspaceOnWeb'))), findsOneWidget);
    });

    testBothLayouts('with a workspace from the web app, trying again opens it', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final workspaces = [...server.workspaces];
      server.workspaces.clear();
      final app = await pumpKaneoApp(tester, server: server, size: size);
      expect(inPage(find.text('Demo')), findsNothing);

      server.workspaces.addAll(workspaces);
      await tester.tap(inPage(find.text(app.i18n.t('mobile:common.retry'))));
      await tester.pumpAndSettle();
      expect(inPage(find.text(app.i18n.t('app:home.noWorkspaceOnWeb'))), findsNothing);
      expect(inPage(find.text('Demo')), findsOneWidget);
    });

    testWidgets('a narrow window with no workspace still reaches the account', (tester) async {
      final server = FakeKaneo()..workspaces.clear();
      final app = await pumpKaneoApp(tester, server: server, size: narrowSize);
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.account);
    });

    testBothLayouts('the page is not a placeholder any more', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size);
      expect(find.text(app.i18n.t('app:placeholder.notice')), findsNothing);
    });
  });
}
