// Realtime against a local Kaneo: KAN-40, and B11 and B12 of the black-box tests. Run only through
// tool/with_device.sh with dev.env. It creates its own A- projects, and deletes them again.
//
// The app reaches the server through a relay in this test, so that its network can be taken away. The
// other client, which plays the web app, goes straight to the server.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:window_manager/window_manager.dart';

const _email = String.fromEnvironment('KANEO_DEV_EMAIL');
const _password = String.fromEnvironment('KANEO_DEV_PASSWORD');

/// Passes bytes between the app and the server, until told not to.
class _Relay {
  _Relay._(this._server, this._target);

  static Future<_Relay> start(Uri target) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _Relay._(server, target);
    server.listen(relay._accept);
    return relay;
  }

  final ServerSocket _server;
  final Uri _target;
  final _links = <_Link>[];
  bool _refusing = false;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> _accept(Socket client) async {
    if (_refusing) {
      client.destroy();
      return;
    }
    final Socket upstream;
    try {
      upstream = await Socket.connect(_target.host, _target.port);
    } on SocketException {
      client.destroy();
      return;
    }
    final link = _Link(client, upstream);
    _links.add(link);
    client.listen(link.toServer, onDone: link.close, onError: (_) => link.close());
    upstream.listen(link.toClient, onDone: link.close, onError: (_) => link.close());
  }

  /// A network that goes away with a clear signal: connections end, and new ones fail.
  void cut() {
    _refusing = true;
    for (final link in _links) {
      link.close();
    }
    _links.clear();
  }

  /// A network that goes away without saying so: nothing ends, and nothing gets through either.
  void silence() {
    _refusing = true;
    for (final link in _links) {
      link.silent = true;
    }
  }

  void restore() => _refusing = false;

  Future<void> close() async {
    cut();
    await _server.close();
  }
}

class _Link {
  _Link(this._client, this._upstream);

  final Socket _client;
  final Socket _upstream;
  bool silent = false;

  void toServer(List<int> bytes) {
    if (!silent) _upstream.add(bytes);
  }

  void toClient(List<int> bytes) {
    if (!silent) _client.add(bytes);
  }

  void close() {
    _client.destroy();
    _upstream.destroy();
  }
}

Finder _card(String id) => find.byKey(ValueKey('board-card-$id'));

Finder _inColumn(String slug, String id) =>
    find.descendant(of: find.byKey(ValueKey('drop-column-$slug')), matching: _card(id));

Future<bool> _until(WidgetTester tester, bool Function() ready, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return ready();
}

Future<void> _wait(WidgetTester tester, Duration time) async {
  await _until(tester, () => false, time);
}

