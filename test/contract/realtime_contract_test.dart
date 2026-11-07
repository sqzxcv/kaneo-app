// Checks on a real local Kaneo what `BoardSync` and `UserSync` take for granted about its sockets:
// which credentials get in, and what events come for which changes. Skipped unless dev.env is passed:
//
//     flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// It creates a temporary project on that server and deletes it again. Never point it at anything
// but a local Kaneo.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _serverUrl = String.fromEnvironment('KANEO_DEV_SERVER_URL');
const _apiKey = String.fromEnvironment('KANEO_DEV_API_KEY');
const _email = String.fromEnvironment('KANEO_DEV_EMAIL');
const _password = String.fromEnvironment('KANEO_DEV_PASSWORD');
const _workspaceId = String.fromEnvironment('KANEO_DEV_WORKSPACE_ID');

bool get _isLocal {
  final host = Uri.tryParse(_serverUrl)?.host;
  return host == 'localhost' || host == '127.0.0.1';
}

Session _session(CredentialType type, String token) => Session(
  serverUrl: _serverUrl,
  credentialType: type,
  token: token,
  userId: 'contract',
  userName: '',
  userEmail: '',
);

/// Collects what a socket sends, and waits for what a test expects within the time allowed.
class _Listener {
  _Listener(Session session, String path) : _channel = connectAuthenticatedSocket(session, path) {
    _channel.stream.listen(
      (frame) {
        final event = RealtimeEvent.parse(frame);
        if (event != null) {
          events.add(event);
          _changed.add(null);
        }
      },
      onError: (Object _) {},
      onDone: () => _changed.add(null),
    );
  }

  final WebSocketChannel _channel;
  final events = <RealtimeEvent>[];
  final _changed = StreamController<void>.broadcast();

  Future<void> get ready => _channel.ready;
  int? get closeCode => _channel.closeCode;
  void send(String text) => _channel.sink.add(text);
  Future<void> close() async => _channel.sink.close();

  /// Within five seconds, as a board has to be up to date by then.
  Future<RealtimeEvent> next(String type, {bool Function(RealtimeEvent event)? where}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final found = events.where((e) => e.type == type && (where?.call(e) ?? true)).firstOrNull;
      if (found != null) {
        events.remove(found);
        return found;
      }
      final left = deadline.difference(DateTime.now());
      if (left.isNegative) {
        fail('No $type within 5 seconds. Got: ${events.map((e) => e.data).toList()}');
      }
      await _changed.stream.first.timeout(left, onTimeout: () {});
    }
  }
}

