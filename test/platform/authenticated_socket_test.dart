import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

void main() {
  for (final type in CredentialType.values) {
    test('native sockets authenticate $type for both user and project events', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final accepted = <WebSocket>[];
      addTearDown(() async {
        for (final socket in accepted) {
          await socket.close();
        }
      });
      server.listen((request) async {
        expect(
          request.headers.value(type == CredentialType.apiKey ? 'x-api-key' : 'Authorization'),
          type == CredentialType.apiKey ? 'test-secret' : 'Bearer test-secret',
        );
        expect(request.uri.toString(), isNot(contains('test-secret')));
        expect(request.uri.queryParameters['windowId'], startsWith('flutter-'));
        final socket = await WebSocketTransformer.upgrade(request);
        accepted.add(socket);
        socket.add('{"type":"TASK_UPDATED"}');
      });
      final session = Session(
        serverUrl: 'http://127.0.0.1:${server.port}',
        credentialType: type,
        token: 'test-secret',
        userId: 'test-user',
        userName: '',
        userEmail: '',
      );
      for (final path in ['api/ws/user', 'api/ws/project-1']) {
        final channel = connectAuthenticatedSocket(session, path);
        await channel.ready;
        expect(await channel.stream.first, '{"type":"TASK_UPDATED"}');
        await channel.sink.close();
      }
    });
  }

  test('HTTPS upgrades to WSS and each connection gets a new window identity', () {
    const session = Session(
      serverUrl: 'https://kaneo.example.com/prefix',
      credentialType: CredentialType.apiKey,
      token: 'secret',
      userId: 'u',
      userName: '',
      userEmail: '',
    );
    final first = authenticatedSocketUrl(session, '/api/ws/user');
    final second = authenticatedSocketUrl(session, '/api/ws/user');
    expect(first.scheme, 'wss');
    expect(first.path, '/prefix/api/ws/user');
    expect(first.query, isNot(second.query));
    expect(first.toString(), isNot(contains('secret')));
  });
}
