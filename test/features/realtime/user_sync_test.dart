import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/inbox/notifications.dart';

import '../../support/test_app.dart';

const _socket = FakeKaneo.userSocket;

int _inboxReads(FakeKaneo server) => server.requestsTo('api/notification').length;

Future<void> _within5Seconds(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testBothLayouts('the account has a socket on every page', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(tester, server: server, size: size);
    expect(server.openSockets(_socket), hasLength(1));
    app.container.read(routerProvider).go(AppRoutes.inbox);
    await tester.pumpAndSettle();
    expect(server.openSockets(_socket), hasLength(1));
    expect(server.sockets.where((s) => s.path == _socket), hasLength(1));
  });

  testBothLayouts('signed out there is no socket', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(tester, server: server, size: size, session: null);
    expect(server.sockets, isEmpty);
  });

  testBothLayouts('a new notification reaches the inbox on its own', (tester, size) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
    final before = app.container.read(inboxUnreadCountProvider);
    server.addNotification(title: 'Live notification', content: 'Fresh', resourceId: 'task-1');
    server.emit(_socket, 'NOTIFICATION_CREATED');
    await _within5Seconds(tester);
    expect(app.container.read(inboxUnreadCountProvider), before + 1);
    expect(find.textContaining('Live notification'), findsWidgets);
  });

  testBothLayouts('several notifications at once make one read', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(tester, server: server, size: size);
    final reads = _inboxReads(server);
    for (var i = 0; i < 5; i++) {
      server.emit(_socket, 'NOTIFICATION_CREATED');
    }
    await _within5Seconds(tester);
    expect(_inboxReads(server), reads + 1);
  });

  testBothLayouts('the activity page follows along', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.activity);
    final reads = server.requestsTo('api/activity/workspace/').length;
    server.emit(_socket, 'NOTIFICATION_CREATED');
    await _within5Seconds(tester);
    expect(server.requestsTo('api/activity/workspace/').length, reads + 1);
  });

  testBothLayouts('the sync as a socket opens says nothing when it holds no news', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    await pumpKaneoApp(tester, server: server, size: size);
    final requests = server.requests.length;
    for (final ids in const [
      [FakeKaneo.workspaceId],
      // An administrator is told about every workspace there is.
      [FakeKaneo.workspaceId, 'workspace-not-a-member-of'],
      'nonsense',
    ]) {
      server.emit(_socket, 'WORKSPACE_ACCESS_SYNC', {'workspaceIds': ids});
    }
    await _within5Seconds(tester);
    expect(server.requests.length, requests);
  });

  testBothLayouts('a workspace gone reads what is open', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(tester, server: server, size: size);
    final reads = server.requestsTo('api/workspace').length;
    server.emit(_socket, 'WORKSPACE_ACCESS_SYNC', {'workspaceIds': <String>[]});
    await _within5Seconds(tester);
    expect(server.requestsTo('api/workspace').length, greaterThan(reads));
  });

  for (final type in const [
    'PROJECT_ACCESS_CHANGED',
    'WORKSPACE_ACCESS_REVOKED',
    'WORKSPACE_RESTORED',
  ]) {
    testBothLayouts('$type shows what access is left', (tester, size) async {
      final server = FakeKaneo();
      await pumpKaneoApp(tester, server: server, size: size);
      expect(find.text('Demo').evaluate(), isNotEmpty);
      server.projects.first['name'] = 'Renamed project';
      server.emit(_socket, type, {'workspaceId': FakeKaneo.workspaceId});
      await _within5Seconds(tester);
      expect(find.text('Renamed project').evaluate(), isNotEmpty);
    });
  }

  testBothLayouts('after time without a socket, what is open catches up, the inbox too', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(tester, server: server, size: size);
    final unread = app.container.read(inboxUnreadCountProvider);
    server.unreachable = true;
    server.dropSockets();
    await tester.pump(const Duration(seconds: 30));
    server.projects.first['name'] = 'Renamed offline';
    server.addNotification(title: 'Arrived offline', resourceId: 'task-1');
    server.unreachable = false;
    await tester.pump(RealtimeConnection.maxRetryDelay);
    await _within5Seconds(tester);
    expect(find.text('Renamed offline').evaluate(), isNotEmpty);
    expect(app.container.read(inboxUnreadCountProvider), unread + 1);
    expect(tester.takeException(), isNull);
  });

  testBothLayouts('the first socket has nothing to catch up on', (tester, size) async {
    final server = FakeKaneo();
    await pumpKaneoApp(tester, server: server, size: size);
    final requests = server.requests.length;
    await _within5Seconds(tester);
    expect(server.requests.length, requests);
  });

  testBothLayouts('a socket closed for a revoked credential leads to the login page', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(tester, server: server, size: size);
    server.credentialsRevoked = true;
    server.dropSockets(code: 4001, reason: 'Session ended');
    await _within5Seconds(tester);
    await tester.pumpAndSettle();
    expect(app.container.read(sessionProvider), isNull);
    expect(find.byType(FilledButton).evaluate(), isNotEmpty);
    expect(server.sockets.where((s) => s.isOpen), isEmpty);
  });

  testBothLayouts('in the background the socket goes, and in front it comes back', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final app = await pumpKaneoApp(tester, server: server, size: size);
    final unread = app.container.read(inboxUnreadCountProvider);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(server.openSockets(_socket), isEmpty);
    server.addNotification(title: 'Arrived in the background', resourceId: 'task-1');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _within5Seconds(tester);
    expect(server.openSockets(_socket), hasLength(1));
    expect(app.container.read(inboxUnreadCountProvider), unread + 1);
  });
}
