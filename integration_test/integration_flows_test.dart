// KAN-45: the flows that cross from one line of phase one into another, in the real app on a device,
// against a local Kaneo. Run only through tool/with_device.sh, with dev.env for the server address:
//
//     tool/with_device.sh --boot "iPhone 17" flutter test integration_test/integration_flows_test.dart \
//       -d "iPhone 17" --dart-define-from-file=$HOME/.config/kaneo-app/dev.env \
//       --dart-define=E_TEST_DEVICE=iphone --dart-define=E_TEST_EVIDENCE=<a folder>
//     FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=app.kaneo.kaneoApp.ETest tool/with_device.sh \
//       flutter test integration_test/integration_flows_test.dart -d macos \
//       --dart-define-from-file=$HOME/.config/kaneo-app/dev.env --dart-define=E_TEST_DEVICE=macos
//
// It signs up two accounts of its own, with workspaces and projects named E-..., and removes them
// again, so nothing moves on the account everyone shares. The app signs in with passwords, which
// have no request limit. Pictures are rendered by the app itself, so they need no unlocked screen;
// macOS keeps them in the app's container, because of its sandbox, and says where.
//
// What reaches the operating system is replaced: a banner and the tap on it are for the
// administrator. What the app does with the tap is real.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

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
import 'package:kaneo_app/features/notifications/notification_check.dart';
import 'package:kaneo_app/features/notifications/notification_host.dart';
import 'package:kaneo_app/features/search/search_page.dart';
import 'package:kaneo_app/features/shell/account_page.dart';
import 'package:kaneo_app/features/task/task_view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const _device = String.fromEnvironment('E_TEST_DEVICE', defaultValue: 'device');
const _evidence = String.fromEnvironment('E_TEST_EVIDENCE');

final _capture = GlobalKey();
final _stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _card(String id) => _key('board-card-$id');
Finder _inColumn(String slug, String id) =>
    find.descendant(of: _key('drop-column-$slug'), matching: _card(id));
Finder _taskOpen(String id) => find.byWidgetPredicate((w) => w is TaskView && w.taskId == id);

/// Text of [marker]'s, anywhere on screen, including the sidebar on wide windows.
Finder _anything(String marker) => find.textContaining(marker, findRichText: true);

String _password() {
  final random = Random.secure();
  return 'E-${base64Url.encode(List.generate(15, (_) => random.nextInt(256)))}';
}

/// An account of this test's own.
class _Person {
  _Person(this.name, this.email, this.password, this.session, this.api);

  final String name;
  final String email;
  final String password;
  final Session session;
  final KaneoApi api;
}

/// Everything the flows start from. Each account's and workspace's data carries its own marker, so
/// that a page showing any of it can be caught.
class _World {
  late final String server;
  late final _Person ana;
  late final _Person bo;
  late final Workspace one;
  late final Workspace two;
  late final Workspace boHome;
  late final Project board;
  late final Project elsewhere;
  late final Project boProject;
  late final List<ProjectColumn> columns;
  late final Task open;
  late final Task edited;
  late final Task notified;
  late final Task inTwo;
  late final Task boTask;
  late final String oneNotice;
  late final String twoNotice;
  late final String boNotice;

  String get oneMarker => 'E-one-$_stamp';
  String get twoMarker => 'E-two-$_stamp';
  String get boMarker => 'E-bo-$_stamp';
}

final _w = _World();

/// The operating system's side of phone notifications. The app's side is real.
class _PhoneHost implements NotificationHost {
  void Function(String? payload)? onTap;
  final shown = <({String title, String payload})>[];

  @override
  Future<void> initialize(void Function(String? payload)? onTap) async {
    if (onTap != null) this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule() async {}

  @override
  Future<void> unschedule() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    String? body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async => shown.add((title: title, payload: payload));

  @override
  Future<void> clear() async {}
}

/// The operating system's side of desktop notifications. The app's side is real.
class _DesktopHost implements DesktopHost {
  void Function(String? payload)? onTap;
  final shown = <({String title, String? body, String payload})>[];

  @override
  Future<void> configureWindow() async {}

  @override
  Future<void> initializeNotifications(void Function(String? payload) onTap, String label) async {
    this.onTap = onTap;
  }

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> showNotice({
    required int id,
    required String title,
    String? body,
    required String payload,
  }) async => shown.add((title: title, body: body, payload: payload));

