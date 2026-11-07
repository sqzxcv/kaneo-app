// Run on macOS with the D line's fixed signed test bundle ID and private dev.env defines.
// Creates only its own D- workspace/project and temporary local account, then removes them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/shell/app_sidebar.dart';
import 'package:kaneo_app/features/task/task_page.dart';
import 'package:window_manager/window_manager.dart';

class RecordingDesktopHost extends NativeDesktopHost {
  final shown = <({int id, String payload})>[];
  void Function(String?)? tap;

  @override
  Future<void> initializeNotifications(void Function(String?) onTap, String actionLabel) async {
    tap = onTap;
    await super.initializeNotifications(onTap, actionLabel);
  }

  @override
  Future<void> showNotice({
    required int id,
    required String title,
    String? body,
    required String payload,
  }) async {
    await super.showNotice(id: id, title: title, body: body, payload: payload);
    shown.add((id: id, payload: payload));
  }
}

Future<void> until(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: 'Timed out waiting for desktop state.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop window minimum and native notifications from local Kaneo', (tester) async {
    expect(Platform.isMacOS, isTrue);
    final config = DevConfig.fromEnvironment();
    expect(config.isConfigured, isTrue);
    expect(['localhost', '127.0.0.1'].contains(Uri.parse(config.serverUrl).host), isTrue);
    final base = await bootstrap(sessionStorage: MemorySessionStorage());
    final prefs = base.read(prefsProvider);
    final previous = prefs.getBool(notificationChecksEnabledKey);
    await prefs.setBool(notificationChecksEnabledKey, false);
    final host = RecordingDesktopHost();
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        i18nProvider.overrideWithValue(base.read(i18nProvider)),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
        desktopHostProvider.overrideWithValue(host),
      ],
    );
    base.dispose();
    addTearDown(() async {
      container.dispose();
      if (previous == null) {
        await prefs.remove(notificationChecksEnabledKey);
      } else {
        await prefs.setBool(notificationChecksEnabledKey, previous);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KaneoApp()),
    );
    await until(tester, () => container.read(sessionProvider) != null && host.tap != null);
    await container.read(selectedWorkspaceIdProvider.notifier).select(config.workspaceId);
    await windowManager.setSize(minimumDesktopWindowSize);
    await tester.pump(const Duration(seconds: 1));
    final context = tester.element(find.byType(AppSidebar));
    expect(MediaQuery.sizeOf(context).shortestSide, greaterThanOrEqualTo(600));
    expect(find.byType(NavigationBar), findsNothing);
    debugPrint('Desktop minimum window and wide layout passed.');

    final permission = await host.requestNotificationPermission();
    expect(
      permission,
      isTrue,
      reason: 'Grant notifications to the DTest app in macOS System Settings, then rerun.',
    );
    await container.read(notificationChecksEnabledProvider.notifier).setEnabled(true);
    await tester.pump(const Duration(seconds: 1));
    final runtime = container.read(desktopRuntimeProvider(container.read(routerProvider)))!;
    await runtime.check();
    final i18n = container.read(i18nProvider);
    final auth = container.read(authenticationProvider);
    final owner = await auth.withPassword(
      config.serverUrl,
      const String.fromEnvironment('KANEO_DEV_EMAIL'),
      const String.fromEnvironment('KANEO_DEV_PASSWORD'),
    );
    final ownerClient = ApiClient(session: () => owner, i18n: i18n, onSessionExpired: (_) {});
    final ownerApi = KaneoApi(ownerClient, i18n);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final workspace = await ownerApi.createWorkspace(
      name: 'D-Desktop-$stamp',
      slug: 'd-desktop-$stamp',
    );
    addTearDown(() async {
      await ownerApi.deleteWorkspace(workspace.id);
      await ownerApi.signOut();
    });
    final project = await ownerApi.createProject(
      name: 'D-Desktop-$stamp',
      workspaceId: workspace.id,
      icon: 'Layout',
      slug: 'D${stamp.toUpperCase()}',
    );
    // Project deletion also removes only the tasks created by this test.
    addTearDown(() => ownerApi.deleteProject(project.id));
    final email = 'd-desktop-$stamp@example.invalid';
    final password = 'D-test-$stamp-password';
    final anonymous = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
    await anonymous.request(
      'api/auth/sign-up/email',
      serverUrl: config.serverUrl,
      method: 'POST',
      body: {'name': 'D desktop test', 'email': email, 'password': password},
    );
    final second = await Authentication(
      anonymous,
      i18n,
    ).withPassword(config.serverUrl, email, password);
    final secondApi = KaneoApi(
      ApiClient(session: () => second, i18n: i18n, onSessionExpired: (_) {}),
      i18n,
    );
    addTearDown(() => secondApi.deleteUser(password: password));
    await ownerApi.inviteMember(organizationId: workspace.id, email: email, role: 'member');
    final invitation = (await secondApi.pendingInvitations()).firstWhere(
      (i) => i.workspaceId == workspace.id,
    );
    await secondApi.acceptInvitation(invitation.id);
    await runtime.check();
    host.shown.clear();
    final task = await secondApi.createTask(
      project.id,
      CreateTaskBody(
        title: 'D-Desktop notification test',
        description: '',
        priority: 'no-priority',
        status: 'to-do',
        userId: owner.userId,
      ),
    );
    await runtime.check();
    await until(tester, () => host.shown.isNotEmpty);
    final delivered = await FlutterLocalNotificationsPlugin().getActiveNotifications();
    expect(
      delivered.any((n) => n.id == host.shown.last.id),
      isTrue,
      reason: 'The native notification was not delivered.',
    );
    // This exercises the OS callback's registered handler. Clicking the system banner itself is
    // left for manual acceptance; widget tests cover this handler in both layouts.
    host.tap!(host.shown.last.payload);
    await until(tester, () => find.byType(TaskPage).evaluate().isNotEmpty);
    expect(tester.widget<TaskPage>(find.byType(TaskPage)).taskId, task.id);
    await container.read(notificationChecksEnabledProvider.notifier).setEnabled(false);
    await tester.pump(const Duration(milliseconds: 500));
    expect((await FlutterLocalNotificationsPlugin().getActiveNotifications()).isEmpty, isTrue);
  });
}
