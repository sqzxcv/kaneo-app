import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/inbox/notifications.dart';
import 'package:kaneo_app/features/task/task_panel.dart';
import 'package:kaneo_app/features/task/task_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/test_app.dart';

const _aboutTask = 'About a task';
const _aboutWorkspace = 'About the workspace';
const _alreadyRead = 'Already read';
const _readWorkspace = 'Read and about the workspace';
const _otherWorkspace = 'ws-other';

/// Two unread notifications, one of them about a task, and two read ones.
FakeKaneo _server() {
  final server = FakeKaneo();
  server.notifications.clear();
  server.addNotification(title: _aboutTask, resourceId: 'task-1');
  server.addNotification(
    type: 'custom',
    title: _aboutWorkspace,
    resourceId: FakeKaneo.workspaceId,
    resourceType: 'workspace',
  );
  server.addNotification(title: _alreadyRead, resourceId: 'task-2', isRead: true);
  server.addNotification(
    type: 'custom',
    title: _readWorkspace,
    resourceId: FakeKaneo.workspaceId,
    resourceType: 'workspace',
    isRead: true,
  );
  return server;
}

/// [_server] with a second workspace that has an unread notification of its own.
FakeKaneo _twoWorkspaces() {
  final server = _server();
  server.workspaces.add({...server.workspaces.first, 'id': _otherWorkspace, 'name': 'Other'});
  server.addProject(id: 'project-other', name: 'Other project', slug: 'OTH')['workspaceId'] =
      _otherWorkspace;
  final task = server.addTask(projectId: 'project-other', title: 'Other task');
  server.addNotification(title: 'Other notice', resourceId: task['id'] as String);
  return server;
}

/// The count in the navigation, which shows nothing at zero.
void _expectUnread(int count) {
  final badge = find.byKey(inboxUnreadKey);
  if (count == 0) {
    expect(badge, findsNothing);
  } else {
    expect(find.descendant(of: badge, matching: find.text('$count')), findsOneWidget);
  }
}

void _go(TestApp app, String location) => app.container.read(routerProvider).go(location);

String _location(TestApp app) => app.container.read(routerProvider).state.uri.path;

Finder _markAll(TestApp app) => find.byTooltip(app.i18n.t('mobile:inbox.markAllRead'));

Finder _clearButton(TestApp app) => find.byTooltip(app.i18n.t('mobile:inbox.clearAll'));

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(inPage(find.text(text)));
  await tester.pumpAndSettle();
}

