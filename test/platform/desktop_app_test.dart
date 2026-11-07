import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/shell/app_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';
import 'fake_desktop_host.dart';

Future<({ProviderContainer container, FakeKaneo server, FakeDesktopHost host})> desktopApp(
  WidgetTester tester,
  Size size, {
  bool enabled = true,
  Session? session = testSession,
  FakeKaneo? server,
}) async {
  setWindowSize(tester, size);
  SharedPreferences.setMockInitialValues({notificationChecksEnabledKey: enabled});
  final i18n = await loadTestI18n(tester);
  final host = FakeDesktopHost();
  final fake = server ?? FakeKaneo();
  final overrides = [
    prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
    i18nProvider.overrideWithValue(i18n),
    sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
    initialSessionProvider.overrideWithValue(session),
    httpAdapterProvider.overrideWithValue(fake),
    realtimeSocketProvider.overrideWithValue(fake.connectSocket),
    isDesktopProvider.overrideWithValue(true),
    desktopHostProvider.overrideWithValue(host),
  ];
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: const KaneoApp()));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(KaneoApp)));
  return (container: container, server: fake, host: host);
}

Future<void> checkDesktop(WidgetTester tester, DesktopRuntime runtime) async {
  var completed = false;
  final pending = runtime.check().whenComplete(() => completed = true);
  for (var i = 0; i < 100 && !completed; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(completed, isTrue, reason: 'Desktop check did not finish');
  await pending;
}

void main() {
  testWidgets('desktop minimum size still renders the wide sidebar', (tester) async {
    final app = await desktopApp(tester, minimumDesktopWindowSize);
    expect(app.host.size, minimumDesktopWindowSize);
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('desktop notifications show new activity and route clicks through openTask', (
    tester,
    size,
  ) async {
    final app = await desktopApp(tester, size);
    expect(app.host.notices, isEmpty);
    app.server.addNotification(title: 'New desktop activity', resourceId: 'task-1');
    final router = app.container.read(routerProvider);
    await checkDesktop(tester, app.container.read(desktopRuntimeProvider(router))!);
    expect(app.host.notices.single.title, 'New desktop activity');
    app.host.onTap!(app.host.notices.single.payload);
    await tester.pumpAndSettle();
    expect(inPage(find.text('Set up the project')), findsOneWidget);
    expect(app.host.foregrounds, 1);
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('desktop notification opt-out stops checks and clears visible notices', (
    tester,
    size,
  ) async {
    final app = await desktopApp(tester, size);
    app.server.addNotification(title: 'New desktop activity', resourceId: 'task-1');
    final router = app.container.read(routerProvider);
    final runtime = app.container.read(desktopRuntimeProvider(router))!;
    await checkDesktop(tester, runtime);
    final payload = app.host.notices.single.payload;
    await app.container.read(notificationChecksEnabledProvider.notifier).setEnabled(false);
    await tester.pumpAndSettle();
    final count = app.server.requestsTo('api/notification').length;
    await checkDesktop(tester, runtime);
    app.host.onTap!(payload);
    await tester.pumpAndSettle();
    expect(app.server.requestsTo('api/notification'), hasLength(count));
    expect(app.host.notices, isEmpty);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);
  });

  testBothLayouts('desktop sign-out rejects a stale system notification click', (
    tester,
    size,
  ) async {
    final app = await desktopApp(tester, size);
    app.server.addNotification(title: 'Old account notification', resourceId: 'task-1');
    final router = app.container.read(routerProvider);
    await checkDesktop(tester, app.container.read(desktopRuntimeProvider(router))!);
    final payload = app.host.notices.single.payload;
    await app.container.read(sessionProvider.notifier).signOut();
    await tester.pumpAndSettle();
    app.host.onTap!(payload);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
    expect(app.host.notices, isEmpty);
  });

  testBothLayouts('empty notifications and failed checks leave the current page usable', (
    tester,
    size,
  ) async {
    final fake = FakeKaneo()..notifications.clear();
    final app = await desktopApp(tester, size, server: fake);
    final router = app.container.read(routerProvider);
    final runtime = app.container.read(desktopRuntimeProvider(router))!;
    expect(app.host.notices, isEmpty);
    fake.failNext('api/notification', status: 403);
    await checkDesktop(tester, runtime);
    expect(app.host.notices, isEmpty);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);
    expect(inPage(find.text('Demo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('composing Chinese text survives a desktop layout resize', (tester, size) async {
    await desktopApp(tester, size, session: null);
    final email = find.byKey(const ValueKey('login-email'));
    await tester.showKeyboard(email);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        composing: TextRange(start: 0, end: 2),
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    tester.view.physicalSize = size == wideSize ? narrowSize : wideSize;
    await tester.pumpAndSettle();
    final controller = tester.widget<TextFormField>(email).controller!;
    expect(controller.text, '中文');
    expect(controller.value.composing, const TextRange(start: 0, end: 2));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '中文输入', selection: TextSelection.collapsed(offset: 4)),
    );
    await tester.pump();
    expect(controller.text, '中文输入');
    expect(tester.takeException(), isNull);
  });
}
