import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/inbox/inbox_page.dart';
import 'package:kaneo_app/features/notifications/notification_check.dart';
import 'package:kaneo_app/features/notifications/notification_host.dart';
import 'package:kaneo_app/features/notifications/notification_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../platform/fake_desktop_host.dart';
import '../../support/test_app.dart';
import 'fake_notification_host.dart';

const _taskId = 'task-1';
const _taskTitle = 'Set up the project';
const _switch = ValueKey('notification-checks');

const _otherUser = 'user-2';
const _otherSession = Session(
  serverUrl: FakeKaneo.serverUrl,
  credentialType: CredentialType.bearer,
  token: FakeKaneo.sessionToken,
  userId: _otherUser,
  userName: 'Other User',
  userEmail: 'other@example.invalid',
);

/// The app on a phone or tablet, with the OS and the task's isolate replaced.
class _Phone {
  _Phone(this.tester, this.app, this.host, this.storage);

  final WidgetTester tester;
  final TestApp app;
  final FakeNotificationHost host;
  final SessionStorage storage;

  FakeKaneo get server => app.server;

  bool get enabled => app.container.read(notificationChecksEnabledProvider);

  String get location => app.container.read(routerProvider).state.uri.path;

  /// What the OS does every 15 minutes or so.
  Future<void> startCheck() =>
      runBackgroundCheck(host: host, storage: storage, adapter: server, catalogs: readCatalogFile);

  Future<void> runCheck() => _finish(tester, startCheck());

  Future<void> leave() async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await _letRun(tester);
  }

  Future<void> comeBack() async {
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(String payload) async {
    host.onTap!(payload);
    await tester.pumpAndSettle();
  }

  int get checks => server.requestsTo('api/notification', method: 'GET').length;
}

Future<_Phone> _openPhone(
  WidgetTester tester, {
  Size size = wideSize,
  FakeKaneo? server,
  FakeNotificationHost? host,
  Session? session = testSession,
  String location = AppRoutes.home,
  Map<String, Object> preferences = const {notificationChecksEnabledKey: true},
}) async {
  final fake = host ?? FakeNotificationHost();
  final storage = MemorySessionStorage(session);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  final app = await pumpKaneoApp(
    tester,
    server: server ?? FakeKaneo(),
    size: size,
    session: session,
    sessionStorage: storage,
    location: location,
    preferences: preferences,
    overrides: [
      backgroundChecksSupportedProvider.overrideWithValue(true),
      notificationHostProvider.overrideWithValue(fake),
    ],
  );
  await _letRun(tester);
  return _Phone(tester, app, fake, storage);
}

