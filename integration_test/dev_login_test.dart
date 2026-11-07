// Starts the real app against the local Kaneo, signs in with dev.env and opens every placeholder
// page. Needs `tool/local_kaneo.sh start` and a device from the queue:
//
//     tool/with_device.sh --boot "iPhone 17" flutter test integration_test -d "iPhone 17" \
//       --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//     tool/with_device.sh flutter test integration_test -d macos \
//       --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/auth/login_page.dart';

/// Pumps until [finder] matches. The server is real, so `pumpAndSettle` alone is not enough.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('developer sign-in opens every page and loads real data', (tester) async {
    final config = DevConfig.fromEnvironment();
    expect(config.isConfigured, isTrue, reason: 'Pass dev.env with --dart-define-from-file.');

    final container = await bootstrap(sessionStorage: MemorySessionStorage());
    addTearDown(container.dispose);
    await container.read(languageChoiceProvider.notifier).select(defaultLocale);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KaneoApp()),
    );

    // Signs in by itself and lands on the home page, which lists the seeded projects.
    final api = container.read(kaneoApiProvider);
    await waitFor(tester, find.text('Demo'));
    final session = container.read(sessionProvider)!;
    expect(session.credentialType, CredentialType.apiKey);
    expect(session.token, config.apiKey);

    final projects = await api.projects(config.workspaceId);
    expect(projects.map((p) => p.name), containsAll(['Demo', 'Second project']));
    // Once on the page, and once more in the sidebar on wide windows.
    expect(find.text('Second project'), findsWidgets);

    final router = container.read(routerProvider);
    final notice = find.text(container.read(i18nProvider).t('app:placeholder.notice'));

    // The board, from the server.
    router.push(AppRoutes.board(config.projectId));
    final board = await loadFullBoard(api, config.projectId);
    await waitFor(tester, find.text(board.name));
    expect(board.columns.map((c) => c.name), containsAll(['To Do', 'Done']));
    final firstTask = board.columns.expand((c) => c.tasks!).first;
    await waitFor(tester, find.text(firstTask.title));
    router.pop();
    await tester.pump(const Duration(milliseconds: 500));

    // A task.
    router.push(AppRoutes.task(firstTask.id));
    await waitFor(tester, find.text(firstTask.title));
    router.pop();
    await tester.pump(const Duration(milliseconds: 500));

    // The new-task page.
    router.push(AppRoutes.newTask(projectId: config.projectId));
    await waitFor(tester, find.text(container.read(i18nProvider).t('mobile:board.newTask')));
    router.pop();
    await tester.pump(const Duration(milliseconds: 500));

    // The other pages of the shell.
    router.go(AppRoutes.inbox);
    await waitFor(tester, find.text(container.read(i18nProvider).t('mobile:nav.inbox')));
    await waitFor(tester, notice);
    await tester.pump(const Duration(seconds: 1));

    final assigned = await api.assignedTasks(config.workspaceId);
    expect(assigned.tasks, isNotEmpty);
    router.go(AppRoutes.myTasks);
    await waitFor(tester, find.text(assigned.tasks.first.title));

    final activity = await api.workspaceActivity(config.workspaceId);
    expect(activity, isNotEmpty);
    router.go(AppRoutes.activity);
    await waitFor(tester, find.text(activity.first.taskTitle));

    router.go(AppRoutes.search);
    await waitFor(tester, find.byKey(const ValueKey('search-field')));
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'board');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(tester, find.text('Review the board layout'));

    router.go(AppRoutes.account);
    await waitFor(tester, find.text(session.userEmail));

    // A failure other than 401 is shown in place, as something readable.
    router.push(AppRoutes.board('does-not-exist'));
    await waitFor(tester, find.text(container.read(i18nProvider).t('mobile:ui.loadFailed')));
    expect(find.byType(LoginPage), findsNothing);
    expect(container.read(sessionProvider), isNotNull);
    router.pop();
    await tester.pump(const Duration(milliseconds: 500));

    // Switching language on a running app, with plurals.
    await container.read(languageChoiceProvider.notifier).select('zh-CN');
    await tester.pump(const Duration(milliseconds: 500));
    router.push(AppRoutes.board(config.projectId));
    await waitFor(tester, find.text('${board.columns.length} 列'));
    router.pop();
    await tester.pump(const Duration(milliseconds: 500));
    await container.read(languageChoiceProvider.notifier).select(defaultLocale);

    // A key the server rejects returns to the login page.
    await container
        .read(sessionProvider.notifier)
        .signIn(
          Session(
            serverUrl: session.serverUrl,
            credentialType: CredentialType.apiKey,
            token: 'not-a-real-key',
            userId: session.userId,
            userName: session.userName,
            userEmail: session.userEmail,
          ),
        );
    // The home page stays open under the others, so it is the inbox that sends the next request.
    router.go(AppRoutes.inbox);
    await waitFor(tester, find.byType(LoginPage));
    expect(container.read(sessionProvider), isNull);
  });
}
