import 'package:kaneo_app/core/core.dart';

class HierarchyRow {
  const HierarchyRow({
    required this.task,
    required this.depth,
    required this.childCount,
    required this.expanded,
    required this.parentTitles,
  });
  final BoardTask task;
  final int depth;
  final int childCount;
  final bool expanded;
  final List<String> parentTitles;
}

/// Projects a relation graph to a deterministic forest, with each visible task appearing once.
/// Only visible, same-status parents can hide a child. Multi-parent nodes use their first parent
/// in task order; every cycle is broken at its first task. This affects display, never relations.
List<HierarchyRow> buildBoardHierarchy({
  required List<BoardTask> tasks,
  required Iterable<BoardTask> allTasks,
  required List<TaskRelation> relations,
  required Set<String> expanded,
}) {
  final byId = {for (final task in tasks) task.id: task};
  final all = {for (final task in allTasks) task.id: task};
  final rank = {for (final (index, task) in tasks.indexed) task.id: index};
  final parentIds = <String, Set<String>>{};
  final relatedParents = <String, RelatedTask>{};
  for (final relation in relations) {
    if (relation.relationType != 'subtask' ||
        relation.sourceTaskId == relation.targetTaskId ||
        !byId.containsKey(relation.targetTaskId)) {
      continue;
    }
    parentIds.putIfAbsent(relation.targetTaskId, () => {}).add(relation.sourceTaskId);
    if (relation.sourceTask != null) relatedParents[relation.sourceTaskId] = relation.sourceTask!;
  }
  final parent = <String, String?>{};
  for (final task in tasks) {
    final eligible =
        (parentIds[task.id] ?? <String>{}).where((id) => byId[id]?.status == task.status).toList()
          ..sort((a, b) => rank[a]!.compareTo(rank[b]!));
    parent[task.id] = eligible.firstOrNull;
  }
  // Iterative cycle detection also handles imported chains much deeper than the call stack.
  final checked = <String>{};
  for (final task in tasks) {
    final path = <String>[];
    final offsets = <String, int>{};
    String? id = task.id;
    while (id != null && !checked.contains(id)) {
      final cycleStart = offsets[id];
      if (cycleStart != null) {
        final root = path.skip(cycleStart).reduce((a, b) => rank[a]! < rank[b]! ? a : b);
        parent[root] = null;
        break;
      }
      offsets[id] = path.length;
      path.add(id);
      id = parent[id];
    }
    checked.addAll(path);
  }
  final children = <String, List<String>>{};
  for (final task in tasks) {
    final parentId = parent[task.id];
    if (parentId != null) children.putIfAbsent(parentId, () => []).add(task.id);
  }
  final stack = <({String id, int depth})>[
    for (final task in tasks.reversed)
      if (parent[task.id] == null) (id: task.id, depth: 0),
  ];
  final rows = <HierarchyRow>[];
  while (stack.isNotEmpty) {
    final entry = stack.removeLast();
    final task = byId[entry.id]!;
    final childIds = children[entry.id] ?? <String>[];
    final isExpanded = childIds.isNotEmpty && expanded.contains(entry.id);
    final titles = <String>{};
    for (final id in parentIds[entry.id] ?? <String>{}) {
      final known = all[id];
      if (known?.status == task.status && byId.containsKey(id)) continue;
      final title = known?.title ?? relatedParents[id]?.title;
      if (title != null && title.isNotEmpty) titles.add(title);
    }
    rows.add(
      HierarchyRow(
        task: task,
        depth: entry.depth,
        childCount: childIds.length,
        expanded: isExpanded,
        parentTitles: titles.toList(),
      ),
    );
    if (isExpanded) {
      for (final child in childIds.reversed) {
        stack.add((id: child, depth: entry.depth + 1));
      }
    }
  }
  return rows;
}
