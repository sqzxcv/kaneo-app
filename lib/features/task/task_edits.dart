import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../core/core.dart';
import '../board/board_data.dart';
import 'description_autosave.dart';
import 'task_activity.dart';
import 'task_relations.dart';

/// The labels on a task. Each is the task's own copy of a workspace label.
final taskLabelsQuery = cachedQueryFamily<List<Label>, String>(
  (taskId) => QuerySpec(
    key: 'task-labels/$taskId',
    fetch: (ref) => ref.read(kaneoApiProvider).taskLabels(taskId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) =>
        (j as List).map((e) => Label.fromJson((e as Map).cast<String, dynamic>())).toList(),
  ),
);

/// [board] with its card for [task] showing the task's current fields, in the column of its status.
///
/// [assigneeImage] is only used when the assignee changed. The task itself doesn't carry a picture.
BoardData boardWithTask(BoardData board, Task task, {String? assigneeImage}) {
  final card = boardTasks(board).where((t) => t.id == task.id).firstOrNull;
  if (card == null) return board;
  final updated = card.copyWith(
    title: task.title,
    status: task.status,
    priority: task.priority,
    startDate: task.startDate,
    dueDate: task.dueDate,
    userId: task.userId,
    assigneeId: task.assigneeId,
    assigneeName: task.assigneeName,
    assigneeImage: task.userId == card.userId ? card.assigneeImage : assigneeImage,
  );
  final status = task.status;
  final inColumn = board.columns.any((c) => c.slug == status);
  if (status == card.status || !(inColumn || status == statusPlanned || status == statusArchived)) {
    return updateBoardTask(board, task.id, (_) => updated);
  }

  List<BoardTask> without(List<BoardTask>? tasks) => _without(tasks, task.id);
  // A change of status keeps the task's position, so this is where the server will have it too.
  List<BoardTask> into(List<BoardTask>? tasks) => _inPlace(without(tasks), updated);

  return board.copyWith(
    columns: [
      for (final column in board.columns)
        column.copyWith(tasks: column.slug == status ? into(column.tasks) : without(column.tasks)),
    ],
    plannedTasks: !inColumn && status == statusPlanned
        ? into(board.plannedTasks)
        : without(board.plannedTasks),
    archivedTasks: !inColumn && status == statusArchived
        ? into(board.archivedTasks)
        : without(board.archivedTasks),
  );
}

List<BoardTask> _without(List<BoardTask>? tasks, String id) => [
  for (final t in tasks ?? const <BoardTask>[])
    if (t.id != id) t,
];

List<BoardTask> _inPlace(List<BoardTask> tasks, BoardTask card) =>
    [...tasks, card]
      ..sort((a, b) => (a.position ?? double.maxFinite).compareTo(b.position ?? double.maxFinite));

/// [board] with [card], a task it didn't have yet, in the column of its status. A status with nowhere
/// to show leaves the board as it is, and so does a card already there, which is the newer of the two.
BoardData boardWithNewCard(BoardData board, BoardTask card) {
  if (boardTasks(board).any((t) => t.id == card.id)) return board;
  final status = card.status;
  final inColumn = board.columns.any((c) => c.slug == status);
  return board.copyWith(
    columns: [
      for (final column in board.columns)
        column.slug == status
            ? column.copyWith(tasks: _inPlace(column.tasks ?? const [], card))
            : column,
    ],
    plannedTasks: !inColumn && status == statusPlanned
        ? _inPlace(board.plannedTasks, card)
        : board.plannedTasks,
    archivedTasks: !inColumn && status == statusArchived
        ? _inPlace(board.archivedTasks, card)
        : board.archivedTasks,
  );
}

/// [board] without the card of the task [id], which has left the project or no longer exists.
BoardData boardWithoutCard(BoardData board, String id) => board.copyWith(
  columns: [for (final column in board.columns) column.copyWith(tasks: _without(column.tasks, id))],
  plannedTasks: _without(board.plannedTasks, id),
  archivedTasks: _without(board.archivedTasks, id),
);