void main() {
  late KaneoApi api;
  late String sessionToken;
  late Project project;
  late List<ProjectColumn> columns;

  setUpAll(() async {
    if (_apiKey.isEmpty) return;
    final i18n = await I18n.load(read: (_) async => null);
    final signedOut = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
    final signIn = await signedOut.requestRaw(
      'api/auth/sign-in/email',
      method: 'POST',
      body: {'email': _email, 'password': _password},
      serverUrl: _serverUrl,
    );
    expect(signIn.isOk, isTrue, reason: 'Could not sign in: ${signIn.status}');
    sessionToken = signIn.header('set-auth-token')!;
    final client = ApiClient(
      session: () => _session(CredentialType.bearer, sessionToken),
      i18n: i18n,
      onSessionExpired: (_) {},
    );
    api = KaneoApi(client, i18n);
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    project = await api.createProject(
      name: 'A-realtime-contract-$stamp',
      workspaceId: _workspaceId,
      icon: 'Layout',
      slug: 'ARC${stamp.toUpperCase()}',
    );
    columns = await api.columns(project.id);
  });

  tearDownAll(() async {
    if (_apiKey.isNotEmpty) await api.deleteProject(project.id);
  });

  Future<Task> task(String title, {String? status}) => api.createTask(
    project.id,
    CreateTaskBody(
      title: title,
      description: '',
      priority: 'no-priority',
      status: status ?? columns.first.slug,
    ),
  );

  group('local Kaneo sockets', () {
    test('the server is local', () => expect(_isLocal, isTrue, reason: _serverUrl));

    for (final (name, type) in const [
      ('an API key', CredentialType.apiKey),
      ('a session token', CredentialType.bearer),
    ]) {
      Session session() => _session(type, type == CredentialType.apiKey ? _apiKey : sessionToken);

      group('with $name', () {
        test('a board hears a change made by the same account, and each kind of it', () async {
          final socket = _Listener(session(), 'api/ws/${project.id}');
          addTearDown(socket.close);
          await socket.ready;

          final created = await task('Contract $type');
          expect(
            (await socket.next('TASK_CREATED', where: (e) => e.taskId == created.id)).data,
            containsPair('projectId', project.id),
          );

          await api.updateTitle(created.id, 'Renamed');
          final title = await socket.next('TASK_UPDATED', where: (e) => e.taskId == created.id);
          expect(title.data['taskTitleChanged'], isTrue);

          await api.updateStatus(created.id, columns[1].slug);
          await socket.next('TASK_UPDATED', where: (e) => e.taskId == created.id);
          // With no ids at all, which is why the board can't tell whose progress changed from this.
          await socket.next(
            'TASK_RELATION_UPDATED',
            where: (e) => e.taskId == null && e.sourceTaskId == null && e.targetTaskId == null,
          );

          final other = await task('Contract other $type');
          await socket.next('TASK_CREATED', where: (e) => e.taskId == other.id);
          await api.reorderTasks(project.id, [
            PositionUpdate(id: other.id, position: 0, status: columns[1].slug),
          ]);
          final reorder = await socket.next('TASKS_REORDERED');
          final moved = PositionUpdate.fromJson(
            ((reorder.data['tasks'] as List).single as Map).cast<String, dynamic>(),
          );
          expect(moved.id, other.id);
          expect(moved.position, 0);
          expect(moved.status, columns[1].slug);
          await socket.next('TASK_UPDATED', where: (e) => e.taskId == other.id);

          final label = await api.createLabel(
            name: 'contract-$type',
            color: 'blue',
            workspaceId: _workspaceId,
          );
          await api.attachLabel(label.id, created.id);
          await socket.next('TASK_LABEL_UPDATED', where: (e) => e.taskId == created.id);

          await api.createRelation(created.id, other.id, 'subtask');
          await socket.next(
            'TASK_RELATION_UPDATED',
            where: (e) => e.sourceTaskId == created.id && e.targetTaskId == other.id,
          );

          await api.deleteTask(other.id);
          await socket.next('TASK_DELETED', where: (e) => e.taskId == other.id);
          await api.deleteTask(created.id);
          await api.deleteLabel(label.id);
        });

        test('the keepalive is accepted', () async {
          final socket = _Listener(session(), 'api/ws/${project.id}');
          addTearDown(socket.close);
          await socket.ready;
          socket.send('{"type":"ping"}');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(socket.closeCode, isNull);
        });

        test('the account hears which workspaces it has as the socket opens', () async {
          final socket = _Listener(session(), 'api/ws/user');
          addTearDown(socket.close);
          await socket.ready;
          final sync = await socket.next('WORKSPACE_ACCESS_SYNC');
          expect(sync.data['workspaceIds'], contains(_workspaceId));
        });

        test('a task read for a board brings the progress of its parent', () async {
          final parent = await task('Contract parent $type');
          final child = await task('Contract child $type');
          await api.createRelation(parent.id, child.id, 'subtask');
          final read = await api.taskForBoard(child.id);
          expect(read.task.id, child.id);
          expect(read.task.position, isNotNull);
          expect(read.subtaskCounts, isNotNull);
          final progress = read.parentSubtaskCounts.single;
          expect(progress.taskId, parent.id);
          expect(progress.counts.total, 1);
          await api.deleteTask(child.id);
          await api.deleteTask(parent.id);
        });
      });
    }

    test('a wrong key does not get in', () async {
      final socket = _Listener(_session(CredentialType.apiKey, 'wrong-key'), 'api/ws/user');
      await expectLater(socket.ready, throwsA(anything));
    });

    test('a project that does not exist does not let anyone in', () async {
      final socket = _Listener(_session(CredentialType.apiKey, _apiKey), 'api/ws/no-such-project');
      await expectLater(socket.ready, throwsA(anything));
    });
  }, skip: _apiKey.isEmpty ? 'Pass dev.env to run: see the top of this file.' : false);
}
