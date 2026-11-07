import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../core/core.dart';
import '../board/board_data.dart';

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

  List<BoardTask> without(List<BoardTask>? tasks) => [
    for (final t in tasks ?? const <BoardTask>[])
      if (t.id != task.id) t,
  ];
  // A change of status keeps the task's position, so this is where the server will have it too.
  List<BoardTask> into(List<BoardTask>? tasks) => [...without(tasks), updated]
    ..sort((a, b) => (a.position ?? double.maxFinite).compareTo(b.position ?? double.maxFinite));

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