/// Waits for [ready], and says how long it took.
Future<void> _expectWithin(
  WidgetTester tester,
  String what,
  Duration limit,
  bool Function() ready,
) async {
  final clock = Stopwatch()..start();
  final done = await _until(tester, ready, limit);
  debugPrint('A_RESULT $what ${done ? 'PASS' : 'FAIL'} ${clock.elapsedMilliseconds}ms');
  expect(done, isTrue, reason: '$what: not within $limit');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final type in CredentialType.values) {
    testWidgets('realtime with $type', (tester) async {
      final config = DevConfig.fromEnvironment();
      final target = Uri.parse(config.serverUrl);
      expect(['localhost', '127.0.0.1', '::1'], contains(target.host), reason: 'Local Kaneo only.');
      if (Platform.isMacOS) {
        await windowManager.ensureInitialized();
        await windowManager.setSize(const Size(1366, 1024));
      }
      final relay = await _Relay.start(target);
      addTearDown(relay.close);

      final container = await bootstrap(sessionStorage: MemorySessionStorage());
      addTearDown(container.dispose);
      await container.read(languageChoiceProvider.notifier).select(defaultLocale);
      final auth = container.read(authenticationProvider);

      // The other client, which isn't behind the relay and has no limit on its requests.
      final other = await auth.withPassword(config.serverUrl, _email, _password);
      final web = KaneoApi(
        ApiClient(
          session: () => other,
          i18n: container.read(i18nProvider),
          onSessionExpired: (_) {},
        ),
        container.read(i18nProvider),
      );
      final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final project = await web.createProject(
        name: 'A-realtime-${type.name}-$stamp',
        workspaceId: config.workspaceId,
        icon: 'Layout',
        slug: 'AR${stamp.toUpperCase()}',
      );
      addTearDown(() => web.deleteProject(project.id));
      final columns = await web.columns(project.id);
      final todo = columns.first.slug;
      final doing = columns[1].slug;
      final review = columns[2].slug;
      Future<Task> create(String title, {String? status}) => web.createTask(
        project.id,
        CreateTaskBody(
          title: title,
          description: '',
          priority: 'no-priority',
          status: status ?? todo,
        ),
      );
      final task = await create('A Moved');
      final parent = await create('A Parent');
      final child = await create('A Child');
      await web.createRelation(parent.id, child.id, 'subtask');
      final bystander = await create('A Bystander', status: review);

      final session = type == CredentialType.apiKey
          ? await auth.withApiKey(relay.url, config.apiKey)
          : await auth.withPassword(relay.url, _email, _password);
      await container.read(sessionProvider.notifier).signIn(session);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const KaneoApp()),
      );
      container.read(routerProvider).go(AppRoutes.board(project.id));
      expect(
        await _until(tester, () => _card(task.id).evaluate().isNotEmpty, _seconds(30)),
        isTrue,
      );
      // Long enough for the sockets to be open.
      await _wait(tester, _seconds(1));

      debugPrint('A_CHECK B11 other client changes status and title');
      await web.updateStatus(task.id, doing);
      await web.updateTitle(task.id, 'A Moved on the web');
      await _expectWithin(
        tester,
        'B11_status_and_title',
        _seconds(5),
        () =>
            _inColumn(doing, task.id).evaluate().isNotEmpty &&
            find.text('A Moved on the web').evaluate().isNotEmpty,
      );

      debugPrint('A_CHECK B11 other client moves a card the way the web app does');
      await web.reorderTasks(project.id, [
        PositionUpdate(id: task.id, position: 0, status: review),
      ]);
      await _expectWithin(
        tester,
        'B11_web_move',
        _seconds(5),
        () => _inColumn(review, task.id).evaluate().isNotEmpty,
      );
      expect(_inColumn(review, bystander.id), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      debugPrint('A_CHECK B11 new, deleted, and the progress of a parent');
      final added = await create('A Added on the web');
      await _expectWithin(
        tester,
        'B11_created',
        _seconds(5),
        () => _card(added.id).evaluate().isNotEmpty,
      );
      await web.deleteTask(added.id);
      await _expectWithin(
        tester,
        'B11_deleted',
        _seconds(5),
        () => _card(added.id).evaluate().isEmpty,
      );
      final done = columns.firstWhere((c) => c.isFinal == true).slug;
      await web.updateStatus(child.id, done);
      await _expectWithin(tester, 'B11_parent_progress', _seconds(5), () {
        final board = container.read(boardQuery(project.id)).value;
        final card = board?.columns
            .expand((c) => c.tasks ?? const <BoardTask>[])
            .where((t) => t.id == parent.id)
            .firstOrNull;
        return card?.subtaskCounts?.completed == 1;
      });

      debugPrint('A_CHECK B12 the network drops for 30 seconds, with a clear signal');
      relay.cut();
      await _wait(tester, _seconds(5));
      await web.updateTitle(task.id, 'A Changed during the outage');
      await _wait(tester, _seconds(25));
      expect(find.text('A Changed during the outage'), findsNothing);
      expect(_card(task.id), findsOneWidget, reason: 'The board stays on screen.');
      relay.restore();
      await _expectWithin(
        tester,
        'B12_after_cut',
        RealtimeConnection.maxRetryDelay + _seconds(5),
        () => find.text('A Changed during the outage').evaluate().isNotEmpty,
      );

      debugPrint('A_CHECK B12 and live again afterwards');
      await web.updateTitle(task.id, 'A Live after the outage');
      await _expectWithin(
        tester,
        'B12_live_after_cut',
        _seconds(5),
        () => find.text('A Live after the outage').evaluate().isNotEmpty,
      );

      debugPrint('A_CHECK B12 the network goes quiet for 30 seconds, with no signal at all');
      relay.silence();
      await _wait(tester, _seconds(5));
      await web.updateTitle(task.id, 'A Changed during the silence');
      await _wait(tester, _seconds(25));
      relay.restore();
      await _expectWithin(
        tester,
        'B12_after_silence',
        // The ping that notices, its answer not coming, a read cut short by the same silence, a retry.
        _seconds(30) + RealtimeConnection.maxRetryDelay + _seconds(5),
        () => find.text('A Changed during the silence').evaluate().isNotEmpty,
      );

      debugPrint('A_CHECK back in the foreground');
      // No frames come in the background, so this can't pump until the app is back.
      void go(List<AppLifecycleState> states) {
        for (final state in states) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      }

      go(const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      await Future<void>.delayed(_seconds(1));
      await web.updateTitle(task.id, 'A Changed in the background');
      await Future<void>.delayed(_seconds(3));
      go(const [AppLifecycleState.hidden, AppLifecycleState.inactive]);
      expect(
        find.text('A Changed in the background'),
        findsNothing,
        reason: 'There is no socket in the background.',
      );
      go(const [AppLifecycleState.resumed]);
      await _expectWithin(
        tester,
        'foreground',
        _seconds(5),
        () => find.text('A Changed in the background').evaluate().isNotEmpty,
      );
      await web.updateTitle(task.id, 'A Live in the foreground');
      await _expectWithin(
        tester,
        'live_in_foreground',
        _seconds(5),
        () => find.text('A Live in the foreground').evaluate().isNotEmpty,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));
  }

  // KAN-59. No board is open below this task, so it has its project's socket to itself.
  testWidgets('a task opened away from its board follows changes made elsewhere', (tester) async {
    final config = DevConfig.fromEnvironment();
    final target = Uri.parse(config.serverUrl);
    expect(['localhost', '127.0.0.1', '::1'], contains(target.host), reason: 'Local Kaneo only.');
    if (Platform.isMacOS) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1366, 1024));
    }
    final container = await bootstrap(sessionStorage: MemorySessionStorage());
    addTearDown(container.dispose);
    await container.read(languageChoiceProvider.notifier).select(defaultLocale);

    final session = await container
        .read(authenticationProvider)
        .withPassword(config.serverUrl, _email, _password);
    final web = KaneoApi(
      ApiClient(
        session: () => session,
        i18n: container.read(i18nProvider),
        onSessionExpired: (_) {},
      ),
      container.read(i18nProvider),
    );
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final project = await web.createProject(
      name: 'A-realtime-task-$stamp',
      workspaceId: config.workspaceId,
      icon: 'Layout',
      slug: 'ART${stamp.toUpperCase()}',
    );
    addTearDown(() => web.deleteProject(project.id));
    final task = await web.createTask(
      project.id,
      CreateTaskBody(
        title: 'A On its own',
        description: '',
        priority: 'no-priority',
        status: (await web.columns(project.id)).first.slug,
      ),
    );

    await container.read(sessionProvider.notifier).signIn(session);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KaneoApp()),
    );
    container.read(routerProvider).go(AppRoutes.task(task.id));
    final title = find.byKey(const ValueKey('task-title'));
    expect(await _until(tester, () => title.evaluate().isNotEmpty, _seconds(30)), isTrue);
    // Long enough for the socket to be open.
    await _wait(tester, _seconds(1));

    await web.updateTitle(task.id, 'A Renamed on the web');
    await _expectWithin(
      tester,
      'KAN59_title',
      _seconds(5),
      () => tester.widget<TextField>(title).controller!.text == 'A Renamed on the web',
    );
    await web.createComment(task.id, 'A Said on the web');
    await _expectWithin(
      tester,
      'KAN59_comment',
      _seconds(5),
      () => find.text('A Said on the web').evaluate().isNotEmpty,
    );
    expect(
      container.read(boardQuery(project.id).exists),
      isFalse,
      reason: 'Nobody needs the board here.',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Duration _seconds(int seconds) => Duration(seconds: seconds);
