// KAN-48: the acceptance criteria of KAN-4, KAN-10, KAN-11, KAN-12 and KAN-25 on a real device,
// against a local Kaneo. Run only through tool/with_device.sh with dev.env and these:
//
//     --dart-define=A_TEST_DEVICE=ipad|iphone|macos
//     --dart-define=A_TEST_EVIDENCE=<a folder, for the simulators>
//
// It signs up accounts of its own, whose workspaces and projects start with A-, so that nothing moves
// on the account everyone shares, and removes them again. macOS keeps the pictures in the app's
// container, because of its sandbox, and says where.
//
// Every criterion gets a line, `A_RESULT <id> PASS|FAIL|N/A|UNVERIFIED <note>`, and a failure doesn't
// stop the ones after it. Pictures are rendered by the app itself, so they need no unlocked screen.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/activity/activity_page.dart';
import 'package:kaneo_app/features/auth/login_page.dart';
import 'package:kaneo_app/features/home/home_page.dart';
import 'package:kaneo_app/features/inbox/inbox_page.dart';
import 'package:kaneo_app/features/inbox/my_tasks_page.dart';
import 'package:kaneo_app/features/inbox/notifications.dart' show inboxUnreadKey;
import 'package:kaneo_app/features/notifications/notification_check.dart';
import 'package:kaneo_app/features/notifications/notification_host.dart';
import 'package:kaneo_app/features/shell/account_page.dart';
import 'package:kaneo_app/features/shell/app_shell.dart' show shellPageKey;
import 'package:kaneo_app/features/shell/app_sidebar.dart';
import 'package:kaneo_app/features/task/task_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const _device = String.fromEnvironment('A_TEST_DEVICE', defaultValue: 'device');
const _evidence = String.fromEnvironment('A_TEST_EVIDENCE');
const _password = String.fromEnvironment('KANEO_DEV_PASSWORD');
const _seenKey = 'kaneo.notifications.seen';

bool get _isPhone => _device == 'iphone';
bool get _isMac => _device == 'macos';

final _captureKey = GlobalKey();

Finder _card(String id) => find.byKey(ValueKey('board-card-$id'));
Finder _taskOpen(String id) => find.byWidgetPredicate((w) => w is TaskView && w.taskId == id);

/// The count in the navigation. Nothing unread shows no count at all.
Finder _unread(int count) => count == 0
    ? find.byKey(inboxUnreadKey)
    : find.descendant(of: find.byKey(inboxUnreadKey), matching: find.text('$count'));

void _expectUnread(int count, {String? reason}) {
  expect(_unread(count), count == 0 ? findsNothing : findsOneWidget, reason: reason);
}

/// Stands in for the system's clock, for the night that can't be waited for.
class _Clock {
  DateTime? frozen;
  DateTime now() => frozen ?? DateTime.now();
}

/// The operating system's side of notifications. Nothing here reaches the system: banners and what
/// happens when they are tapped are for the administrator to see on a real device.
class _RecordingHost implements NotificationHost {
  void Function(String? payload)? onTap;
  final shown = <({String title, String? body, String payload})>[];
  int clears = 0;
  int schedules = 0;
  int unschedules = 0;

