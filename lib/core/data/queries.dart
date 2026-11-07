import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/board_loader.dart';
import '../api/models.dart';
import '../cache/cached_query.dart';
import '../providers.dart';

List<T> _decodeList<T>(Object? json, T Function(Map<String, dynamic>) fromJson) =>
    (json as List).map((e) => fromJson((e as Map).cast<String, dynamic>())).toList();

Map<String, dynamic> _decodeMap(Object? json) => (json as Map).cast<String, dynamic>();

final meQuery = cachedQuery<CurrentUser>(
  QuerySpec(
    key: 'me',
    fetch: (ref) => ref.read(kaneoApiProvider).me(),
    encode: (v) => v.toJson(),
    decode: (j) => CurrentUser.fromJson(_decodeMap(j)),
  ),
);

final workspacesQuery = cachedQuery<List<Workspace>>(
  QuerySpec(
    key: 'workspaces',
    fetch: (ref) => ref.read(kaneoApiProvider).workspaces(),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, Workspace.fromJson),
  ),
);

const _lastWorkspaceKey = 'kaneo.lastWorkspaceId';

/// The workspace the user picked last, kept per device.
final selectedWorkspaceIdProvider = NotifierProvider<SelectedWorkspaceId, String?>(
  SelectedWorkspaceId.new,
);

class SelectedWorkspaceId extends Notifier<String?> {
  @override
  String? build() => ref.watch(prefsProvider).getString(_lastWorkspaceKey);

  Future<void> select(String workspaceId) async {
    state = workspaceId;
    await ref.read(prefsProvider).setString(_lastWorkspaceKey, workspaceId);
  }
}

/// The remembered workspace if it still exists, otherwise the first one, or null if there are none.
///
/// Stays on the data it has while the list refreshes or fails to, like every cached query. Pages are
/// built under this, so losing it for a moment would throw away whatever they hold.
final currentWorkspaceProvider = Provider.autoDispose<AsyncValue<Workspace?>>((ref) {
  final selected = ref.watch(selectedWorkspaceIdProvider);
  final workspaces = ref.watch(workspacesQuery);
  if (!workspaces.hasValue) return workspaces.whenData((_) => null);
  final list = workspaces.requireValue;
  for (final workspace in list) {
    if (workspace.id == selected) return AsyncData(workspace);
  }
  return AsyncData(list.firstOrNull);
});

final projectsQuery = cachedQueryFamily<List<Project>, String>(
  (workspaceId) => QuerySpec(
    key: 'projects/$workspaceId',
    fetch: (ref) => ref.read(kaneoApiProvider).projects(workspaceId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, Project.fromJson),
  ),
);

/// [projectsQuery] with the archived projects as well.
final allProjectsQuery = cachedQueryFamily<List<Project>, String>(
  (workspaceId) => QuerySpec(
    key: 'projects-all/$workspaceId',
    fetch: (ref) => ref.read(kaneoApiProvider).projects(workspaceId, includeArchived: true),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, Project.fromJson),
  ),
);

/// Every page of a board, merged.
final boardQuery = cachedQueryFamily<BoardData, String>(
  (projectId) => QuerySpec(
    key: 'board/$projectId',
    fetch: (ref) => loadFullBoard(ref.read(kaneoApiProvider), projectId),
    encode: (v) => v.toJson(),
    decode: (j) => BoardData.fromJson(_decodeMap(j)),
  ),
);

final projectRelationsQuery = cachedQueryFamily<List<TaskRelation>, String>(
  (projectId) => QuerySpec(
    key: 'relations/$projectId',
    fetch: (ref) => ref.read(kaneoApiProvider).projectRelations(projectId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, TaskRelation.fromJson),
  ),
);

final columnsQuery = cachedQueryFamily<List<ProjectColumn>, String>(
  (projectId) => QuerySpec(
    key: 'columns/$projectId',
    fetch: (ref) => ref.read(kaneoApiProvider).columns(projectId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, ProjectColumn.fromJson),
  ),
);

final taskQuery = cachedQueryFamily<Task, String>(
  (taskId) => QuerySpec(
    key: 'task/$taskId',
    fetch: (ref) => ref.read(kaneoApiProvider).task(taskId),
    encode: (v) => v.toJson(),
    decode: (j) => Task.fromJson(_decodeMap(j)),
  ),
);

final assignedTasksQuery = cachedQueryFamily<AssignedTasks, String>(
  (workspaceId) => QuerySpec(
    key: 'assigned/$workspaceId',
    fetch: (ref) => ref.read(kaneoApiProvider).assignedTasks(workspaceId),
    encode: (v) => v.toJson(),
    decode: (j) => AssignedTasks.fromJson(_decodeMap(j)),
  ),
);

final notificationsQuery = cachedQueryFamily<List<InboxNotification>, String>(
  (workspaceId) => QuerySpec(
    key: 'notifications/$workspaceId',
    fetch: (ref) => ref.read(kaneoApiProvider).notifications(workspaceId: workspaceId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, InboxNotification.fromJson),
  ),
);

final workspaceActivityQuery = cachedQueryFamily<List<WorkspaceActivity>, String>(
  (workspaceId) => QuerySpec(
    key: 'activity/$workspaceId',
    fetch: (ref) => ref.read(kaneoApiProvider).workspaceActivity(workspaceId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, WorkspaceActivity.fromJson),
  ),
);

/// Pass the project id too when listing the people who can be assigned in a project.
final membersQuery =
    cachedQueryFamily<List<WorkspaceMember>, ({String workspaceId, String? projectId})>(
      (arg) => QuerySpec(
        key: 'members/${arg.workspaceId}/${arg.projectId ?? ''}',
        fetch: (ref) =>
            ref.read(kaneoApiProvider).workspaceMembers(arg.workspaceId, projectId: arg.projectId),
        encode: (v) => v.map((e) => e.toJson()).toList(),
        decode: (j) => _decodeList(j, WorkspaceMember.fromJson),
      ),
    );

final workspaceLabelsQuery = cachedQueryFamily<List<Label>, String>(
  (workspaceId) => QuerySpec(
    key: 'labels/$workspaceId',
    fetch: (ref) => ref.read(kaneoApiProvider).workspaceLabels(workspaceId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) => _decodeList(j, Label.fromJson),
  ),
);

final capabilitiesQuery = cachedQueryFamily<WorkspaceCapabilities, String>(
  (workspaceId) => QuerySpec(
    key: 'capabilities/$workspaceId',
    fetch: (ref) => ref.read(kaneoApiProvider).workspaceCapabilities(workspaceId),
    encode: (v) => v.toJson(),
    decode: (j) => WorkspaceCapabilities.fromJson(_decodeMap(j)),
  ),
);