/// Lets requests that aren't held through, without waiting for anything else to finish.
Future<void> _letRequestsThrough(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('the list', () {
    testBothLayouts('shows who is looking for me, read or not', (tester, size) async {
      await pumpKaneoApp(tester, server: _server(), size: size, location: AppRoutes.inbox);
      for (final title in [_aboutTask, _aboutWorkspace, _alreadyRead, _readWorkspace]) {
        expect(inPage(find.text(title)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('splits today from earlier, with the time next to each', (tester, size) async {
      final server = FakeKaneo();
      server.notifications.clear();
      server.addNotification(title: 'Recent one')['createdAt'] = DateTime(
        2026,
        11,
        6,
        10,
      ).toUtc().toIso8601String();
      server.addNotification(title: 'Old one')['createdAt'] = DateTime(
        2026,
        9,
        1,
      ).toUtc().toIso8601String();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.inbox,
        overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 11, 6, 15))],
      );
      final today = find.text(app.i18n.t('mobile:inbox.today'));
      final earlier = find.text(app.i18n.t('mobile:inbox.earlier'));
      expect(tester.getTopLeft(today).dy, lessThan(tester.getTopLeft(find.text('Recent one')).dy));
      expect(
        tester.getTopLeft(find.text('Recent one')).dy,
        lessThan(tester.getTopLeft(earlier).dy),
      );
      expect(tester.getTopLeft(earlier).dy, lessThan(tester.getTopLeft(find.text('Old one')).dy));
      expect(find.text(app.i18n.t('mobile:time.hoursShort', {'count': 5})), findsOneWidget);
    });

    testBothLayouts('without anything from today it says recent', (tester, size) async {
      final server = FakeKaneo();
      server.notifications.clear();
      server.addNotification(title: 'Old one')['createdAt'] = '2020-01-01T00:00:00.000Z';
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      expect(find.text(app.i18n.t('mobile:inbox.recent')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:inbox.earlier')), findsNothing);
      expect(find.text(app.i18n.t('mobile:inbox.today')), findsNothing);
    });

    testBothLayouts('an event reads as a sentence, in the language', (tester, size) async {
      final server = FakeKaneo();
      server.notifications.clear();
      server.addNotification(
        type: 'task_mention',
        eventData: {'mentionerName': 'Ann', 'taskTitle': 'Fix it'},
        resourceId: 'task-1',
      );
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.inbox,
        locale: 'zh-CN',
      );
      final title = app.i18n.t('notifications:events.task_mention.title', {'mentionerName': 'Ann'});
      expect(title, isNot('Ann mentioned you'));
      expect(find.text(title), findsOneWidget);
    });

    testWidgets('stays a reading column on a big window, with the time next to the text', (
      tester,
    ) async {
      final server = FakeKaneo();
      server.notifications.clear();
      server.addNotification(title: 'Recent one')['createdAt'] = DateTime(
        2026,
        11,
        6,
        10,
      ).toUtc().toIso8601String();
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: const Size(1920, 1080),
        location: AppRoutes.inbox,
        overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 11, 6, 15))],
      );
      final column = tester.getRect(
        find.descendant(of: find.byType(ContentWidth), matching: find.byType(ConstrainedBox)).first,
      );
      expect(column.width, contentMaxWidth);
      final time = find.text(app.i18n.t('mobile:time.hoursShort', {'count': 5}));
      expect(tester.getTopRight(time).dx, lessThanOrEqualTo(column.right));
    });
  });

  group('marking everything read', () {
    testBothLayouts('marks them all and says so', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      _expectUnread(2);

      await tester.tap(_markAll(app));
      await tester.pumpAndSettle();

      _expectUnread(0);
      expect(server.notifications.every((n) => n['isRead'] == true), isTrue);
      expect(find.text(app.i18n.t('mobile:inbox.allCaughtUpToast')), findsOneWidget);
      // Nothing is lost: read notifications stay in the list.
      expect(inPage(find.text(_aboutTask)), findsOneWidget);
    });

    testBothLayouts('stays in the current workspace', (tester, size) async {
      final server = _twoWorkspaces();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await tester.tap(_markAll(app));
      await tester.pumpAndSettle();

      final request = server.requestsTo('api/notification/read-all', method: 'PATCH').single;
      expect(request.query['workspaceId'], FakeKaneo.workspaceId);
      final other = server.notifications.singleWhere((n) => n['title'] == 'Other notice');
      expect(other['isRead'], isFalse);
    });

    testBothLayouts('there is nothing to do with nothing unread', (tester, size) async {
      final server = _server();
      for (final notification in server.notifications) {
        notification['isRead'] = true;
      }
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      await tester.tap(_markAll(app), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/notification/read-all'), isEmpty);
    });

    testBothLayouts('goes back and says why when the server refuses', (tester, size) async {
      final server = _server()
        ..failNext('api/notification/read-all', status: 500, body: {'message': 'Not today'});
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await tester.tap(_markAll(app));
      await tester.pumpAndSettle();

      _expectUnread(2);
      expect(find.text('Not today'), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:inbox.allCaughtUpToast')), findsNothing);
    });
  });

  group('clearing', () {
    Future<void> confirm(WidgetTester tester, TestApp app) async {
      await tester.tap(_clearButton(app));
      await tester.pumpAndSettle();
      await tester.tap(find.text(app.i18n.t('mobile:inbox.confirmClear.confirm')));
      await tester.pumpAndSettle();
    }

    testBothLayouts('asks first, and then empties the inbox', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await tester.tap(_clearButton(app));
      await tester.pumpAndSettle();
      expect(find.text(app.i18n.t('mobile:inbox.confirmClear.title')), findsOneWidget);
      expect(server.requestsTo('api/notification/clear-all'), isEmpty);

      await tester.tap(find.text(app.i18n.t('mobile:inbox.confirmClear.confirm')));
      await tester.pumpAndSettle();

      expect(server.notifications, isEmpty);
      expect(find.text(app.i18n.t('mobile:inbox.empty.title')), findsOneWidget);
      _expectUnread(0);
    });

    testBothLayouts('cancelling keeps everything', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await tester.tap(_clearButton(app));
      await tester.pumpAndSettle();
      await tester.tap(find.text(app.i18n.t('mobile:common.cancel')));
      await tester.pumpAndSettle();

      expect(server.requestsTo('api/notification/clear-all'), isEmpty);
      expect(server.notifications, hasLength(4));
      expect(inPage(find.text(_aboutTask)), findsOneWidget);
      _expectUnread(2);
    });

    testBothLayouts('stays in the current workspace', (tester, size) async {
      final server = _twoWorkspaces();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await confirm(tester, app);

      final request = server.requestsTo('api/notification/clear-all', method: 'DELETE').single;
      expect(request.query['workspaceId'], FakeKaneo.workspaceId);
      expect(server.notifications.map((n) => n['title']), ['Other notice']);
    });

    testBothLayouts('goes back and says why when the server refuses', (tester, size) async {
      final server = _server()
        ..failNext('api/notification/clear-all', status: 500, body: {'message': 'Not today'});
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await confirm(tester, app);

      expect(find.text('Not today'), findsOneWidget);
      expect(inPage(find.text(_aboutTask)), findsOneWidget);
      _expectUnread(2);
    });

    testBothLayouts('an empty inbox has nothing to clear', (tester, size) async {
      final server = _server()..notifications.clear();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      await tester.tap(_clearButton(app), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(app.i18n.t('mobile:inbox.confirmClear.title')), findsNothing);
    });
  });

  group('tapping a notification', () {
    testBothLayouts('about a task opens that task as a full page and marks it read', (
      tester,
      size,
    ) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await _tapText(tester, _aboutTask);

      expect(taskOpen('task-1'), findsOneWidget);
      expect(_location(app), AppRoutes.task('task-1'));
      expect(find.byKey(taskPanelKey), findsNothing);
      final id = server.notifications.first['id'];
      expect(server.requestsTo('api/notification/$id/read', method: 'PATCH'), hasLength(1));
      expect(server.notifications.first['isRead'], isTrue);
    });

    testBothLayouts('coming back shows it read', (tester, size) async {
      final app = await pumpKaneoApp(
        tester,
        server: _server(),
        size: size,
        location: AppRoutes.inbox,
      );

      await _tapText(tester, _aboutTask);
      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();

      expect(_location(app), AppRoutes.inbox);
      expect(inPage(find.text(_aboutTask)), findsOneWidget);
      _expectUnread(1);
    });

    testBothLayouts('about something else only marks it read', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await _tapText(tester, _aboutWorkspace);

      expect(find.byType(TaskView), findsNothing);
      expect(_location(app), AppRoutes.inbox);
      final notification = server.notifications.singleWhere((n) => n['title'] == _aboutWorkspace);
      expect(notification['isRead'], isTrue);
      _expectUnread(1);
    });

    testBothLayouts('already read about a task opens it and sends nothing', (tester, size) async {
      final server = _server();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await _tapText(tester, _alreadyRead);

      expect(taskOpen('task-2'), findsOneWidget);
      expect(server.requestsTo('/read', method: 'PATCH'), isEmpty);
    });

    testBothLayouts('already read about something else does nothing', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await _tapText(tester, _readWorkspace);

      expect(_location(app), AppRoutes.inbox);
      expect(server.requestsTo('/read', method: 'PATCH'), isEmpty);
      _expectUnread(2);
    });

    testBothLayouts('still opens the task when marking it read fails, and says why', (
      tester,
      size,
    ) async {
      final server = _server()..fail('/read', status: 500, body: {'message': 'Not today'});
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await _tapText(tester, _aboutTask);

      expect(taskOpen('task-1'), findsOneWidget);
      expect(find.text('Not today'), findsOneWidget);
      expect(server.notifications.first['isRead'], isFalse);

      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      _expectUnread(2);
    });

    testBothLayouts('something else goes back to unread when marking it fails', (
      tester,
      size,
    ) async {
      final server = _server()..fail('/read', status: 500, body: {'message': 'Not today'});
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      await _tapText(tester, _aboutWorkspace);

      expect(find.text('Not today'), findsOneWidget);
      _expectUnread(2);
    });
  });

  group('the count in the navigation', () {
    testBothLayouts('is there on other pages', (tester, size) async {
      await pumpKaneoApp(tester, server: _server(), size: size);
      _expectUnread(2);
    });

    testBothLayouts('is gone with nothing unread', (tester, size) async {
      final server = _server();
      for (final notification in server.notifications) {
        notification['isRead'] = true;
      }
      await pumpKaneoApp(tester, server: server, size: size);
      _expectUnread(0);
    });

    testBothLayouts('stops at 99+', (tester, size) async {
      final server = _server();
      for (var i = 0; i < 100; i++) {
        server.addNotification(title: 'Number $i');
      }
      await pumpKaneoApp(tester, server: server, size: size);
      expect(
        find.descendant(of: find.byKey(inboxUnreadKey), matching: find.text('99+')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('drops as soon as one is read, before the server answers', (
      tester,
      size,
    ) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      final gate = server.hold('/read', method: 'PATCH');

      await tester.tap(inPage(find.text(_aboutWorkspace)));
      await tester.pump();

      _expectUnread(1);
      expect(server.notifications[1]['isRead'], isFalse);

      gate.release();
      await tester.pumpAndSettle();
      _expectUnread(1);
      expect(server.notifications[1]['isRead'], isTrue);
      expect(_location(app), AppRoutes.inbox);
    });

    testBothLayouts('drops to nothing as soon as all are read', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      final gate = server.hold('api/notification/read-all');

      await tester.tap(_markAll(app));
      await tester.pump();

      _expectUnread(0);

      gate.release();
      await tester.pumpAndSettle();
      _expectUnread(0);
    });

    testBothLayouts('picks up what arrived, when moving between pages', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size);
      _expectUnread(2);

      server.addNotification(title: 'New one');
      _go(app, AppRoutes.activity);
      await tester.pumpAndSettle();
      _expectUnread(3);
    });

    testBothLayouts('a failed load shows no count, and no words of its own', (tester, size) async {
      final server = _server()..fail('api/notification', status: 500);
      final app = await pumpKaneoApp(tester, server: server, size: size);
      _expectUnread(0);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('follows the workspace', (tester, size) async {
      final server = _twoWorkspaces();
      await pumpKaneoApp(tester, server: server, size: size);
      _expectUnread(2);

      await tester.tap(find.text('Test Workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();

      _expectUnread(1);
    });

    testBothLayouts('says what it is to a screen reader', (tester, size) async {
      final handle = tester.ensureSemantics();
      final app = await pumpKaneoApp(tester, server: _server(), size: size);
      final label = app.i18n.t('mobile:nav.inboxUnread', {'count': 2});
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(label))), findsOneWidget);
      handle.dispose();
    });
  });

  group('a change on its way', () {
    testBothLayouts('is not undone by an answer read before it', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);

      // A refresh is out when the person taps. It answers with what it read before the tap.
      final stale = jsonDecode(jsonEncode(server.notifications));
      var answered = false;
      server.on('api/notification', method: 'GET', (request) {
        if (answered) return FakeResponse(200, server.notifications);
        answered = true;
        return FakeResponse(200, stale);
      });
      final read = server.hold('api/notification', method: 'GET');
      final write = server.hold('/read', method: 'PATCH');
      final actions = app.container.read(inboxActionsProvider(FakeKaneo.workspaceId));
      unawaited(actions.refresh());
      await tester.pump();

      await tester.tap(inPage(find.text(_aboutWorkspace)));
      await tester.pump();
      _expectUnread(1);

      read.release();
      await _letRequestsThrough(tester);
      expect(answered, isTrue);
      _expectUnread(1);

      write.release();
      await tester.pumpAndSettle();
      _expectUnread(1);
      expect(server.notifications[1]['isRead'], isTrue);
    });

    testBothLayouts('holds back refreshes, which load again when it lands', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      final loads = server.requestsTo('api/notification', method: 'GET').length;
      final write = server.hold('/read', method: 'PATCH');

      await tester.tap(inPage(find.text(_aboutWorkspace)));
      await tester.pump();
      _go(app, AppRoutes.activity);
      await _letRequestsThrough(tester);
      expect(server.requestsTo('api/notification', method: 'GET'), hasLength(loads));
      _expectUnread(1);

      write.release();
      await tester.pumpAndSettle();
      expect(server.requestsTo('api/notification', method: 'GET'), hasLength(loads + 1));
      _expectUnread(1);
    });
  });

  group('coming back to the page', () {
    testBothLayouts('shows what it had at once, then what is new', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      _go(app, AppRoutes.home);
      await tester.pumpAndSettle();

      server.addNotification(title: 'New one');
      final gate = server.hold('api/notification', method: 'GET');
      _go(app, AppRoutes.inbox);
      await tester.pump();
      await tester.pump();

      expect(inPage(find.text(_aboutTask)), findsOneWidget);
      expect(find.text('New one'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      _expectUnread(2);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text('New one')), findsOneWidget);
      _expectUnread(3);
    });

    testBothLayouts('keeps what it had when the refresh fails', (tester, size) async {
      final server = _server();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      _go(app, AppRoutes.home);
      await tester.pumpAndSettle();

      server.fail('api/notification', status: 500, method: 'GET');
      _go(app, AppRoutes.inbox);
      await tester.pumpAndSettle();

      expect(inPage(find.text(_aboutTask)), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsNothing);
      _expectUnread(2);
    });

    testBothLayouts('after the app restarted, shows what the cache has', (tester, size) async {
      final server = _server();
      final store = MemoryCacheStore();
      await store.write('notifications/${FakeKaneo.workspaceId}', [
        {
          'id': 'cached',
          'userId': FakeKaneo.userId,
          'title': 'From last time',
          'type': 'custom',
          'isRead': false,
          'createdAt': '2026-11-06T12:00:00.000Z',
        },
      ]);
      final gate = server.hold('api/notification', method: 'GET');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.inbox,
        settle: false,
        overrides: [cacheStoreProvider.overrideWithValue(store)],
      );
      await _letRequestsThrough(tester);

      expect(inPage(find.text('From last time')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      _expectUnread(1);

      gate.release();
      await tester.pumpAndSettle();
      expect(find.text('From last time'), findsNothing);
      expect(inPage(find.text(_aboutTask)), findsOneWidget);
    });

    testBothLayouts('pulling down loads again', (tester, size) async {
      final server = _server();
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      server.addNotification(title: 'New one');

      await tester.fling(inPage(find.byType(ListView)), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(inPage(find.text('New one')), findsOneWidget);
    });
  });

  group('states', () {
    testBothLayouts('shows progress while it first loads', (tester, size) async {
      final server = _server();
      final gate = server.hold('api/notification', method: 'GET');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.inbox,
        settle: false,
      );
      await _letRequestsThrough(tester);
      expect(inPage(find.byType(CircularProgressIndicator)), findsOneWidget);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.byType(CircularProgressIndicator)), findsNothing);
      expect(inPage(find.text(_aboutTask)), findsOneWidget);
    });

    testBothLayouts('says why it failed, and tries again', (tester, size) async {
      final server = _server()
        ..failNext('api/notification', status: 500, body: {'message': 'Not today'}, method: 'GET');
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      expect(find.text('Not today'), findsOneWidget);

      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(inPage(find.text(_aboutTask)), findsOneWidget);
      _expectUnread(2);
    });

    testBothLayouts('without permission says so, with no way to retry', (tester, size) async {
      final server = _server()..fail('api/notification', status: 403, method: 'GET');
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
    });

    testBothLayouts('empty says what will appear here', (tester, size) async {
      final server = _server()..notifications.clear();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      expect(find.text(app.i18n.t('mobile:inbox.empty.title')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:inbox.empty.message')), findsOneWidget);
    });

    testBothLayouts('with no workspace there is nothing to act on', (tester, size) async {
      final server = _server()..workspaces.clear();
      final app = await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.inbox);
      expect(find.text(app.i18n.t('mobile:home.noWorkspace.title')), findsOneWidget);
      expect(_markAll(app), findsNothing);
      expect(find.byIcon(LucideIcons.trash2), findsNothing);
    });
  });

  group('every language fits', () {
    for (final locale in supportedLocales.keys) {
      for (final size in const [narrowSize, Size(600, 600)]) {
        testWidgets('$locale at ${size.width.toInt()}', (tester) async {
          await pumpKaneoApp(
            tester,
            server: _server(),
            size: size,
            location: AppRoutes.inbox,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          expect(find.textContaining('mobile:'), findsNothing);
          expect(find.textContaining('notifications:'), findsNothing);
        });
      }
    }
  });
}