/// Undoes a failed edit from [before] to [after], and leaves alone what has changed since.
Task revertTaskEdit(Task current, {required Task before, required Task after}) {
  T field<T>(T Function(Task task) read) =>
      read(before) == read(after) ? read(current) : read(before);
  return current.copyWith(
    title: field((t) => t.title),
    status: field((t) => t.status),
    priority: field((t) => t.priority),
    startDate: field((t) => t.startDate),
    dueDate: field((t) => t.dueDate),
    userId: field((t) => t.userId),
    assigneeId: field((t) => t.assigneeId),
    assigneeName: field((t) => t.assigneeName),
  );
}

/// The labels to offer on a task: one for each name, the workspace's own where there is one. Other
/// tasks' copies are left out, and so is anything on its way to being deleted.
List<Label> taskLabelOptions(List<Label> workspaceLabels, String taskId) {
  final deleting = {
    for (final label in workspaceLabels)
      if (label.deletionStartedAt != null) label.name,
  };
  final byName = <String, Label>{};
  for (final label in workspaceLabels) {
    if (deleting.contains(label.name)) continue;
    if (label.taskId != null && label.taskId != taskId) continue;
    final existing = byName[label.name];
    if (existing == null || (label.taskId == null && existing.taskId != null)) {
      byName[label.name] = label;
    }
  }
  return byName.values.toList();
}

/// What it takes to go from the labels on a task to a selection among the offered ones.
class LabelChanges {
  const LabelChanges({required this.attach, required this.detach});

  /// Ids of the labels to copy onto the task.
  final List<String> attach;

  /// Ids of the task's own copies to remove.
  final List<String> detach;

  bool get isEmpty => attach.isEmpty && detach.isEmpty;
}

/// The ids in [options] of the labels already on the task. Copies are matched by name.
Set<String> selectedLabelIds(List<Label> attached, List<Label> options) {
  final names = {for (final label in attached) label.name};
  return {
    for (final option in options)
      if (names.contains(option.name)) option.id,
  };
}

/// An id in [selected] that isn't among [options] is a label created while picking. A label on the
/// task that wasn't offered wasn't deselected, so it stays.
LabelChanges labelChanges({
  required List<Label> attached,
  required List<Label> options,
  required Set<String> selected,
}) {
  final current = selectedLabelIds(attached, options);
  final removed = {
    for (final option in options)
      if (current.contains(option.id) && !selected.contains(option.id)) option.name,
  };
  return LabelChanges(
    attach: [
      for (final id in selected)
        if (!current.contains(id)) id,
    ],
    detach: [
      for (final label in attached)
        if (removed.contains(label.name)) label.id,
    ],
  );
}

/// Saves changes to one task and keeps the board and the lists in step with them.
///
/// A change shows at once and is undone if the server refuses it. Requests go out one at a time,
/// because setting the start date sends the whole task and would undo a change still on its way.
class TaskEdits {
  TaskEdits._(this._ref, this.taskId);

  final Ref _ref;
  final String taskId;

  Future<void> _queue = Future.value();
  int _queued = 0;
  KeepAliveLink? _keepAlive;

  /// Whether a change is still on its way. Reading the task now could give the state before it.
  bool get saving => _queued > 0;

  /// [leaving] is for a page being taken down, when nothing on screen may rebuild yet.
  void setTitle(String title, {bool leaving = false}) {
    void edit() => _edit((t) => t.copyWith(title: title), (api) => api.updateTitle(taskId, title));
    leaving ? _enqueue(() async => edit()) : edit();
  }

  void setStatus(String status) => _edit(
    (t) => t.copyWith(status: status),
    (api) => api.updateStatus(taskId, status),
    refreshBoard: true,
  );

  void setPriority(String priority) =>
      _edit((t) => t.copyWith(priority: priority), (api) => api.updatePriority(taskId, priority));

  void setAssignee(WorkspaceMember? member) => _edit(
    (t) => t.copyWith(userId: member?.id, assigneeId: member?.id, assigneeName: member?.name),
    (api) => api.updateAssignee(taskId, member?.id),
  );

  void setDueDate(String? date) =>
      _edit((t) => t.copyWith(dueDate: date), (api) => api.updateDueDate(taskId, date));

