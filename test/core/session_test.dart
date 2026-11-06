import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_kaneo.dart';

const _session = Session(
  serverUrl: FakeKaneo.serverUrl,
  credentialType: CredentialType.apiKey,
  token: FakeKaneo.apiKey,
  userId: FakeKaneo.userId,
  userName: 'Test User',
  userEmail: FakeKaneo.email,
);

Future<ProviderContainer> _container(
  FakeKaneo server,
  SessionStorage storage, {
  Session? session,
  DevConfig devConfig = const DevConfig(),
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      i18nProvider.overrideWithValue(await I18n.load(read: (_) async => null)),
      httpAdapterProvider.overrideWithValue(server),
      sessionStorageProvider.overrideWithValue(storage),
      initialSessionProvider.overrideWithValue(session),
      devConfigProvider.overrideWithValue(devConfig),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _BrokenStorage implements SessionStorage {
  @override
  Future<void> clear() async => throw Exception('no secret service');

  @override
  Future<Session?> read() async => throw Exception('no secret service');

  @override
  Future<void> write(Session session) async => throw Exception('no secret service');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a session survives JSON', () {
    final copy = Session.fromJson(_session.toJson());
    expect(copy.token, _session.token);
    expect(copy.credentialType, CredentialType.apiKey);
    expect(copy.serverUrl, _session.serverUrl);
    expect(copy.userEmail, _session.userEmail);
  });

  group('developer sign-in', () {
    const config = DevConfig(serverUrl: '${FakeKaneo.serverUrl}/api/', apiKey: FakeKaneo.apiKey);

    test('signs in with the key from the config and stores the session', () async {
      final server = FakeKaneo();
      final storage = MemorySessionStorage();
      final container = await _container(server, storage, devConfig: config);

      await container.read(sessionProvider.notifier).devSignIn();

      final session = container.read(sessionProvider);
      expect(session?.serverUrl, FakeKaneo.serverUrl);
      expect(session?.credentialType, CredentialType.apiKey);
      expect(session?.token, FakeKaneo.apiKey);
      expect(session?.userEmail, FakeKaneo.email);
      expect((await storage.read())?.token, FakeKaneo.apiKey);
      expect(server.requests.single.headers['x-api-key'], FakeKaneo.apiKey);
    });

    test('a wrong key fails and leaves everyone signed out', () async {
      final server = FakeKaneo();
      final container = await _container(
        server,
        MemorySessionStorage(),
        devConfig: const DevConfig(serverUrl: FakeKaneo.serverUrl, apiKey: 'wrong'),
      );
      await expectLater(
        container.read(sessionProvider.notifier).devSignIn(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      expect(container.read(sessionProvider), isNull);
    });

    test('does nothing without a config', () async {
      final server = FakeKaneo();
      final container = await _container(server, MemorySessionStorage());
      await container.read(sessionProvider.notifier).devSignIn();
      expect(server.requests, isEmpty);
      expect(container.read(sessionProvider), isNull);
    });

    test('a release build ignores the config', () {
      // `flutter test` runs in debug, so this reads the defines, which are unset here.
      expect(DevConfig.fromEnvironment().isConfigured, isFalse);
    });
  });

  group('signing out', () {
    test('forgets the session and the cache', () async {
      final storage = MemorySessionStorage(_session);
      final container = await _container(FakeKaneo(), storage, session: _session);
      final store = container.read(cacheStoreProvider);
      await store.write('a', 1);

      await container.read(sessionProvider.notifier).signOut();

      expect(container.read(sessionProvider), isNull);
      expect(await storage.read(), isNull);
      expect(store.peek('a'), isNull);
    });

    test('still signs out when secure storage is unavailable', () async {
      final container = await _container(FakeKaneo(), _BrokenStorage(), session: _session);
      await container.read(sessionProvider.notifier).signOut();
      expect(container.read(sessionProvider), isNull);
    });
  });

  group('an expired session', () {
    test('a 401 from any request signs out', () async {
      final server = FakeKaneo()..credentialsRevoked = true;
      final storage = MemorySessionStorage(_session);
      final container = await _container(server, storage, session: _session);
      await expectLater(container.read(kaneoApiProvider).me(), throwsA(isA<ApiError>()));
      expect(container.read(sessionProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(await storage.read(), isNull);
    });

    test('expiring an old session does not sign out a newer one', () async {
      final container = await _container(
        FakeKaneo(),
        MemorySessionStorage(_session),
        session: _session,
      );
      const newer = Session(
        serverUrl: FakeKaneo.serverUrl,
        credentialType: CredentialType.apiKey,
        token: 'newer',
        userId: FakeKaneo.userId,
        userName: 'Test User',
        userEmail: FakeKaneo.email,
      );
      await container.read(sessionProvider.notifier).signIn(newer);
      container.read(sessionProvider.notifier).expire(_session);
      expect(container.read(sessionProvider)?.token, 'newer');
    });
  });

  test('signing in works when secure storage is unavailable', () async {
    final container = await _container(FakeKaneo(), _BrokenStorage());
    await container.read(sessionProvider.notifier).signIn(_session);
    expect(container.read(sessionProvider)?.token, FakeKaneo.apiKey);
  });

  test('MemorySessionStorage keeps a session until cleared', () async {
    final storage = MemorySessionStorage();
    expect(await storage.read(), isNull);
    await storage.write(_session);
    expect((await storage.read())?.token, FakeKaneo.apiKey);
    await storage.clear();
    expect(await storage.read(), isNull);
  });

  test('authRedirect sends people to the right side of the login page', () {
    final login = Uri.parse(AppRoutes.login);
    final home = Uri.parse(AppRoutes.home);
    final board = Uri.parse(AppRoutes.board('x'));
    expect(authRedirect(signedIn: false, location: home), AppRoutes.login);
    expect(authRedirect(signedIn: false, location: board), AppRoutes.login);
    expect(authRedirect(signedIn: false, location: login), isNull);
    expect(authRedirect(signedIn: true, location: login), AppRoutes.home);
    expect(authRedirect(signedIn: true, location: board), isNull);
  });

  test('route helpers build the paths the router registers', () {
    expect(AppRoutes.board('p1'), '/board/p1');
    expect(AppRoutes.task('t1'), '/task/t1');
    expect(AppRoutes.newTask(), '/task/new');
    expect(
      AppRoutes.newTask(projectId: 'p1', status: 'to-do'),
      '/task/new?projectId=p1&status=to-do',
    );
  });
}
