// Local-only D-platform acceptance. Run through tool/with_device.sh with dev.env.
// Uses the real login UI, HTTP, authenticated sockets and account-scoped disk cache.
// Screenshots contain no credentials and stay outside the repository.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/auth/login_page.dart';
import 'package:kaneo_app/features/task/task_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../test/platform/local_desktop_fixture.dart';

Future<void> _until(
  WidgetTester tester,
  String step,
  bool Function() ready, {
  int seconds = 30,
}) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < Duration(seconds: seconds)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: step);
  debugPrint('D_RESULT $step PASS ${watch.elapsedMilliseconds}ms');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('API key board, realtime, inbox and account isolation on local Kaneo', (
    tester,
  ) async {
    final config = DevConfig.fromEnvironment();
    expect(config.isConfigured, isTrue);
    expect(['localhost', '127.0.0.1'].contains(Uri.parse(config.serverUrl).host), isTrue);
    final base = await bootstrap(sessionStorage: MemorySessionStorage());
    final prefs = base.read(prefsProvider);
    final i18n = await I18n.load(locale: defaultLocale);
    final previousNotifications = prefs.getBool(notificationChecksEnabledKey);
    final previousWorkspace = prefs.getString('kaneo.lastWorkspaceId');
    await prefs.setBool(notificationChecksEnabledKey, false);
    final fixture = await createDesktopFixture(i18n);
    final project = fixture.project;
    final columns = await fixture.ownerApi.columns(project.id);
    final task = await fixture.ownerApi.createTask(
      project.id,
      CreateTaskBody(
        title: 'D API Key board',
        description: '',
        priority: 'no-priority',
        status: columns.first.slug,
      ),
    );
    final privateSpace = await fixture.ownerApi.createWorkspace(
      name: 'D-Private-${project.id}',
      slug: 'd-private-${project.id}',
    );
    addTearDown(() => fixture.ownerApi.deleteWorkspace(privateSpace.id));
    final cacheRoot = await Directory.systemTemp.createTemp('D-auth-cache-');
    final storage = MemorySessionStorage();
    final opened = <String>{};
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        i18nProvider.overrideWithValue(i18n),
        devConfigProvider.overrideWithValue(const DevConfig()),
        sessionStorageProvider.overrideWithValue(storage),
        cacheRootProvider.overrideWithValue(cacheRoot),
        realtimeSocketProvider.overrideWithValue((session, path) {
          final channel = connectAuthenticatedSocket(
            session,
            path,
            pingInterval: realtimePingInterval,
          );
          channel.ready.then(
            (_) => opened.add('${session.credentialType.name}:$path'),
            onError: (Object _) {},
          );
          return channel;
        }),
      ],
    );
    base.dispose();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      if (await cacheRoot.exists()) await cacheRoot.delete(recursive: true);
      if (previousNotifications == null) {
        await prefs.remove(notificationChecksEnabledKey);
      } else {
        await prefs.setBool(notificationChecksEnabledKey, previousNotifications);
      }
      if (previousWorkspace == null) {
        await prefs.remove('kaneo.lastWorkspaceId');
      } else {
        await prefs.setString('kaneo.lastWorkspaceId', previousWorkspace);
      }
    });
    if (Platform.isMacOS) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1366, 1024));
    }
    final capture = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: capture, child: const KaneoApp()),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final root = await getApplicationDocumentsDirectory();
      final directory = await Directory('${root.path}/D-KAN-51/${Platform.operatingSystem}')
          .create(recursive: true);
      final file = File('${directory.path}/$name.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('D_SCREENSHOT ${file.path}');
    }

    Future<void> submitLogin() async {
      await tester.ensureVisible(find.byKey(const ValueKey('login-submit')));
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await _until(
        tester,
        'login',
        () =>
            container.read(sessionProvider) != null ||
            find.byKey(const ValueKey('login-error')).evaluate().isNotEmpty,
      );
      expect(container.read(sessionProvider) != null, isTrue, reason: 'Login failed');
      await _until(tester, 'workspace list', () => container.read(workspacesQuery).hasValue);
    }

    Future<void> logout() async {
      container.read(routerProvider).go(AppRoutes.account);
      await tester.pumpAndSettle();
      final label = i18n.t('mobile:account.signOut.button');
      await tester.tap(find.widgetWithText(OutlinedButton, label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, label));
      await _until(tester, 'logout', () => find.byType(LoginPage).evaluate().isNotEmpty);
      expect(await storage.read(), isNull);
    }

    await shot('01-password-login');
    await tester.tap(find.text(i18n.t('mobile:signIn.apiKey.label')));
    await shot('02-api-key-login');
    await tester.enterText(find.byKey(const ValueKey('login-server')), '${config.serverUrl}/api/');
    await tester.enterText(find.byKey(const ValueKey('login-api-key')), config.apiKey);
    await submitLogin();
    expect(container.read(sessionProvider)!.credentialType, CredentialType.apiKey);
    expect(
      container.read(workspacesQuery).requireValue.any((w) => w.id == privateSpace.id),
      isTrue,
    );
    final ownerCache = container.read(cacheStoreProvider);
    await container.read(selectedWorkspaceIdProvider.notifier).select(project.workspaceId);
    container.read(routerProvider).go(AppRoutes.board(project.id));
    final card = find.byKey(ValueKey('board-card-${task.id}'));
    await _until(tester, 'API key board', () => card.evaluate().isNotEmpty);
    await _until(
      tester,
      'API key sockets',
      () =>
          opened.contains('apiKey:api/ws/user') &&
          opened.any((path) => path.startsWith('apiKey:api/ws/project/')),
    );
    await fixture.ownerApi.updateStatus(task.id, columns[1].slug);
    await fixture.ownerApi.updateTitle(task.id, 'D Updated by another client');
    await _until(
      tester,
      'API key board realtime',
      () =>
          find
              .descendant(
                of: find.byKey(ValueKey('drop-column-${columns[1].slug}')),
                matching: card,
              )
              .evaluate()
              .isNotEmpty &&
          find.text('D Updated by another client').evaluate().isNotEmpty,
      seconds: 5,
    );
    await shot('03-api-key-board-realtime');
    container.read(routerProvider).go(AppRoutes.inbox);
    final inbox = notificationsQuery(project.workspaceId);
    await _until(tester, 'initial inbox', () => container.read(inbox).hasValue);
    final assigned = await fixture.actorApi.createTask(
      project.id,
      CreateTaskBody(
        title: 'D Assigned by another account',
        description: '',
        priority: 'no-priority',
        status: columns.first.slug,
        userId: fixture.owner.userId,
      ),
    );
    await _until(
      tester,
      'API key live notification',
      () =>
          container.read(inbox).value?.any((n) => n.resourceId == assigned.id) == true &&
          find.text(assigned.title).evaluate().isNotEmpty,
      seconds: 5,
    );
    final notification = container
        .read(inbox)
        .requireValue
        .firstWhere((n) => n.resourceId == assigned.id);
    await shot('04-api-key-inbox');
    await tester.tap(find.byKey(ValueKey(notification.id)));
    await _until(
      tester,
      'notification opens assigned task',
      () =>
          find.byType(TaskPage).evaluate().isNotEmpty &&
          tester.widget<TaskPage>(find.byType(TaskPage)).taskId == assigned.id &&
          find.text(assigned.title).evaluate().isNotEmpty,
    );
    await shot('05-notification-task');
    await logout();
    expect(await ownerCache.read('workspaces'), isNull);
    expect(await ownerCache.read('board/${project.id}'), isNull);
    expect(await ownerCache.read('notifications/${project.workspaceId}'), isNull);
    await tester.enterText(find.byKey(const ValueKey('login-server')), config.serverUrl);
    await tester.enterText(find.byKey(const ValueKey('login-email')), fixture.actor.userEmail);
    await tester.enterText(find.byKey(const ValueKey('login-password')), fixture.actorPassword);
    await submitLogin();
    expect(container.read(sessionProvider)!.userId == fixture.actor.userId, isTrue);
    expect(container.read(sessionProvider)!.credentialType, CredentialType.bearer);
    expect(
      container.read(workspacesQuery).requireValue.any((w) => w.id == privateSpace.id),
      isFalse,
    );
    await container.read(selectedWorkspaceIdProvider.notifier).select(project.workspaceId);
    container.read(routerProvider).go(AppRoutes.inbox);
    await _until(tester, 'second account inbox', () => container.read(inbox).hasValue);
    expect(container.read(inbox).requireValue.any((n) => n.id == notification.id), isFalse);
    expect(find.text(assigned.title), findsNothing);
    await shot('06-second-account-inbox');
    await logout();
    await shot('07-logged-out');
  });
}
