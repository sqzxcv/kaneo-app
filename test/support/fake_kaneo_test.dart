import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import 'fake_kaneo.dart';

void main() {
  late FakeKaneo server;
  late KaneoApi api;
  late ApiClient client;
  var token = FakeKaneo.apiKey;

  setUp(() async {
    token = FakeKaneo.apiKey;
    server = FakeKaneo();
    final i18n = await I18n.load(read: (_) async => null);
    client = ApiClient(
      session: () => Session(
        serverUrl: FakeKaneo.serverUrl,
        credentialType: CredentialType.apiKey,
        token: token,
        userId: FakeKaneo.userId,
        userName: 'Test User',
        userEmail: FakeKaneo.email,
      ),
      i18n: i18n,
      onSessionExpired: (_) {},
      adapter: server,
    );
    api = KaneoApi(client, i18n);
  });

  test('wrong credentials get 401, the way the real server answers', () async {
    token = 'wrong';
    await expectLater(
      api.me(),
      throwsA(
        isA<ApiError>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', 'Unauthorized'),
      ),
    );
  });

  test('the config and sign-in routes need no credentials', () async {
    token = 'wrong';
    expect(await client.request('api/config'), containsPair('isCloud', false));
    final ok = await client.requestRaw(
      'api/auth/sign-in/email',
      method: 'POST',
      body: {'email': FakeKaneo.email, 'password': FakeKaneo.password},
    );
    expect(ok.header('set-auth-token'), FakeKaneo.sessionToken);
    final wrong = await client.requestRaw(
      'api/auth/sign-in/email',
      method: 'POST',
      body: {'email': FakeKaneo.email, 'password': 'wrong'},
    );
    expect(wrong.status, 401);
    expect((wrong.body as Map)['message'], 'Invalid email or password');
  });

  test('failNext fails only the next requests', () async {
    server.failNext('api/user/me', status: 500, times: 2);
    await expectLater(api.me(), throwsA(isA<ApiError>()));
    await expectLater(api.me(), throwsA(isA<ApiError>()));
    expect((await api.me()).id, FakeKaneo.userId);
  });

  test('fail keeps failing until cleared, and can match the method', () async {
    server.fail('api/task/', status: 500, method: 'PUT');
    expect((await api.task('task-1')).id, 'task-1');
    await expectLater(api.updateTitle('task-1', 'x'), throwsA(isA<ApiError>()));
    await expectLater(api.updateTitle('task-1', 'x'), throwsA(isA<ApiError>()));
    server.clearOverrides();
    expect((await api.updateTitle('task-1', 'x')).title, 'x');
  });

  test('on replaces a response', () async {
    server.on(
      'api/user/me',
      (request) => const FakeResponse(200, {'id': 'x', 'name': 'n', 'email': 'e'}),
    );
    expect((await api.me()).id, 'x');
  });

  test('hold keeps a request waiting until released', () async {
    final gate = server.hold('api/user/me');
    var done = false;
    final pending = api.me().then((_) => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(done, isFalse);
    gate.release();
    await pending;
    expect(done, isTrue);
  });

  test('unreachable reads as a connection failure', () async {
    server.unreachable = true;
    await expectLater(api.me(), throwsA(isA<ApiError>().having((e) => e.status, 'status', isNull)));
  });

  test('records requests for assertions', () async {
    await api.task('task-1');
    await api.updateTitle('task-1', 'x');
    expect(server.requestsTo('api/task/title'), hasLength(1));
    expect(server.requestsTo('api/task/', method: 'GET'), hasLength(1));
    expect(server.requests.last.body, {'title': 'x'});
  });

  test('tests can add their own data', () async {
    final task = server.addTask(title: 'Mine', status: 'done', priority: 'low');
    server.addComment(task['id'] as String, 'Hi');
    server.addRelation('task-1', task['id'] as String);
    server.addNotification(title: 'New');
    server.addLabel('ui', taskId: task['id'] as String);

    final board = await api.board(FakeKaneo.projectId);
    final done = board.data.columns.firstWhere((c) => c.slug == 'done');
    final added = done.tasks!.firstWhere((t) => t.title == 'Mine');
    expect(added.number, 7);
    expect(added.labels?.single.name, 'ui');
    final parent = board.data.columns.first.tasks!.first;
    expect(parent.subtaskCounts?.total, 2);
    expect(parent.subtaskCounts?.completed, 1);
    expect((await api.notifications()).last.title, 'New');
    expect((await api.activities(task['id'] as String)).first.content, 'Hi');
  });

  test('empty keeps the account and workspace', () async {
    final empty = FakeKaneo.empty();
    expect(empty.workspaces, isNotEmpty);
    expect(empty.projects, isEmpty);
    expect(empty.tasks, isEmpty);
    expect(empty.notifications, isEmpty);
  });

  test('a mistake in a route shows up as a message, not as an unreachable server', () async {
    server.columns.first['position'] = 'not a number';
    await expectLater(
      api.columns(FakeKaneo.projectId),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('FakeKaneo failed'))),
    );
  });

  test('an unknown route is a 404', () async {
    await expectLater(
      client.request('api/nope'),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)),
    );
  });
}
