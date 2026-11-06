// Run through tool/with_device.sh. AUTH_TEST_* are supplied from a private local JSON file,
// without KANEO_DEV_* defines, so this exercises production login and actual system storage.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/auth/login_page.dart';

const _server = String.fromEnvironment('AUTH_TEST_SERVER_URL');
const _email = String.fromEnvironment('AUTH_TEST_EMAIL');
const _password = String.fromEnvironment('AUTH_TEST_PASSWORD');
const _apiKey = String.fromEnvironment('AUTH_TEST_API_KEY');
const _phase = String.fromEnvironment('AUTH_TEST_PHASE', defaultValue: 'roundtrip');

Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: 'Timed out waiting for authentication state');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('production login and keychain persistence', (tester) async {
    expect(_server.isNotEmpty, isTrue, reason: 'Pass private AUTH_TEST_* defines.');
    expect(DevConfig.fromEnvironment().isConfigured, isFalse);
    final storage = SecureSessionStorage(key: 'kaneo.auth.integration.session');
    // The separate "save" and "restore" invocations prove that the session survives process exit.
    if (_phase == 'restore' || (_phase == 'restart' && await storage.read() != null)) {
      final container = await bootstrap(sessionStorage: storage);
      addTearDown(container.dispose);
      expect(
        container.read(sessionProvider) != null,
        isTrue,
        reason: 'No saved session after relaunch',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const KaneoApp()),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LoginPage), findsNothing);
      expect((await container.read(kaneoApiProvider).me()).id.isNotEmpty, isTrue);
      await container.read(sessionProvider.notifier).signOut();
      expect(await storage.read() == null, isTrue);
      return;
    }
    final previous = await storage.read();
    expect(
      previous == null,
      isTrue,
      reason: 'Use an empty test app installation; a session already exists.',
    );
    final container = await bootstrap(sessionStorage: storage);
    addTearDown(container.dispose);
    await container.read(languageChoiceProvider.notifier).select(defaultLocale);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KaneoApp()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('login-server')), '$_server/api/');
    await tester.enterText(find.byKey(const ValueKey('login-email')), _email);
    await tester.enterText(find.byKey(const ValueKey('login-password')), _password);
    await tester.ensureVisible(find.byKey(const ValueKey('login-submit')));
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await waitUntil(
      tester,
      () =>
          container.read(sessionProvider) != null ||
          find.byKey(const ValueKey('login-error')).evaluate().isNotEmpty,
    );
    expect(container.read(sessionProvider) != null, isTrue, reason: 'Password sign-in failed');
    final stored = await SecureSessionStorage(key: 'kaneo.auth.integration.session').read();
    expect(stored != null && stored.token == container.read(sessionProvider)?.token, isTrue);
    await container.read(sessionProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(await storage.read() == null, isTrue);
    await tester.enterText(find.byKey(const ValueKey('login-server')), _server);
    await tester.tap(find.text(container.read(i18nProvider).t('mobile:signIn.apiKey.label')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-api-key')), _apiKey);
    await tester.ensureVisible(find.byKey(const ValueKey('login-submit')));
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await waitUntil(
      tester,
      () =>
          container.read(sessionProvider) != null ||
          find.byKey(const ValueKey('login-error')).evaluate().isNotEmpty,
    );
    expect(container.read(sessionProvider) != null, isTrue, reason: 'API key sign-in failed');
    expect(
      (await SecureSessionStorage(key: 'kaneo.auth.integration.session').read())?.credentialType ==
          CredentialType.apiKey,
      isTrue,
    );
    if (_phase != 'save' && _phase != 'restart') {
      await container.read(sessionProvider.notifier).signOut();
    }
  });
}
