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

  group('comments', () {
    test('only the author can change one', () async {
      final theirs = server.addComment('task-1', 'Theirs', authorId: 'user-2');
      await expectLater(api.updateComment(theirs['id'] as String, 'x'), throwsA(isA<ApiError>()));
      await expectLater(api.deleteComment(theirs['id'] as String), throwsA(isA<ApiError>()));
      expect(theirs['content'], 'Theirs');
      expect(server.activities, contains(theirs));

      final mine = server.addComment('task-1', 'Mine');
      await api.updateComment(mine['id'] as String, 'Edited');
      expect(mine['content'], 'Edited');
      expect(mine['updatedAt'], isNot(mine['createdAt']));
      await api.deleteComment(mine['id'] as String);
      expect(server.activities, isNot(contains(mine)));
    });

    test('a mention notifies the other person, not the author', () async {
      final before = (await api.notifications()).length;
      await api.createComment(
        'task-1',
        '<kaneo-mention id="user-2" label="Second User"></kaneo-mention> '
            '<kaneo-mention id="${FakeKaneo.userId}" label="Test User"></kaneo-mention>',
      );
      final notification = server.notificationsToOthers.single;
      expect(notification['userId'], 'user-2');
      expect(notification['type'], 'task_mention');
      expect(notification['resourceId'], 'task-1');
      expect(await api.notifications(), hasLength(before));
    });

    test('a change of status says what changed', () async {
      await api.updateStatus('task-1', 'done');
      final event = server.activities.first;
      expect(event['type'], 'status_changed');
      expect(event['eventData'], {'oldStatus': 'to-do', 'newStatus': 'done'});
    });
  });

  // KAN-66: see test/contract/task_edits_contract_test.dart.
  test(
    'labels go on tasks as copies, and another task\'s copy moves, as on the real server',
    () async {
      List<String?> holders(String name) => [
        for (final l in server.labels)
          if (l['name'] == name) l['taskId'] as String?,
      ];
      final workspace = await api.createLabel(name: 'ws', color: 'red', workspaceId: 'w');
      await api.attachLabel(workspace.id, 'task-1');
      await api.attachLabel(workspace.id, 'task-1');
      expect(holders('ws'), [null, 'task-1']);

      final theirs = server.addLabel('theirs', taskId: 'task-3');
      await api.createLabel(name: 'theirs', color: 'red', workspaceId: 'w', taskId: 'task-1');
      await api.createLabel(name: 'theirs', color: 'red', workspaceId: 'w', taskId: 'task-1');
      expect(holders('theirs'), ['task-3', 'task-1']);

      await api.attachLabel(theirs['id'] as String, 'task-2');
      expect(holders('theirs'), ['task-1', 'task-2']);
    },
  );

  // KAN-60: comments stayed behind, and then every read of the workspace's activity failed.
  test('deleting a project takes what hangs off its tasks, as on the real server', () async {
    server.addComment('task-1', 'Goes with the project');
    server.addTask(id: 'elsewhere', title: 'Elsewhere', projectId: FakeKaneo.secondProjectId);
    server.addComment('elsewhere', 'Stays');
    server.addRelation('task-1', 'elsewhere');
    server.timeEntries.add({'id': 'entry', 'taskId': 'task-1'});
    server.externalLinks.add({'id': 'link', 'taskId': 'task-1'});

    await api.deleteProject(FakeKaneo.projectId);

    expect(server.tasks.where((t) => t['projectId'] == FakeKaneo.projectId), isEmpty);
    expect(server.relations.where((r) => r['targetTaskId'] == 'elsewhere'), isEmpty);
    expect(server.timeEntries, isEmpty);
    expect(server.externalLinks, isEmpty);
    final activity = await api.workspaceActivity(FakeKaneo.workspaceId);
    expect(activity.map((a) => a.excerpt), contains('Stays'));
    expect(activity.map((a) => a.excerpt), isNot(contains('Goes with the project')));
    final found = await api.search('Goes with the project', FakeKaneo.workspaceId);
    expect(found.results, isEmpty);
  });

  group('a second workspace', () {
    const other = 'other-workspace';

    setUp(() {
      server.workspaces.add({...server.workspaces.first, 'id': other, 'name': 'Other'});
      server.addProject(id: 'other-project', name: 'Other', slug: 'OTH')['workspaceId'] = other;
      final task = server.addTask(projectId: 'other-project', title: 'Theirs');
      server.addNotification(title: 'About theirs', resourceId: task['id'] as String);
      server.addNotification(
        type: 'workspace_created',
        title: 'Made',
        resourceId: other,
        resourceType: 'workspace',
      );
    });

    test('has its own assigned tasks, as on the real server', () async {
      final theirs = await api.assignedTasks(other);
      expect(theirs.tasks.map((t) => t.title), ['Theirs']);
      expect(theirs.total, 1);
      final ours = await api.assignedTasks(FakeKaneo.workspaceId);
      expect(ours.tasks.map((t) => t.title), isNot(contains('Theirs')));
      expect(ours.tasks, isNotEmpty);
    });

    test('has its own inbox, as on the real server', () async {
      final theirs = await api.notifications(workspaceId: other);
      expect(theirs.map((n) => n.title), ['About theirs', 'Made']);
      final ours = await api.notifications(workspaceId: FakeKaneo.workspaceId);
      expect(ours.map((n) => n.title), isNot(contains('About theirs')));
      expect(ours.map((n) => n.title), isNot(contains('Made')));
      expect(ours, isNotEmpty);
      final everything = await api.notifications();
      expect(everything.length, theirs.length + ours.length);
    });

    test('marks and clears only its own inbox, as on the real server', () async {
      await api.markAllNotificationsRead(workspaceId: other);
      final ours = await api.notifications(workspaceId: FakeKaneo.workspaceId);
      expect(ours.where((n) => n.isRead != true), isNotEmpty);
      expect((await api.notifications(workspaceId: other)).every((n) => n.isRead == true), isTrue);

      await api.clearAllNotifications(workspaceId: other);
      expect(await api.notifications(workspaceId: other), isEmpty);
      expect((await api.notifications(workspaceId: FakeKaneo.workspaceId)), hasLength(ours.length));
    });
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

  group('search', () {
    List<SearchResult> found(SearchResponse response, String type) =>
        response.results.where((r) => r.type == type).toList();

    test('finds tasks, projects and comments, the way the server names them', () async {
      server.addProject(id: 'rocket', name: 'Rocket launch', slug: 'RKT');
      server.addTask(id: 'fuel', projectId: 'rocket', title: 'Fuel', description: 'For the rocket');
      server.addComment('task-2', 'About the rocket');

      final response = await api.search('rocket', FakeKaneo.workspaceId);
      expect(found(response, 'task').single.id, 'fuel');
      expect(found(response, 'project').single.id, 'rocket');
      final comment = found(response, 'comment').single;
      expect(comment.content, 'About the rocket');
      expect(comment.title, 'Comment on Write the first description');
      expect(comment.projectSlug, 'DEMO');
      expect(comment.taskNumber, 2);
    });

    test('also finds the activity of a task whose title matches, as the server does', () async {
      final response = await api.search('board', FakeKaneo.workspaceId);
      expect(found(response, 'task').single.id, 'task-3');
      expect(found(response, 'activity').single.content, isNull);
    });

    test('puts the best matches first, and can look for one kind', () async {
      server.addComment('task-2', 'About the board');
      final all = await api.search('board', FakeKaneo.workspaceId);
      expect(all.results.map((r) => r.type), ['task', 'comment', 'activity']);

      final comments = await api.search('board', FakeKaneo.workspaceId, type: 'comments');
      expect(comments.results.map((r) => r.type), ['comment']);
    });

    test('stops at the limit, and counts everything', () async {
      for (var i = 0; i < 40; i++) {
        server.addTask(title: 'Rocket $i');
      }
      final response = await api.search('rocket', FakeKaneo.workspaceId);
      expect(response.results, hasLength(30));
      expect(response.totalCount, 80);
    });
  });

  test('an unknown route is a 404', () async {
    await expectLater(
      client.request('api/nope'),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)),
    );
  });

  group('a task read for a board', () {
    test('has its progress and that of its parents in the project', () async {
      final read = await api.taskForBoard('task-2');
      expect(read.task.id, 'task-2');
      expect(read.task.workspaceId, isNull);
      expect(read.subtaskCounts!.total, 0);
      final parent = read.parentSubtaskCounts.single;
      expect(parent.taskId, 'task-1');
      expect(parent.counts.total, 1);
      expect(server.requests.last.query['view'], 'board');
    });

    test('leaves out a parent in another project', () async {
      server.tasks.firstWhere((t) => t['id'] == 'task-1')['projectId'] = FakeKaneo.secondProjectId;
      expect((await api.taskForBoard('task-2')).parentSubtaskCounts, isEmpty);
    });
  });

  group('sockets', () {
    const session = Session(
      serverUrl: FakeKaneo.serverUrl,
      credentialType: CredentialType.apiKey,
      token: FakeKaneo.apiKey,
      userId: FakeKaneo.userId,
      userName: 'Test User',
      userEmail: FakeKaneo.email,
    );

    test('open for a good credential, and carry what is sent', () async {
      final socket = server.connectSocket(session, FakeKaneo.userSocket);
      await socket.ready;
      expect(server.openSockets(FakeKaneo.userSocket), [socket]);
      final frame = socket.stream.first;
      server.emit(FakeKaneo.userSocket, 'NOTIFICATION_CREATED', {'a': 1});
      expect(await frame, '{"type":"NOTIFICATION_CREATED","a":1}');
      socket.sink.add('{"type":"ping"}');
      expect(socket.sent, ['{"type":"ping"}']);
    });

    test('accept a session token as well', () async {
      final socket = server.connectSocket(
        const Session(
          serverUrl: FakeKaneo.serverUrl,
          credentialType: CredentialType.bearer,
          token: FakeKaneo.sessionToken,
          userId: FakeKaneo.userId,
          userName: 'Test User',
          userEmail: FakeKaneo.email,
        ),
        FakeKaneo.userSocket,
      );
      await socket.ready;
      expect(socket.isOpen, isTrue);
    });

    for (final (name, change) in <(String, void Function(FakeKaneo))>[
      ('the server is unreachable', (s) => s.unreachable = true),
      ('the credentials are revoked', (s) => s.credentialsRevoked = true),
      ('sockets are refused', (s) => s.refuseSockets = true),
    ]) {
      test('fail when $name', () async {
        change(server);
        final socket = server.connectSocket(session, FakeKaneo.userSocket);
        await expectLater(socket.ready, throwsA(isA<SocketExceptionForTests>()));
        expect(socket.isOpen, isFalse);
      });
    }

    test('fail for a bad key', () async {
      final socket = server.connectSocket(
        const Session(
          serverUrl: FakeKaneo.serverUrl,
          credentialType: CredentialType.apiKey,
          token: 'wrong',
          userId: FakeKaneo.userId,
          userName: '',
          userEmail: '',
        ),
        FakeKaneo.userSocket,
      );
      await expectLater(socket.ready, throwsA(isA<SocketExceptionForTests>()));
    });

    test('reach only their own path, and drop with the code given', () async {
      final user = server.connectSocket(session, FakeKaneo.userSocket);
      final project = server.connectSocket(session, FakeKaneo.projectSocket('p'));
      await Future.wait([user.ready, project.ready]);
      final frames = <Object?>[];
      project.stream.listen(frames.add);
      server.emit(FakeKaneo.userSocket, 'X');
      await pumpEventQueue();
      expect(frames, isEmpty);
      server.dropSockets(code: 1008, reason: 'gone');
      expect(project.closeCode, 1008);
      expect(project.closeReason, 'gone');
      expect(server.sockets.where((s) => s.isOpen), isEmpty);
    });

    test('close from the app end, and refuse more text after', () async {
      final socket = server.connectSocket(session, FakeKaneo.userSocket);
      await socket.ready;
      await socket.sink.close();
      expect(socket.isOpen, isFalse);
      expect(() => socket.sink.add('x'), throwsStateError);
    });
  });
}