  @override
  Future<void> clearNotices() async {}

  @override
  Future<void> foregroundWindow() async {}
}

/// Drives the app.
class _Run {
  _Run(this.tester, this.container);

  final WidgetTester tester;
  ProviderContainer container;

  GoRouter get router => container.read(routerProvider);
  String t(String key) => container.read(i18nProvider).t(key);
  bool get wide =>
      MediaQuery.sizeOf(tester.element(find.byType(Navigator).first)).shortestSide >= 600;

  Future<void> pumpFor(Duration time) async {
    final end = DateTime.now().add(time);
    do {
      await tester.pump(const Duration(milliseconds: 50));
    } while (DateTime.now().isBefore(end));
  }

  Future<bool> until(bool Function() ready, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!ready() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return ready();
  }

  /// Waits for the server to agree, pumping the app meanwhile.
  Future<void> server(String what, Future<bool> Function() agrees) async {
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(end)) {
      if (await agrees()) return;
      await pumpFor(const Duration(milliseconds: 200));
    }
    fail('The server never had $what');
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
    await pumpFor(const Duration(milliseconds: 150));
    await tester.tap(target);
    await pumpFor(const Duration(milliseconds: 400));
  }

  Future<void> go(String location, Finder page) async {
    router.go(location);
    await see(page);
    await pumpFor(const Duration(milliseconds: 300));
  }

