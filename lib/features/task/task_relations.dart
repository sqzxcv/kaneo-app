import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';

/// The relation type that makes the target a subtask of the source.
const String relationSubtask = 'subtask';

/// The relation type where the source holds up the target.
const String relationBlocks = 'blocks';

/// A task's relations in both directions, each with a summary of the task at either end.
final taskRelationsQuery = cachedQueryFamily<List<TaskRelation>, String>(
  (taskId) => QuerySpec(
    key: 'task-relations/$taskId',
    fetch: (ref) => ref.read(kaneoApiProvider).relations(taskId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) =>
        (j as List).map((e) => TaskRelation.fromJson((e as Map).cast<String, dynamic>())).toList(),
  ),
);

/// The task [taskId] is a subtask of. A task has at most one, as in the web app.
RelatedTask? parentTaskOf(String taskId, List<TaskRelation> relations) => relations
    .where((r) => r.relationType == relationSubtask && r.targetTaskId == taskId)
    .firstOrNull
    ?.sourceTask;

List<RelatedTask> subtasksOf(String taskId, List<TaskRelation> relations) => [
  for (final relation in relations)
    if (relation.relationType == relationSubtask && relation.sourceTaskId == taskId)
      ?relation.targetTask,
];

/// How another task is linked to the one on show, in the order the web app lists them.
enum TaskLinkKind { blockedBy, blocks, related }

typedef LinkedTask = ({TaskLinkKind kind, RelatedTask task});

/// The tasks linked to [taskId] other than as parent or subtask. Direction only matters for `blocks`.
List<LinkedTask> linkedTasksOf(String taskId, List<TaskRelation> relations) {
  final linked = <LinkedTask>[];
  for (final relation in relations) {
    if (relation.relationType == relationSubtask) continue;
    final outgoing = relation.sourceTaskId == taskId;
    final other = outgoing ? relation.targetTask : relation.sourceTask;
    if (other == null) continue;
    final kind = relation.relationType != relationBlocks
        ? TaskLinkKind.related
        : outgoing
        ? TaskLinkKind.blocks
        : TaskLinkKind.blockedBy;
    linked.add((kind: kind, task: other));
  }
  return [
    for (final kind in TaskLinkKind.values)
      for (final link in linked)
        if (link.kind == kind) link,
  ];
}

/// The status of the column a task moves to when ticked off, which is the project's first final
/// column, or when that is undone, which is its first other column. Null if it has no such column.
String? completionStatus(List<ProjectColumn> columns, {required bool done}) {
  final inOrder = [...columns]..sort((a, b) => (a.position ?? 0).compareTo(b.position ?? 0));
  return inOrder.where((c) => (c.isFinal == true) == done).firstOrNull?.slug;
}

/// [relations] with the summaries of [taskId] saying whether it is done.
List<TaskRelation> relationsWithDone(List<TaskRelation> relations, String taskId, bool done) {
  RelatedTask? updated(RelatedTask? task) => task == null || task.id != taskId
      ? task
      : RelatedTask(
          id: task.id,
          title: task.title,
          status: task.status,
          isCompleted: done,
          priority: task.priority,
          number: task.number,
          projectId: task.projectId,
          assigneeName: task.assigneeName,
        );
  return [
    for (final relation in relations)
      TaskRelation(
        id: relation.id,
        sourceTaskId: relation.sourceTaskId,
        targetTaskId: relation.targetTaskId,
        relationType: relation.relationType,
        createdAt: relation.createdAt,
        sourceTask: updated(relation.sourceTask),
        targetTask: updated(relation.targetTask),
      ),
  ];
}

/// A save of a task. [count] tells two saves of one task apart.
typedef SavedTask = ({String taskId, int count});

/// The task saved last, for the lists that show a summary of it beside another task. Those are on
/// other routes, often out of sight, and have to read it again.
class SavedTaskNotifier extends Notifier<SavedTask?> {
  @override
  SavedTask? build() => null;

  void saved(String taskId) => state = (taskId: taskId, count: (state?.count ?? 0) + 1);
}

final savedTaskProvider = NotifierProvider<SavedTaskNotifier, SavedTask?>(SavedTaskNotifier.new);
