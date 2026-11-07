// Runs the API client against a real local Kaneo, and compares FakeKaneo's answers with it, so the
// fake cannot drift away from the server unnoticed. Skipped unless dev.env is passed:
//
//     flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// It creates a temporary project on that server and deletes it again. Never point it at anything
// but a local Kaneo.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/fake_kaneo.dart';

const _serverUrl = String.fromEnvironment('KANEO_DEV_SERVER_URL');
const _apiKey = String.fromEnvironment('KANEO_DEV_API_KEY');
const _email = String.fromEnvironment('KANEO_DEV_EMAIL');
const _password = String.fromEnvironment('KANEO_DEV_PASSWORD');
const _workspaceId = String.fromEnvironment('KANEO_DEV_WORKSPACE_ID');
const _projectId = String.fromEnvironment('KANEO_DEV_PROJECT_ID');

bool get _isLocal {
  final host = Uri.tryParse(_serverUrl)?.host;
  return host == 'localhost' || host == '127.0.0.1';
}

/// The field names of a JSON value, as `a.b` for nested objects and across all items of a list.
/// What is inside `eventData` depends on the kind of event, so it is not compared.
Set<String> _shape(Object? value, [String prefix = '']) {
  if (value is Map) {
    return {
      for (final entry in value.entries) ...{
        '$prefix${entry.key}',
        if (entry.key != 'eventData') ..._shape(entry.value, '$prefix${entry.key}.'),
      },
    };
  }
  if (value is List) return {for (final item in value) ..._shape(item, prefix)};
  return const {};
}

/// What the task menu relies on. Everything is on two temporary projects.
Future<void> _checkMoveCopyDelete(KaneoApi api, String workspaceId) async {
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
  final source = await api.createProject(
    name: 'C-Move source $stamp',
    workspaceId: workspaceId,
    icon: 'Layout',
    slug: 'CS$stamp',
  );
  addTearDown(() => api.deleteProject(source.id));
  final target = await api.createProject(
    name: 'C-Move target $stamp',
    workspaceId: workspaceId,
    icon: 'Layout',
    slug: 'CT$stamp',
  );
  addTearDown(() => api.deleteProject(target.id));
  final label = await api.createLabel(name: 'C-$stamp', color: 'red', workspaceId: workspaceId);
  addTearDown(() => api.deleteLabel(label.id));
  final blocked = await api.createColumn(source.id, name: 'Blocked');
  Future<Task> create(String title, String status) => api.createTask(
    source.id,
    CreateTaskBody(title: title, description: 'Text', priority: 'low', status: status),
  );
  final parent = await create('Parent', 'to-do');
  final child = await create('Child', blocked.slug);
  final sibling = await create('Sibling', 'in-progress');
  await api.createRelation(parent.id, child.id, 'subtask');
  await api.attachLabel(label.id, child.id);
  Matcher failsWith(int status) =>
      throwsA(isA<ApiError>().having((e) => e.status, 'status', status));

  // A copy keeps the column and the labels, stays a subtask, and has a number of its own.
  final copy = await api.duplicateTask(child.id);
  expect(copy.id, isNot(child.id));
  expect(copy.title, child.title);
  expect(copy.status, blocked.slug);
  expect(copy.number, sibling.number! + 1);
  expect([for (final l in await api.taskLabels(copy.id)) l.name], [label.name]);
  Future<Set<String>> subtasks() async => {
    for (final r in await api.relations(parent.id))
      if (r.relationType == 'subtask') r.targetTaskId,
  };
  expect(await subtasks(), {child.id, copy.id});

  // A move needs somewhere else to go, and a project that exists.
  await expectLater(api.moveTask(child.id, source.id), failsWith(400));
  await expectLater(api.moveTask(child.id, 'no-such-project'), failsWith(404));

  // Without its column it goes to the first one. It gets the number the new project is up to, and
  // stays linked to its parent.
  await api.moveTask(child.id, target.id);
  final moved = await api.task(child.id);
  expect(moved.projectId, target.id);
  expect(moved.status, (await api.columns(target.id)).first.slug);
  expect(moved.number, 1);
  expect(moved.workspaceId, workspaceId);
  final link = (await api.relations(parent.id)).firstWhere((r) => r.targetTaskId == child.id);
  expect(link.targetTask?.projectId, target.id);
  expect(link.targetTask?.number, 1);

  // With its column it stays in it.
  await api.moveTask(sibling.id, target.id);
  expect((await api.task(sibling.id)).status, 'in-progress');
  expect((await api.task(sibling.id)).number, 2);

  // Deleting takes the links with it, so that the other end reads as before they were made.
  await api.deleteTask(parent.id);
  await expectLater(api.task(parent.id), failsWith(404));
  expect(await api.relations(child.id), isEmpty);
  expect(await api.relations(copy.id), isEmpty);
}