  Future<void> shot(String name) async {
    await pumpFor(const Duration(milliseconds: 400));
    final boundary = _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = await _evidenceDirectory();
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('E_EVIDENCE ${file.path}');
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

  /// Nothing of [marker]'s is anywhere on screen, whatever the page has loaded by now.
  Future<void> nothingOf(String marker, String page) async {
    await pumpFor(const Duration(milliseconds: 800));
    expect(_anything(marker), findsNothing, reason: '$page shows something of $marker');
  }

  Future<void> search(String text) async {
    final field = _key('search-field');
    await see(field);
    await tester.enterText(field, text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpFor(const Duration(milliseconds: 300));
  }
}

Directory? _evidenceRoot;

Future<Directory> _evidenceDirectory() async {
  if (_evidenceRoot != null) return _evidenceRoot!;
  final Directory directory;
  if (Platform.isMacOS || _evidence.isEmpty) {
    directory = Directory('${(await getApplicationDocumentsDirectory()).path}/E-KAN-45/$_device');
  } else {
    directory = Directory('$_evidence/$_device');
  }
  await directory.create(recursive: true);
  debugPrint('E_EVIDENCE_DIR ${directory.path}');
  return _evidenceRoot = directory;
}

KaneoApi _apiFor(Session session, I18n i18n) =>
    KaneoApi(ApiClient(session: () => session, i18n: i18n, onSessionExpired: (_) {}), i18n);

Future<_Person> _signUp(I18n i18n, String name, String email) async {
  final password = _password();
  final signedOut = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
  final response = await signedOut.requestRaw(
    'api/auth/sign-up/email',
    method: 'POST',
    body: {'name': name, 'email': email, 'password': password},
    serverUrl: _w.server,
  );
  expect(response.isOk, isTrue, reason: 'Could not sign up: ${response.status}');
  final session = await Authentication(signedOut, i18n).withPassword(_w.server, email, password);
  return _Person(name, email, password, session, _apiFor(session, i18n));
}

/// A notice about [taskId] for whoever [api] signs in as, as the server sends for activity.
Future<String> _notify(KaneoApi api, String workspaceId, String title, String taskId) async {
  await api.client.request(
    'api/notification',
    method: 'POST',
    body: {
      'title': title,
      'message': 'From the integration flows',
      'type': 'info',
      'relatedEntityId': taskId,
      'relatedEntityType': 'task',
    },
  );
  final all = await api.notifications(workspaceId: workspaceId);
  return all.firstWhere((n) => n.title == title).id;
}

Future<void> _setUp(I18n i18n) async {
  final w = _w;
  w.server = DevConfig.fromEnvironment().serverUrl;
  expect(
    ['localhost', '127.0.0.1', '::1'],
    contains(Uri.parse(w.server).host),
    reason: 'Local only',
  );
  final key = _stamp.toUpperCase();

  w.ana = await _signUp(i18n, 'E Ana $_stamp', 'e-flows-ana-$_device-$_stamp@kaneo.local');
  w.bo = await _signUp(i18n, 'E Bo $_stamp', 'e-flows-bo-$_device-$_stamp@kaneo.local');
  final ana = w.ana.api;
  final bo = w.bo.api;

  w.one = await ana.createWorkspace(name: 'E-One $_stamp', slug: 'e-one-$_device-$_stamp');
  w.two = await ana.createWorkspace(name: 'E-Two $_stamp', slug: 'e-two-$_device-$_stamp');
  w.boHome = await bo.createWorkspace(name: 'E-Bo $_stamp', slug: 'e-bo-$_device-$_stamp');

  Future<Project> project(KaneoApi api, Workspace workspace, String name, String slug) =>
      api.createProject(name: name, workspaceId: workspace.id, icon: 'Layout', slug: slug);
  w.board = await project(ana, w.one, '${w.oneMarker} board', 'EO$key');
  w.elsewhere = await project(ana, w.two, '${w.twoMarker} project', 'ET$key');
  w.boProject = await project(bo, w.boHome, '${w.boMarker} project', 'EB$key');
  w.columns = await ana.columns(w.board.id);

  Future<Task> task(KaneoApi api, Project project, String title, String userId) async {
    final columns = await api.columns(project.id);
    return api.createTask(
      project.id,
      CreateTaskBody(
        title: title,
        description: '',
        priority: 'low',
        status: columns.first.slug,
        userId: userId,
      ),
    );
  }

  final anaId = w.ana.session.userId;
  w.open = await task(ana, w.board, '${w.oneMarker} open me', anaId);
  w.edited = await task(ana, w.board, '${w.oneMarker} edit me', anaId);
  w.notified = await task(ana, w.board, '${w.oneMarker} notified', anaId);
  w.inTwo = await task(ana, w.elsewhere, '${w.twoMarker} task', anaId);
  w.boTask = await task(bo, w.boProject, '${w.boMarker} task', w.bo.session.userId);

  await ana.createComment(w.open.id, '${w.oneMarker} comment');
  await ana.createComment(w.inTwo.id, '${w.twoMarker} comment');
  await bo.createComment(w.boTask.id, '${w.boMarker} comment');

  w.oneNotice = await _notify(ana, w.one.id, '${w.oneMarker} notice', w.notified.id);
  w.twoNotice = await _notify(ana, w.two.id, '${w.twoMarker} notice', w.inTwo.id);
  w.boNotice = await _notify(bo, w.boHome.id, '${w.boMarker} notice', w.boTask.id);
  debugPrint('E_SETUP accounts ${w.ana.email} ${w.bo.email}, stamp $_stamp');
}

/// Removes what [_setUp] made, as far as it got.
Future<void> _tearDown() async {
  final w = _w;
  for (final (what, remove) in <(String, Future<void> Function())>[
    ('workspace one', () => w.ana.api.deleteWorkspace(w.one.id)),
    ('workspace two', () => w.ana.api.deleteWorkspace(w.two.id)),
    ('workspace bo', () => w.bo.api.deleteWorkspace(w.boHome.id)),
    ('account ana', () => w.ana.api.deleteUser(password: w.ana.password)),
    ('account bo', () => w.bo.api.deleteUser(password: w.bo.password)),
  ]) {
    try {
      await remove();
    } catch (error) {
      debugPrint('E_CLEANUP $what: $error');
    }
  }
}

/// Starts the app afresh, signed in as [person], in [workspace].
Future<_Run> _start(
  WidgetTester tester,
  _Person person, {
  required Workspace workspace,
  bool notifications = false,
  NotificationHost? phone,
  DesktopHost? desktop,
}) async {
  // Typed text goes straight to the fields. Input methods are for the administrator to try.
  tester.testTextInput.register();
  addTearDown(tester.testTextInput.unregister);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('kaneo.lastWorkspaceId', workspace.id);
  // Present either way, so that the first launch doesn't ask the system for permission.
  await prefs.setBool(notificationChecksEnabledKey, notifications);

  final storage = MemorySessionStorage(person.session);
  final base = await bootstrap(sessionStorage: storage);
  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      prefsProvider.overrideWithValue(base.read(prefsProvider)),
      i18nProvider.overrideWithValue(base.read(i18nProvider)),
      sessionStorageProvider.overrideWithValue(storage),
      initialSessionProvider.overrideWithValue(person.session),
      cacheRootProvider.overrideWithValue(base.read(cacheRootProvider)),
      notificationHostProvider.overrideWithValue(phone ?? _PhoneHost()),
      desktopHostProvider.overrideWithValue(desktop ?? _DesktopHost()),
      // Signing out has to stay signed out, not sign in again with dev.env.
      devConfigProvider.overrideWithValue(const DevConfig()),
    ],
  );
  base.dispose();
  await container.read(languageChoiceProvider.notifier).select(defaultLocale);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: UncontrolledProviderScope(container: container, child: const KaneoApp()),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    container.dispose();
    await SystemChrome.setPreferredOrientations(const []);
  });
  final run = _Run(tester, container);
  await run.see(find.byType(HomePage));
  return run;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Object> savedPrefs;

  setUpAll(() async {
    if (Platform.isMacOS) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1366, 1024));
    }
    // The preferences outlive the run, and the other tests on this device read them.
    final prefs = await SharedPreferences.getInstance();
    savedPrefs = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    await _setUp(await I18n.load(locale: defaultLocale));
  });

  tearDownAll(() async {
    await _tearDown();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    for (final MapEntry(:key, :value) in savedPrefs.entries) {
      if (value is bool) await prefs.setBool(key, value);
      if (value is String) await prefs.setString(key, value);
      if (value is int) await prefs.setInt(key, value);
      if (value is double) await prefs.setDouble(key, value);
      if (value is List<String>) await prefs.setStringList(key, value);
    }
  });

  testWidgets('the board opens a task, beside it when wide and as a page when narrow', (
    tester,
  ) async {
    final w = _w;
    final run = await _start(tester, w.ana, workspace: w.one);
    await run.go(AppRoutes.board(w.board.id), _card(w.open.id));
    await run.tap(_card(w.open.id));
    await run.see(_taskOpen(w.open.id));
    final title = find.descendant(of: _taskOpen(w.open.id), matching: _key('task-title'));
    await run.see(title);
    expect(tester.widget<TextField>(title).controller!.text, w.open.title);

    final route = ModalRoute.of(tester.element(_taskOpen(w.open.id)))!;
    if (run.wide) {
      // A panel over the board, which stays where it was.
      expect(route, isA<PopupRoute<void>>());
      expect(run.router.state.uri.path, AppRoutes.board(w.board.id));
      expect(_card(w.open.id), findsOneWidget);
    } else {
      expect(route, isNot(isA<PopupRoute<void>>()));
      expect(run.router.state.uri.path, AppRoutes.task(w.open.id));
    }
    // The comment comes from the task line's activity, on the same task.
    await run.see(find.descendant(of: _taskOpen(w.open.id), matching: _anything('comment')));
    await run.shot('1-board-opens-task');

    await run.leaveTask(w.open.id);
    expect(run.router.state.uri.path, AppRoutes.board(w.board.id));
    await run.see(_card(w.open.id));
  });

  testWidgets('what changes in a task shows on its board', (tester) async {
    final w = _w;
    final run = await _start(tester, w.ana, workspace: w.one);
    final todo = w.columns[0];
    final doing = w.columns[1];
    await run.go(AppRoutes.board(w.board.id), _inColumn(todo.slug, w.edited.id));
    await run.tap(_card(w.edited.id));
    await run.see(_taskOpen(w.edited.id));
    final task = _taskOpen(w.edited.id);
    Finder inTask(Finder finder) => find.descendant(of: task, matching: finder);

    // The title, as typed.
    final renamed = '${w.oneMarker} edited in the task';
    final title = inTask(_key('task-title'));
    await run.tap(title);
    await tester.enterText(title, renamed);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await run.pumpFor(const Duration(milliseconds: 300));
    await run.server(
      'the new title',
      () async => (await w.ana.api.task(w.edited.id)).title == renamed,
    );

    // The column, and the priority, from their pickers.
    await run.tap(inTask(_key('task-status')));
    await run.tap(find.text(doing.name).last);
    await run.server('the new column', () async {
      return (await w.ana.api.task(w.edited.id)).status == doing.slug;
    });
    await run.tap(inTask(_key('task-priority')));
    await run.tap(find.text('High').last);
    await run.server('the new priority', () async {
      return (await w.ana.api.task(w.edited.id)).priority == 'high';
    });
    await run.see(
      find.descendant(of: inTask(_key('task-status')), matching: find.text(doing.name)),
    );

    if (run.wide) {
      // The board is right behind the panel, and has already caught up.
      await run.see(_inColumn(doing.slug, w.edited.id));
      expect(_inColumn(todo.slug, w.edited.id), findsNothing);
    }
    await run.shot('2-task-edited');
    await run.leaveTask(w.edited.id);

    // Back on the board, without reloading it.
    expect(run.router.state.uri.path, AppRoutes.board(w.board.id));
    final card = _inColumn(doing.slug, w.edited.id);
    await run.see(card);
    expect(_inColumn(todo.slug, w.edited.id), findsNothing);
    await run.see(find.descendant(of: card, matching: find.text(renamed)));
    expect(find.text(w.edited.title), findsNothing);
    await run.shot('2-board-in-sync');
  });

  testWidgets('a notification opens its task, from the inbox and from the system', (tester) async {
    final w = _w;
    final prefs = await SharedPreferences.getInstance();
    final phone = _PhoneHost();
    final desktop = _DesktopHost();
    final run = await _start(
      tester,
      w.ana,
      workspace: w.one,
      notifications: true,
      phone: phone,
      desktop: desktop,
    );

    // The inbox.
    await run.go(AppRoutes.inbox, find.byType(InboxPage));
    await run.tap(_key(w.oneNotice));
    await run.see(_taskOpen(w.notified.id));
    final title = find.descendant(of: _taskOpen(w.notified.id), matching: _key('task-title'));
    await run.see(title);
    expect(tester.widget<TextField>(title).controller!.text, w.notified.title);
    await run.server('the notice read', () async {
      final all = await w.ana.api.notifications(workspaceId: w.one.id);
      return all.firstWhere((n) => n.id == w.oneNotice).isRead == true;
    });
    await run.shot('3-inbox-opens-task');
    await run.leaveTask(w.notified.id);
    await run.go(AppRoutes.home, find.byType(HomePage));

    // The system: a notice the app's own check found on the server, tapped.
    final String payload;
    final title2 = '${w.oneMarker} system notice';
    if (Platform.isMacOS) {
      final runtime = run.container.read(desktopRuntimeProvider(run.router))!;
      expect(await run.until(() => desktop.onTap != null), isTrue);
      // What is already there isn't news. Once a check has seen it, the next one shows what's new.
      await runtime.check();
      await run.pumpFor(const Duration(milliseconds: 500));
      await runtime.check();
      await _notify(w.ana.api, w.one.id, title2, w.open.id);
      await run.server('a desktop notice', () async {
        await runtime.check();
        return desktop.shown.any((n) => n.title == title2);
      });
      payload = desktop.shown.lastWhere((n) => n.title == title2).payload;
      desktop.onTap!(payload);
    } else {
      expect(await run.until(() => phone.onTap != null), isTrue);
      // The background task, as the system would run it with the app away.
      final background = _PhoneHost();
      final session = MemorySessionStorage(w.ana.session);
      await prefs.setBool(notificationForegroundKey, false);
      await prefs.remove('kaneo.notifications.seen');
      await runBackgroundCheck(host: background, storage: session);
      await _notify(w.ana.api, w.one.id, title2, w.open.id);
      await runBackgroundCheck(host: background, storage: session);
      expect(background.shown.map((n) => n.title), [title2]);
      payload = background.shown.single.payload;
      await prefs.setBool(notificationForegroundKey, true);
      phone.onTap!(payload);
    }
    await run.see(_taskOpen(w.open.id));
    final opened = find.descendant(of: _taskOpen(w.open.id), matching: _key('task-title'));
    await run.see(opened);
    expect(tester.widget<TextField>(opened).controller!.text, w.open.title);
    await run.shot('3-system-notice-opens-task');
    await run.leaveTask(w.open.id);
  });

  testWidgets('another workspace, then another account, and nothing of the last one shows', (
    tester,
  ) async {
    final w = _w;
    final run = await _start(tester, w.ana, workspace: w.one);
    final home = find.byType(HomePage);
    final inbox = find.byType(InboxPage);
    final myTasks = find.byType(MyTasksPage);
    final activity = find.byType(ActivityPage);
    final search = find.byType(SearchPage);

    /// Every page, with [project], [task], [notice] and [marker]'s comment on them, and nothing of
    /// anyone in [hidden].
    Future<void> everyPage({
      required String name,
      required String marker,
      required Project project,
      required Task task,
      required String notice,
      required List<String> hidden,
    }) async {
      Future<void> clean(String page) async {
        for (final marker in hidden) {
          await run.nothingOf(marker, page);
        }
        await run.shot('4-$name-$page');
      }

      await run.go(AppRoutes.home, find.byKey(homeProjectKey(project.id)));
      await clean('home');
      await run.go(AppRoutes.myTasks, find.descendant(of: myTasks, matching: _key(task.id)));
      await clean('my-tasks');
      await run.go(AppRoutes.inbox, find.descendant(of: inbox, matching: _key(notice)));
      await clean('inbox');
      await run.go(
        AppRoutes.activity,
        find.descendant(of: activity, matching: _anything('$marker comment')),
      );
      await clean('activity');
      await run.go(AppRoutes.search, search);
      await run.search(_stamp);
      await run.see(_key('task-${task.id}'));
      await clean('search');
      await run.go(AppRoutes.board(project.id), _card(task.id));
      await clean('board');
      await run.go(AppRoutes.home, home);
    }

    await everyPage(
      name: 'one',
      marker: w.oneMarker,
      project: w.board,
      task: w.open,
      notice: w.oneNotice,
      hidden: [w.twoMarker, w.boMarker],
    );

    // Another workspace, the way the person picks one.
    await run.go(AppRoutes.home, find.byKey(homeProjectKey(w.board.id)));
    await run.tap(find.text(w.one.name));
    await run.tap(find.text(w.two.name).last);
    await run.see(find.byKey(homeProjectKey(w.elsewhere.id)));
    expect(run.container.read(currentWorkspaceProvider).value?.id, w.two.id);
    await everyPage(
      name: 'two',
      marker: w.twoMarker,
      project: w.elsewhere,
      task: w.inTwo,
      notice: w.twoNotice,
      hidden: [w.oneMarker, w.boMarker],
    );

    // Another account, signing out and in the way the person does.
    await run.go(AppRoutes.account, find.byType(AccountPage));
    final signOut = find.text(run.t('mobile:account.signOut.button'));
    await run.tap(signOut);
    await run.tap(find.text(run.t('mobile:account.signOut.button')).last);
    await run.see(find.byType(LoginPage));
    expect(run.container.read(sessionProvider), isNull);
    await run.shot('4-signed-out');

    await tester.enterText(_key('login-server'), w.server);
    await run.tap(find.text(run.t('app:auth.passwordLogin')));
    await tester.enterText(_key('login-email'), w.bo.email);
    await tester.enterText(_key('login-password'), w.bo.password);
    await run.tap(_key('login-submit'));
    await run.see(home);
    expect(run.container.read(sessionProvider)?.userId, w.bo.session.userId);
    // The workspace picked last was the other account's, which this one can't see.
    await run.see(find.byKey(homeProjectKey(w.boProject.id)));
    expect(run.container.read(currentWorkspaceProvider).value?.id, w.boHome.id);
    await everyPage(
      name: 'bo',
      marker: w.boMarker,
      project: w.boProject,
      task: w.boTask,
      notice: w.boNotice,
      hidden: [w.oneMarker, w.twoMarker],
    );

    // A link to the last account's task leads nowhere, instead of to what was kept of it.
    run.router.push(AppRoutes.task(w.open.id));
    await run.pumpFor(const Duration(seconds: 2));
    await run.nothingOf(w.oneMarker, 'the last account task');
    expect(run.container.read(sessionProvider)?.userId, w.bo.session.userId);
    await run.shot('4-bo-last-account-task');
  });
}
