import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/auth/login_page.dart';
import 'package:kaneo_app/features/home/home_page.dart';
import 'package:kaneo_app/features/shell/app_shell.dart';
import 'package:kaneo_app/features/shell/app_sidebar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/test_app.dart';

Finder inSidebar(Finder finder) => find.descendant(of: find.byType(AppSidebar), matching: finder);

void expectWide() {
  expect(find.byType(AppSidebar), findsOneWidget);
  expect(find.byType(NavigationBar), findsNothing);
}

void expectNarrowWithTabs() {
  expect(find.byType(NavigationBar), findsOneWidget);
  expect(find.byType(AppSidebar), findsNothing);
}

void expectNarrowWithoutTabs() {
  expect(find.byType(NavigationBar), findsNothing);
  expect(find.byType(AppSidebar), findsNothing);
}

/// The way back, whether a page's bar adds it by itself or the page has its own, as the board does.
final Finder backButton = find.byTooltip('Back');

Future<void> resize(WidgetTester tester, Size size) async {
  setWindowSize(tester, size);
  await tester.pumpAndSettle();
}

/// Every page, with something it shows when its data arrives, and whether it has the tabs.
final Map<String, ({Finder shows, bool tabs})> _pages = {
  AppRoutes.home: (shows: inPage(find.text('Demo')), tabs: true),
  AppRoutes.inbox: (shows: find.text('Assigned to you'), tabs: true),
  AppRoutes.myTasks: (shows: find.text('Set up the project'), tabs: true),
  AppRoutes.activity: (shows: find.text('Set up the project'), tabs: true),
  AppRoutes.search: (shows: find.byKey(const ValueKey('search-field')), tabs: false),
  AppRoutes.account: (shows: find.text(FakeKaneo.email), tabs: false),
  AppRoutes.board(FakeKaneo.projectId): (shows: find.text('Fix the drag preview'), tabs: false),
  AppRoutes.task('task-2'): (shows: find.text('Write the first description'), tabs: false),
  AppRoutes.newTask(projectId: FakeKaneo.projectId): (shows: find.text('New task'), tabs: false),
};

