import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import 'task_edits.dart';
import 'task_relations.dart';

/// The status a new task starts in: [preferred] if the project has it, otherwise its first open
/// column, or `planned` if it has none. A slug two columns share can't pick a column, as in the web
/// app, because creating a task only names the slug.
String initialTaskStatus(List<ProjectColumn> columns, String? preferred) {
  if (preferred == statusPlanned || preferred == statusArchived) return preferred!;
  if (columns.any((c) => c.slug == preferred)) return preferred!;
  final sorted = _inOrder(columns);
  final open = sorted.where(
    (c) => c.isFinal != true && sorted.where((other) => other.slug == c.slug).length == 1,
  );
  return open.firstOrNull?.slug ?? statusPlanned;
}

/// What a new task can start in. [projectId] and [plannedName] make the `planned` one the board
/// always has, for a project with no such column of its own.
List<ProjectColumn> newTaskStatuses(
  List<ProjectColumn> columns, {
  required String projectId,
  required String plannedName,
}) => [
  if (!columns.any((c) => c.slug == statusPlanned))
    ProjectColumn(id: statusPlanned, projectId: projectId, name: plannedName, slug: statusPlanned),
  ..._inOrder(columns),
];

List<ProjectColumn> _inOrder(List<ProjectColumn> columns) =>
    [...columns]..sort((a, b) => (a.position ?? 0).compareTo(b.position ?? 0));

/// The card a board shows for a task just created. The task doesn't carry the assignee's picture.
BoardTask newTaskCard(Task task, WorkspaceMember? assignee) => BoardTask(
  id: task.id,
  title: task.title,
  number: task.number,
  description: task.description,
  status: task.status,
  priority: task.priority,
  startDate: task.startDate,
  dueDate: task.dueDate,
  position: task.position,
  createdAt: task.createdAt,
  userId: task.userId,
  assigneeId: task.assigneeId ?? task.userId,
  assigneeName: task.assigneeName ?? assignee?.name,
  assigneeImage: assignee?.image,
  projectId: task.projectId,
);

/// Creates tasks and keeps the board and the lists in step with them.
class NewTasks {
  NewTasks._(this._ref);

  final Ref _ref;

  /// Throws if the task wasn't created, and then nothing has changed.
  ///
  /// Once it exists it must not be created again, so a label that can't be added doesn't throw. It
  /// resolves to whether all of [labels] were added.
  Future<bool> create({
    required String workspaceId,
    required String projectId,
    required CreateTaskBody body,
    required List<Label> labels,
    WorkspaceMember? assignee,
  }) async {
    // It has to finish even if the form closes while it is under way.
    final keepAlive = _ref.keepAlive();
    try {
      final api = _ref.read(kaneoApiProvider);
      final task = await api.createTask(projectId, body);
      if (!_ref.mounted) return true;
      _publish(task, assignee);
      var added = true;
      for (final label in labels) {
        try {
          await addTaskLabel(api, label, taskId: task.id, workspaceId: workspaceId);
        } catch (_) {
          added = false;
        }
      }
      if (!_ref.mounted) return added;
      // Brings the labels to the card. The card is there already, so this can take its time.
      _refreshIfOpen(boardQuery(projectId));
      _refreshIfOpen(assignedTasksQuery(workspaceId));
      return added;
    } finally {
      keepAlive.close();
    }
  }

  /// Adds a task called [title] under [parent], with nothing else set, as the web app does: in the
  /// parent's project, planned if the parent is, and otherwise in the first open column.
  ///
  /// Throws if the task wasn't created, and then nothing has changed. Once it exists it must not be
  /// created again, so a link that can't be made doesn't throw. It resolves to whether it was made.
  Future<bool> createSubtask({required Task parent, required String title}) async {
    // It has to finish even if the task closes while it is under way.
    final keepAlive = _ref.keepAlive();
    try {
      final api = _ref.read(kaneoApiProvider);
      final projectId = parent.projectId;
      final preferred = parent.status == statusPlanned ? statusPlanned : null;
      final columns = preferred != null
          ? const <ProjectColumn>[]
          : _ref.read(columnsQuery(projectId)).value ?? await api.columns(projectId);
      final task = await api.createTask(
        projectId,
        CreateTaskBody(
          title: title,
          description: '',
          priority: priorities.first,
          status: initialTaskStatus(columns, preferred),
        ),
      );
      var linked = true;
      try {
        await api.createRelation(parent.id, task.id, relationSubtask);
      } catch (_) {
        linked = false;
      }
      if (!_ref.mounted) return linked;
      // A board shows it among the parent's children, and the parent's progress.
      _refreshIfOpen(boardQuery(projectId));
      _refreshIfOpen(projectRelationsQuery(projectId));
      final relations = taskRelationsQuery(parent.id);
      if (_ref.read(relations.exists)) await _ref.read(relations.notifier).refresh();
      return linked;
    } finally {
      keepAlive.close();
    }
  }

  void _publish(Task task, WorkspaceMember? assignee) {
    final board = boardQuery(task.projectId);
    if (!_ref.read(board.exists)) return;
    final data = _ref.read(board).value;
    if (data == null) return;
    _ref.read(board.notifier).setData(boardWithNewCard(data, newTaskCard(task, assignee)));
  }

  /// Something a page below is showing. Otherwise it refreshes by itself when it next opens.
  void _refreshIfOpen<T>(AsyncNotifierProvider<CachedQuery<T>, T> query) {
    if (_ref.read(query.exists)) unawaited(_ref.read(query.notifier).refresh());
  }
}

final newTasksProvider = Provider.autoDispose<NewTasks>((ref) {
  // A task started under one account must never be published under the next.
  ref.watch(sessionProvider.select((s) => (s?.serverUrl, s?.userId)));
  return NewTasks._(ref);
});