  @override
  Future<void> initialize(void Function(String? payload)? onTap) async {
    if (onTap != null) this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule() async => schedules++;

  @override
  Future<void> unschedule() async => unschedules++;

  @override
  Future<void> show({
    required int id,
    required String title,
    String? body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async => shown.add((title: title, body: body, payload: payload));

  @override
  Future<void> clear() async => clears++;
}

/// Says how often the background task asked who is signed in, which it only does when it checks.
class _CountingStorage extends MemorySessionStorage {
  _CountingStorage(super.session);

  int reads = 0;

  @override
  Future<Session?> read() {
    reads++;
    return super.read();
  }
}

/// An account of this test's own.
class _Person {
  const _Person(this.session, this.api, this.email);

  final Session session;
  final KaneoApi api;
  final String email;
}

class _Result {
  const _Result(this.id, this.status, this.note);

  final String id;
  final String status;
  final String note;

  Map<String, String> toJson() => {'id': id, 'status': status, 'note': note};
}

/// What's going on in one run.
class _Run {
  _Run(this.tester, this.directory);

  final WidgetTester tester;
  final Directory directory;
  final results = <_Result>[];
  late ProviderContainer container;

  GoRouter get router => container.read(routerProvider);
  I18n get i18n => container.read(i18nProvider);
  String t(String key, [Map<String, Object?> args = const {}]) => i18n.t(key, args);

  Future<void> pumpFor(Duration time) async {
    final deadline = DateTime.now().add(time);
    do {
      await tester.pump(const Duration(milliseconds: 50));
    } while (DateTime.now().isBefore(deadline));
  }

  Future<bool> until(bool Function() ready, {int seconds = 20}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return ready();
  }

  Future<void> see(Finder finder, {int seconds = 20}) async {
    expect(
      await until(() => finder.evaluate().isNotEmpty, seconds: seconds),
      isTrue,
      reason: 'Not on screen within ${seconds}s: $finder',
    );
  }

  Future<void> gone(Finder finder, {int seconds = 20}) async {
    expect(
      await until(() => finder.evaluate().isEmpty, seconds: seconds),
      isTrue,
      reason: 'Still on screen after ${seconds}s: $finder',
    );
  }

  Future<void> tap(Finder finder) async {
    await see(finder);
    final target = finder.first;
    if (target.hitTestable().evaluate().isEmpty) await tester.ensureVisible(target);
    await pumpFor(const Duration(milliseconds: 100));
    await tester.tap(target);
    await pumpFor(const Duration(milliseconds: 350));
  }

  Future<void> go(String location, Finder page) async {
    router.go(location);
    await see(page);
    await pumpFor(const Duration(milliseconds: 200));
  }

  Future<void> shot(String name) async {
    await pumpFor(const Duration(milliseconds: 400));
    final boundary = _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('A_EVIDENCE ${file.path}');
  }

  Future<ui.Image> _render() =>
      (_captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();

  /// How many pixels inside [area] differ after [change]. It is what the person gets to see, whatever
  /// the widgets are thought to be doing.
  Future<int> changedPixels(Rect area, Future<void> Function() change) async {
    await pumpFor(const Duration(milliseconds: 300));
    final before = await _render();
    final a = (await before.toByteData())!;
    final width = before.width;
    before.dispose();
    await change();
    await pumpFor(const Duration(milliseconds: 300));
    final after = await _render();
    final b = (await after.toByteData())!;
    after.dispose();
    var changed = 0;
    for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
      for (var x = area.left.floor(); x < area.right.ceil(); x++) {
        final at = (y * width + x) * 4;
        if (at + 4 > a.lengthInBytes || at + 4 > b.lengthInBytes) continue;
        if (a.getUint32(at) != b.getUint32(at)) changed++;
      }
    }
    return changed;
  }

  void record(String id, String status, [String note = '']) {
    results.add(_Result(id, status, note));
    debugPrint('A_RESULT $id $status $note');
  }

  void notApplicable(String id, String why) => record(id, 'N/A', why);

  void unverified(String id, String why) => record(id, 'UNVERIFIED', why);

  /// Closes what the check before may have left open, whether a panel, a popover or a sheet.
  Future<void> _tidy() async {
    router.routerDelegate.navigatorKey.currentState?.popUntil((route) => route is! PopupRoute);
    for (final task in find.byType(TaskView).evaluate().toList().reversed) {
      final route = ModalRoute.of(task);
      if (route is PopupRoute) route.navigator?.pop();
    }
    await pumpFor(const Duration(milliseconds: 400));
  }

  /// Runs one criterion, whatever became of the ones before it. What it returns goes with the result.
  Future<void> check(String id, Future<String?> Function() body) async {
    try {
      await _tidy();
      final note = await body();
      final exception = tester.takeException();
      if (exception != null) throw StateError('$exception');
      record(id, 'PASS', note ?? '');
    } catch (error) {
      tester.takeException();
      final message = '$error'.replaceAll('\n', ' ');
      record(id, 'FAIL', message.length > 400 ? message.substring(0, 400) : message);
      try {
        await shot('failure-$id');
      } catch (_) {
        // The failure is the news. A picture of it is a bonus.
      }
    }
  }

  /// Leaves the task on screen, which is a panel on wide windows and a page on narrow ones.
  Future<void> leaveTask(String id) async {
    final route = ModalRoute.of(tester.element(_taskOpen(id).first))!;
    if (route is PopupRoute) {
      route.navigator!.pop();
    } else {
      router.pop();
    }
    await gone(_taskOpen(id));
    await pumpFor(const Duration(milliseconds: 300));
  }

  /// Turns the device, and says how. An iPad that can share its screen doesn't have to do as asked,
  /// and then the window is given the new size instead, which is all a page gets to know about it.
  Future<String> orient({required bool landscape}) async {
    bool matches() {
      final size = tester.view.physicalSize;
      return landscape ? size.width > size.height : size.height > size.width;
    }

    final already = matches();
    await SystemChrome.setPreferredOrientations(
      landscape
          ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const [DeviceOrientation.portraitUp],
    );
    if (already) {
      await pumpFor(const Duration(milliseconds: 500));
      return 'already that way';
    }
    if (await until(matches, seconds: 6)) {
      await pumpFor(const Duration(milliseconds: 500));
      return 'system rotation';
    }
    final size = tester.view.physicalSize;
    tester.view.physicalSize = Size(size.height, size.width);
    await pumpFor(const Duration(milliseconds: 500));
    return 'the system ignored the request, so the window size was set instead';
  }

  Future<void> resetOrientation() async {
    tester.view.resetPhysicalSize();
    await SystemChrome.setPreferredOrientations(const []);
    await pumpFor(const Duration(seconds: 1));
  }

  Future<void> background() async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  Future<void> foreground() async {
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }
}

Future<ProviderContainer> _startApp(
  WidgetTester tester, {
  required Session? session,
  required _Clock clock,
  required NotificationHost host,
}) async {
  final storage = MemorySessionStorage(session);
  final base = await bootstrap(sessionStorage: storage);
  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      prefsProvider.overrideWithValue(base.read(prefsProvider)),
      i18nProvider.overrideWithValue(base.read(i18nProvider)),
      sessionStorageProvider.overrideWithValue(storage),
      initialSessionProvider.overrideWithValue(session),
      cacheRootProvider.overrideWithValue(base.read(cacheRootProvider)),
      nowProvider.overrideWithValue(clock.now),
      notificationHostProvider.overrideWithValue(host),
      // Signing out has to stay signed out.
      devConfigProvider.overrideWithValue(const DevConfig()),
    ],
  );
  base.dispose();
  await container.read(languageChoiceProvider.notifier).select(defaultLocale);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: UncontrolledProviderScope(container: container, child: const KaneoApp()),
    ),
  );
  return container;
}

Future<_Person> _signUp(String serverUrl, I18n i18n, String name, String email) async {
  final signedOut = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
  final response = await signedOut.requestRaw(
    'api/auth/sign-up/email',
    method: 'POST',
    body: {'name': name, 'email': email, 'password': _password},
    serverUrl: serverUrl,
  );
  expect(response.isOk, isTrue, reason: 'Could not sign up: ${response.status}');
  final session = await Authentication(signedOut, i18n).withPassword(serverUrl, email, _password);
  final api = KaneoApi(
    ApiClient(session: () => session, i18n: i18n, onSessionExpired: (_) {}),
    i18n,
  );
  return _Person(session, api, email);
}