/// Lets what the app started by itself finish, without pumpAndSettle's wait for animations.
Future<void> _letRun(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _finish(WidgetTester tester, Future<void> work) async {
  var done = false;
  final pending = work.whenComplete(() => done = true);
  for (var i = 0; i < 200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done, isTrue, reason: 'The check did not finish');
  await pending;
}

/// Adds [count] notifications about the task, oldest first.
void _arrive(FakeKaneo server, int count, {int startAt = 0}) {
  for (var i = startAt; i < startAt + count; i++) {
    server.addNotification(title: 'Notice $i', resourceId: _taskId)['createdAt'] = DateTime.utc(
      2026,
      11,
      6,
      13,
      0,
      i,
    ).toIso8601String();
  }
}

/// A run of the background task with no app anywhere near it, as after the OS started it.
Future<void> _checkAlone(
  WidgetTester tester,
  FakeKaneo server,
  FakeNotificationHost host, {
  SessionStorage? storage,
}) => _finish(
  tester,
  runBackgroundCheck(
    host: host,
    storage: storage ?? MemorySessionStorage(testSession),
    adapter: server,
    catalogs: readCatalogFile,
  ),
);

/// The same, for a run that ends in the error the task's dispatcher catches.
Future<void> _checkFails(
  WidgetTester tester,
  FakeKaneo server,
  FakeNotificationHost host, {
  SessionStorage? storage,
}) async {
  Object? error;
  await _finish(
    tester,
    runBackgroundCheck(
      host: host,
      storage: storage ?? MemorySessionStorage(testSession),
      adapter: server,
      catalogs: readCatalogFile,
    ).catchError((Object thrown) => error = thrown),
  );
  expect(error, isA<ApiError>());
}

Future<void> _prepareAlone(WidgetTester tester, {Map<String, Object>? preferences}) async {
  SharedPreferences.setMockInitialValues(preferences ?? {notificationChecksEnabledKey: true});
  await loadTestI18n(tester);
}

void main() {
  group('in the background', () {
    testBothLayouts('a new notification shows, and its tap opens the task as a page', (
      tester,
      size,
    ) async {
      final phone = await _openPhone(tester, size: size);
      expect(phone.host.scheduled, isTrue);
      await phone.leave();
      phone.server.addNotification(title: 'Assigned to you', content: 'Hi', resourceId: _taskId);

      await phone.runCheck();

      expect(phone.host.notices, hasLength(1));
      expect(phone.host.notices.single.title, 'Assigned to you');
      expect(phone.host.notices.single.body, 'Hi');

      await phone.comeBack();
      await phone.tap(phone.host.notices.single.payload);
      expect(taskOpen(_taskId), findsOneWidget);
      expect(find.text(_taskTitle), findsWidgets);
      expect(phone.location, AppRoutes.task(_taskId));
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('a tap that launches the app opens the task', (tester, size) async {
      final host = FakeNotificationHost()
        ..launch = encodeNotice(accountScope(testSession), _taskId);
      final phone = await _openPhone(tester, size: size, host: host);
      await tester.pumpAndSettle();
      expect(taskOpen(_taskId), findsOneWidget);
      expect(phone.location, AppRoutes.task(_taskId));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap that launches the app for someone else opens nothing', (tester) async {
      final host = FakeNotificationHost()
        ..launch = encodeNotice(accountScope(_otherSession), _taskId);
      final phone = await _openPhone(tester, host: host);
      await tester.pumpAndSettle();
      expect(taskOpen(_taskId), findsNothing);
      expect(phone.location, AppRoutes.home);
    });

    testBothLayouts('a notification that is not about a task opens the inbox', (
      tester,
      size,
    ) async {
      final phone = await _openPhone(tester, size: size);
      await phone.leave();
      phone.server.addNotification(
        title: 'New workspace',
        resourceId: FakeKaneo.workspaceId,
        resourceType: 'workspace',
      );
      await phone.runCheck();
      await phone.comeBack();
      await phone.tap(phone.host.notices.single.payload);
      expect(phone.location, AppRoutes.inbox);
      expect(find.byType(InboxPage), findsOneWidget);
    });

    testWidgets('says what a server event is about in the chosen language', (tester) async {
      SharedPreferences.setMockInitialValues({
        notificationChecksEnabledKey: true,
        languageChoiceKey: 'zh-CN',
      });
      final i18n = await loadTestI18n(tester, locale: 'zh-CN');
      final server = FakeKaneo();
      final host = FakeNotificationHost();
      await _checkAlone(tester, server, host);
      server.addNotification(
        type: 'task_comment',
        eventData: {'taskTitle': 'Fix it', 'userName': 'Ann'},
        resourceId: _taskId,
      );
      await _checkAlone(tester, server, host);
      expect(host.notices.single.title, i18n.t('notifications:events.task_comment.title').trim());
      expect(host.notices.single.title, isNot(contains('task_comment')));
      expect(host.channels.single, i18n.t('mobile:background.channelName'));
    });

    testWidgets('shows each notification once, and none that were read', (tester) async {
      final phone = await _openPhone(tester);
      await phone.leave();
      phone.server.addNotification(title: 'Read elsewhere', isRead: true);
      phone.server.addNotification(title: 'Still unread', resourceId: _taskId);
      await phone.runCheck();
      await phone.runCheck();
      expect(phone.host.notices.map((n) => n.title), ['Still unread']);
    });

    testWidgets('nothing arrives from what was on screen when the app left', (tester) async {
      final phone = await _openPhone(tester);
      phone.server.addNotification(title: 'Seen in the app', resourceId: _taskId);
      await phone.leave();
      await phone.runCheck();
      expect(phone.host.notices, isEmpty);
    });

    testWidgets('does not check while the app is on screen', (tester) async {
      final phone = await _openPhone(tester);
      phone.server.addNotification(title: 'On screen', resourceId: _taskId);
      final before = phone.checks;
      await phone.runCheck();
      expect(phone.checks, before);
      expect(phone.host.notices, isEmpty);

      await phone.leave();
      phone.server.addNotification(title: 'Off screen', resourceId: _taskId);
      await phone.runCheck();
      expect(phone.host.notices.map((n) => n.title), ['Off screen']);

      await phone.comeBack();
      phone.server.addNotification(title: 'On screen again', resourceId: _taskId);
      final again = phone.checks;
      await phone.runCheck();
      expect(phone.checks, again);
    });

    testWidgets('going to the background does not lose its place when offline', (tester) async {
      final phone = await _openPhone(tester);
      phone.server.unreachable = true;
      await phone.leave();
      phone.server.unreachable = false;
      expect(tester.takeException(), isNull);
      phone.server.addNotification(title: 'While away', resourceId: _taskId);
      await phone.runCheck();
      expect(phone.host.notices.map((n) => n.title), ['While away']);
    });
  });

  group('the first check and a backlog', () {
    testWidgets('the first check shows no history, and the next shows what is new', (tester) async {
      await _prepareAlone(tester);
      final server = FakeKaneo();
      final host = FakeNotificationHost();
      _arrive(server, 20);
      await _checkAlone(tester, server, host);
      expect(host.notices, isEmpty);

      await _checkAlone(tester, server, host);
      expect(host.notices, isEmpty);

      _arrive(server, 1, startAt: 20);
      await _checkAlone(tester, server, host);
      expect(host.notices.map((n) => n.title), ['Notice 20']);
    });

    testWidgets('an empty inbox still counts as a first check', (tester) async {
      await _prepareAlone(tester);
      final server = FakeKaneo()..notifications.clear();
      final host = FakeNotificationHost();
      await _checkAlone(tester, server, host);
      expect(host.notices, isEmpty);
      _arrive(server, 1);
      await _checkAlone(tester, server, host);
      expect(host.notices.map((n) => n.title), ['Notice 0']);
    });

    testWidgets('a first check that fails does not make the history new', (tester) async {
      await _prepareAlone(tester);
      final server = FakeKaneo()..failNext('api/notification', status: 500);
      final host = FakeNotificationHost();
      _arrive(server, 3);
      await _checkFails(tester, server, host);
      await _checkAlone(tester, server, host);
      expect(host.notices, isEmpty);
    });

    testBothLayouts('a backlog folds into one summary and the newest few, and it opens the inbox', (
      tester,
      size,
    ) async {
      final phone = await _openPhone(tester, size: size);
      await phone.leave();
      _arrive(phone.server, 9);
      await phone.runCheck();

      expect(phone.host.notices.map((n) => n.title), [
        'Kaneo',
        'Notice 5',
        'Notice 6',
        'Notice 7',
        'Notice 8',
      ]);
      expect(
        phone.host.notices.first.body,
        phone.app.i18n.t('mobile:background.summary', {'count': 5}),
      );
      expect(phone.host.notices.map((n) => n.id).toSet(), hasLength(5));

      await phone.comeBack();
      await phone.tap(phone.host.notices.first.payload);
      expect(phone.location, AppRoutes.inbox);
    });

    testWidgets('five at once all show, with no summary', (tester) async {
      final phone = await _openPhone(tester);
      await phone.leave();
      _arrive(phone.server, 5);
      await phone.runCheck();
      expect(phone.host.notices.map((n) => n.title), [for (var i = 0; i < 5; i++) 'Notice $i']);
    });

    testWidgets('a damaged record of what was seen counts as a first check', (tester) async {
      await _prepareAlone(
        tester,
        preferences: {notificationChecksEnabledKey: true, 'kaneo.notifications.seen': '{not json'},
      );
      final server = FakeKaneo();
      final host = FakeNotificationHost();
      await _checkAlone(tester, server, host);
      expect(host.notices, isEmpty);
    });
  });

  group('signing out and switching accounts', () {
    testBothLayouts('signing out removes what shows, stops the checks and ignores old taps', (
      tester,
      size,
    ) async {
      final phone = await _openPhone(tester, size: size);
      await phone.leave();
      phone.server.addNotification(title: 'For the old account', resourceId: _taskId);
      await phone.runCheck();
      final payload = phone.host.notices.single.payload;
      await phone.comeBack();

      await phone.app.container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(phone.host.notices, isEmpty);
      expect(phone.host.scheduled, isFalse);

      await phone.tap(payload);
      expect(phone.location, AppRoutes.login);

      final before = phone.checks;
      await phone.leave();
      await phone.runCheck();
      expect(phone.checks, before);
      expect(phone.host.notices, isEmpty);
    });

    testBothLayouts('another account starts over, without the old one and its notifications', (
      tester,
      size,
    ) async {
      final phone = await _openPhone(tester, size: size);
      await phone.leave();
      phone.server.addNotification(title: 'For the old account', resourceId: _taskId);
      await phone.runCheck();
      final oldTap = phone.host.notices.single.payload;
      await phone.comeBack();

      final session = phone.app.container.read(sessionProvider.notifier);
      await session.signOut();
      await tester.pumpAndSettle();
      phone.server.addNotification(title: 'Waiting for the new account')['userId'] = _otherUser;
      await session.signIn(_otherSession);
      await tester.pumpAndSettle();
      expect(phone.host.scheduled, isTrue);

      await phone.leave();
      phone.server.addNotification(title: 'Also for the old account', resourceId: _taskId);
      await phone.runCheck();
      expect(phone.host.notices, isEmpty, reason: 'History of the new, nothing of the old');

      phone.server.addNotification(title: 'For the new account', resourceId: _taskId)['userId'] =
          _otherUser;
      await phone.runCheck();
      expect(phone.host.notices.map((n) => n.title), ['For the new account']);
      await phone.comeBack();

      await phone.tap(oldTap);
      expect(taskOpen(_taskId), findsNothing);
      await phone.tap(phone.host.notices.single.payload);
      expect(taskOpen(_taskId), findsOneWidget);
    });

    testWidgets('the answer of a check that outlived the account is dropped', (tester) async {
      final phone = await _openPhone(tester);
      await phone.leave();
      phone.server.addNotification(title: 'For the old account', resourceId: _taskId);
      final gate = phone.server.hold('api/notification', method: 'GET');
      final pending = phone.startCheck();
      await _letRun(tester);

      await phone.app.container.read(sessionProvider.notifier).signOut();
      await _letRun(tester);
      gate.release();
      await _letRun(tester);
      await pending;
      expect(phone.host.notices, isEmpty);
    });

    testWidgets('a check that is posting stops as soon as the account is gone', (tester) async {
      await _prepareAlone(tester);
      final server = FakeKaneo();
      final host = _SigningOutHost();
      final storage = MemorySessionStorage(testSession);
      await _checkAlone(tester, server, host, storage: storage);
      _arrive(server, 3);
      host.onShown = storage.clear;
      await _checkAlone(tester, server, host, storage: storage);
      expect(host.notices, hasLength(1));
    });

    testWidgets('a token rejected while the app is open signs out and stops the checks', (
      tester,
    ) async {
      final phone = await _openPhone(tester);
      expect(phone.host.scheduled, isTrue);
      phone.server.credentialsRevoked = true;
      await phone.leave();
      await phone.comeBack();
      expect(phone.location, AppRoutes.login);
      expect(phone.host.scheduled, isFalse);
    });

    testWidgets('a rejected token leaves the session for the app to deal with', (tester) async {
      await _prepareAlone(tester);
      final server = FakeKaneo()..credentialsRevoked = true;
      final storage = MemorySessionStorage(testSession);
      await _checkFails(tester, server, FakeNotificationHost(), storage: storage);
      expect((await storage.read())?.token, testSession.token);
    });
  });

  group('the switch', () {
    testBothLayouts('turning it off stops the checks and removes what shows', (tester, size) async {
      final phone = await _openPhone(tester, size: size, location: AppRoutes.account);
      await phone.leave();
      phone.server.addNotification(title: 'Before turning it off', resourceId: _taskId);
      await phone.runCheck();
      final payload = phone.host.notices.single.payload;
      await phone.comeBack();

      expect(tester.widget<SwitchListTile>(find.byKey(_switch)).value, isTrue);
      await tester.tap(find.byKey(_switch));
      await tester.pumpAndSettle();
      expect(phone.enabled, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(_switch)).value, isFalse);
      expect(phone.host.scheduled, isFalse);
      expect(phone.host.notices, isEmpty);

      final before = phone.checks;
      await phone.leave();
      phone.server.addNotification(title: 'After turning it off', resourceId: _taskId);
      await phone.runCheck();
      expect(phone.checks, before);
      expect(phone.host.notices, isEmpty);

      await phone.comeBack();
      await phone.tap(payload);
      expect(phone.location, AppRoutes.account);
    });

    testWidgets('an answer that arrives after it was turned off is dropped', (tester) async {
      final phone = await _openPhone(tester);
      await phone.leave();
      phone.server.addNotification(title: 'Too late', resourceId: _taskId);
      final gate = phone.server.hold('api/notification', method: 'GET');
      final pending = phone.startCheck();
      await _letRun(tester);
      await phone.app.container.read(notificationChecksEnabledProvider.notifier).setEnabled(false);
      await _letRun(tester);
      gate.release();
      await _letRun(tester);
      await pending;
      expect(phone.host.notices, isEmpty);
    });

    testBothLayouts('turning it on asks the OS and shows no history', (tester, size) async {
      final phone = await _openPhone(
        tester,
        size: size,
        location: AppRoutes.account,
        preferences: const {notificationChecksEnabledKey: false},
      );
      expect(phone.host.permissionRequests, 0);
      expect(phone.host.scheduled, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(_switch)).value, isFalse);

      await tester.tap(find.byKey(_switch));
      await tester.pumpAndSettle();
      expect(phone.host.permissionRequests, 1);
      expect(phone.enabled, isTrue);
      expect(phone.host.scheduled, isTrue);

      await phone.leave();
      await phone.runCheck();
      expect(phone.host.notices, isEmpty);
    });

    testBothLayouts('when the OS says no, it says so and stays off', (tester, size) async {
      final phone = await _openPhone(
        tester,
        size: size,
        host: FakeNotificationHost()..allowed = false,
        location: AppRoutes.account,
        preferences: const {notificationChecksEnabledKey: false},
      );
      await tester.tap(find.byKey(_switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(phone.app.i18n.t('mobile:account.notifications.permissionDenied')),
        findsOne,
      );
      expect(phone.enabled, isFalse);
      expect(phone.host.scheduled, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('when asking the OS fails, it says so and stays off', (tester) async {
      final phone = await _openPhone(
        tester,
        host: FakeNotificationHost()..failure = Exception('No answer'),
        location: AppRoutes.account,
        preferences: const {notificationChecksEnabledKey: false},
      );
      await tester.tap(find.byKey(_switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(phone.app.i18n.t('mobile:account.notifications.permissionDenied')),
        findsOne,
      );
      expect(phone.enabled, isFalse);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('says how often it checks, in the words of the current app', (tester) async {
      final phone = await _openPhone(tester, location: AppRoutes.account);
      expect(find.text(phone.app.i18n.t('mobile:account.notifications.phone')), findsOneWidget);
      expect(find.text(phone.app.i18n.t('mobile:account.notifications.phoneHint')), findsOneWidget);
    });
  });

  group('asking the first time', () {
    testWidgets('the first signed-in launch asks once and remembers', (tester) async {
      final phone = await _openPhone(tester, preferences: const {});
      expect(phone.host.permissionRequests, 1);
      expect(phone.enabled, isTrue);
      await _letRun(tester);
      expect(phone.host.scheduled, isTrue);
    });

    testWidgets('a refusal is remembered too', (tester) async {
      final phone = await _openPhone(
        tester,
        host: FakeNotificationHost()..allowed = false,
        preferences: const {},
      );
      expect(phone.host.permissionRequests, 1);
      expect(phone.enabled, isFalse);
      expect(phone.host.scheduled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(notificationChecksEnabledKey), isFalse);
    });

    testWidgets('it waits for someone to sign in', (tester) async {
      final phone = await _openPhone(tester, session: null, preferences: const {});
      expect(phone.host.permissionRequests, 0);
      await phone.app.container.read(sessionProvider.notifier).signIn(testSession);
      await tester.pumpAndSettle();
      expect(phone.host.permissionRequests, 1);
    });

    testWidgets('later launches do not ask again', (tester) async {
      final phone = await _openPhone(tester);
      expect(phone.host.permissionRequests, 0);
      expect(phone.host.schedules, 1);
    });
  });

  group('when the OS fails', () {
    testBothLayouts('scheduling leaves the app usable', (tester, size) async {
      final phone = await _openPhone(
        tester,
        size: size,
        host: FakeNotificationHost()..failure = Exception('No BGTaskScheduler'),
      );
      expect(phone.host.scheduled, isFalse);
      expect(inPage(find.text('Demo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('off the phone', () {
    testWidgets('a platform without background checks leaves the OS alone', (tester) async {
      final host = FakeNotificationHost();
      final app = await pumpKaneoApp(
        tester,
        preferences: const {notificationChecksEnabledKey: true},
        overrides: [notificationHostProvider.overrideWithValue(host)],
      );
      final router = app.container.read(routerProvider);
      expect(app.container.read(notificationRuntimeProvider(router)), isNull);
      expect(host.initialized, isFalse);
      expect(host.schedules, 0);
    });

    testWidgets('the desktop switch asks through its own host and has no phone wording', (
      tester,
    ) async {
      final desktop = FakeDesktopHost()..allowed = false;
      final app = await pumpKaneoApp(
        tester,
        location: AppRoutes.account,
        preferences: const {notificationChecksEnabledKey: false},
        overrides: [
          isDesktopProvider.overrideWithValue(true),
          desktopHostProvider.overrideWithValue(desktop),
        ],
      );
      expect(find.text(app.i18n.t('mobile:account.notifications.title')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:account.notifications.phoneHint')), findsNothing);

      await tester.tap(find.byKey(_switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(app.i18n.t('mobile:account.notifications.permissionDenied')), findsOne);
      expect(app.container.read(notificationChecksEnabledProvider), isFalse);
      await tester.pumpAndSettle();
    });
  });
}

/// Calls [onShown] after each notification, to change things between one and the next.
class _SigningOutHost extends FakeNotificationHost {
  Future<void> Function()? onShown;

  @override
  Future<void> show({
    required int id,
    required String title,
    String? body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async {
    await super.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      channelName: channelName,
      channelDescription: channelDescription,
    );
    await onShown?.call();
  }
}
