import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/fake_kaneo.dart';

const _session = Session(
  serverUrl: FakeKaneo.serverUrl,
  credentialType: CredentialType.apiKey,
  token: FakeKaneo.apiKey,
  userId: FakeKaneo.userId,
  userName: 'Test User',
  userEmail: FakeKaneo.email,
);

void main() {
  late FakeKaneo server;
  late I18n i18n;
  late Session? session;
  late List<Session> expired;

  ApiClient client({HttpClientAdapter? adapter}) => ApiClient(
    session: () => session,
    i18n: i18n,
    onSessionExpired: expired.add,
    adapter: adapter ?? server,
  );

  setUp(() async {
    server = FakeKaneo();
    i18n = await I18n.load(
      read: (asset) async => asset.endsWith('overrides/en-US.json')
          ? null
          : {
              'mobile': {
                'errors': {
                  'sessionExpired': 'Your session expired.',
                  'forbidden': 'Not allowed.',
                  'notFound': 'Not found.',
                  'tooManyRequests': 'Slow down.',
                  'serverProblem': 'The server had a problem ({{status}}).',
                  'requestFailed': 'Request failed ({{status}}).',
                  'unreachable': 'Could not reach the server.',
                  'notSignedIn': 'Not signed in.',
                },
              },
            },
    );
    session = _session;
    expired = [];
  });

  group('normalizeServerUrl', () {
    test('adds https to a bare host', () {
      expect(normalizeServerUrl('kaneo.example.com'), 'https://kaneo.example.com');
    });

    test('keeps http for a server on the local network', () {
      expect(normalizeServerUrl('http://192.168.1.5:1337'), 'http://192.168.1.5:1337');
    });

    test('drops a trailing slash and a trailing /api', () {
      expect(normalizeServerUrl(' https://kaneo.example.com/api/ '), 'https://kaneo.example.com');
      expect(normalizeServerUrl('https://kaneo.example.com///'), 'https://kaneo.example.com');
    });
  });

  group('resolveUrl', () {
    test('resolves a relative path against the server', () {
      expect(resolveUrl('https://a.test/', '/api/asset/1'), 'https://a.test/api/asset/1');
    });

    test('leaves absolute urls alone', () {
      expect(resolveUrl('https://a.test', 'https://b.test/x.png'), 'https://b.test/x.png');
      expect(resolveUrl('https://a.test', 'data:image/png;base64,AA'), 'data:image/png;base64,AA');
    });

    test('is null without a path', () {
      expect(resolveUrl('https://a.test', null), isNull);
      expect(resolveUrl('https://a.test', ''), isNull);
    });
  });

  group('credentials', () {
    test('an API key goes in x-api-key and nowhere else', () async {
      await client().request('api/user/me');
      final headers = server.requests.single.headers;
      expect(headers['x-api-key'], FakeKaneo.apiKey);
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('a session token goes in the Authorization header', () async {
      session = const Session(
        serverUrl: FakeKaneo.serverUrl,
        credentialType: CredentialType.bearer,
        token: FakeKaneo.sessionToken,
        userId: FakeKaneo.userId,
        userName: 'Test User',
        userEmail: FakeKaneo.email,
      );
      await client().request('api/user/me');
      final headers = server.requests.single.headers;
      expect(headers['Authorization'], 'Bearer ${FakeKaneo.sessionToken}');
      expect(headers.containsKey('x-api-key'), isFalse);
    });

    test('credentials are not sent to a server other than the session one', () async {
      await client().requestRaw('api/config', serverUrl: 'https://other.test');
      final headers = server.requests.single.headers;
      expect(headers.containsKey('x-api-key'), isFalse);
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('without a session or a server the request fails with a readable message', () async {
      session = null;
      await expectLater(
        client().request('api/user/me'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Not signed in.')),
      );
    });
  });

  group('request bodies', () {
    test('null fields are dropped by default', () async {
      await client().request(
        'api/label',
        method: 'POST',
        body: {'name': 'a', 'color': 'red', 'workspaceId': 'w', 'taskId': null},
      );
      expect(server.requests.single.body, {'name': 'a', 'color': 'red', 'workspaceId': 'w'});
    });

    test('keepNulls sends an explicit null', () async {
      await client().request(
        'api/task/assignee/task-1',
        method: 'PUT',
        body: {'userId': null},
        keepNulls: true,
      );
      expect(server.requests.single.body, {'userId': null});
    });

    test('null query values are left out', () async {
      await client().request('api/user/me', query: {'a': null, 'b': 1});
      expect(server.requests.single.query, {'b': '1'});
    });
  });

  group('failures', () {
    test('401 expires the session the request was made with', () async {
      server.credentialsRevoked = true;
      await expectLater(client().request('api/user/me'), throwsA(isA<ApiError>()));
      expect(expired, [_session]);
    });

    test('401 from a sign-in route does not expire the session', () async {
      server.fail('api/auth/', status: 401, body: {'message': 'Invalid email or password'});
      await expectLater(
        client().request('api/auth/sign-in/email', method: 'POST', body: {}),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      expect(expired, isEmpty);
    });

    test('401 with explicit credentials does not expire the session', () async {
      server.credentialsRevoked = true;
      await expectLater(
        client().request(
          'api/user/me',
          serverUrl: FakeKaneo.serverUrl,
          credentials: const ApiCredentials(CredentialType.apiKey, 'wrong'),
        ),
        throwsA(isA<ApiError>()),
      );
      expect(expired, isEmpty);
    });

    test('401 after signing in again does not expire the new session', () async {
      server.hold('api/user/me');
      server.credentialsRevoked = true;
      final pending = client().request('api/user/me');
      session = const Session(
        serverUrl: FakeKaneo.serverUrl,
        credentialType: CredentialType.apiKey,
        token: 'a-newer-key',
        userId: FakeKaneo.userId,
        userName: 'Test User',
        userEmail: FakeKaneo.email,
      );
      server.clearOverrides();
      final gate = server.hold('never');
      gate.release();
      expect(expired, isEmpty);
      // The first request is still held; nothing was expired while it waited.
      pending.ignore();
    });

    final messages = <int, String>{
      403: 'Not allowed.',
      404: 'Not found.',
      429: 'Slow down.',
      500: 'The server had a problem (500).',
      503: 'The server had a problem (503).',
      418: 'Request failed (418).',
    };
    messages.forEach((status, message) {
      test('$status without a server message reads "$message"', () async {
        server.failNext('api/user/me', status: status);
        await expectLater(
          client().request('api/user/me'),
          throwsA(
            isA<ApiError>()
                .having((e) => e.message, 'message', message)
                .having((e) => e.status, 'status', status),
          ),
        );
        expect(expired, isEmpty);
      });
    });

    test('the server\'s own message wins', () async {
      server.failNext('api/user/me', status: 400, body: {'message': 'Title is required'});
      await expectLater(
        client().request('api/user/me'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Title is required')),
      );
    });

    test('a nested error message is found', () async {
      server.failNext(
        'api/user/me',
        status: 400,
        body: {
          'error': {'message': 'Nested'},
        },
      );
      await expectLater(
        client().request('api/user/me'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Nested')),
      );
    });

    test('an HTML error page is not shown to the person', () async {
      server.failNext('api/user/me', status: 502, body: '<html><body>Bad gateway</body></html>');
      await expectLater(
        client().request('api/user/me'),
        throwsA(
          isA<ApiError>().having((e) => e.message, 'message', 'The server had a problem (502).'),
        ),
      );
    });

    test('an unreachable server gives a readable message and no status', () async {
      server.unreachable = true;
      await expectLater(
        client().request('api/user/me'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.message, 'message', 'Could not reach the server.')
              .having((e) => e.status, 'status', isNull),
        ),
      );
    });
  });

  test('requestRaw returns the status and headers whatever the outcome', () async {
    final failed = await client().requestRaw(
      'api/auth/sign-in/email',
      method: 'POST',
      body: {'email': FakeKaneo.email, 'password': 'wrong'},
    );
    expect(failed.status, 401);
    expect(failed.isOk, isFalse);

    final signedIn = await client().requestRaw(
      'api/auth/sign-in/email',
      method: 'POST',
      body: {'email': FakeKaneo.email, 'password': FakeKaneo.password},
    );
    expect(signedIn.isOk, isTrue);
    expect(signedIn.header('Set-Auth-Token'), FakeKaneo.sessionToken);
  });
}