/// Projects left behind by runs that got cut off. Only ever this line's own.
Future<void> _removeOldProjects(String serverUrl, I18n i18n, String workspaceId) async {
  final signedOut = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
  final session = await Authentication(
    signedOut,
    i18n,
  ).withPassword(serverUrl, const String.fromEnvironment('KANEO_DEV_EMAIL'), _password);
  final api = KaneoApi(
    ApiClient(session: () => session, i18n: i18n, onSessionExpired: (_) {}),
    i18n,
  );
  for (final project in await api.projects(workspaceId, includeArchived: true)) {
    if (project.name.startsWith('A-macos-') || project.name.startsWith('A-Second-macos-')) {
      await api.deleteProject(project.id);
      debugPrint('A_CLEANUP removed ${project.name}');
    }
  }
}

Future<void> _notify(
  KaneoApi api,
  String title, {
  String? taskId,
  String? workspaceId,
  String message = 'From the acceptance test',
}) => api.client.request(
  'api/notification',
  method: 'POST',
  body: {
    'title': title,
    'message': message,
    'type': 'info',
    if (taskId != null) ...{'relatedEntityId': taskId, 'relatedEntityType': 'task'},
    if (workspaceId != null) ...{'relatedEntityId': workspaceId, 'relatedEntityType': 'workspace'},
  },
);

