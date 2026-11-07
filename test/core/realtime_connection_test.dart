import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/test_app.dart';

const _path = 'api/ws/project-1';

class _Probe {
  _Probe(this.server) {
    connection = RealtimeConnection(
      openSocket: () => server.connectSocket(testSession, _path),
      onEvent: events.add,
      onOpen: () => opens++,
      onRevoked: () => revoked++,
    );
  }

  final FakeKaneo server;
  late final RealtimeConnection connection;
  final events = <RealtimeEvent>[];
  int opens = 0;
  int revoked = 0;
}

Future<void> _pass(WidgetTester tester, [Duration time = Duration.zero]) => tester.pump(time);

/// The fake clock insists that nothing is left running when the test ends.
void _testConnection(
  String description,
  Future<void> Function(WidgetTester tester, _Probe probe) body,
) {
  testWidgets(description, (tester) async {
    final probe = _Probe(FakeKaneo());
    await body(tester, probe);
    probe.connection.stop();
  });
}

void main() {
  group('parsing a frame', () {
    test('keeps what an event says, with empty ids left out', () {
      final event = RealtimeEvent.parse(
        '{"type":"TASK_UPDATED","projectId":"p","taskId":"t","sourceTaskId":""}',
      )!;
      expect(event.type, 'TASK_UPDATED');
      expect(event.taskId, 't');
      expect(event.sourceTaskId, isNull);
      expect(event.targetTaskId, isNull);
      expect(RealtimeEvent.parse('{"type":"TASK_UPDATED","taskId":""}')!.taskId, isNull);
    });

    test('ignores keepalives, and anything else that is not an event', () {
      for (final frame in [
        '{"type":"PING"}',
        '{"type":"pong"}',
        '{"type":""}',
        '{"no":"type"}',
        '[1,2]',
        'not json',
        null,
        42,
      ]) {
        expect(RealtimeEvent.parse(frame), isNull, reason: '$frame');
      }
    });
  });

  _testConnection('passes on events, and says when it opens', (tester, probe) async {
    probe.connection.start();
    await _pass(tester);
    expect(probe.opens, 1);
    probe.server.emit(_path, 'TASK_UPDATED', {'taskId': 't'});
    probe.server.emitRaw(_path, 'not json');
    probe.server.emit(_path, 'PING');
    expect(probe.events.map((e) => e.taskId), ['t']);
  });

  _testConnection('sends the one keepalive the server accepts, every 30 seconds', (
    tester,
    probe,
  ) async {
    probe.connection.start();
    await _pass(tester);
    final socket = probe.server.sockets.single;
    await _pass(tester, const Duration(seconds: 29));
    expect(socket.sent, isEmpty);
    await _pass(tester, const Duration(seconds: 1));
    expect(socket.sent, ['{"type":"ping"}']);
    await _pass(tester, const Duration(seconds: 30));
    expect(socket.sent, hasLength(2));
  });

  _testConnection('a drop opens a new socket, and it says so', (tester, probe) async {
    probe.connection.start();
    await _pass(tester);
    probe.server.dropSockets();
    await _pass(tester, const Duration(milliseconds: 999));
    expect(probe.server.sockets, hasLength(1));
    await _pass(tester, const Duration(milliseconds: 1));
    await _pass(tester);
    expect(probe.server.openSockets(_path), hasLength(1));
    expect(probe.opens, 2);
    expect(probe.revoked, 0);
  });

  _testConnection('waits longer after each failure, up to its limit, and retries for good', (
    tester,
    probe,
  ) async {
    final server = probe.server..unreachable = true;
    probe.connection.start();
    await _pass(tester);
    expect(server.sockets, hasLength(1));
    var seen = 1;
    for (final wait in const [1, 2, 4, 8, 15, 15, 15]) {
      await _pass(tester, Duration(seconds: wait - 1));
      await _pass(tester, const Duration(milliseconds: 999));
      expect(server.sockets, hasLength(seen), reason: 'before the wait of $wait s is up');
      await _pass(tester, const Duration(milliseconds: 1));
      await _pass(tester);
      expect(server.sockets, hasLength(++seen), reason: 'after the wait of $wait s');
    }
    expect(probe.opens, 0);

    server.unreachable = false;
    await _pass(tester, RealtimeConnection.maxRetryDelay);
    await _pass(tester);
    expect(probe.opens, 1);
  });

  _testConnection('counts from the start again only after a socket has lasted', (
    tester,
    probe,
  ) async {
    final server = probe.server;
    probe.connection.start();
    await _pass(tester);

    // Closed right after opening, again and again, as when the server turns it away.
    for (final wait in const [1, 2, 4]) {
      server.dropSockets();
      await _pass(tester, Duration(seconds: wait));
      await _pass(tester);
      expect(probe.opens, greaterThan(1));
    }
    final soFar = server.sockets.length;
    server.dropSockets();
    await _pass(tester, const Duration(seconds: 4));
    await _pass(tester);
    expect(server.sockets, hasLength(soFar), reason: 'the next wait is 8 seconds');
    await _pass(tester, const Duration(seconds: 4));
    await _pass(tester);
    expect(server.sockets, hasLength(soFar + 1));

    await _pass(tester, RealtimeConnection.keepAliveInterval);
    server.dropSockets();
    await _pass(tester, const Duration(seconds: 1));
    await _pass(tester);
    expect(server.sockets, hasLength(soFar + 2));
  });

  for (final code in [1008, 4001]) {
    _testConnection('a close with $code says access ended, and still retries', (
      tester,
      probe,
    ) async {
      probe.connection.start();
      await _pass(tester);
      probe.server.dropSockets(code: code);
      await _pass(tester);
      expect(probe.revoked, 1);
      expect(probe.connection.isRunning, isTrue);
    });
  }

  testWidgets('a socket that cannot even be made is tried again', (tester) async {
    final server = FakeKaneo();
    var refused = 1;
    final connection = RealtimeConnection(
      openSocket: () {
        if (refused-- > 0) throw const SocketExceptionForTests();
        return server.connectSocket(testSession, _path);
      },
      onEvent: (_) {},
    )..start();
    expect(connection.isRunning, isTrue);
    await _pass(tester, const Duration(seconds: 1));
    await _pass(tester);
    expect(server.openSockets(_path), hasLength(1));
    connection.stop();
  });

  _testConnection('stop closes the socket and calls off the retry', (tester, probe) async {
    probe.connection.start();
    await _pass(tester);
    probe.connection.stop();
    expect(probe.server.openSockets(_path), isEmpty);
    expect(probe.connection.isRunning, isFalse);

    probe.connection.start();
    await _pass(tester);
    probe.server.dropSockets();
    await _pass(tester);
    probe.connection.stop();
    final sockets = probe.server.sockets.length;
    await _pass(tester, const Duration(minutes: 1));
    expect(probe.server.sockets, hasLength(sockets));
  });

  _testConnection('a socket stopped before it opened neither opens nor reports', (
    tester,
    probe,
  ) async {
    probe.connection.start();
    probe.connection.stop();
    await _pass(tester);
    expect(probe.opens, 0);
    expect(probe.server.openSockets(_path), isEmpty);
  });

  _testConnection('a late close of an old socket leaves the new one alone', (tester, probe) async {
    probe.connection.start();
    await _pass(tester);
    final old = probe.server.sockets.single;
    probe.connection.start();
    await _pass(tester);
    expect(probe.server.sockets, hasLength(2));
    expect(old.isOpen, isFalse);
    final current = probe.server.sockets.last;
    await _pass(tester, const Duration(minutes: 1));
    expect(probe.server.sockets, hasLength(2));
    expect(current.isOpen, isTrue);
  });
}
