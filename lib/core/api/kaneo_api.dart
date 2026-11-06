import '../i18n/i18n.dart';
import 'api_client.dart';
import 'models.dart';

typedef _FromJson<T> = T Function(Map<String, dynamic>);

/// The Kaneo REST API, ported from `kaneo/apps/mobile/src/lib/api/endpoints.ts`.
///
/// Every route lives under `/api`; Better Auth routes are under `/api/auth`.
class KaneoApi {
  KaneoApi(this.client, this._i18n);

  /// For routes not listed here, and for reading response headers.
  final ApiClient client;
  final I18n _i18n;

  T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on TypeError {
      throw ApiError(_i18n.t('app:errors.badResponse'));
    }
  }

  Map<String, dynamic> _map(Object? body) => (body as Map).cast<String, dynamic>();

  T _one<T>(Object? body, _FromJson<T> fromJson) => _decode(() => fromJson(_map(body)));

  List<T> _many<T>(Object? body, _FromJson<T> fromJson) =>
      _decode(() => (body as List).map((e) => fromJson(_map(e))).toList());

  Future<T> _getOne<T>(String path, _FromJson<T> fromJson, [Map<String, Object?>? query]) async =>
      _one(await client.request(path, query: query), fromJson);

  Future<List<T>> _getMany<T>(
    String path,
    _FromJson<T> fromJson, [
    Map<String, Object?>? query,
  ]) async => _many(await client.request(path, query: query), fromJson);

  Future<Object?> _post(String path, [Object? body]) =>
      client.request(path, method: 'POST', body: body ?? const <String, Object?>{});

  Future<Object?> _put(String path, [Object? body]) =>
      client.request(path, method: 'PUT', body: body ?? const <String, Object?>{});

  Future<Object?> _patch(String path, {Object? body, Map<String, Object?>? query}) =>
      client.request(path, method: 'PATCH', body: body ?? const <String, Object?>{}, query: query);

  Future<Object?> _delete(String path, {Object? body, Map<String, Object?>? query}) =>
      client.request(path, method: 'DELETE', body: body, query: query);

  // --- User ---

  Future<CurrentUser> me() => _getOne('api/user/me', CurrentUser.fromJson);

  Future<void> updateUser({String? name, String? image, bool clearImage = false}) => client.request(
    'api/auth/update-user',
    method: 'POST',
    body: {'name': ?name, if (image != null || clearImage) 'image': image},
    keepNulls: true,
  );

  /// Returns the new token when the server issued one.
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool revokeOtherSessions,
  }) async {
    final body = await _post('api/auth/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      'revokeOtherSessions': revokeOtherSessions,
    });
    return body is Map ? body['token'] as String? : null;
  }

  Future<FinalizedAsset> uploadAvatar({required String contentType, required String data}) async =>
      _one(
        await _put('api/user/avatar', {'contentType': contentType, 'data': data}),
        FinalizedAsset.fromJson,
      );

  Future<void> deleteAvatar() => _delete('api/user/avatar');

  Future<void> signOut() => _post('api/auth/sign-out');

  Future<void> deleteUser({String? password}) =>
      _post('api/auth/delete-user', {'password': ?password});

  // --- Workspaces ---

  /// Older servers have no `api/workspace` list; Better Auth's list works everywhere but carries no role.
  Future<List<Workspace>> workspaces() async {
    try {
      return await _getMany('api/workspace', Workspace.fromJson);
    } on ApiError catch (e) {
      if (e.status == 404) return _getMany('api/auth/organization/list', Workspace.fromJson);
      rethrow;
    }
  }

  Future<WorkspaceCapabilities> workspaceCapabilities(String workspaceId) =>
      _getOne('api/workspace/$workspaceId/capabilities', WorkspaceCapabilities.fromJson);

  Future<bool> workspacePermission(
    String organizationId,
    Map<String, List<String>> permissions,
  ) async {
    final body = await _post('api/auth/organization/has-permission', {
      'organizationId': organizationId,
      'permissions': permissions,
    });
    return body is Map && body['success'] == true;
  }

  Future<List<WorkspaceMember>> workspaceMembers(String workspaceId, {String? projectId}) =>
      _getMany('api/workspace/$workspaceId/members', WorkspaceMember.fromJson, {
        'projectId': projectId,
      });

  Future<Workspace> createWorkspace({
    required String name,
    required String slug,
    Map<String, String>? metadata,
  }) async => _one(
    await _post('api/auth/organization/create', {'name': name, 'slug': slug, 'metadata': metadata}),
    Workspace.fromJson,
  );

  Future<void> updateWorkspace(
    String organizationId, {
    String? name,
    String? description,
    Map<String, Object?>? metadata,
  }) => client.request(
    'api/auth/organization/update',
    method: 'POST',
    body: {
      'organizationId': organizationId,
      'data': {'name': ?name, 'description': ?description, 'metadata': ?metadata},
    },
    keepNulls: true,
  );

  Future<void> deleteWorkspace(String organizationId) =>
      _post('api/auth/organization/delete', {'organizationId': organizationId});

  Future<void> leaveWorkspace(String organizationId) =>
      _post('api/auth/organization/leave', {'organizationId': organizationId});

  Future<void> setActiveWorkspace(String? organizationId) => client.request(
    'api/auth/organization/set-active',
    method: 'POST',
    body: {'organizationId': organizationId},
    keepNulls: true,
  );

  Future<FullOrganization> fullWorkspace(String organizationId) => _getOne(
    'api/auth/organization/get-full-organization',
    FullOrganization.fromJson,
    {'organizationId': organizationId},
  );

  Future<List<String>> workspaceRoles(String organizationId) async {
    final body = await client.request(
      'api/auth/organization/list-roles',
      query: {'organizationId': organizationId},
    );
    return _decode(() => (body as List).map((e) => (e as Map)['role'] as String).toList());
  }

  Future<void> inviteMember({
    required String organizationId,
    required String email,
    required String role,
    bool? resend,
  }) => _post('api/auth/organization/invite-member', {
    'organizationId': organizationId,
    'email': email,
    'role': role,
    'resend': resend,
  });

  Future<void> cancelInvitation(String invitationId) =>
      _post('api/auth/organization/cancel-invitation', {'invitationId': invitationId});

  Future<void> removeMember(String organizationId, String memberIdOrEmail) => _post(
    'api/auth/organization/remove-member',
    {'organizationId': organizationId, 'memberIdOrEmail': memberIdOrEmail},
  );

  Future<void> updateMemberRole(String organizationId, String memberId, String role) => _post(
    'api/auth/organization/update-member-role',
    {'organizationId': organizationId, 'memberId': memberId, 'role': role},
  );

  Future<List<PendingInvitation>> pendingInvitations() =>
      _getMany('api/invitation/pending', PendingInvitation.fromJson);

  Future<void> acceptInvitation(String invitationId) =>
      _post('api/auth/organization/accept-invitation', {'invitationId': invitationId});

  Future<void> rejectInvitation(String invitationId) =>
      _post('api/auth/organization/reject-invitation', {'invitationId': invitationId});

  // --- Projects ---

  Future<List<Project>> projects(String workspaceId, {bool includeArchived = false}) => _getMany(
    'api/project',
    Project.fromJson,
    {'workspaceId': workspaceId, if (includeArchived) 'includeArchived': 'true'},
  );

  Future<Project> project(String id) => _getOne('api/project/$id', Project.fromJson);

  Future<Project> createProject({
    required String name,
    required String workspaceId,
    required String icon,
    required String slug,
  }) async => _one(
    await _post('api/project', {
      'name': name,
      'workspaceId': workspaceId,
      'icon': icon,
      'slug': slug,
    }),
    Project.fromJson,
  );

  Future<Project> updateProject(
    String id, {
    required String name,
    required String icon,
    required String slug,
    required String description,
    required bool isPublic,
  }) async => _one(
    await _put('api/project/$id', {
      'name': name,
      'icon': icon,
      'slug': slug,
      'description': description,
      'isPublic': isPublic,
    }),
    Project.fromJson,
  );

  Future<void> deleteProject(String id) => _delete('api/project/$id');

  Future<void> archiveProject(String id) => _put('api/project/$id/archive');

  Future<void> unarchiveProject(String id) => _put('api/project/$id/unarchive');

  Future<void> moveProject(String id, String workspaceId) =>
      _put('api/project/$id/move', {'workspaceId': workspaceId});

  // --- Tasks ---

  /// One page of a board. Use `loadFullBoard` to follow every page.
  Future<BoardResponse> board(String projectId, {int? page, int? relatedPage}) => _getOne(
    'api/task/tasks/$projectId',
    BoardResponse.fromJson,
    {'page': page, 'relatedPage': relatedPage, 'limit': 100},
  );

  Future<AssignedTasks> assignedTasks(String workspaceId) =>
      _getOne('api/task/assigned', AssignedTasks.fromJson, {'workspaceId': workspaceId});

  Future<Task> task(String id) => _getOne('api/task/$id', Task.fromJson, {'view': 'detail'});

  Future<Task> taskByTicketId(String ticketId, {String? workspaceId}) => _getOne(
    'api/task/by-ticket-id/${Uri.encodeComponent(ticketId)}',
    Task.fromJson,
    {'workspaceId': workspaceId},
  );

  Future<DescriptionPage> descriptionPage(String id, int offset, {String? version}) => _getOne(
    'api/task/$id/description',
    DescriptionPage.fromJson,
    {'offset': offset, 'version': version},
  );

  Future<Task> createTask(String projectId, CreateTaskBody body) async =>
      _one(await _post('api/task/$projectId', body.toJson()), Task.fromJson);

  Future<Task> updateTask(String id, UpdateTaskBody body) async =>
      _one(await _put('api/task/$id', body.toJson()), Task.fromJson);

  Future<void> deleteTask(String id) => _delete('api/task/$id');

  Future<Task> updateTitle(String id, String title) async =>
      _one(await _put('api/task/title/$id', {'title': title}), Task.fromJson);

  Future<Task> updateDescription(String id, String description) async =>
      _one(await _put('api/task/description/$id', {'description': description}), Task.fromJson);

  Future<Task> updateStatus(String id, String status) async =>
      _one(await _put('api/task/status/$id', {'status': status}), Task.fromJson);

  Future<Task> updatePriority(String id, String priority) async =>
      _one(await _put('api/task/priority/$id', {'priority': priority}), Task.fromJson);

  /// Pass null to unassign.
  Future<Task> updateAssignee(String id, String? userId) async => _one(
    await client.request(
      'api/task/assignee/$id',
      method: 'PUT',
      body: {'userId': userId},
      keepNulls: true,
    ),
    Task.fromJson,
  );

  Future<Task> updateDueDate(String id, String? dueDate) async =>
      _one(await _put('api/task/due-date/$id', {'dueDate': dueDate}), Task.fromJson);

  Future<void> moveTask(String id, String destinationProjectId, {String? destinationStatus}) =>
      _put('api/task/move/$id', {
        'destinationProjectId': destinationProjectId,
        'destinationStatus': destinationStatus,
      });

  Future<Task> duplicateTask(String id) async =>
      _one(await _post('api/task/duplicate/$id'), Task.fromJson);

  Future<void> reorderTasks(String projectId, List<PositionUpdate> tasks) => _post(
    'api/task/reorder',
    {'projectId': projectId, 'tasks': tasks.map((t) => t.toJson()).toList()},
  );

  Future<ImageUploadResponse> createImageUpload(
    String taskId, {
    required String filename,
    required String contentType,
    required int size,
    required String surface,
  }) async => _one(
    await _put('api/task/image-upload/$taskId', {
      'filename': filename,
      'contentType': contentType,
      'size': size,
      'surface': surface,
    }),
    ImageUploadResponse.fromJson,
  );

  Future<FinalizedAsset> finalizeImageUpload(
    String taskId, {
    required String key,
    required String filename,
    required String contentType,
    required int size,
    required String surface,
  }) async => _one(
    await _post('api/task/image-upload/$taskId/finalize', {
      'key': key,
      'filename': filename,
      'contentType': contentType,
      'size': size,
      'surface': surface,
    }),
    FinalizedAsset.fromJson,
  );

  // --- Columns ---

  Future<List<ProjectColumn>> columns(String projectId) =>
      _getMany('api/column/$projectId', ProjectColumn.fromJson);

  Future<ProjectColumn> createColumn(
    String projectId, {
    required String name,
    bool? isFinal,
  }) async => _one(
    await _post('api/column/$projectId', {'name': name, 'isFinal': isFinal}),
    ProjectColumn.fromJson,
  );

  Future<ProjectColumn> updateColumn(String id, {String? name, bool? isFinal}) async => _one(
    await _put('api/column/$id', {'name': name, 'isFinal': isFinal}),
    ProjectColumn.fromJson,
  );

  Future<void> deleteColumn(String id) => _delete('api/column/$id');

  Future<void> reorderColumns(String projectId, List<ColumnPosition> columns) =>
      _put('api/column/reorder/$projectId', {'columns': columns.map((c) => c.toJson()).toList()});

  // --- Activity and comments ---

  Future<List<Activity>> activities(String taskId) =>
      _getMany('api/activity/$taskId', Activity.fromJson);

  Future<List<WorkspaceActivity>> workspaceActivity(String workspaceId) =>
      _getMany('api/activity/workspace/$workspaceId', WorkspaceActivity.fromJson);

  Future<void> createComment(String taskId, String comment) =>
      _post('api/activity/comment', {'taskId': taskId, 'comment': comment});

  Future<void> updateComment(String activityId, String comment) =>
      _put('api/activity/comment', {'activityId': activityId, 'comment': comment});

  Future<void> deleteComment(String activityId) =>
      _delete('api/activity/comment', body: {'activityId': activityId});

  // --- Labels ---

  Future<List<Label>> workspaceLabels(String workspaceId) =>
      _getMany('api/label/workspace/$workspaceId', Label.fromJson);

  Future<List<Label>> taskLabels(String taskId) =>
      _getMany('api/label/task/$taskId', Label.fromJson);

  Future<Label> createLabel({
    required String name,
    required String color,
    required String workspaceId,
    String? taskId,
  }) async => _one(
    await _post('api/label', {
      'name': name,
      'color': color,
      'workspaceId': workspaceId,
      'taskId': taskId,
    }),
    Label.fromJson,
  );

  Future<Label> updateLabel(String id, {required String name, required String color}) async =>
      _one(await _put('api/label/$id', {'name': name, 'color': color}), Label.fromJson);

  Future<void> deleteLabel(String id) => _delete('api/label/$id');

  Future<void> attachLabel(String labelId, String taskId) =>
      _put('api/label/$labelId/task', {'taskId': taskId});

  /// [taskLabelId] is the task's own copy of the label, not the workspace label.
  Future<void> detachLabel(String taskLabelId) => _delete('api/label/$taskLabelId/task');

  // --- Time ---

  Future<List<TimeEntry>> timeEntries(String taskId) =>
      _getMany('api/time-entry/task/$taskId', TimeEntry.fromJson);

  Future<TimeEntry> createTimeEntry({
    required String taskId,
    required String startTime,
    String? endTime,
    String? description,
  }) async => _one(
    await _post('api/time-entry', {
      'taskId': taskId,
      'startTime': startTime,
      'endTime': endTime,
      'description': description,
    }),
    TimeEntry.fromJson,
  );

  Future<TimeEntry> updateTimeEntry(
    String id, {
    required String startTime,
    String? endTime,
    String? description,
  }) async => _one(
    await _put('api/time-entry/$id', {
      'startTime': startTime,
      'endTime': endTime,
      'description': description,
    }),
    TimeEntry.fromJson,
  );

  // --- Relations and links ---

  Future<List<TaskRelation>> relations(String taskId) =>
      _getMany('api/task-relation/$taskId', TaskRelation.fromJson);

  /// Every relation between two tasks in the project, without the task summaries. For views that
  /// show many tasks at once and already hold them.
  Future<List<TaskRelation>> projectRelations(String projectId) =>
      _getMany('api/task-relation/project/$projectId', TaskRelation.fromJson);

  Future<void> createRelation(String sourceTaskId, String targetTaskId, String relationType) =>
      _post('api/task-relation', {
        'sourceTaskId': sourceTaskId,
        'targetTaskId': targetTaskId,
        'relationType': relationType,
      });

  Future<void> deleteRelation(String id) => _delete('api/task-relation/$id');

  Future<List<ExternalLink>> externalLinks(String taskId) =>
      _getMany('api/external-link/task/$taskId', ExternalLink.fromJson);

  Future<void> createExternalLink(String taskId, String url, {String? title}) =>
      _post('api/external-link/task/$taskId', {'url': url, 'title': title});

  Future<void> deleteExternalLink(String taskId, String id) =>
      _delete('api/external-link/task/$taskId/$id');

  // --- Custom fields ---

  Future<List<CustomFieldDefinition>> customFields(String projectId) =>
      _getMany('api/custom-field/project/$projectId', CustomFieldDefinition.fromJson);

  Future<List<CustomFieldValue>> taskCustomFieldValues(String taskId) =>
      _getMany('api/custom-field/task/$taskId', CustomFieldValue.fromJson);

  Future<void> createCustomField({
    required String projectId,
    required String name,
    required String type,
    required bool required_,
    String? defaultValue,
    List<String>? options,
  }) => _post('api/custom-field', {
    'projectId': projectId,
    'name': name,
    'type': type,
    'required': required_,
    'defaultValue': defaultValue,
    'options': options,
  });

  Future<void> deleteCustomField(String id) => _delete('api/custom-field/$id');

  Future<void> setCustomFieldValue(String taskId, String fieldId, String value) =>
      _put('api/custom-field/value', {'taskId': taskId, 'fieldId': fieldId, 'value': value});

  // --- Notifications ---

  Future<List<InboxNotification>> notifications({String? workspaceId}) =>
      _getMany('api/notification', InboxNotification.fromJson, {'workspaceId': workspaceId});

  Future<void> markNotificationRead(String id) => _patch('api/notification/$id/read');

  Future<void> markAllNotificationsRead({String? workspaceId}) =>
      _patch('api/notification/read-all', query: {'workspaceId': workspaceId});

  Future<void> clearAllNotifications({String? workspaceId}) =>
      _delete('api/notification/clear-all', query: {'workspaceId': workspaceId});

  Future<NotificationPreferences> notificationPreferences() =>
      _getOne('api/notification-preferences', NotificationPreferences.fromJson);

  Future<void> updateNotificationPreferences(UpdateNotificationPreferences body) =>
      _put('api/notification-preferences', body.toJson());

  // --- Search ---

  Future<SearchResponse> search(String q, String workspaceId, {String type = 'all'}) => _getOne(
    'api/search',
    SearchResponse.fromJson,
    {'q': q, 'workspaceId': workspaceId, 'type': type, 'limit': '30'},
  );
}