  /// The start date has no route of its own: the whole task goes back, and any field left out is
  /// cleared. So this starts from what the server holds now, not from what is on screen.
  void setStartDate(String? date) => _edit((t) => t.copyWith(startDate: date), (api) async {
    final fresh = await api.task(taskId);
    await api.updateTask(
      taskId,
      UpdateTaskBody(
        title: fresh.title,
        startDate: date,
        dueDate: fresh.dueDate,
        priority: fresh.priority ?? priorities.first,
        status: fresh.status,
        projectId: fresh.projectId,
        position: (fresh.position ?? 0).floor(),
        userId: fresh.userId,
      ),
    );
  });

  /// Shows what the server holds afterwards, even if only some of the changes went through.
  void setLabels(LabelChanges changes) {
    if (!_ref.mounted) return;
    final api = _ref.read(kaneoApiProvider);
    _enqueue(() async {
      try {
        for (final id in changes.detach) {
          await api.detachLabel(id);
        }
        for (final id in changes.attach) {
          await api.attachLabel(id, taskId);
        }
      } catch (error) {
        _report(error);
      }
      if (!_ref.mounted) return;
      final labels = taskLabelsQuery(taskId);
      await _ref.read(labels.notifier).refresh();
      if (!_ref.mounted) return;
      _publishLabels(_ref.read(labels).value);
      final workspaceId = _ref.read(taskQuery(taskId)).value?.workspaceId;
      if (workspaceId == null) return;
      await _refreshIfOpen(assignedTasksQuery(workspaceId));
      if (_ref.mounted) await _refreshIfOpen(workspaceLabelsQuery(workspaceId));
    });
  }

  /// Ticks off [subtask] of this task, or undoes that. The list shows it at once and goes back if it
  /// can't be saved. Resolves once that is settled.
  Future<void> setSubtaskDone(RelatedTask subtask, bool done) async {
    if (!_ref.mounted) return;
    final workspaceId = _ref.read(taskQuery(taskId)).value?.workspaceId;
    _showSubtaskDone(subtask.id, done);
    // The subtask's own edits, because its changes have to go out one at a time as well.
    final saved = await _ref
        .read(taskEditsProvider(subtask.id))
        ._setDone(done, projectId: subtask.projectId, workspaceId: workspaceId);
    if (!saved) _showSubtaskDone(subtask.id, !done);
  }

  /// Adds a comment. Like editing and deleting one, this resolves to whether it was saved, and says
  /// why not otherwise. The task's activity has been read again by then, so it shows the result.
  Future<bool> addComment(String text) => _changeComment((api) => api.createComment(taskId, text));

  Future<bool> editComment(String activityId, String text) =>
      _changeComment((api) => api.updateComment(activityId, text));

  Future<bool> deleteComment(String activityId) =>
      _changeComment((api) => api.deleteComment(activityId));

  Future<bool> _changeComment(Future<void> Function(KaneoApi api) send) {
    if (!_ref.mounted) return Future.value(false);
    final saved = Completer<bool>();
    final api = _ref.read(kaneoApiProvider);
    _enqueue(() async {
      try {
        await send(api);
      } catch (error) {
        _report(error);
        saved.complete(false);
        return;
      }
      if (_ref.mounted) await _refreshIfOpen(taskActivitiesQuery(taskId));
      saved.complete(true);
    });
    return saved.future;
  }

  /// Moves this task to the project [projectId], which picks its number and perhaps a new column.
  /// Resolves to whether it moved, and says why not otherwise. The task shows the result by then.
  Future<bool> moveTo(String projectId) {
    if (!_ref.mounted) return Future.value(false);
    final moved = Completer<bool>();
    final api = _ref.read(kaneoApiProvider);
    _enqueue(() async {
      final before = _ref.read(taskQuery(taskId)).value;
      try {
        await api.moveTask(taskId, projectId);
      } catch (error) {
        _report(error);
        moved.complete(false);
        return;
      }
      if (_ref.mounted) await _refreshIfOpen(taskQuery(taskId));
      moved.complete(true);
      if (!_ref.mounted) return;
      _ref.read(savedTaskProvider.notifier).saved(taskId);
      if (before != null) _removeCard(before.projectId);
      await Future.wait([
        _refreshIfOpen(taskActivitiesQuery(taskId)),
        _refreshLists({?before?.projectId, projectId}, before?.workspaceId),
      ]);
    });
    return moved.future;
  }

