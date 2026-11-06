import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKaneo server;
  late Authentication auth;
  late I18n i18n;

  setUp(() async {
    server = FakeKaneo();
    i18n = await I18n.load(read: readCatalogFile);
    auth = Authentication(
      ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {}, adapter: server),
      i18n,
    );
  });

  test('addresses accept bare domains, /api and local HTTP', () {
    expect(auth.serverAddress('kaneo.example.com'), 'https://kaneo.example.com');
    expect(auth.serverAddress(' https://kaneo.example.com/api/ '), 'https://kaneo.example.com');
    expect(auth.serverAddress('http://192.168.1.2:1337/api'), 'http://192.168.1.2:1337');
    expect(auth.serverAddress('http://[::1]:1337'), 'http://[::1]:1337');
  });

  test('invalid addresses are rejected before sending credentials', () async {
    for (final input in [
      '',
      ' ',
      'https://',
      'https://bad host',
      'https://user:pass@a.test',
      'https://a.test?key=secret',
      'https://a.test#part',
      'ftp://a.test',
    ]) {
      expect(() => auth.serverAddress(input), throwsA(isA<ApiError>()), reason: input);
    }
    expect(server.requests, isEmpty);
  });

  test('password sign-in accepts the auth header and validates the current user', () async {
    final session = await auth.withPassword(
      FakeKaneo.serverUrl,
      ' ${FakeKaneo.email} ',
      FakeKaneo.password,
    );
    expect(session.credentialType, CredentialType.bearer);
    expect(session.token, FakeKaneo.sessionToken);
    expect(session.userId, FakeKaneo.userId);
    final request = server.requestsTo('api/auth/sign-in/email').single;
    expect(request.body, {
      'email': FakeKaneo.email,
      'password': FakeKaneo.password,
      'rememberMe': true,
    });
    expect(server.requests.last.headers['Authorization'], 'Bearer ${FakeKaneo.sessionToken}');
  });

  test('token body fallback works when the proxy strips the auth header', () async {
    server.on(
      'api/auth/sign-in/email',
      (_) => FakeResponse(200, {'token': FakeKaneo.sessionToken}),
    );
    expect(
      (await auth.withPassword(FakeKaneo.serverUrl, FakeKaneo.email, FakeKaneo.password)).token,
      FakeKaneo.sessionToken,
    );
  });

  test('a successful response without a token remains signed out', () async {
    server.on('api/auth/sign-in/email', (_) => const FakeResponse(200, {}));
    await expectLater(
      auth.withPassword(FakeKaneo.serverUrl, FakeKaneo.email, FakeKaneo.password),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', i18n.t('app:auth.noSession'))),
    );
  });

  test('API key sign-in validates with x-api-key', () async {
    final session = await auth.withApiKey('${FakeKaneo.serverUrl}/api/', ' ${FakeKaneo.apiKey} ');
    expect(session.credentialType, CredentialType.apiKey);
    expect(session.serverUrl, FakeKaneo.serverUrl);
    expect(server.requests.last.headers['x-api-key'], FakeKaneo.apiKey);
    expect(server.requests.last.headers.containsKey('Authorization'), isFalse);
  });

  test('wrong password preserves the server reason', () async {
    await expectLater(
      auth.withPassword(FakeKaneo.serverUrl, FakeKaneo.email, 'wrong'),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Invalid email or password')),
    );
  });

  test('wrong and forbidden API keys have a useful sign-in message', () async {
    for (final status in [401, 403]) {
      server.failNext('api/user/me', status: status);
      await expectLater(
        auth.withApiKey(FakeKaneo.serverUrl, 'wrong'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            i18n.t('mobile:errors.apiKeyRejected'),
          ),
        ),
      );
    }
  });

  test('non-Kaneo and malformed identity responses cannot create a session', () async {
    server.on('api/config', (_) => const FakeResponse(200, '<html>Not Kaneo</html>'));
    await expectLater(
      auth.withApiKey(FakeKaneo.serverUrl, FakeKaneo.apiKey),
      throwsA(isA<ApiError>()),
    );
    expect(server.requestsTo('api/user/me'), isEmpty);
    server.clearOverrides();
    server.on('api/user/me', (_) => const FakeResponse(200, {}));
    await expectLater(
      auth.withApiKey(FakeKaneo.serverUrl, FakeKaneo.apiKey),
      throwsA(isA<ApiError>()),
    );
  });

  test('unreachable instances give a readable error', () async {
    server.unreachable = true;
    await expectLater(
      auth.withApiKey(FakeKaneo.serverUrl, FakeKaneo.apiKey),
      throwsA(
        isA<ApiError>().having((e) => e.message, 'message', i18n.t('mobile:errors.unreachable')),
      ),
    );
  });
}