/// A project takes the record of its tasks with it. FakeKaneo once kept that, and from then on could
/// answer neither the workspace's activity nor a search.
Future<void> _checkDeletedProject(KaneoApi api, String workspaceId) async {
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
  final project = await api.createProject(
    name: 'A-Deleted project $stamp',
    workspaceId: workspaceId,
    icon: 'Layout',
    slug: 'AD$stamp',
  );
  var deleted = false;
  addTearDown(() async {
    if (!deleted) await api.deleteProject(project.id);
  });
  final task = await api.createTask(
    project.id,
    CreateTaskBody(title: 'A-Task $stamp', description: '', priority: 'low', status: 'to-do'),
  );
  final words = 'A-Comment $stamp';
  await api.createComment(task.id, words);
  Future<List<String>> found() async => [
    for (final result in (await api.search(words, workspaceId)).results) result.type,
  ];
  Future<List<String?>> inActivity() async => [
    for (final activity in await api.workspaceActivity(workspaceId)) activity.taskId,
  ];
  expect(await found(), contains('comment'));
  expect(await inActivity(), contains(task.id));

  await api.deleteProject(project.id);
  deleted = true;

  expect(await found(), isEmpty);
  expect(await inActivity(), isNot(contains(task.id)));
}

void main() {
  late I18n i18n;
  late ApiClient real;
  late KaneoApi api;
  late ApiClient fake;
  late FakeKaneo fakeServer;

  ApiClient client(
    String serverUrl,
    String token,
    FakeKaneo? adapter, {
    CredentialType type = CredentialType.apiKey,
  }) => ApiClient(
    session: () => Session(
      serverUrl: serverUrl,
      credentialType: type,
      token: token,
      userId: 'unused',
      userName: 'unused',
      userEmail: 'unused',
    ),
    i18n: i18n,
    onSessionExpired: (_) {},
    adapter: adapter,
  );

  setUpAll(() async {
    i18n = await I18n.load(read: (_) async => null);
    fakeServer = FakeKaneo();
    fake = client(FakeKaneo.serverUrl, FakeKaneo.apiKey, fakeServer);
    if (_apiKey.isEmpty) return;

    // API keys are limited to 100 requests a minute, which this file would exceed. Sessions are not.
    final signedOut = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
    final signIn = await signedOut.requestRaw(
      'api/auth/sign-in/email',
      method: 'POST',
      body: {'email': _email, 'password': _password},
      serverUrl: _serverUrl,
    );
    expect(signIn.isOk, isTrue, reason: 'Could not sign in: ${signIn.status}');
    real = client(_serverUrl, signIn.header('set-auth-token')!, null, type: CredentialType.bearer);
    api = KaneoApi(real, i18n);
  });

  group('local Kaneo', () {
    test('the server is local', () => expect(_isLocal, isTrue, reason: _serverUrl));

    test('every read in KaneoApi parses what the server sends', () async {
      expect((await api.me()).email, isNotEmpty);
      final workspaces = await api.workspaces();
      expect(workspaces.map((w) => w.id), contains(_workspaceId));
      await api.workspaceCapabilities(_workspaceId);
      expect(await api.workspaceMembers(_workspaceId), isNotEmpty);
      await api.workspaceMembers(_workspaceId, projectId: _projectId);
      expect((await api.fullWorkspace(_workspaceId)).members, isNotEmpty);
      expect(await api.workspaceRoles(_workspaceId), isNotEmpty);
      await api.pendingInvitations();
      expect(
        await api.workspacePermission(_workspaceId, {
          'task': ['read'],
        }),
        isTrue,
      );

      expect(await api.projects(_workspaceId), isNotEmpty);
      await api.projects(_workspaceId, includeArchived: true);
      final project = await api.project(_projectId);

      final board = await loadFullBoard(api, _projectId);
      expect(board.columns, isNotEmpty);
      final tasks = board.columns.expand((c) => c.tasks ?? const <BoardTask>[]).toList();
      expect(tasks, isNotEmpty);
      await api.assignedTasks(_workspaceId);

      for (final summary in tasks) {
        final task = await api.task(summary.id);
        expect(task.projectId, _projectId);
        await loadDescription(api, task);
        await api.activities(summary.id);
        await api.taskLabels(summary.id);
        await api.relations(summary.id);
        await api.externalLinks(summary.id);
        await api.timeEntries(summary.id);
        await api.taskCustomFieldValues(summary.id);
      }
      final first = tasks.first;
      expect((await api.taskByTicketId(ticketId(project.slug, first.number))).id, first.id);

      expect(await api.columns(_projectId), isNotEmpty);
      await api.projectRelations(_projectId);
      await api.customFields(_projectId);
      await api.workspaceActivity(_workspaceId);
      await api.workspaceLabels(_workspaceId);
      await api.notifications(workspaceId: _workspaceId);
      await api.notificationPreferences();
      await api.search('the', _workspaceId);
    });

    test('the writes in KaneoApi are accepted, on a temporary project', () async {
      final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
      final project = await api.createProject(
        name: 'Contract test $stamp',
        workspaceId: _workspaceId,
        icon: 'Layout',
        slug: 'CW$stamp',
      );
      addTearDown(() => api.deleteProject(project.id));
      final me = await api.me();

      await api.updateProject(
        project.id,
        name: 'Renamed $stamp',
        icon: 'Layout',
        slug: project.slug,
        description: 'Temporary',
        isPublic: false,
      );
      final columns = await api.columns(project.id);
      final column = await api.createColumn(project.id, name: 'Blocked');
      await api.updateColumn(column.id, name: 'Stuck');
      await api.reorderColumns(project.id, [
        for (final (index, c) in [column, ...columns].indexed)
          ColumnPosition(id: c.id, position: index),
      ]);
      await api.deleteColumn(column.id);

      final task = await api.createTask(
        project.id,
        CreateTaskBody(
          title: 'First',
          description: 'Text',
          priority: 'low',
          status: columns.first.slug,
          userId: me.id,
        ),
      );
      final second = await api.createTask(
        project.id,
        CreateTaskBody(
          title: 'Second',
          description: '',
          priority: 'no-priority',
          status: columns.first.slug,
        ),
      );
      expect((await api.updateTitle(task.id, 'Renamed')).title, 'Renamed');
      expect((await api.updateDescription(task.id, '**More**')).description, '**More**');
      expect((await api.updatePriority(task.id, 'urgent')).priority, 'urgent');
      expect((await api.updateStatus(task.id, columns[1].slug)).status, columns[1].slug);
      expect((await api.updateAssignee(task.id, null)).userId, isNull);
      expect((await api.updateAssignee(task.id, me.id)).userId, me.id);
      final due = toApiDate(DateTime(2030, 1, 15));
      expect((await api.updateDueDate(task.id, due)).dueDate, isNotNull);
      final updated = await api.updateTask(
        task.id,
        UpdateTaskBody(
          title: 'Full update',
          priority: 'high',
          status: columns.first.slug,
          projectId: project.id,
          position: 5,
        ),
      );
      expect(updated.title, 'Full update');
      await api.reorderTasks(project.id, [
        PositionUpdate(id: task.id, position: 1, status: columns.last.slug),
        PositionUpdate(id: second.id, position: 2),
      ]);
      expect((await api.task(task.id)).status, columns.last.slug);
      final copy = await api.duplicateTask(second.id);
      await api.deleteTask(copy.id);

      await api.createComment(task.id, 'A comment');
      final comment = (await api.activities(task.id)).firstWhere((a) => a.type == 'comment');
      await api.updateComment(comment.id, 'Edited');
      await api.deleteComment(comment.id);

      final label = await api.createLabel(
        name: 'contract-$stamp',
        color: 'blue',
        workspaceId: _workspaceId,
      );
      addTearDown(() => api.deleteLabel(label.id));
      await api.updateLabel(label.id, name: 'contract-$stamp-2', color: 'teal');
      await api.attachLabel(label.id, task.id);
      final attached = await api.taskLabels(task.id);
      expect(attached.single.name, 'contract-$stamp-2');
      await api.detachLabel(attached.single.id);

      await api.createRelation(task.id, second.id, 'subtask');
      final relations = await api.projectRelations(project.id);
      expect(relations.single.relationType, 'subtask');
      await api.deleteRelation(relations.single.id);

      final entry = await api.createTimeEntry(
        taskId: task.id,
        startTime: DateTime.utc(2030).toIso8601String(),
      );
      await api.updateTimeEntry(
        entry.id,
        startTime: DateTime.utc(2030).toIso8601String(),
        endTime: DateTime.utc(2030, 1, 1, 1).toIso8601String(),
      );

      await api.createExternalLink(task.id, 'https://example.com', title: 'Example');
      final links = await api.externalLinks(task.id);
      await api.deleteExternalLink(task.id, links.single.id);

      await api.markAllNotificationsRead(workspaceId: _workspaceId);
      final preferences = await api.notificationPreferences();
      await api.updateNotificationPreferences(
        UpdateNotificationPreferences(taskCommentEnabled: preferences.taskCommentEnabled),
      );

      await api.moveTask(second.id, _projectId, destinationStatus: 'to-do');
      addTearDown(() => api.deleteTask(second.id));
      await api.archiveProject(project.id);
      await api.unarchiveProject(project.id);
    });

    test(
      'moving, copying and deleting a task do the same on the server and on FakeKaneo',
      () async {
        await _checkMoveCopyDelete(api, _workspaceId);
        await _checkMoveCopyDelete(KaneoApi(fake, i18n), FakeKaneo.workspaceId);
      },
    );

    test('deleting a project takes its activity with it, on the server and on FakeKaneo', () async {
      await _checkDeletedProject(api, _workspaceId);
      await _checkDeletedProject(KaneoApi(fake, i18n), FakeKaneo.workspaceId);
    });

    test('the API key from dev.env works, in the x-api-key header', () async {
      final byKey = KaneoApi(client(_serverUrl, _apiKey, null), i18n);
      expect((await byKey.me()).email, _email);
    });

    test('a wrong key gets 401, and other failures are readable', () async {
      final wrong = KaneoApi(client(_serverUrl, 'wrong-key', null), i18n);
      await expectLater(
        wrong.me(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      await expectLater(
        api.project('does-not-exist'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', isNotEmpty),
        ),
      );
    });

    group('FakeKaneo answers with the fields of the real server', () {
      String real_(String template, {String task = '', String ws = _workspaceId}) => template
          .replaceAll('{project}', _projectId)
          .replaceAll('{workspace}', ws)
          .replaceAll('{task}', task);
      String fake_(String template) => template
          .replaceAll('{project}', FakeKaneo.projectId)
          .replaceAll('{workspace}', FakeKaneo.workspaceId)
          .replaceAll('{task}', 'task-1');

      const routes = {
        'api/user/me',
        'api/config',
        'api/workspace',
        'api/workspace/{workspace}/capabilities',
        'api/workspace/{workspace}/members',
        'api/auth/organization/get-full-organization?organizationId={workspace}',
        'api/auth/organization/list-roles?organizationId={workspace}',
        'api/project?workspaceId={workspace}',
        'api/project/{project}',
        'api/task/tasks/{project}',
        'api/task/assigned?workspaceId={workspace}',
        'api/task/{task}?view=detail',
        'api/task/{task}?view=board',
        'api/task/{task}/description?offset=0',
        'api/column/{project}',
        'api/activity/{task}',
        'api/activity/workspace/{workspace}',
        'api/label/workspace/{workspace}',
        'api/task-relation/{task}',
        'api/task-relation/project/{project}',
        'api/notification',
        'api/notification-preferences',
        'api/search?q=board&workspaceId={workspace}&type=all&limit=30',
      };

      for (final route in routes) {
        test(route, () async {
          final board = await api.board(_projectId);
          final parent = (await api.projectRelations(_projectId)).firstOrNull?.sourceTaskId;
          final taskId = parent ?? board.data.columns.first.tasks!.first.id;

          Future<Object?> get(ApiClient c, String url) {
            final uri = Uri.parse(url);
            return c.request(uri.path, query: uri.queryParameters);
          }

          final realShape = _shape(await get(real, real_(route, task: taskId)));
          final fakeShape = _shape(await get(fake, fake_(route)));
          expect(
            realShape.difference(fakeShape),
            isEmpty,
            reason: 'Fields the real server sends and FakeKaneo does not',
          );
          expect(
            fakeShape.difference(realShape),
            isEmpty,
            reason: 'Fields FakeKaneo sends and the real server does not',
          );
        });
      }
    });
  }, skip: _apiKey.isEmpty ? 'Pass dev.env to run: see the top of this file.' : false);
}