  /// Makes a copy of this task. Resolves to the copy, or to null after saying why there is none.
  Future<Task?> duplicate() {
    if (!_ref.mounted) return Future.value();
    final copied = Completer<Task?>();
    final api = _ref.read(kaneoApiProvider);
    _enqueue(() async {
      final Task copy;
      try {
        copy = await api.duplicateTask(taskId);
      } catch (error) {
        _report(error);
        copied.complete(null);
        return;
      }
      copied.complete(copy);
      if (!_ref.mounted) return;
      // A copy of a subtask is a subtask too, so an open parent has to read its list again.
      _ref.read(savedTaskProvider.notifier).saved(taskId);
      final workspaceId = _ref.read(taskQuery(taskId)).value?.workspaceId;
      await _refreshLists({copy.projectId}, workspaceId);
    });
    return copied.future;
  }

  /// Deletes this task. Resolves to whether it is gone, and says why not otherwise.
  Future<bool> delete() {
    if (!_ref.mounted) return Future.value(false);
    final deleted = Completer<bool>();
    final api = _ref.read(kaneoApiProvider);
    _enqueue(() async {
      final task = _ref.read(taskQuery(taskId)).value;
      try {
        await api.deleteTask(taskId);
      } catch (error) {
        _report(error);
        deleted.complete(false);
        return;
      }
      deleted.complete(true);
      if (!_ref.mounted) return;
      // Closing the text box would otherwise try to save what is in it, and fail.
      _ref.read(descriptionAutosaveProvider(taskId)).discard();
      _ref.read(taskQuery(taskId).notifier).forget();
      _ref.read(savedTaskProvider.notifier).saved(taskId);
      if (task == null) return;
      _removeCard(task.projectId);
      await _refreshLists({task.projectId}, task.workspaceId);
    });
    return deleted.future;
  }

  void _removeCard(String projectId) {
    final board = boardQuery(projectId);
    if (!_ref.read(board.exists)) return;
    final data = _ref.read(board).value;
    if (data != null) _ref.read(board.notifier).setData(boardWithoutCard(data, taskId));
  }

  /// What shows the tasks of [projectIds], or counts them, once they have changed.
  Future<void> _refreshLists(Set<String> projectIds, String? workspaceId) async {
    if (!_ref.mounted) return;
    await Future.wait([
      for (final id in projectIds) ...[
        _refreshIfOpen(boardQuery(id)),
        _refreshIfOpen(projectRelationsQuery(id)),
      ],
      if (workspaceId != null) ...[
        _refreshIfOpen(assignedTasksQuery(workspaceId)),
        _refreshIfOpen(projectsQuery(workspaceId)),
      ],
    ]);
  }

  void _showSubtaskDone(String subtaskId, bool done) {
    if (!_ref.mounted) return;
    final query = taskRelationsQuery(taskId);
    if (!_ref.read(query.exists)) return;
    final relations = _ref.read(query).value;
    if (relations == null) return;
    _ref.read(query.notifier).setData(relationsWithDone(relations, subtaskId, done));
  }

  /// Moves this task to the column [done] calls for, read afresh because a project's columns change.
  /// Resolves to whether it was saved, and says why not otherwise.
  ///
  /// This task may not be loaded, as with a subtask ticked off from its parent, so it takes the
  /// project and the workspace from whoever asks.
  Future<bool> _setDone(bool done, {required String projectId, required String? workspaceId}) {
    final saved = Completer<bool>();
    final api = _ref.read(kaneoApiProvider);
    _enqueue(() async {
      final String? status;
      try {
        status = completionStatus(await api.columns(projectId), done: done);
        if (status != null) await api.updateStatus(taskId, status);
      } catch (error) {
        _report(error);
        saved.complete(false);
        return;
      }
      if (status == null) {
        if (_ref.mounted) {
          final message = _ref.read(i18nProvider).t('tasks:subtasks.noCompletionColumn');
          showGlobalToast(message, kind: ToastKind.error);
        }
        saved.complete(false);
        return;
      }
      saved.complete(true);
      if (!_ref.mounted) return;
      final task = _ref.read(taskQuery(taskId)).value;
      if (task != null) _publish(task.copyWith(status: status));
      _ref.read(savedTaskProvider.notifier).saved(taskId);
      await _refreshIfOpen(taskActivitiesQuery(taskId));
      if (!_ref.mounted) return;
      await _refreshIfOpen(boardQuery(projectId));
      if (workspaceId != null && _ref.mounted) {
        await _refreshIfOpen(assignedTasksQuery(workspaceId));
      }
    });
    return saved.future;
  }

