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

  for (final type in CredentialType.values) {
    test('a connection over a real socket follows the server, with $type', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final accepted = <WebSocket>[];
      final received = <Object?>[];
      final credentials = <String?>[];
      server.listen((request) async {
        credentials.add(
          request.headers.value(type == CredentialType.apiKey ? 'x-api-key' : 'Authorization'),
        );
        final socket = await WebSocketTransformer.upgrade(request);
        accepted.add(socket);
        socket.listen(received.add);
      });
      final session = Session(
        serverUrl: 'http://127.0.0.1:${server.port}',
        credentialType: type,
        token: 'test-secret',
        userId: 'test-user',
        userName: '',
        userEmail: '',
      );
      final events = <RealtimeEvent>[];
      var opens = 0;
      final connection = RealtimeConnection(
        openSocket: () => connectAuthenticatedSocket(
          session,
          'api/ws/project-1',
          pingInterval: realtimePingInterval,
        ),
        onEvent: events.add,
        onOpen: () => opens++,
      );
      addTearDown(connection.stop);
      connection.start();
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 500 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready(), isTrue);
      }

      await until(() => opens == 1 && accepted.isNotEmpty);
      accepted.first.add('{"type":"TASK_UPDATED","taskId":"t"}');
      await until(() => events.isNotEmpty);
      expect(events.single.taskId, 't');

      // The server goes away, and the connection is back by itself soon after.
      await accepted.first.close();
      await until(() => opens == 2 && accepted.length == 2);
      expect(
        credentials.toSet().single,
        type == CredentialType.apiKey ? 'test-secret' : 'Bearer test-secret',
      );

      // And it's the new socket that counts.
      accepted.last.add('{"type":"TASK_UPDATED","taskId":"u"}');
      await until(() => events.length == 2);
      expect(events.last.taskId, 'u');

      connection.stop();
      await until(() => accepted.last.closeCode != null);
    });
  }

  test('a network gone quiet is noticed from the pings alone', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async => (await WebSocketTransformer.upgrade(request)).drain<void>());

    // Between the two, so that bytes can stop going through while both ends stay open.
    var quiet = false;
    final relay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(relay.close);
    final held = <Socket>[];
    addTearDown(() {
      for (final socket in held) {
        socket.destroy();
      }
    });
    relay.listen((client) async {
      final upstream = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      held.addAll([client, upstream]);
      client.listen((bytes) {
        if (!quiet) upstream.add(bytes);
      });
      upstream.listen((bytes) {
        if (!quiet) client.add(bytes);
      });
    });

    final channel = connectAuthenticatedSocket(
      Session(
        serverUrl: 'http://127.0.0.1:${relay.port}',
        credentialType: CredentialType.apiKey,
        token: 'k',
        userId: 'u',
        userName: '',
        userEmail: '',
      ),
      'api/ws/user',
      pingInterval: const Duration(seconds: 1),
    );
    await channel.ready;
    final done = channel.stream.drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(channel.closeCode, isNull, reason: 'While the pings are answered it stays open.');
    quiet = true;
    await done.timeout(const Duration(seconds: 10));
    expect(channel.closeCode, WebSocketStatus.goingAway);
  });

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
