import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/fake_kaneo.dart';

void main() {
  late FakeKaneo server;
  late KaneoApi api;
  const workspace = FakeKaneo.workspaceId;
  const project = FakeKaneo.projectId;

  setUp(() async {
    server = FakeKaneo();
    final i18n = await I18n.load(read: (_) async => null);
    api = KaneoApi(
      ApiClient(
        session: () => const Session(
          serverUrl: FakeKaneo.serverUrl,
          credentialType: CredentialType.apiKey,
          token: FakeKaneo.apiKey,
          userId: FakeKaneo.userId,
          userName: 'Test User',
          userEmail: FakeKaneo.email,
        ),
        i18n: i18n,
        onSessionExpired: (_) {},
        adapter: server,
      ),
      i18n,
    );
  });

  test('user routes', () async {
    expect((await api.me()).email, FakeKaneo.email);
    await api.updateUser(name: 'New Name');
    expect((await api.me()).name, 'New Name');
    await api.updateUser(clearImage: true);
    expect(server.requests.last.body, {'image': null});
    expect(
      await api.changePassword(currentPassword: 'a', newPassword: 'b', revokeOtherSessions: false),
      FakeKaneo.sessionToken,
    );
    expect((await api.uploadAvatar(contentType: 'image/png', data: 'AA')).id, 'avatar-1');
    await api.deleteAvatar();
    await api.deleteUser(password: 'a');
    await api.signOut();
    expect(server.requestsTo('api/auth/sign-out', method: 'POST'), hasLength(1));
  });

  test('workspace routes', () async {
    expect((await api.workspaces()).single.role, 'owner');
    expect((await api.workspaceCapabilities(workspace)).createTasks, isTrue);
    expect(
      await api.workspacePermission(workspace, {
        'task': ['read'],
      }),
      isTrue,
    );
    expect(await api.workspaceMembers(workspace), hasLength(2));
    await api.workspaceMembers(workspace, projectId: project);
    expect(server.requests.last.query['projectId'], project);

    final created = await api.createWorkspace(name: 'Second', slug: 'second');
    expect(created.slug, 'second');
    await api.updateWorkspace(created.id, name: 'Renamed');
    expect((await api.workspaces()).last.name, 'Renamed');
    await api.setActiveWorkspace(created.id);
    await api.setActiveWorkspace(null);
    expect(server.requests.last.body, {'organizationId': null});
    await api.leaveWorkspace(created.id);
    expect(await api.workspaces(), hasLength(1));

    final full = await api.fullWorkspace(workspace);
    expect(full.members, hasLength(2));
    expect(await api.workspaceRoles(workspace), contains('member'));

    await api.inviteMember(organizationId: workspace, email: 'x@example.com', role: 'member');
    final pending = await api.pendingInvitations();
    expect(pending.single.email, 'x@example.com');
    await api.acceptInvitation(pending.single.id);
    expect(await api.pendingInvitations(), isEmpty);
    await api.updateMemberRole(workspace, 'user-2', 'admin');
    await api.removeMember(workspace, 'user-2');
    expect(await api.workspaceMembers(workspace), hasLength(1));
  });

  test('falls back to the older workspace list on a 404', () async {
    server.failNext(RegExp(r'^api/workspace$'), status: 404);
    expect((await api.workspaces()).single.id, workspace);
    expect(server.requestsTo('api/auth/organization/list'), hasLength(1));
  });

  test('other failures of the workspace list are not swallowed', () async {
    server.failNext(RegExp(r'^api/workspace$'), status: 500);
    await expectLater(api.workspaces(), throwsA(isA<ApiError>()));
  });

  test('project routes', () async {
    expect(await api.projects(workspace), hasLength(2));
    expect((await api.project(project)).slug, 'DEMO');
    final created = await api.createProject(
      name: 'New',
      workspaceId: workspace,
      icon: 'Layout',
      slug: 'NEW',
    );
    final updated = await api.updateProject(
      created.id,
      name: 'Renamed',
      icon: 'Layout',
      slug: 'NEW',
      description: 'd',
      isPublic: true,
    );
    expect(updated.name, 'Renamed');
    await api.archiveProject(created.id);
    expect(await api.projects(workspace), hasLength(2));
    expect(await api.projects(workspace, includeArchived: true), hasLength(3));
    await api.unarchiveProject(created.id);
    await api.moveProject(created.id, workspace);
    await api.deleteProject(created.id);
    expect(await api.projects(workspace), hasLength(2));
  });

  test('task reads', () async {
    final board = await api.board(project, page: 1);
    expect(board.data.slug, 'DEMO');
    expect(board.data.columns, hasLength(4));
    expect(board.pagination?.totalPages, 1);
    expect(server.requests.last.query['limit'], '100');

    final assigned = await api.assignedTasks(workspace);
    expect(assigned.total, 5);
    expect(assigned.tasks.first.projectSlug, 'DEMO');

    final task = await api.task('task-1');
    expect(task.title, 'Set up the project');
    expect(server.requests.last.query['view'], 'detail');

    expect((await api.taskByTicketId('DEMO-2')).id, 'task-2');
    expect((await api.descriptionPage('task-2', 0)).nextOffset, isNull);
  });

  test('task writes', () async {
    final created = await api.createTask(
      project,
      const CreateTaskBody(title: 'New', description: 'Text', priority: 'low', status: 'to-do'),
    );
    expect(created.title, 'New');
    final id = created.id;

    expect((await api.updateTitle(id, 'Renamed')).title, 'Renamed');
    expect((await api.updateDescription(id, 'More')).description, 'More');
    expect((await api.updateStatus(id, 'done')).status, 'done');
    expect((await api.updatePriority(id, 'urgent')).priority, 'urgent');
    expect((await api.updateAssignee(id, 'user-2')).userId, 'user-2');
    expect((await api.updateAssignee(id, null)).userId, isNull);
    expect(server.requests.last.body, {'userId': null});
    expect((await api.updateDueDate(id, '2026-12-01T00:00:00.000Z')).dueDate, isNotNull);

    final full = await api.updateTask(
      id,
      const UpdateTaskBody(
        title: 'Again',
        priority: 'low',
        status: 'to-do',
        projectId: project,
        position: 3,
      ),
    );
    expect(full.title, 'Again');

    await api.moveTask(id, FakeKaneo.secondProjectId, destinationStatus: 'to-do');
    expect((await api.task(id)).projectId, FakeKaneo.secondProjectId);

    final copy = await api.duplicateTask(id);
    expect(copy.id, isNot(id));

    await api.reorderTasks(project, const [
      PositionUpdate(id: 'task-1', position: 9, status: 'in-progress'),
    ]);
    expect((await api.task('task-1')).status, 'in-progress');

    await api.deleteTask(id);
    await expectLater(api.task(id), throwsA(isA<ApiError>().having((e) => e.status, 's', 404)));
  });

  test('image uploads', () async {
    final upload = await api.createImageUpload(
      'task-1',
      filename: 'a.png',
      contentType: 'image/png',
      size: 1,
      surface: 'description',
    );
    expect(upload.uploadUrl, contains('task-1'));
    final asset = await api.finalizeImageUpload(
      'task-1',
      key: upload.key,
      filename: 'a.png',
      contentType: 'image/png',
      size: 1,
      surface: 'description',
    );
    expect(asset.url, contains('asset'));
  });

  test('column routes', () async {
    final columns = await api.columns(project);
    expect(columns.map((c) => c.slug), ['to-do', 'in-progress', 'in-review', 'done']);
    final created = await api.createColumn(project, name: 'Blocked');
    expect(created.slug, 'blocked');
    expect((await api.updateColumn(created.id, name: 'Stuck')).name, 'Stuck');
    await api.reorderColumns(project, [ColumnPosition(id: created.id, position: 0)]);
    expect((await api.columns(project)).firstWhere((c) => c.id == created.id).position, 0);
    await api.deleteColumn(created.id);
    expect(await api.columns(project), hasLength(4));
  });

  test('activity and comments', () async {
    await api.createComment('task-1', 'Hello');
    final activities = await api.activities('task-1');
    final comment = activities.firstWhere((a) => a.content == 'Hello');
    await api.updateComment(comment.id, 'Edited');
    expect((await api.activities('task-1')).map((a) => a.content), contains('Edited'));
    await api.deleteComment(comment.id);
    expect((await api.activities('task-1')).map((a) => a.content), isNot(contains('Edited')));
    expect((await api.workspaceActivity(workspace)).first.projectSlug, 'DEMO');
  });

  test('labels', () async {
    final created = await api.createLabel(name: 'ui', color: 'blue', workspaceId: workspace);
    expect((await api.updateLabel(created.id, name: 'UI', color: 'teal')).name, 'UI');
    await api.attachLabel(created.id, 'task-1');
    final onTask = await api.taskLabels('task-1');
    expect(onTask.single.name, 'UI');
    await api.detachLabel(onTask.single.id);
    expect(await api.taskLabels('task-1'), isEmpty);
    await api.deleteLabel(created.id);
    expect((await api.workspaceLabels(workspace)).map((l) => l.id), isNot(contains(created.id)));
  });

  test('time entries', () async {
    final entry = await api.createTimeEntry(taskId: 'task-1', startTime: '2026-11-06T10:00:00Z');
    final updated = await api.updateTimeEntry(
      entry.id,
      startTime: '2026-11-06T10:00:00Z',
      endTime: '2026-11-06T11:00:00Z',
    );
    expect(updated.endTime, isNotNull);
    expect(await api.timeEntries('task-1'), hasLength(1));
  });

  test('relations and external links', () async {
    expect((await api.relations('task-1')).single.targetTask?.id, 'task-2');
    expect((await api.projectRelations(project)).single.relationType, 'subtask');
    await api.createRelation('task-3', 'task-4', 'blocks');
    final relations = await api.projectRelations(project);
    expect(relations, hasLength(2));
    await api.deleteRelation(relations.last.id);
    expect(await api.projectRelations(project), hasLength(1));

    await api.createExternalLink('task-1', 'https://example.com', title: 'Example');
    final links = await api.externalLinks('task-1');
    expect(links.single.title, 'Example');
    await api.deleteExternalLink('task-1', links.single.id);
    expect(await api.externalLinks('task-1'), isEmpty);
  });

  test('custom fields', () async {
    await api.createCustomField(projectId: project, name: 'Size', type: 'text', required_: false);
    final fields = await api.customFields(project);
    await api.setCustomFieldValue('task-1', fields.single.id, 'L');
    expect((await api.taskCustomFieldValues('task-1')).single.value, 'L');
    await api.deleteCustomField(fields.single.id);
    expect(await api.customFields(project), isEmpty);
  });

  test('notifications', () async {
    final notifications = await api.notifications(workspaceId: workspace);
    expect(notifications, hasLength(2));
    await api.markNotificationRead(notifications.first.id);
    await api.markAllNotificationsRead(workspaceId: workspace);
    expect((await api.notifications()).every((n) => n.isRead == true), isTrue);
    await api.clearAllNotifications(workspaceId: workspace);
    expect(await api.notifications(), isEmpty);

    expect((await api.notificationPreferences()).taskCommentEnabled, isTrue);
    await api.updateNotificationPreferences(
      const UpdateNotificationPreferences(taskCommentEnabled: false),
    );
    expect((await api.notificationPreferences()).taskCommentEnabled, isFalse);
  });

  test('search', () async {
    final found = await api.search('board', workspace);
    expect(found.results.single.title, 'Review the board layout');
    expect(server.requests.last.query, containsPair('limit', '30'));
    expect(server.requests.last.query, containsPair('type', 'all'));
  });

  test('a response in an unexpected shape gives a readable error', () async {
    server.failNext('api/user/me', status: 200, body: {'unexpected': true});
    await expectLater(
      api.me(),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', 'app:errors.badResponse')),
    );
  });
}