  void _edit(
    Task Function(Task task) change,
    Future<void> Function(KaneoApi api) send, {
    bool refreshBoard = false,
  }) {
    if (!_ref.mounted) return;
    final query = taskQuery(taskId);
    final before = _ref.read(query).value;
    if (before == null) return;
    final after = change(before);
    _publish(after);
    final api = _ref.read(kaneoApiProvider);
    _enqueue(() async {
      try {
        await send(api);
      } catch (error) {
        if (!_ref.mounted) return;
        _publish(revertTaskEdit(_ref.read(query).value ?? after, before: before, after: after));
        _report(error);
        return;
      }
      if (!_ref.mounted) return;
      _ref.read(savedTaskProvider.notifier).saved(taskId);
      // The server records the change, and the task's activity on screen should say so.
      await _refreshIfOpen(taskActivitiesQuery(taskId));
      if (!_ref.mounted) return;
      // The board shows a parent's progress, which depends on the status of its children.
      if (refreshBoard) await _refreshIfOpen(boardQuery(after.projectId));
      final workspaceId = after.workspaceId;
      if (workspaceId != null && _ref.mounted) {
        await _refreshIfOpen(assignedTasksQuery(workspaceId));
      }
    });
  }

  void _publish(Task task) {
    _ref.read(taskQuery(taskId).notifier).setData(task);
    final board = boardQuery(task.projectId);
    if (!_ref.read(board.exists)) return;
    final data = _ref.read(board).value;
    if (data == null) return;
    _ref.read(board.notifier).setData(boardWithTask(data, task, assigneeImage: _imageOf(task)));
  }

  void _publishLabels(List<Label>? labels) {
    final projectId = _ref.read(taskQuery(taskId)).value?.projectId;
    if (labels == null || projectId == null) return;
    final board = boardQuery(projectId);
    if (!_ref.read(board.exists)) return;
    final data = _ref.read(board).value;
    if (data == null) return;
    _ref
        .read(board.notifier)
        .setData(
          updateBoardTask(
            data,
            taskId,
            (card) => card.copyWith(
              labels: [
                for (final label in labels)
                  TaskLabel(id: label.id, name: label.name, color: label.color),
              ],
            ),
          ),
        );
  }

  String? _imageOf(Task task) {
    final workspaceId = task.workspaceId;
    if (workspaceId == null || task.userId == null) return null;
    final members = membersQuery((workspaceId: workspaceId, projectId: task.projectId));
    if (!_ref.read(members.exists)) return null;
    return _ref.read(members).value?.where((m) => m.id == task.userId).firstOrNull?.image;
  }

  /// Something a page below is showing. Otherwise it refreshes by itself when it next opens.
  Future<void> _refreshIfOpen<T>(AsyncNotifierProvider<CachedQuery<T>, T> query) async {
    if (_ref.read(query.exists)) await _ref.read(query.notifier).refresh();
  }

  void _report(Object error) {
    if (!_ref.mounted) return;
    // The client has already said why, and is on its way to the login page.
    if (error is ApiError && error.status == 401) return;
    final message = error is ApiError
        ? error.message
        : _ref.read(i18nProvider).t('mobile:common.somethingWrong');
    showGlobalToast(message, kind: ToastKind.error);
  }

  void _enqueue(Future<void> Function() job) {
    if (!_ref.mounted) return;
    _queued++;
    _keepAlive ??= _ref.keepAlive();
    _queue = _queue.then((_) => job()).whenComplete(() {
      if (--_queued > 0) return;
      _keepAlive?.close();
      _keepAlive = null;
    });
  }
}

/// One per task. It lives while a task is on screen and until its last change has been saved, which
/// can be after the page has closed.
final taskEditsProvider = Provider.autoDispose.family<TaskEdits, String>((ref, taskId) {
  // A change made under one account must never be sent under the next. Anything else about a session
  // can change while a task is open, and has to leave this as it is.
  ref.watch(sessionProvider.select((s) => (s?.serverUrl, s?.userId)));
  // A failed save still has to correct the remembered task.
  ref.listen(taskQuery(taskId), (_, _) {});
  return TaskEdits._(ref, taskId);
});