Future<Directory> _evidenceDirectory() async {
  final Directory directory;
  if (_isMac || _evidence.isEmpty) {
    directory = Directory('${(await getApplicationDocumentsDirectory()).path}/A-KAN-48/$_device');
  } else {
    directory = Directory('$_evidence/$_device');
  }
  await directory.create(recursive: true);
  debugPrint('A_EVIDENCE_DIR ${directory.path}');
  return directory;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('KAN-48 shell acceptance on $_device', (tester) async {
    // Typed text goes straight to the fields. Input methods are for the administrator to try.
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);

    final config = DevConfig.fromEnvironment();
    final server = config.serverUrl;
    expect(
      ['localhost', '127.0.0.1', '::1'],
      contains(Uri.parse(server).host),
      reason: 'Local only',
    );
    if (_isMac) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1366, 1024));
    }

    // The preferences outlive the run, and the other tests on this device read them.
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    addTearDown(() async {
      await prefs.clear();
      for (final MapEntry(:key, :value) in saved.entries) {
        if (value is bool) await prefs.setBool(key, value);
        if (value is String) await prefs.setString(key, value);
        if (value is int) await prefs.setInt(key, value);
        if (value is double) await prefs.setDouble(key, value);
        if (value is List<String>) await prefs.setStringList(key, value);
      }
    });
    await prefs.remove('kaneo.lastWorkspaceId');
    await prefs.remove(_seenKey);
    // Present and off, so that the first launch doesn't ask the system for permission.
    await prefs.setBool(notificationChecksEnabledKey, false);

    final i18n = await I18n.load(locale: defaultLocale);
    await _removeOldProjects(server, i18n, config.workspaceId);

    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final key = stamp.toUpperCase();
    final ana = await _signUp(server, i18n, 'A Ana', 'a-shell-ana-$stamp@kaneo.local');
    addTearDown(() => ana.api.deleteUser(password: _password));
    final bo = await _signUp(server, i18n, 'A Bo', 'a-shell-bo-$stamp@kaneo.local');
    addTearDown(() => bo.api.deleteUser(password: _password));
    final boWorkspace = await bo.api.createWorkspace(name: 'A-Bo', slug: 'a-bo-$stamp');
    addTearDown(() => bo.api.deleteWorkspace(boWorkspace.id));
    final api = ana.api;
    final me = ana.session.userId;

    final one = await api.createWorkspace(name: 'A-One $stamp', slug: 'a-one-$stamp');
    addTearDown(() => api.deleteWorkspace(one.id));
    final two = await api.createWorkspace(name: 'A-Two $stamp', slug: 'a-two-$stamp');
    addTearDown(() => api.deleteWorkspace(two.id));

    Future<Project> project(String workspaceId, String name, String slug) =>
        api.createProject(name: name, workspaceId: workspaceId, icon: 'Layout', slug: slug);
    final main_ = await project(one.id, 'A-$_device-$stamp', 'AM$key');
    final second = await project(one.id, 'A-Second-$_device-$stamp', 'AS$key');
    final third = await project(one.id, 'A-Third-$_device-$stamp', 'AT$key');
    final findable = await project(one.id, 'A Findme $stamp project', 'AF$key');
    final elsewhere = await project(two.id, 'A-Elsewhere-$_device-$stamp', 'AE$key');

    Future<Task> task(
      Project project,
      String title, {
      String status = 'to-do',
      bool mine = true,
      String? due,
    }) => api.createTask(
      project.id,
      CreateTaskBody(
        title: title,
        description: '',
        priority: 'no-priority',
        status: status,
        userId: mine ? me : null,
        dueDate: due,
      ),
    );

    final today = await task(main_, 'A Today $stamp', due: toApiDate(DateTime.now()));
    final other = await task(main_, 'A Not mine $stamp', mine: false);
    final undated = await task(second, 'A Undated $stamp', status: 'in-progress');
    final found = await task(main_, 'A Findme $stamp task');
    final inTwo = await task(elsewhere, 'A In two $stamp');

    await _notify(api, 'A About a task $stamp', taskId: today.id);
    await _notify(api, 'A About nothing $stamp', workspaceId: one.id);
    await _notify(api, 'A In the second workspace $stamp', taskId: inTwo.id);
    await api.createComment(today.id, 'A Comment $stamp');

    final clock = _Clock();
    final host = _RecordingHost();
    final run = _Run(tester, await _evidenceDirectory());
    run.container = await _startApp(tester, session: ana.session, clock: clock, host: host);
    addTearDown(() async {
      run.container.dispose();
      await SystemChrome.setPreferredOrientations(const []);
    });
    await run.see(find.byKey(homeProjectKey(main_.id)));
    expect(run.container.read(currentWorkspaceProvider).value?.id, one.id);

    final home = find.byType(HomePage);
    final inbox = find.byType(InboxPage);
    final myTasks = find.byType(MyTasksPage);
    final activity = find.byType(ActivityPage);
    final account = find.byType(AccountPage);
    final sidebar = find.byType(AppSidebar);
    final tabs = find.byType(NavigationBar);

    // --- KAN-4 and KAN-25: which layout ---

    if (_isPhone) {
      run.notApplicable('KAN-4.1', 'an iPad criterion');
    } else {
      await run.check('KAN-4.1', () async {
        if (_isMac) {
          for (final size in const [Size(1366, 1024), Size(960, 1000), Size(1200, 700)]) {
            await windowManager.setSize(size);
            await run.pumpFor(const Duration(seconds: 1));
            await run.see(sidebar);
            expect(tabs, findsNothing);
          }
          await windowManager.setSize(const Size(1366, 1024));
          await run.pumpFor(const Duration(seconds: 1));
          await run.shot('home');
          return 'macOS windows, tall and wide';
        }
        final portrait = await run.orient(landscape: false);
        await run.see(sidebar);
        expect(tabs, findsNothing);
        await run.shot('ipad-portrait-home');
        final landscape = await run.orient(landscape: true);
        await run.see(sidebar);
        expect(tabs, findsNothing);
        await run.shot('ipad-landscape-home');
        return 'portrait: $portrait; landscape: $landscape';
      });
    }

    if (!_isPhone) {
      run.notApplicable('KAN-4.2', 'a phone criterion');
    } else {
      await run.check('KAN-4.2', () async {
        final portrait = await run.orient(landscape: false);
        await run.see(tabs);
        expect(sidebar, findsNothing);
        await run.shot('iphone-portrait-home');
        final landscape = await run.orient(landscape: true);
        await run.see(tabs);
        expect(sidebar, findsNothing);
        await run.shot('iphone-landscape-home');
        // The tabs do what they should from here too.
        await run.tap(find.descendant(of: tabs, matching: find.byIcon(LucideIcons.inbox)));
        await run.see(inbox);
        await run.shot('iphone-landscape-inbox');
        await run.resetOrientation();
        await run.orient(landscape: false);
        await run.tap(find.descendant(of: tabs, matching: find.byIcon(LucideIcons.house)));
        await run.see(home);
        return 'portrait: $portrait; landscape: $landscape';
      });
      // KAN-25 looks for the same thing.
    }

    if (_isPhone) {
      run.notApplicable('KAN-25.3', 'wide windows only');
    } else {
      await run.check('KAN-25.3', () async {
        await run.go(AppRoutes.home, home);
        Finder inSidebar(String text) => find.descendant(of: sidebar, matching: find.text(text));
        await run.see(inSidebar(one.name));
        await run.see(inSidebar(run.t('navigation:sidebar.home')));
        await run.see(inSidebar(run.t('navigation:sidebar.inbox')));
        await run.see(inSidebar(run.t('navigation:sidebar.myTasks')));
        await run.see(inSidebar(main_.name));
        await run.see(inSidebar(run.t('mobile:home.account')));
        return null;
      });
    }

    // --- KAN-10: the home page ---

    if (_isPhone) {
      run.notApplicable('KAN-10.1', 'wide windows only');
    } else {
      await run.check('KAN-10.1', () async {
        await run.go(AppRoutes.home, home);
        await run.see(find.byKey(homeProjectKey(main_.id)));
        final page = tester.getSize(find.byKey(shellPageKey)).width;
        final cards = [
          for (final p in [main_, second, third, findable])
            tester.getRect(find.byKey(homeProjectKey(p.id))),
        ];
        final first = cards.first;
        for (final card in cards) {
          expect(card.width, lessThan(page / 2), reason: 'A card must not fill the page.');
          expect(card.width, moreOrLessEquals(first.width, epsilon: 1));
        }
        final lefts = {for (final card in cards) card.left.round()};
        final tops = {for (final card in cards) card.top.round()};
        expect(lefts.length, greaterThan(1), reason: 'Side by side');
        expect(tops.length, lessThan(cards.length), reason: 'Side by side');
        await run.shot('home-grid');
        return '${lefts.length} columns, cards ${first.width.round()} wide, page ${page.round()}';
      });
    }

    await run.check('KAN-10.2', () async {
      await run.go(AppRoutes.home, home);
      final now = DateTime.now();
      final night = DateTime(now.year, now.month, now.day, 23, 59, 50);
      final morning = DateTime(now.year, now.month, now.day + 1, 0, 0, 10);
      clock.frozen = night;
      await run.background();
      await run.foreground();
      await tester.pump();
      await run.see(find.text(formatLongDate(run.i18n, night)));
      await run.see(find.text(greeting(run.i18n, night)));
      await run.background();
      clock.frozen = morning;
      await run.foreground();
      // Within the frame that follows, with nothing else happening first.
      await tester.pump();
      expect(find.text(formatLongDate(run.i18n, morning)), findsOneWidget);
      expect(find.text(greeting(run.i18n, morning)), findsOneWidget);
      expect(find.text(formatLongDate(run.i18n, night)), findsNothing);
      await run.shot('home-after-midnight');
      clock.frozen = null;
      await run.background();
      await run.foreground();
      await tester.pump();
      return 'clock injected, lifecycle events simulated; a real night and a real background are '
          'for the administrator';
    });

    // --- KAN-4: how wide pages grow, and what a mouse gets ---

    if (_isPhone) {
      run.notApplicable('KAN-4.4', 'wide windows only');
      run.notApplicable('KAN-4.5', 'wide windows only');
    } else {
      await run.check('KAN-4.4', () async {
        final notes = <String>[];
        for (final (name, location, page) in [
          ('account', AppRoutes.account, account),
          ('inbox', AppRoutes.inbox, inbox),
          ('my-tasks', AppRoutes.myTasks, myTasks),
          ('activity', AppRoutes.activity, activity),
        ]) {
          await run.go(location, page);
          final panel = tester.getSize(find.byKey(shellPageKey)).width;
          expect(
            panel,
            greaterThan(contentMaxWidth),
            reason: 'The window has to be wide for this.',
          );
          final content = find.descendant(of: page, matching: find.byType(ContentWidth)).first;
          final inner = find.descendant(of: content, matching: find.byType(ConstrainedBox)).first;
          expect(tester.getSize(inner).width, lessThanOrEqualTo(contentMaxWidth));
          await run.shot('wide-$name');
          notes.add('$name ${tester.getSize(inner).width.round()}/${panel.round()}');
        }
        return notes.join(', ');
      });

      await run.check('KAN-4.5', () async {
        await run.go(AppRoutes.home, home);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        // Hovering something shows, in pixels.
        final row = find.descendant(of: sidebar, matching: find.text(run.t('mobile:nav.activity')));
        final rowArea = tester.getRect(row).inflate(6);
        final rowChange = await run.changedPixels(
          rowArea,
          () => mouse.moveTo(tester.getCenter(row)),
        );
        expect(rowChange, greaterThan(100), reason: 'No hover feedback on a sidebar row');
        final project = find.byKey(homeProjectKey(main_.id));
        final cardChange = await run.changedPixels(
          tester.getRect(project),
          () => mouse.moveTo(tester.getCenter(project)),
        );
        expect(cardChange, greaterThan(100), reason: 'No hover feedback on a project card');
        await run.shot('hover-project-card');

        // A popover opens by what was clicked, and not as a sheet across the window.
        final window = tester.getSize(find.byType(MaterialApp));
        final switcher = find.descendant(of: sidebar, matching: find.text(one.name));
        final anchor = tester.getRect(switcher);
        await mouse.moveTo(anchor.center);
        await tester.pump();
        await mouse.down(anchor.center);
        await mouse.up();
        await run.see(find.byType(PopoverBody));
        await run.pumpFor(const Duration(milliseconds: 300));
        final popover = tester.getRect(find.byType(PopoverBody));
        expect(find.byType(BottomSheet), findsNothing);
        expect(popover.width, lessThan(window.width / 2));
        expect(
          (popover.top - anchor.bottom).abs(),
          lessThan(24),
          reason: 'Popover $popover, $anchor',
        );
        await run.shot('popover-workspace');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await run.gone(find.byType(PopoverBody));

        // A right-click opens its menu where the pointer is.
        await run.go(AppRoutes.board(main_.id), _card(today.id));
        final card = tester.getCenter(_card(today.id));
        await mouse.moveTo(card);
        await tester.pump();
        await mouse.removePointer();
        final rightClick = await tester.startGesture(
          card,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await rightClick.up();
        // A mouse stays where it is, and what's under it after this would look hovered in the pictures.
        await rightClick.removePointer();
        await run.see(find.byType(PopoverBody));
        await run.pumpFor(const Duration(milliseconds: 300));
        final menu = tester.getRect(find.byType(PopoverBody));
        expect(find.byType(BottomSheet), findsNothing);
        expect(menu.inflate(12).contains(card), isTrue, reason: 'Menu $menu, click $card');
        await run.shot('menu-right-click');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await run.gone(find.byType(PopoverBody));
        return 'simulated mouse events, real rendering; a real mouse on an iPad is for the '
            'administrator (KAN-13)';
      });
    }

    // --- KAN-4 and KAN-25: crossing the line ---

    Future<void> filterBoard() async {
      await run.go(AppRoutes.board(main_.id), _card(today.id));
      await run.tap(find.byIcon(LucideIcons.listFilter));
      await run.tap(find.text(run.t('mobile:board.me')).last);
      await run.see(find.byKey(const ValueKey('filter-count')));
      await run.gone(_card(other.id));
      expect(_card(today.id), findsOneWidget);
    }

    Future<void> clearFilter() async {
      // Filters live with the page, so a new page starts without.
      await run.go(AppRoutes.home, home);
    }

    if (_isPhone) {
      run.notApplicable('KAN-4.3', 'a phone stays narrow');
      run.notApplicable('KAN-25.2', 'a phone stays narrow');
    } else if (_isMac) {
      await run.check('KAN-4.3', () async {
        await filterBoard();
        await windowManager.setSize(minimumDesktopWindowSize);
        await run.pumpFor(const Duration(seconds: 1));
        await run.shot('board-filtered-smallest-window');
        expect(sidebar, findsOneWidget);
        expect(find.byKey(const ValueKey('filter-count')), findsOneWidget);
        expect(_card(other.id), findsNothing);
        expect(run.router.state.uri.path, AppRoutes.board(main_.id));
        await windowManager.setSize(const Size(1366, 1024));
        await run.pumpFor(const Duration(seconds: 1));
        expect(find.byKey(const ValueKey('filter-count')), findsOneWidget);
        await clearFilter();
        return 'the smallest macOS window is still wide, so nothing crosses here. A real resize kept '
            'the page and the filter. Crossing is checked on the iPad.';
      });
      run.notApplicable('KAN-25.2', 'the smallest macOS window is still wide');
    } else {
      await run.check('KAN-4.3', () async {
        final original = tester.view.physicalSize;
        final ratio = tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await filterBoard();
        await run.shot('board-filtered-wide');
        tester.view.physicalSize = Size(500, original.longestSide / ratio) * ratio;
        await run.gone(sidebar);
        await run.pumpFor(const Duration(milliseconds: 500));
        expect(MediaQuery.sizeOf(tester.element(_card(today.id))).shortestSide, lessThan(600));
        expect(run.router.state.uri.path, AppRoutes.board(main_.id));
        expect(find.byKey(const ValueKey('filter-count')), findsOneWidget);
        expect(_card(today.id), findsOneWidget);
        expect(_card(other.id), findsNothing);
        await run.shot('board-filtered-narrow');
        tester.view.physicalSize = original;
        await run.see(sidebar);
        await run.pumpFor(const Duration(milliseconds: 500));
        expect(run.router.state.uri.path, AppRoutes.board(main_.id));
        expect(find.byKey(const ValueKey('filter-count')), findsOneWidget);
        expect(_card(other.id), findsNothing);
        await clearFilter();
        return 'split view simulated with the window size. A real split view is for the '
            'administrator';
      });

      await run.check('KAN-25.2', () async {
        final original = tester.view.physicalSize;
        final ratio = tester.view.devicePixelRatio;
        for (final (name, location, page) in [
          ('inbox', AppRoutes.inbox, inbox),
          ('my-tasks', AppRoutes.myTasks, myTasks),
          ('activity', AppRoutes.activity, activity),
          ('account', AppRoutes.account, account),
          ('home', AppRoutes.home, home),
        ]) {
          await run.go(location, page);
          tester.view.physicalSize = Size(500, original.longestSide / ratio) * ratio;
          await run.gone(sidebar);
          await run.see(page);
          expect(run.router.state.uri.path, location);
          if (location != AppRoutes.account) expect(tabs, findsOneWidget);
          await run.shot('narrow-$name');
          tester.view.physicalSize = original;
          await run.see(sidebar);
          await run.see(page);
          expect(tabs, findsNothing);
          expect(run.router.state.uri.path, location);
        }
        return 'window size set, both ways';
      });
    }
    await run.resetOrientation();

    // --- KAN-11: the inbox, my tasks and search ---

    await run.check('KAN-11.1', () async {
      final notes = <String>[];
      // My tasks.
      await run.go(AppRoutes.myTasks, find.byKey(ValueKey(today.id)));
      await run.go(AppRoutes.home, home);
      await run.pumpFor(const Duration(seconds: 1));
      final added = await task(main_, 'A Added later $stamp');
      run.router.go(AppRoutes.myTasks);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(ValueKey(today.id)), findsOneWidget, reason: 'Not there at once');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await run.see(find.byKey(ValueKey(added.id)), seconds: 5);
      notes.add('my tasks');

      // The activity.
      await run.go(AppRoutes.activity, find.text('A Comment $stamp'));
      await run.go(AppRoutes.home, home);
      await run.pumpFor(const Duration(seconds: 1));
      await api.createComment(today.id, 'A Later comment $stamp');
      run.router.go(AppRoutes.activity);
      await tester.pump();
      await tester.pump();
      expect(find.text('A Comment $stamp'), findsOneWidget, reason: 'Not there at once');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await run.see(find.text('A Later comment $stamp'), seconds: 5);
      notes.add('activity');

      // The home page's projects, which nothing else keeps up to date.
      await run.go(AppRoutes.account, account);
      await run.pumpFor(const Duration(seconds: 1));
      final extra = await project(one.id, 'A-Late-$_device-$stamp', 'AL$key');
      run.router.go(AppRoutes.home);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(homeProjectKey(main_.id)), findsOneWidget, reason: 'Not there at once');
      await run.see(find.byKey(homeProjectKey(extra.id)), seconds: 5);
      await api.deleteProject(extra.id);
      notes.add('home');
      return notes.join(', ');
    });

    await run.check('KAN-11.2', () async {
      await run.go(AppRoutes.inbox, inbox);
      final list = await api.notifications(workspaceId: one.id);
      final aboutTask = list.firstWhere((n) => n.title == 'A About a task $stamp');
      final aboutNothing = list.firstWhere((n) => n.title == 'A About nothing $stamp');
      final unread = list.where((n) => n.isRead != true).length;
      await run.see(find.byKey(ValueKey(aboutNothing.id)));
      await run.see(_unread(unread));
      await run.shot('inbox-unread-$unread');

      Future<void> readOnServer(String id) async {
        for (var i = 0; i < 50; i++) {
          final current = await api.notifications(workspaceId: one.id);
          if (current.firstWhere((n) => n.id == id).isRead == true) return;
          await tester.pump(const Duration(milliseconds: 100));
        }
        fail('Never read on the server: $id');
      }

      // Not about a task: read, and nothing else.
      await tester.tap(find.byKey(ValueKey(aboutNothing.id)));
      await tester.pump();
      await tester.pump();
      _expectUnread(unread - 1, reason: 'KAN-11.3: the count has to drop at once');
      await readOnServer(aboutNothing.id);
      await run.pumpFor(const Duration(milliseconds: 300));
      expect(inbox, findsOneWidget);
      expect(find.byType(TaskView), findsNothing);

      // About a task: read, and it opens.
      await tester.tap(find.byKey(ValueKey(aboutTask.id)));
      await tester.pump();
      await tester.pump();
      await run.see(_taskOpen(today.id));
      await run.shot('task-from-inbox');
      await readOnServer(aboutTask.id);

      // KAN-59: nothing below this task has its project's connection.
      await run.pumpFor(const Duration(seconds: 1));
      await api.updateTitle(today.id, 'A Renamed elsewhere $stamp');
      bool renamed() =>
          tester.widget<TextField>(find.byKey(const ValueKey('task-title'))).controller!.text ==
          'A Renamed elsewhere $stamp';
      final stopwatch = Stopwatch()..start();
      expect(await run.until(renamed, seconds: 5), isTrue, reason: 'KAN-59: not within 5 seconds');
      final latency = stopwatch.elapsedMilliseconds;
      await run.leaveTask(today.id);
      return 'KAN-59 on this device: ${latency}ms';
    });

    await run.check('KAN-11.3', () async {
      await run.go(AppRoutes.inbox, inbox);
      final list = await api.notifications(workspaceId: one.id);
      final unread = list.where((n) => n.isRead != true).length;
      await _notify(api, 'A One more $stamp', workspaceId: one.id);
      await run.see(_unread(unread + 1), seconds: 5);
      final latest = (await api.notifications(workspaceId: one.id))
          .firstWhere((n) => n.title == 'A One more $stamp');
      await run.see(find.byKey(ValueKey(latest.id)));
      await tester.tap(find.byKey(ValueKey(latest.id)));
      await tester.pump();
      await tester.pump();
      _expectUnread(unread, reason: 'The count has to drop at once');
      return 'the count arrived over the socket and left in the next frame, with the write still '
          'on its way';
    });

    await run.check('KAN-11.4', () async {
      await run.go(AppRoutes.myTasks, find.byKey(ValueKey(today.id)));
      Finder inList(String text) => find.descendant(of: myTasks, matching: find.text(text));
      await run.see(inList(run.t('mobile:myTasks.due.today')));
      await run.see(inList(run.t('mobile:myTasks.due.none')));
      await run.shot('my-tasks-by-due');
      await run.tap(find.text(run.t('mobile:myTasks.by.project')));
      await run.see(inList(main_.name));
      await run.see(inList(second.name));
      // A row still says when it's due. This heading has nothing else to come from.
      expect(inList(run.t('mobile:myTasks.due.none')), findsNothing);
      await run.shot('my-tasks-by-project');
      await run.tap(find.text(run.t('mobile:myTasks.by.status')));
      await run.see(inList('To Do'));
      await run.see(inList('In Progress'));
      await run.see(find.byKey(ValueKey(undated.id)));
      await run.shot('my-tasks-by-status');
      await run.tap(find.byKey(ValueKey(undated.id)));
      await run.see(_taskOpen(undated.id));
      await run.shot('task-from-my-tasks');
      await run.leaveTask(undated.id);
      return null;
    });

    await run.check('KAN-11.5', () async {
      await run.go(AppRoutes.search, find.byKey(const ValueKey('search-field')));
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'Findme $stamp');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      final foundTask = find.byKey(ValueKey('task-${found.id}'));
      final foundProject = find.byKey(ValueKey('project-${findable.id}'));
      await run.see(foundTask);
      await run.see(foundProject);
      await run.shot('search-results');
      await run.tap(foundTask);
      await run.see(_taskOpen(found.id));
      await run.leaveTask(found.id);
      await run.tap(foundProject);
      expect(
        await run.until(() => run.router.state.uri.path == AppRoutes.board(findable.id)),
        isTrue,
      );
      await run.pumpFor(const Duration(seconds: 1));
      await run.shot('board-from-search');
      await run.go(AppRoutes.home, home);
      await run.pumpFor(const Duration(seconds: 1));
      return null;
    });

    await run.check('pages', () async {
      await run.go(AppRoutes.board(main_.id), _card(found.id));
      await run.pumpFor(const Duration(seconds: 1));
      await run.shot('board');
      await run.go(AppRoutes.activity, activity);
      await run.shot('activity');
      await run.go(AppRoutes.account, account);
      await run.shot('account');
      await run.go(AppRoutes.home, home);
      await run.shot('home');
      return null;
    });

    // --- KAN-10: another workspace, and the next launch ---

    await run.check('KAN-10.3', () async {
      await run.go(AppRoutes.home, find.byKey(homeProjectKey(main_.id)));
      await run.tap(find.text(one.name));
      await run.shot('workspace-switcher');
      await run.tap(find.text(two.name).last);
      await run.see(find.byKey(homeProjectKey(elsewhere.id)));
      expect(find.byKey(homeProjectKey(main_.id)), findsNothing);
      await run.shot('home-second-workspace');
      await run.go(AppRoutes.myTasks, find.byKey(ValueKey(inTwo.id)));
      expect(find.byKey(ValueKey(today.id)), findsNothing);
      await run.shot('my-tasks-second-workspace');
      await run.go(AppRoutes.inbox, find.text('A In the second workspace $stamp'));
      expect(find.text('A About nothing $stamp'), findsNothing);
      await run.shot('inbox-second-workspace');
      return null;
    });

    await run.check('KAN-10.4', () async {
      final before = run.container;
      await tester.pumpWidget(const SizedBox());
      before.dispose();
      await run.pumpFor(const Duration(milliseconds: 300));
      run.container = await _startApp(tester, session: ana.session, clock: clock, host: host);
      await run.see(find.byKey(homeProjectKey(elsewhere.id)));
      expect(run.container.read(currentWorkspaceProvider).value?.id, two.id);
      await run.shot('home-next-launch');
      // Back to where the rest of this expects to be.
      await run.container.read(selectedWorkspaceIdProvider.notifier).select(one.id);
      await run.see(find.byKey(homeProjectKey(main_.id)));
      return 'the app was started again in the same process, on the preferences it left. A real '
          'restart is for the administrator';
    });

    // --- KAN-12: what happens around notifications ---

    run.unverified(
      'KAN-12.1',
      'not in this file: integration_test/realtime_test.dart cuts the network with a relay, and its '
          'results are next to this one',
    );

    run.unverified(
      'KAN-12.2',
      'system banners, tapping one and the permission prompt are for the administrator',
    );
    if (_isMac) {
      run.notApplicable(
        'KAN-12.2-handler',
        'macOS has its own runtime: integration_test/desktop_test.dart',
      );
    } else {
      await run.check('KAN-12.2-handler', () async {
        await run.container.read(notificationChecksEnabledProvider.notifier).setEnabled(true);
        await run.pumpFor(const Duration(milliseconds: 500));
        expect(host.onTap, isNotNull);
        host.onTap!(encodeNotice(accountScope(ana.session), found.id));
        await run.see(_taskOpen(found.id));
        await run.shot('task-from-notification');
        await run.go(AppRoutes.home, home);
        return 'what a tap calls, called directly';
      });
    }

    final background = _RecordingHost();
    Future<void> check(SessionStorage storage) =>
        runBackgroundCheck(host: background, storage: storage);

    await run.check('KAN-12.3', () async {
      // What the app does as it goes to the background, which this can't have happen for real.
      await prefs.setBool(notificationChecksEnabledKey, true);
      await prefs.setBool(notificationForegroundKey, false);
      await prefs.remove(_seenKey);
      final storage = MemorySessionStorage(ana.session);
      await _notify(api, 'A Unread history $stamp', workspaceId: one.id);
      await check(storage);
      expect(background.shown, isEmpty, reason: 'The first check must not replay the history.');

      await check(storage);
      expect(background.shown, isEmpty, reason: 'Nothing new since.');

      await _notify(api, 'A Single $stamp', taskId: today.id);
      await check(storage);
      expect(background.shown.map((n) => n.title), ['A Single $stamp']);
      expect(decodeNotice(background.shown.single.payload)?.taskId, today.id);
      background.shown.clear();

      for (var i = 1; i <= 7; i++) {
        await _notify(api, 'A Backlog $i $stamp', taskId: today.id);
        // Keeps them in order, as their times are the only thing that says which is older.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await check(storage);
      expect(background.shown, hasLength(5), reason: 'Past five, the oldest fold into a summary.');
      expect(background.shown.first.title, 'Kaneo');
      expect(background.shown.first.body, run.t('mobile:background.summary', {'count': 3}));
      expect(background.shown.skip(1).map((n) => n.title), [
        for (var i = 4; i <= 7; i++) 'A Backlog $i $stamp',
      ]);
      background.shown.clear();
      return 'the check itself against the real server, with a recording host. No system banner';
    });

    await run.check('KAN-12.5', () async {
      await run.go(AppRoutes.account, account);
      final enabled = run.container.read(notificationChecksEnabledProvider.notifier);
      await enabled.setEnabled(true);
      await run.pumpFor(const Duration(milliseconds: 500));
      final toggle = find.byKey(const ValueKey('notification-checks'));
      if (toggle.hitTestable().evaluate().isEmpty) await tester.ensureVisible(toggle);
      await run.pumpFor(const Duration(milliseconds: 200));
      await run.shot('account-notifications-on');
      final unschedules = host.unschedules;
      await run.tap(toggle);
      expect(run.container.read(notificationChecksEnabledProvider), isFalse);
      expect(prefs.getBool(notificationChecksEnabledKey), isFalse);
      await run.shot('account-notifications-off');
      if (!_isMac) expect(host.unschedules, greaterThan(unschedules), reason: 'Still scheduled');

      await prefs.setBool(notificationForegroundKey, false);
      await _notify(api, 'A While off $stamp', taskId: today.id);
      final storage = _CountingStorage(ana.session);
      await check(storage);
      expect(storage.reads, 0, reason: 'Switched off, it must not even look.');
      expect(background.shown, isEmpty);
      return _isMac
          ? 'the switch and the check; the OS side on macOS is in integration_test/desktop_test.dart'
          : 'the switch unscheduled the task, and a check that ran anyway did nothing';
    });

    await run.check('KAN-12.4', () async {
      await run.go(AppRoutes.account, account);
      final enabled = run.container.read(notificationChecksEnabledProvider.notifier);
      await enabled.setEnabled(true);
      await run.pumpFor(const Duration(milliseconds: 500));
      final clears = host.clears;

      // Signing out, as the person does.
      final button = find.text(run.t('mobile:account.signOut.button'));
      if (button.hitTestable().evaluate().isEmpty) await tester.ensureVisible(button.first);
      await run.pumpFor(const Duration(milliseconds: 200));
      await run.tap(button);
      await run.tap(find.text(run.t('mobile:account.signOut.button')).last);
      await run.see(find.byType(LoginPage));
      expect(run.container.read(sessionProvider), isNull);
      await run.shot('signed-out');
      if (!_isMac) {
        expect(await run.until(() => host.clears > clears), isTrue, reason: 'Banners not cleared');
      }

      // Somebody else: nothing of the first account shows, and its notices lead nowhere.
      final clearsAtSignIn = host.clears;
      await run.container.read(sessionProvider.notifier).signIn(bo.session);
      await run.pumpFor(const Duration(milliseconds: 500));
      run.router.go(AppRoutes.inbox);
      await run.see(inbox);
      expect(
        await run.until(() => run.container.read(notificationsQuery(boWorkspace.id)).hasValue),
        isTrue,
      );
      await run.pumpFor(const Duration(milliseconds: 500));
      // The first account's all carry this. The second's own, about its workspace, don't.
      expect(find.textContaining(stamp), findsNothing, reason: 'Something of the first account');
      await run.shot('other-account-inbox');
      if (!_isMac) {
        expect(host.clears, greaterThanOrEqualTo(clearsAtSignIn));
        host.onTap!(encodeNotice(accountScope(ana.session), today.id));
        await run.pumpFor(const Duration(seconds: 1));
        expect(
          find.byType(TaskView),
          findsNothing,
          reason: "A notice of the last account's opened",
        );
      }

      // The background check, too, doesn't replay the first account as new for the second.
      await prefs.setBool(notificationChecksEnabledKey, true);
      await prefs.setBool(notificationForegroundKey, false);
      background.shown.clear();
      await check(MemorySessionStorage(bo.session));
      expect(background.shown, isEmpty);
      return 'system banners actually going away is for the administrator';
    });

    final summary = const JsonEncoder.withIndent('  ').convert(run.results);
    await File('${run.directory.path}/results.json').writeAsString(summary);
    final failed = run.results.where((r) => r.status == 'FAIL').map((r) => r.id).toList();
    debugPrint('A_SUMMARY ${run.results.length} results, failed: $failed');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(failed, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
