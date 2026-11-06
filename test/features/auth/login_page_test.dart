import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/auth/login_page.dart';

import '../../support/test_app.dart';

Finder field(String name) => find.byKey(ValueKey('login-$name'));

Future<void> passwordForm(WidgetTester tester, {String password = FakeKaneo.password}) async {
  await tester.enterText(field('server'), 'https://kaneo.test/api/');
  await tester.enterText(field('email'), FakeKaneo.email);
  await tester.enterText(field('password'), password);
}

Future<void> apiKeyForm(WidgetTester tester, {String key = FakeKaneo.apiKey}) async {
  await tester.enterText(field('server'), FakeKaneo.serverUrl);
  // Tap the second segment directly, independent of the translated label.
  final segment = find
      .descendant(of: find.byType(SegmentedButton<CredentialType>), matching: find.byType(Text))
      .last;
  await tester.tap(segment);
  await tester.pumpAndSettle();
  await tester.enterText(field('api-key'), key);
}

Future<void> submit(WidgetTester tester, {bool settle = true}) async {
  await tester.ensureVisible(field('submit'));
  await tester.tap(field('submit'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class BrokenStorage extends MemorySessionStorage {
  @override
  Future<void> write(Session session) async => throw Exception('keychain unavailable');
}

void main() {
  testBothLayouts('login only offers self-hosted password and API key', (tester, size) async {
    final app = await pumpKaneoApp(tester, size: size, session: null);
    expect(field('server'), findsOneWidget);
    expect(field('email'), findsOneWidget);
    expect(field('password'), findsOneWidget);
    for (final key in ['cloud', 'continueInBrowser', 'emailCode', 'createAccount']) {
      expect(find.text(app.i18n.t('mobile:signIn.$key')), findsNothing);
    }
    expect(find.text(app.i18n.t('app:auth.devSignIn')), findsNothing);
    expect(tester.getSize(field('server')).width, lessThanOrEqualTo(440));
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('required fields prevent requests', (tester, size) async {
    final app = await pumpKaneoApp(tester, size: size, session: null);
    await submit(tester);
    expect(app.server.requests, isEmpty);
    expect(app.container.read(sessionProvider), isNull);
    expect(find.text(app.i18n.t('app:auth.invalidAddress')), findsOneWidget);
  });

  testBothLayouts('password login stores a session and loads projects', (tester, size) async {
    final storage = MemorySessionStorage();
    final app = await pumpKaneoApp(tester, size: size, session: null, sessionStorage: storage);
    await passwordForm(tester);
    await submit(tester);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('Demo'), findsOneWidget);
    expect((await storage.read())?.credentialType, CredentialType.bearer);
    expect(
      app.server.requestsTo('api/user/me').last.headers['Authorization'],
      'Bearer ${FakeKaneo.sessionToken}',
    );
  });

  testBothLayouts('password failures show server reason then allow retry', (tester, size) async {
    final app = await pumpKaneoApp(tester, size: size, session: null);
    await passwordForm(tester, password: 'wrong');
    await submit(tester);
    expect(find.text('Invalid email or password'), findsOneWidget);
    expect(app.container.read(sessionProvider), isNull);
    await tester.enterText(field('password'), FakeKaneo.password);
    await submit(tester);
    expect(find.byType(LoginPage), findsNothing);
  });

  testBothLayouts('API key login keeps the server field and authenticates board and inbox reads', (
    tester,
    size,
  ) async {
    final app = await pumpKaneoApp(tester, size: size, session: null);
    await apiKeyForm(tester);
    expect(tester.widget<TextFormField>(field('server')).controller!.text, FakeKaneo.serverUrl);
    await submit(tester);
    expect(app.container.read(sessionProvider)?.credentialType, CredentialType.apiKey);
    app.container.read(routerProvider).go(AppRoutes.board(FakeKaneo.projectId));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    await tester.runAsync(
      () => app.container.read(kaneoApiProvider).notifications(workspaceId: FakeKaneo.workspaceId),
    );
    for (final request in app.server.requests.where((r) => r.path != 'api/config')) {
      expect(request.headers['x-api-key'], FakeKaneo.apiKey);
      expect(request.headers.containsKey('Authorization'), isFalse);
    }
  });

  for (final status in [401, 403]) {
    testBothLayouts('API key rejection $status is readable and keeps login open', (
      tester,
      size,
    ) async {
      final server = FakeKaneo()..fail('api/user/me', status: status);
      final app = await pumpKaneoApp(tester, size: size, session: null, server: server);
      await apiKeyForm(tester, key: 'wrong');
      await submit(tester);
      expect(find.text(app.i18n.t('mobile:errors.apiKeyRejected')), findsOneWidget);
      expect(app.container.read(sessionProvider), isNull);
    });
  }

  testBothLayouts('unreachable server gives a readable error', (tester, size) async {
    final server = FakeKaneo()..unreachable = true;
    final app = await pumpKaneoApp(tester, size: size, session: null, server: server);
    await passwordForm(tester);
    await submit(tester);
    expect(find.text(app.i18n.t('mobile:errors.unreachable')), findsOneWidget);
    expect(app.container.read(sessionProvider), isNull);
  });

  testBothLayouts('login shows progress and suppresses duplicate submissions', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final gate = server.hold('api/auth/sign-in/email');
    final app = await pumpKaneoApp(tester, size: size, session: null, server: server);
    await passwordForm(tester);
    await submit(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(field('submit')).onPressed, isNull);
    expect(tester.widget<TextFormField>(field('server')).enabled, isFalse);
    gate.release();
    await tester.pumpAndSettle();
    expect(app.server.requestsTo('api/auth/sign-in/email'), hasLength(1));
  });

  testBothLayouts('secure storage failure is visible and does not enter the app', (
    tester,
    size,
  ) async {
    final app = await pumpKaneoApp(
      tester,
      size: size,
      session: null,
      sessionStorage: BrokenStorage(),
    );
    await passwordForm(tester);
    await submit(tester);
    expect(find.text(app.i18n.t('app:auth.storageFailed')), findsOneWidget);
    expect(app.container.read(sessionProvider), isNull);
  });

  testBothLayouts('saved login restores without credentials being requested again', (
    tester,
    size,
  ) async {
    final storage = MemorySessionStorage();
    await pumpKaneoApp(tester, size: size, session: null, sessionStorage: storage);
    await passwordForm(tester);
    await submit(tester);
    await tester.pumpWidget(const SizedBox());
    final app = await pumpKaneoApp(
      tester,
      size: size,
      session: await storage.read(),
      sessionStorage: storage,
    );
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('Demo'), findsOneWidget);
    expect(app.server.requestsTo('api/auth/sign-in/email'), isEmpty);
  });

  testBothLayouts('sign out then another account cannot see old projects or notifications', (
    tester,
    size,
  ) async {
    final storage = MemorySessionStorage(testSession);
    final app = await pumpKaneoApp(tester, size: size, sessionStorage: storage);
    final store = app.container.read(cacheStoreProvider);
    await store.write('notifications/${FakeKaneo.workspaceId}', [
      {'id': 'old-notification'},
    ]);
    expect(find.text('Demo'), findsOneWidget);
    app.container.read(routerProvider).go(AppRoutes.account);
    await tester.pumpAndSettle();
    await tester.tap(find.text(app.i18n.t('mobile:account.signOut.button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(app.i18n.t('mobile:account.signOut.button')).last);
    await tester.pumpAndSettle();
    expect(await storage.read(), isNull);
    expect(store.peek('notifications/${FakeKaneo.workspaceId}'), isNull);
    app.server.user['id'] = 'second-user';
    app.server.user['name'] = 'Second User';
    app.server.workspaces.clear();
    await passwordForm(tester);
    await submit(tester);
    expect(app.container.read(sessionProvider)?.userId, 'second-user');
    expect(find.text('Demo'), findsNothing);
    expect(
      app.container.read(cacheStoreProvider).peek('notifications/${FakeKaneo.workspaceId}'),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
