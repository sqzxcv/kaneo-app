import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/auth/login_page.dart';
import 'package:kaneo_app/features/shell/app_sidebar.dart';
import 'package:kaneo_app/features/task/open_task.dart';

import '../support/test_app.dart';

/// Every phase-one page, with something it shows when its data arrives.
final Map<String, Finder> _pages = {
  AppRoutes.home: find.text('Demo'),
  AppRoutes.inbox: find.text('Assigned to you'),
  AppRoutes.myTasks: find.text('Set up the project'),
  AppRoutes.activity: find.text('Set up the project'),
  AppRoutes.search: find.byKey(const ValueKey('search-field')),
  AppRoutes.account: find.text(FakeKaneo.email),
  AppRoutes.board(FakeKaneo.projectId): find.text('Fix the drag preview'),
  AppRoutes.task('task-2'): find.text('Write the first description'),
  AppRoutes.newTask(projectId: FakeKaneo.projectId): find.text('New task'),
};

void main() {
  group('every route opens a page', () {
    _pages.forEach((location, shows) {
      testBothLayouts(location, (tester, size) async {
        await pumpKaneoApp(tester, size: size, location: location);
        expect(shows, findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('navigation', () {
    testBothLayouts('the tabs switch pages', (tester, size) async {
      await pumpKaneoApp(tester, size: size);
      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned to you'), findsOneWidget);
    });

    testBothLayouts('a project opens its board, and a task opens from there', (tester, size) async {
      await pumpKaneoApp(tester, size: size);
      await tester.tap(inPage(find.text('Demo')));
      await tester.pumpAndSettle();
      expect(find.text('To Do'), findsOneWidget);
      expect(find.text('1 task'), findsNWidgets(2));
      expect(find.text('2 tasks'), findsNWidgets(2));

      await tester.ensureVisible(find.text('Set up the project'));
      await tester.tap(find.text('Set up the project'));
      await tester.pumpAndSettle();
      expect(find.text('Task'), findsOneWidget);
    });

    testBothLayouts('openTask and openNewTask go through the shared entry points', (
      tester,
      size,
    ) async {
      final app = await pumpKaneoApp(tester, size: size);
      final router = app.container.read(routerProvider);
      final context = tester.element(find.byType(Scaffold).last);

      openTask(context, 'task-1', projectId: FakeKaneo.projectId);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/task/task-1');
      expect(find.text('Set up the project'), findsWidgets);

      router.pop();
      await tester.pumpAndSettle();
      openNewTask(tester.element(find.byType(Scaffold).last), projectId: 'p1', status: 'done');
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/task/new?projectId=p1&status=done');
    });

    testBothLayouts('`new` is not read as a task id', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.newTask());
      expect(server.requestsTo('api/task/new'), isEmpty);
    });

    testBothLayouts('search finds tasks', (tester, size) async {
      await pumpKaneoApp(tester, size: size, location: AppRoutes.search);
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'board');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Review the board layout'), findsOneWidget);
    });
  });

  group('signing in and out', () {
    testBothLayouts('without a session every page goes to the login page', (tester, size) async {
      await pumpKaneoApp(tester, size: size, session: null, location: AppRoutes.inbox);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Assigned to you'), findsNothing);
    });

    testBothLayouts('the login page has no developer button without a config', (
      tester,
      size,
    ) async {
      await pumpKaneoApp(tester, size: size, session: null);
      expect(find.text('Developer sign-in'), findsNothing);
    });

    testBothLayouts('with a config the app signs in by itself and opens the home page', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        session: null,
        devConfig: const DevConfig(serverUrl: FakeKaneo.serverUrl, apiKey: FakeKaneo.apiKey),
      );
      expect(app.container.read(sessionProvider)?.token, FakeKaneo.apiKey);
      expect(inPage(find.text('Demo')), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    testBothLayouts('a wrong developer key stays on the login page and says why', (
      tester,
      size,
    ) async {
      await pumpKaneoApp(
        tester,
        size: size,
        session: null,
        devConfig: const DevConfig(serverUrl: FakeKaneo.serverUrl, apiKey: 'wrong'),
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Unauthorized'), findsOneWidget);
      expect(find.text('Developer sign-in'), findsOneWidget);
    });

    testBothLayouts('the developer button signs in', (tester, size) async {
      final server = FakeKaneo()..failNext('api/user/me', status: 500);
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        session: null,
        devConfig: const DevConfig(serverUrl: FakeKaneo.serverUrl, apiKey: FakeKaneo.apiKey),
      );
      expect(find.byType(LoginPage), findsOneWidget);
      await tester.tap(find.text('Developer sign-in'));
      await tester.pumpAndSettle();
      expect(inPage(find.text('Demo')), findsOneWidget);
    });

    testBothLayouts('signing out from the account page goes to the login page', (
      tester,
      size,
    ) async {
      final storage = MemorySessionStorage(testSession);
      final app = await pumpKaneoApp(
        tester,
        size: size,
        sessionStorage: storage,
        location: AppRoutes.account,
      );
      final signOut = app.i18n.t('mobile:account.signOut.button');
      await tester.tap(find.text(signOut));
      await tester.pumpAndSettle();
      await tester.tap(find.text(signOut).last);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(await storage.read(), isNull);
    });

    testBothLayouts('a signed-in person cannot stay on the login page', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size);
      app.container.read(routerProvider).go(AppRoutes.login);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(inPage(find.text('Demo')), findsOneWidget);
    });
  });

  group('a 401 returns to the login page', () {
    final pages = {
      AppRoutes.home,
      AppRoutes.inbox,
      AppRoutes.myTasks,
      AppRoutes.activity,
      AppRoutes.board(FakeKaneo.projectId),
      AppRoutes.task('task-1'),
    };
    for (final location in pages) {
      testBothLayouts('from $location', (tester, size) async {
        final server = FakeKaneo()..credentialsRevoked = true;
        final storage = MemorySessionStorage(testSession);
        final app = await pumpKaneoApp(
          tester,
          server: server,
          size: size,
          sessionStorage: storage,
          location: location,
        );
        expect(find.byType(LoginPage), findsOneWidget);
        expect(app.container.read(sessionProvider), isNull);
        expect(await storage.read(), isNull);
      });
    }

    testBothLayouts('and says the session expired', (tester, size) async {
      final server = FakeKaneo()..credentialsRevoked = true;
      final app = await pumpKaneoApp(tester, server: server, size: size, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(app.i18n.t('mobile:errors.sessionExpired')), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testBothLayouts('also from a key revoked while the app is open', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size);
      expect(inPage(find.text('Demo')), findsOneWidget);

      server.credentialsRevoked = true;
      await tester.tap(inPage(find.text('Demo')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('other errors show something readable', () {
    final cases = {500: 'The server had a problem', 404: 'Project not found'};
    cases.forEach((status, message) {
      testBothLayouts('$status on the board', (tester, size) async {
        final server = FakeKaneo()
          ..fail('api/task/tasks/', status: status, body: {'message': message});
        final app = await pumpKaneoApp(
          tester,
          server: server,
          size: size,
          location: AppRoutes.board(FakeKaneo.projectId),
        );
        expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(find.byType(LoginPage), findsNothing);
        expect(app.container.read(sessionProvider), isNotNull);
      });
    });

    testBothLayouts('a server error without a message', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/tasks/', status: 503);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      expect(find.text(app.i18n.t('mobile:errors.serverProblem', {'status': 503})), findsOneWidget);
    });

    testBothLayouts('an unreachable server, in Chinese', (tester, size) async {
      final server = FakeKaneo()..unreachable = true;
      final app = await pumpKaneoApp(tester, server: server, size: size, locale: 'zh-CN');
      expect(find.text(app.i18n.t('mobile:errors.unreachable')), findsOneWidget);
      expect(app.i18n.t('mobile:errors.unreachable'), isNot(contains('mobile:')));
      expect(find.textContaining('DioException'), findsNothing);
    });

    testBothLayouts('retry loads the page once the server is back', (tester, size) async {
      final server = FakeKaneo()..failNext('api/task/tasks/', status: 500);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(find.text('Fix the drag preview'), findsWidgets);
    });

    testBothLayouts('no permission reads as that, with no retry', (tester, size) async {
      final server = FakeKaneo()..fail('api/task/tasks/', status: 403);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
    });
  });

  group('loading and empty states', () {
    testBothLayouts('a page shows progress while it loads', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold('api/workspace');
      await pumpKaneoApp(tester, server: server, size: size, settle: false);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(inPage(find.text('Demo')), findsOneWidget);
    });

    testBothLayouts('a workspace with no projects', (tester, size) async {
      final app = await pumpKaneoApp(tester, server: FakeKaneo.empty(), size: size);
      expect(find.text(app.i18n.t('mobile:home.empty.title')), findsOneWidget);
    });

    testBothLayouts('an account with no workspace', (tester, size) async {
      final server = FakeKaneo()..workspaces.clear();
      final app = await pumpKaneoApp(tester, server: server, size: size);
      expect(find.text(app.i18n.t('mobile:home.noWorkspace.title')), findsOneWidget);
    });

    testBothLayouts('an empty inbox', (tester, size) async {
      final server = FakeKaneo.empty();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      expect(find.text(app.i18n.t('mobile:inbox.empty.title')), findsOneWidget);
    });

    testBothLayouts('no tasks assigned', (tester, size) async {
      final server = FakeKaneo.empty();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.myTasks);
      expect(find.text('Set up the project'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('no activity', (tester, size) async {
      final server = FakeKaneo.empty();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.activity,
      );
      expect(find.text(app.i18n.t('mobile:activity.empty')), findsOneWidget);
    });
  });

  group('switching language', () {
    Future<void> pickLanguage(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const ValueKey('language')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text(name),
        find.byType(Scrollable).last,
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
    }

    testBothLayouts('changes every string on screen, and the plural forms', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size, location: AppRoutes.account);
      expect(find.text('Account'), findsWidgets);

      await pickLanguage(tester, '简体中文');
      expect(app.i18n.locale, 'zh-CN');
      expect(find.text(app.i18n.t('mobile:account.title')), findsWidgets);
      expect(app.i18n.t('mobile:account.title'), isNot('Account'));
      expect(find.text('Account'), findsNothing);
      expect(find.text('Sign out'), findsNothing);
      expect(find.text('Home'), findsNothing);

      app.container.read(routerProvider).push(AppRoutes.board(FakeKaneo.projectId));
      await tester.pumpAndSettle();
      expect(find.text('4 列'), size == wideSize ? findsOneWidget : findsNothing);
      expect(find.text('2 个任务'), findsNWidgets(2));
      expect(find.text('1 个任务'), findsNWidgets(2));
      expect(find.textContaining('tasks'), findsNothing);
    });

    testBothLayouts('English gets English plurals back', (tester, size) async {
      final app = await pumpKaneoApp(
        tester,
        size: size,
        location: AppRoutes.account,
        locale: 'zh-CN',
        preferences: {'kaneo.language': 'zh-CN'},
      );
      await tester.runAsync(
        () => app.container.read(languageChoiceProvider.notifier).select('en-US'),
      );
      await tester.pumpAndSettle();
      app.container.read(routerProvider).push(AppRoutes.board(FakeKaneo.projectId));
      await tester.pumpAndSettle();
      expect(find.text('4 columns'), size == wideSize ? findsOneWidget : findsNothing);
      expect(find.text('1 task'), findsNWidgets(2));
      expect(find.text('2 tasks'), findsNWidgets(2));
    });

    testBothLayouts('the choice is remembered', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size, location: AppRoutes.account);
      await pickLanguage(tester, '简体中文');
      expect(app.container.read(prefsProvider).getString('kaneo.language'), 'zh-CN');
    });

    testBothLayouts('Simplified Chinese account page has no Danger zone or Delete account', (
      tester,
      size,
    ) async {
      await pumpKaneoApp(tester, size: size, location: AppRoutes.account, locale: 'zh-CN');
      expect(find.textContaining('Danger zone'), findsNothing);
      expect(find.textContaining('Delete account'), findsNothing);
    });

    testBothLayouts('Material widgets follow the language too', (tester, size) async {
      final app = await pumpKaneoApp(tester, size: size, locale: 'zh-CN');
      final context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context).languageCode, 'zh');
      expect(MaterialLocalizations.of(context).okButtonLabel, isNot('OK'));
      expect(app.i18n.locale, 'zh-CN');
    });

    for (final locale in supportedLocales.keys) {
      testWidgets('$locale runs without errors', (tester) async {
        await pumpKaneoApp(tester, locale: locale, location: AppRoutes.account);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('mobile:'), findsNothing);
        expect(find.textContaining('settings:'), findsNothing);
        expect(find.textContaining('app:'), findsNothing);
      });
    }
  });

  testWidgets('a pushed board keeps the shell and can go back', (tester) async {
    final app = await pumpKaneoApp(tester, size: wideSize);
    final router = app.container.read<GoRouter>(routerProvider);
    router.push(AppRoutes.board(FakeKaneo.projectId));
    await tester.pumpAndSettle();
    expect(find.byType(AppSidebar), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.home);
  });
}