void main() {
  group('the shorter side picks the layout', () {
    const wide = {
      'iPad Pro 13 on its side': Size(1366, 1024),
      'iPad Pro 13 upright': Size(1024, 1366),
      'iPad mini on its side': Size(1133, 744),
      'iPad mini upright': Size(744, 1133),
      'a desktop window': Size(1920, 1080),
      'exactly on the line, upright': Size(600, 1000),
      'exactly on the line, on its side': Size(1000, 600),
    };
    wide.forEach((name, size) {
      testWidgets('$name shows the sidebar and no tabs', (tester) async {
        await pumpKaneoApp(tester, size: size);
        expectWide();
        expect(tester.takeException(), isNull);
      });
    });

    const narrow = {
      'iPhone upright': Size(390, 844),
      'iPhone on its side': Size(844, 390),
      'a large phone upright': Size(430, 932),
      'a large phone on its side': Size(932, 430),
      'an iPad in a split view': Size(507, 1366),
      'just under the line, upright': Size(599, 1000),
      'just under the line, on its side': Size(1000, 599),
    };
    narrow.forEach((name, size) {
      testWidgets('$name shows the tabs and no sidebar', (tester) async {
        await pumpKaneoApp(tester, size: size);
        expectNarrowWithTabs();
        expect(tester.takeException(), isNull);
      });
    });

    test('isWideSize is true from 600 on the shorter side', () {
      expect(isWideSize(const Size(600, 600)), isTrue);
      expect(isWideSize(const Size(599.9, 2000)), isFalse);
      expect(isWideSize(const Size(2000, 599.9)), isFalse);
    });
  });

  group('every page, in every orientation', () {
    const sizes = {
      'iPad on its side': wideSize,
      'iPad upright': Size(1024, 1366),
      'the smallest wide window': Size(600, 600),
      'iPhone upright': narrowSize,
      'iPhone on its side': Size(844, 390),
    };
    _pages.forEach((location, page) {
      sizes.forEach((name, size) {
        testWidgets('$location on $name', (tester) async {
          await pumpKaneoApp(tester, size: size, location: location);
          expect(page.shows, findsWidgets);
          if (isWideSize(size)) {
            expectWide();
          } else {
            page.tabs ? expectNarrowWithTabs() : expectNarrowWithoutTabs();
          }
          expect(tester.takeException(), isNull);
        });
      });
    });
  });

  group('crossing the breakpoint', () {
    _pages.forEach((location, page) {
      testWidgets('keeps $location, narrowing then widening', (tester) async {
        final app = await pumpKaneoApp(tester, size: wideSize, location: location);
        final router = app.container.read(routerProvider);
        expectWide();

        await resize(tester, narrowSize);
        page.tabs ? expectNarrowWithTabs() : expectNarrowWithoutTabs();
        expect(router.state.uri.toString(), location);
        expect(page.shows, findsWidgets);

        await resize(tester, wideSize);
        expectWide();
        expect(router.state.uri.toString(), location);
        expect(page.shows, findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('keeps $location, widening then narrowing', (tester) async {
        final app = await pumpKaneoApp(tester, size: narrowSize, location: location);
        final router = app.container.read(routerProvider);

        await resize(tester, wideSize);
        expectWide();
        expect(router.state.uri.toString(), location);
        expect(page.shows, findsWidgets);

        await resize(tester, narrowSize);
        page.tabs ? expectNarrowWithTabs() : expectNarrowWithoutTabs();
        expect(router.state.uri.toString(), location);
        expect(page.shows, findsWidgets);
      });
    });

    testWidgets('an iPad going into and out of a split view', (tester) async {
      final app = await pumpKaneoApp(tester, size: const Size(1024, 1366));
      app.container.read(routerProvider).go(AppRoutes.inbox);
      await tester.pumpAndSettle();
      expectWide();

      await resize(tester, const Size(507, 1366));
      expectNarrowWithTabs();
      expect(find.text('Assigned to you'), findsOneWidget);

      await resize(tester, const Size(1024, 1366));
      expectWide();
      expect(find.text('Assigned to you'), findsOneWidget);
    });

    testBothLayouts('a phone turning over changes nothing', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size, location: AppRoutes.inbox);
      final router = app.container.read(routerProvider);
      final before = isWideSize(size);

      await resize(tester, size.flipped);
      expect(isWideSize(size.flipped), before);
      before ? expectWide() : expectNarrowWithTabs();
      expect(router.state.uri.path, AppRoutes.inbox);
      expect(find.text('Assigned to you'), findsOneWidget);
    });

    testBothLayouts('keeps what the person typed and the results on screen', (tester, size) async {
      await pumpKaneoApp(tester, size: size, location: AppRoutes.search);
      final field = find.byKey(const ValueKey('search-field'));
      await tester.enterText(field, 'board');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Review the board layout'), findsOneWidget);
      final state = tester.state(field);

      final other = isWideSize(size) ? narrowSize : wideSize;
      await resize(tester, other);
      expect(tester.widget<TextField>(field).controller, isNull);
      expect(find.text('board'), findsOneWidget);
      expect(find.text('Review the board layout'), findsOneWidget);
      expect(tester.state(field), same(state));

      await resize(tester, size);
      expect(find.text('board'), findsOneWidget);
      expect(find.text('Review the board layout'), findsOneWidget);
      expect(tester.state(field), same(state));
    });

    testBothLayouts('does not load the open page again', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      final requests = server.requestsTo('api/task/tasks/').length;

      await resize(tester, isWideSize(size) ? narrowSize : wideSize);
      expect(server.requestsTo('api/task/tasks/'), hasLength(requests));
    });

    testBothLayouts('keeps the pages to go back to', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size);
      final router = app.container.read(routerProvider);
      await tester.tap(inPage(find.text('Demo')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Set up the project'),
        100,
        scrollable: inPage(find.byType(Scrollable)).first,
      );
      await tester.tap(find.text('Set up the project'));
      await tester.pumpAndSettle();
      expect(taskOpen('task-1'), findsOneWidget);

      await resize(tester, isWideSize(size) ? narrowSize : wideSize);
      expect(taskOpen('task-1'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(taskOpen('task-1'), findsNothing);
      expect(router.state.uri.path, AppRoutes.board(FakeKaneo.projectId));
      router.pop();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.home);
    });

    final fromSidebar = <String, ({String label, String location})>{
      'a board': (label: 'Demo', location: AppRoutes.board(FakeKaneo.projectId)),
      'the account page': (label: 'Account', location: AppRoutes.account),
    };
    fromSidebar.forEach((name, page) {
      testWidgets('$name opened from the sidebar has a way back once the window is narrow', (
        tester,
      ) async {
        final app = await pumpKaneoApp(tester, size: wideSize);
        final router = app.container.read(routerProvider);
        await tester.tap(inSidebar(find.text(page.label)));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, page.location);

        await resize(tester, narrowSize);
        expectNarrowWithoutTabs();
        await tester.tap(backButton);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.home);
        expectNarrowWithTabs();
      });
    });

    testWidgets('a page reached by link has a way back on a narrow window', (tester) async {
      final app = await pumpKaneoApp(
        tester,
        size: narrowSize,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.home);
      expectNarrowWithTabs();
    });
  });

  group('the sidebar', () {
    testWidgets('shows the workspace, main pages, projects and account', (tester) async {
      await pumpKaneoApp(tester, size: wideSize);
      for (final text in [
        'Test Workspace',
        'Home',
        'Inbox',
        'My tasks',
        'Activity',
        'Projects',
        'Demo',
        'Second project',
        'Account',
      ]) {
        expect(inSidebar(find.text(text)), findsOneWidget, reason: text);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('is as wide as the web app, whatever the window', (tester) async {
      await pumpKaneoApp(tester, size: wideSize);
      expect(tester.getSize(find.byType(AppSidebar)).width, sidebarWidth);
      expect(tester.getTopLeft(find.byType(AppSidebar)).dx, 0);
      await resize(tester, const Size(600, 800));
      expect(tester.getSize(find.byType(AppSidebar)).width, sidebarWidth);
    });

    testWidgets('is in the current language', (tester) async {
      final app = await pumpKaneoApp(tester, size: wideSize, locale: 'zh-CN');
      for (final key in [
        'navigation:sidebar.home',
        'navigation:sidebar.inbox',
        'navigation:sidebar.myTasks',
        'navigation:sidebar.projects',
        'mobile:home.account',
      ]) {
        final text = app.i18n.t(key);
        expect(text, isNot(contains(':')), reason: key);
        expect(inSidebar(find.text(text)), findsOneWidget, reason: key);
      }
      for (final english in ['Home', 'Inbox', 'My tasks', 'Projects', 'Account']) {
        expect(inSidebar(find.text(english)), findsNothing, reason: english);
      }
    });

    final destinations = <String, ({String path, Finder shows})>{
      'Inbox': (path: AppRoutes.inbox, shows: find.text('Assigned to you')),
      'My tasks': (path: AppRoutes.myTasks, shows: inPage(find.text('Set up the project'))),
      'Activity': (path: AppRoutes.activity, shows: inPage(find.text('Set up the project'))),
      'Account': (path: AppRoutes.account, shows: find.text(FakeKaneo.email)),
    };
    destinations.forEach((label, page) {
      testWidgets('$label opens its page and is marked, and Home goes back', (tester) async {
        final handle = tester.ensureSemantics();
        final app = await pumpKaneoApp(tester, size: wideSize);
        final router = app.container.read(routerProvider);
        expect(
          tester.getSemantics(inSidebar(find.text('Home'))),
          isSemantics(isSelected: true, isButton: true),
        );

        await tester.tap(inSidebar(find.text(label)));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, page.path);
        expect(page.shows, findsWidgets);
        expect(
          tester.getSemantics(inSidebar(find.text(label))),
          isSemantics(isSelected: true, isButton: true),
        );
        expect(
          tester.getSemantics(inSidebar(find.text('Home'))),
          isNot(isSemantics(isSelected: true)),
        );

        await tester.tap(inSidebar(find.text('Home')));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.home);
        handle.dispose();
      });
    });

    testWidgets('a project opens its board and is marked, the others are not', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpKaneoApp(tester, size: wideSize);
      await tester.tap(inSidebar(find.text('Demo')));
      await tester.pumpAndSettle();
      expect(
        app.container.read(routerProvider).state.uri.path,
        AppRoutes.board(FakeKaneo.projectId),
      );
      expect(find.text('Fix the drag preview'), findsWidgets);
      expect(tester.getSemantics(inSidebar(find.text('Demo'))), isSemantics(isSelected: true));
      expect(
        tester.getSemantics(inSidebar(find.text('Second project'))),
        isNot(isSemantics(isSelected: true)),
      );
      handle.dispose();
    });

    testWidgets('a project pushed from the home page is marked too', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpKaneoApp(tester, size: wideSize);
      await tester.tap(inPage(find.text('Demo')));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(inSidebar(find.text('Demo'))), isSemantics(isSelected: true));
      handle.dispose();
    });

    testWidgets('the search button opens search', (tester) async {
      final app = await pumpKaneoApp(tester, size: wideSize);
      await tester.tap(inSidebar(find.byTooltip('Search')));
      await tester.pumpAndSettle();
      expect(app.container.read(routerProvider).state.uri.path, AppRoutes.search);
      expect(find.byKey(const ValueKey('search-field')), findsOneWidget);
    });

    testWidgets('shows each project with its icon, and the default for an unknown one', (
      tester,
    ) async {
      final server = FakeKaneo();
      server.addProject(name: 'With an icon', slug: 'ICO')['icon'] = 'Rocket';
      server.addProject(name: 'Old icon', slug: 'OLD')['icon'] = 'NoLongerExists';
      await pumpKaneoApp(tester, server: server, size: wideSize);
      expect(inSidebar(find.byIcon(LucideIcons.rocket)), findsOneWidget);
      expect(inSidebar(find.byIcon(LucideIcons.layout)), findsNWidgets(3));
    });

    testWidgets('long names and many projects stay inside it, and the list scrolls', (
      tester,
    ) async {
      final server = FakeKaneo();
      final longName = 'A very long project name ' * 10;
      server.addProject(name: longName, slug: 'LONG');
      server.workspaces.first['name'] = 'A very long workspace name ' * 10;
      for (var i = 0; i < 40; i++) {
        server.addProject(name: 'Project $i', slug: 'P$i');
      }
      await pumpKaneoApp(tester, server: server, size: const Size(600, 600));
      expect(tester.takeException(), isNull);
      expect(inSidebar(find.text('Account')), findsOneWidget);
      expect(inSidebar(find.text('Project 39')), findsNothing);

      await tester.scrollUntilVisible(
        inSidebar(find.text('Project 39')),
        100,
        scrollable: inSidebar(find.byType(Scrollable)),
      );
      expect(inSidebar(find.text('Project 39')), findsOneWidget);
      expect(inSidebar(find.text('Account')), findsOneWidget);
    });

    testWidgets('and the page stay clear of the status bar and the home indicator', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      addTearDown(tester.view.resetPadding);
      await pumpKaneoApp(tester, size: wideSize);
      final sidebar = tester.getRect(find.byType(AppSidebar));
      expect(sidebar.top, 24);
      expect(sidebar.bottom, wideSize.height - 20);
      // The page's own bar does not add the status bar a second time.
      final page = tester.getRect(find.byKey(shellPageKey));
      expect(page.top, 24 + 8);
      expect(tester.getRect(inPage(find.byType(AppBar))).top, page.top);
      expect(tester.getSize(inPage(find.byType(AppBar))).height, kToolbarHeight);
    });

    testWidgets('is not the navigation of the login page', (tester) async {
      await pumpKaneoApp(tester, size: wideSize, session: null);
      expect(find.byType(AppSidebar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    group('switching workspace', () {
      const otherWorkspace = 'ws-other';

      FakeKaneo twoWorkspaces() {
        final server = FakeKaneo();
        server.workspaces.add({...server.workspaces.first, 'id': otherWorkspace, 'name': 'Other'});
        server.addProject(name: 'Other project', slug: 'OTH')['workspaceId'] = otherWorkspace;
        return server;
      }

      testWidgets('moves the sidebar and the pages to the new workspace, and is remembered', (
        tester,
      ) async {
        final app = await pumpKaneoApp(tester, server: twoWorkspaces(), size: wideSize);
        expect(inSidebar(find.text('Other project')), findsNothing);

        await tester.tap(inSidebar(find.text('Test Workspace')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other'));
        await tester.pumpAndSettle();

        expect(inSidebar(find.text('Other')), findsOneWidget);
        expect(inSidebar(find.text('Other project')), findsOneWidget);
        expect(inSidebar(find.text('Demo')), findsNothing);
        expect(inPage(find.text('Other project')), findsOneWidget);
        expect(app.container.read(selectedWorkspaceIdProvider), otherWorkspace);
        expect(
          app.container.read(prefsProvider).getString('kaneo.lastWorkspaceId'),
          otherWorkspace,
        );
      });

      testWidgets('leaves a page of the old workspace for the home page', (tester) async {
        final app = await pumpKaneoApp(
          tester,
          server: twoWorkspaces(),
          size: wideSize,
          location: AppRoutes.board(FakeKaneo.projectId),
        );
        await tester.tap(inSidebar(find.text('Test Workspace')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other'));
        await tester.pumpAndSettle();
        expect(app.container.read(routerProvider).state.uri.path, AppRoutes.home);
        expect(find.byType(HomePage), findsOneWidget);
      });

      testWidgets('picking the same workspace, or none, stays on the page', (tester) async {
        final app = await pumpKaneoApp(
          tester,
          server: twoWorkspaces(),
          size: wideSize,
          location: AppRoutes.inbox,
        );
        final router = app.container.read(routerProvider);

        await tester.tap(inSidebar(find.text('Test Workspace')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test Workspace').last);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.inbox);
        expect(app.container.read(selectedWorkspaceIdProvider), isNull);

        await tester.tap(inSidebar(find.text('Test Workspace')));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(700, 10));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.inbox);
        expect(app.container.read(selectedWorkspaceIdProvider), isNull);
      });

      testWidgets('still works when the window turns narrow with the list open', (tester) async {
        final app = await pumpKaneoApp(
          tester,
          server: twoWorkspaces(),
          size: wideSize,
          location: AppRoutes.inbox,
        );
        await tester.tap(inSidebar(find.text('Test Workspace')));
        await tester.pumpAndSettle();

        await resize(tester, narrowSize);
        expect(find.byType(AppSidebar), findsNothing);
        await tester.tap(find.text('Other'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(app.container.read(selectedWorkspaceIdProvider), otherWorkspace);
        expect(app.container.read(routerProvider).state.uri.path, AppRoutes.home);
        expect(inPage(find.text('Other project')), findsOneWidget);
      });

      testWidgets('opens on the remembered workspace', (tester) async {
        await pumpKaneoApp(
          tester,
          server: twoWorkspaces(),
          size: wideSize,
          preferences: {'kaneo.lastWorkspaceId': otherWorkspace},
        );
        expect(inSidebar(find.text('Other')), findsOneWidget);
        expect(inSidebar(find.text('Other project')), findsOneWidget);
      });
    });

    group('while data is on its way or missing', () {
      testWidgets('holds its place without a second spinner', (tester) async {
        final server = FakeKaneo();
        final gate = server.hold('api/workspace');
        await pumpKaneoApp(tester, server: server, size: wideSize, settle: false);
        await tester.pump();
        expect(inSidebar(find.byType(CircularProgressIndicator)), findsNothing);
        expect(inSidebar(find.text('Inbox')), findsOneWidget);
        expect(inSidebar(find.text('Account')), findsOneWidget);
        expect(inSidebar(find.text('Test Workspace')), findsNothing);
        gate.release();
        await tester.pumpAndSettle();
        expect(inSidebar(find.text('Test Workspace')), findsOneWidget);
        expect(inSidebar(find.text('Demo')), findsOneWidget);
      });

      testWidgets('keeps the rest usable while the projects load', (tester) async {
        final server = FakeKaneo();
        final gate = server.hold('api/project');
        await pumpKaneoApp(tester, server: server, size: wideSize, settle: false);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(inSidebar(find.text('Test Workspace')), findsOneWidget);
        expect(inSidebar(find.text('Projects')), findsOneWidget);
        expect(inSidebar(find.text('Demo')), findsNothing);
        expect(inSidebar(find.byType(CircularProgressIndicator)), findsNothing);
        gate.release();
        await tester.pumpAndSettle();
        expect(inSidebar(find.text('Demo')), findsOneWidget);
      });

      testWidgets('says the projects failed, and retry loads them', (tester) async {
        final server = FakeKaneo()..fail('api/project', status: 500);
        final app = await pumpKaneoApp(tester, server: server, size: wideSize);
        final unavailable = app.i18n.t('app:shell.projectsUnavailable');
        expect(inSidebar(find.text(unavailable)), findsOneWidget);
        expect(inSidebar(find.text('Inbox')), findsOneWidget);

        server.clearOverrides();
        await tester.tap(inSidebar(find.byTooltip(app.i18n.t('mobile:common.retry'))));
        await tester.pumpAndSettle();
        expect(inSidebar(find.text(unavailable)), findsNothing);
        expect(inSidebar(find.text('Demo')), findsOneWidget);
      });

      testWidgets('offers no retry when the projects are not allowed', (tester) async {
        final server = FakeKaneo()..fail('api/project', status: 403);
        final app = await pumpKaneoApp(tester, server: server, size: wideSize);
        expect(inSidebar(find.text(app.i18n.t('app:shell.projectsUnavailable'))), findsOneWidget);
        expect(inSidebar(find.byTooltip(app.i18n.t('mobile:common.retry'))), findsNothing);
      });

      testWidgets('says there are no projects', (tester) async {
        final app = await pumpKaneoApp(tester, server: FakeKaneo.empty(), size: wideSize);
        expect(inSidebar(find.text(app.i18n.t('app:shell.noProjects'))), findsOneWidget);
      });

      testWidgets('with no workspace leaves that to the page and keeps the account', (
        tester,
      ) async {
        final server = FakeKaneo()..workspaces.clear();
        final app = await pumpKaneoApp(tester, server: server, size: wideSize);
        expect(inSidebar(find.text('Projects')), findsNothing);
        expect(inSidebar(find.text('Account')), findsOneWidget);
        expect(inPage(find.text(app.i18n.t('mobile:home.noWorkspace.title'))), findsOneWidget);

        await tester.tap(inSidebar(find.text('Account')));
        await tester.pumpAndSettle();
        expect(find.text(FakeKaneo.email), findsOneWidget);
      });

      testWidgets('says the workspaces failed, and retry loads them', (tester) async {
        final server = FakeKaneo()..fail('api/workspace', status: 500);
        final app = await pumpKaneoApp(tester, server: server, size: wideSize);
        final unavailable = app.i18n.t('app:shell.workspaceUnavailable');
        expect(inSidebar(find.text(unavailable)), findsOneWidget);
        expect(inSidebar(find.text('Account')), findsOneWidget);

        server.clearOverrides();
        await tester.tap(inSidebar(find.byTooltip(app.i18n.t('mobile:common.retry'))));
        await tester.pumpAndSettle();
        expect(inSidebar(find.text(unavailable)), findsNothing);
        expect(inSidebar(find.text('Test Workspace')), findsOneWidget);
        expect(inSidebar(find.text('Demo')), findsOneWidget);
      });

      testWidgets('offers no retry when the workspaces are not allowed', (tester) async {
        final server = FakeKaneo()..fail('api/workspace', status: 403);
        final app = await pumpKaneoApp(tester, server: server, size: wideSize);
        expect(inSidebar(find.text(app.i18n.t('app:shell.workspaceUnavailable'))), findsOneWidget);
        expect(inSidebar(find.byTooltip(app.i18n.t('mobile:common.retry'))), findsNothing);
      });

      testWidgets('keeps the projects on screen when a refresh fails', (tester) async {
        final server = FakeKaneo();
        final app = await pumpKaneoApp(tester, server: server, size: wideSize);
        server.fail('api/project', status: 500);
        final query = projectsQuery(FakeKaneo.workspaceId);
        unawaited(app.container.read(query.notifier).refresh());
        await tester.pumpAndSettle();
        expect(inSidebar(find.text('Demo')), findsOneWidget);
        expect(inSidebar(find.text(app.i18n.t('app:shell.projectsUnavailable'))), findsNothing);
      });
    });
  });

  group('moving between pages', () {
    testBothLayouts('picks up a project added elsewhere', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size);
      server.addProject(name: 'Added on the web', slug: 'WEB');
      expect(find.text('Added on the web'), findsNothing);

      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();
      if (isWideSize(size)) expect(inSidebar(find.text('Added on the web')), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(inPage(find.text('Added on the web')), findsOneWidget);
    });

    testWidgets('picks up a renamed workspace in the sidebar', (tester) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: wideSize);
      server.workspaces.first['name'] = 'Renamed';

      await tester.tap(inSidebar(find.text('Inbox')));
      await tester.pumpAndSettle();
      expect(inSidebar(find.text('Renamed')), findsOneWidget);
    });

    testWidgets('notices a revoked key from any page of a wide window', (tester) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: wideSize, location: AppRoutes.account);
      server.credentialsRevoked = true;

      await tester.tap(inSidebar(find.text('Home')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('does not refresh the sidebar while staying on the page', (tester) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: wideSize, location: AppRoutes.inbox);
      final requests = server.requestsTo('api/project').length;

      await tester.tap(inSidebar(find.text('Inbox')));
      await tester.pumpAndSettle();
      await resize(tester, wideSize.flipped);
      expect(server.requestsTo('api/project'), hasLength(requests));
    });
  });

  group('the workspace list refreshing in the background', () {
    testBothLayouts('leaves the open page alone, while it loads and when it fails', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.search,
      );
      final field = find.byKey(const ValueKey('search-field'));
      await tester.enterText(field, 'board');
      await tester.pump();
      final state = tester.state(field);

      final gate = server.hold('api/workspace');
      unawaited(app.container.read(workspacesQuery.notifier).refresh());
      await tester.pump();
      expect(tester.state(field), same(state));
      expect(find.text('board'), findsOneWidget);
      if (isWideSize(size)) expect(inSidebar(find.text('Test Workspace')), findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
      expect(tester.state(field), same(state));

      server.fail('api/workspace', status: 500);
      unawaited(app.container.read(workspacesQuery.notifier).refresh());
      await tester.pumpAndSettle();
      expect(tester.state(field), same(state));
      expect(find.text('board'), findsOneWidget);
      if (isWideSize(size)) {
        expect(inSidebar(find.text('Test Workspace')), findsOneWidget);
        expect(inSidebar(find.text('Demo')), findsOneWidget);
        expect(inSidebar(find.text(app.i18n.t('app:shell.workspaceUnavailable'))), findsNothing);
      }
    });
  });

  group('the bottom tabs', () {
    testWidgets('are the four of the current app, in its order', (tester) async {
      await pumpKaneoApp(tester, size: narrowSize);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        [for (final d in bar.destinations) (d as NavigationDestination).label],
        ['Home', 'My tasks', 'Inbox', 'Activity'],
      );
    });

    final tabs = <String, ({String path, Finder shows})>{
      'My tasks': (path: AppRoutes.myTasks, shows: find.text('Set up the project')),
      'Inbox': (path: AppRoutes.inbox, shows: find.text('Assigned to you')),
      'Activity': (path: AppRoutes.activity, shows: find.text('Set up the project')),
    };
    final orientations = {'upright': narrowSize, 'on its side': narrowSize.flipped};
    tabs.forEach((label, page) {
      orientations.forEach((orientation, size) {
        testWidgets('$label opens its page and home goes back, $orientation', (tester) async {
          final app = await pumpKaneoApp(tester, size: size);
          final router = app.container.read(routerProvider);
          await tester.tap(
            find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
          );
          await tester.pumpAndSettle();
          expect(router.state.uri.path, page.path);
          expect(page.shows, findsWidgets);
          final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
          expect((bar.destinations[bar.selectedIndex] as NavigationDestination).label, label);

          await tester.tap(
            find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')),
          );
          await tester.pumpAndSettle();
          expect(router.state.uri.path, AppRoutes.home);
        });
      });
    });

    testWidgets('go away on a pushed page and come back with it', (tester) async {
      await pumpKaneoApp(tester, size: narrowSize);
      await tester.tap(inPage(find.text('Demo')));
      await tester.pumpAndSettle();
      expectNarrowWithoutTabs();
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expectNarrowWithTabs();
    });

    testWidgets('a phone on its side keeps the page clear of the notch', (tester) async {
      tester.view.padding = const FakeViewPadding(left: 47, right: 47, bottom: 21);
      addTearDown(tester.view.resetPadding);
      await pumpKaneoApp(tester, size: narrowSize.flipped);
      final page = tester.getRect(find.byKey(shellPageKey));
      expect(page.left, 47);
      expect(page.right, narrowSize.height - 47);
      final tabs = tester.getBottomLeft(find.text('Home').last);
      expect(tabs.dx, greaterThanOrEqualTo(47));
      expect(tabs.dy, lessThanOrEqualTo(narrowSize.width - 21));
    });
  });

  group('where the sidebar is absent', () {
    testWidgets('the home page leads to search and the account', (tester) async {
      final app = await pumpKaneoApp(tester, size: narrowSize);
      final router = app.container.read(routerProvider);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.search);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.account);
      expect(find.text(FakeKaneo.email), findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.home);
    });

    testWidgets('wide windows leave those to the sidebar', (tester) async {
      await pumpKaneoApp(tester, size: wideSize);
      expect(inPage(find.byTooltip('Search')), findsNothing);
      expect(inPage(find.byTooltip('Account')), findsNothing);
    });
  });

  group('reading pages', () {
    const pages = [
      AppRoutes.account,
      AppRoutes.inbox,
      AppRoutes.myTasks,
      AppRoutes.activity,
      AppRoutes.search,
    ];
    Finder content() =>
        find.descendant(of: find.byType(ContentWidth), matching: find.byType(ConstrainedBox)).first;

    for (final location in pages) {
      testWidgets('$location stops growing on wide windows and is centered', (tester) async {
        await pumpKaneoApp(tester, size: const Size(1920, 1080), location: location);
        final rect = tester.getRect(content());
        final page = tester.getRect(find.byKey(shellPageKey));
        expect(rect.width, contentMaxWidth);
        expect(rect.center.dx, closeTo(page.center.dx, 0.5));
      });

      testWidgets('$location fills narrow windows', (tester) async {
        await pumpKaneoApp(tester, size: narrowSize, location: location);
        expect(tester.getRect(content()).width, narrowSize.width);
      });
    }

    testWidgets('a window too small for the limit is simply filled', (tester) async {
      await pumpKaneoApp(tester, size: const Size(800, 800), location: AppRoutes.account);
      final page = tester.getRect(find.byKey(shellPageKey));
      expect(tester.getRect(content()).width, page.width);
    });

    testWidgets('the account page has no way back on wide windows and one on narrow', (
      tester,
    ) async {
      await pumpKaneoApp(tester, size: wideSize);
      await tester.tap(inSidebar(find.text('Account')));
      await tester.pumpAndSettle();
      expect(backButton, findsNothing);
      await resize(tester, narrowSize);
      expect(backButton, findsOneWidget);
    });

    testBothLayouts('the account page is a real page now', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size, location: AppRoutes.account);
      expect(find.text(app.i18n.t('app:placeholder.notice')), findsNothing);
      expect(find.text('Test User'), findsOneWidget);
      expect(find.byKey(const ValueKey('language')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:account.signOut.button')), findsOneWidget);
    });
  });

  group('project icons', () {
    test('every name the web app offers has an icon of its own', () {
      expect(projectIcon('Rocket'), LucideIcons.rocket);
      expect(projectIcon('Home'), LucideIcons.house);
      expect(projectIcon('Wand2'), LucideIcons.wandSparkles);
      expect(projectIcon('Tool'), LucideIcons.penTool);
    });

    test('a missing or unknown name gets the default', () {
      expect(projectIcon(null), LucideIcons.layout);
      expect(projectIcon('NoLongerExists'), LucideIcons.layout);
    });
  });
}
