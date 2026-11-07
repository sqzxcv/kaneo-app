import 'package:kaneo_app/core/core.dart';

const unassignedBoardFilter = '__unassigned__';

class BoardFilters {
  const BoardFilters({
    this.text = '',
    this.assignees = const {},
    this.priorities = const {},
    this.labels = const {},
    this.overdue = false,
  });
  final String text;
  final Set<String> assignees;
  final Set<String> priorities;
  final Set<String> labels;
  final bool overdue;
  int get count =>
      (text.trim().isEmpty ? 0 : 1) +
      assignees.length +
      priorities.length +
      labels.length +
      (overdue ? 1 : 0);
  bool get active => count > 0;

  BoardFilters copyWith({
    String? text,
    Set<String>? assignees,
    Set<String>? priorities,
    Set<String>? labels,
    bool? overdue,
  }) => BoardFilters(
    text: text ?? this.text,
    assignees: assignees ?? this.assignees,
    priorities: priorities ?? this.priorities,
    labels: labels ?? this.labels,
    overdue: overdue ?? this.overdue,
  );

  bool matches(BoardTask task, {DateTime? now}) {
    final query = text.trim().toLowerCase();
    final number = query.replaceFirst(RegExp(r'^(#|[a-z]+-)'), '');
    if (query.isNotEmpty &&
        !task.title.toLowerCase().contains(query) &&
        (task.number == null || '${task.number}' != number)) {
      return false;
    }
    if (assignees.isNotEmpty &&
        !assignees.contains(task.assigneeId ?? task.userId ?? unassignedBoardFilter)) {
      return false;
    }
    if (priorities.isNotEmpty && !priorities.contains(task.priority ?? 'no-priority')) return false;
    if (labels.isNotEmpty && !(task.labels ?? <TaskLabel>[]).any((l) => labels.contains(l.id))) {
      return false;
    }
    return !overdue || isOverdue(task.dueDate, now: now);
  }
}

/// Virtual collections stay separate in the cache; this expanded form is only for board UI/moves.
BoardData expandBoardCollections(
  BoardData board, {
  String plannedName = '',
  String archivedName = '',
}) => board.copyWith(
  columns: [
    if (!board.columns.any((c) => c.slug == statusPlanned))
      BoardColumn(
        id: '__planned',
        slug: statusPlanned,
        name: plannedName,
        icon: 'Clock',
        tasks: board.plannedTasks,
      ),
    ...board.columns,
    if (!board.columns.any((c) => c.slug == statusArchived))
      BoardColumn(
        id: '__archived',
        slug: statusArchived,
        name: archivedName,
        icon: 'Archive',
        isFinal: true,
        tasks: board.archivedTasks,
      ),
  ],
);

BoardData collapseBoardCollections(BoardData board) => board.copyWith(
  columns: board.columns.where((c) => c.id != '__planned' && c.id != '__archived').toList(),
  plannedTasks:
      board.columns.where((c) => c.id == '__planned').firstOrNull?.tasks ?? board.plannedTasks,
  archivedTasks:
      board.columns.where((c) => c.id == '__archived').firstOrNull?.tasks ?? board.archivedTasks,
);

BoardData filterBoard(
  BoardData expanded,
  BoardFilters filters, {
  bool showPlanned = false,
  bool showArchived = false,
}) => expanded.copyWith(
  columns: [
    for (final column in expanded.columns)
      if ((showPlanned || column.id != '__planned') && (showArchived || column.id != '__archived'))
        column.copyWith(tasks: column.tasks?.where(filters.matches).toList()),
  ],
);

/// Drop indices refer to the visible cards. Preserve hidden cards around the visible insertion.
int unfilteredDropIndex(BoardColumn full, BoardColumn visible, int index) {
  final tasks = full.tasks ?? <BoardTask>[];
  final shown = visible.tasks ?? <BoardTask>[];
  if (shown.isEmpty) return tasks.length;
  if (index >= shown.length) return tasks.indexWhere((t) => t.id == shown.last.id) + 1;
  return tasks.indexWhere((t) => t.id == shown[index.clamp(0, shown.length - 1)].id);
}
