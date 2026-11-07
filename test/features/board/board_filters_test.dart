import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_filters.dart';
import 'package:kaneo_app/features/board/board_move.dart';

void main() {
  const task = BoardTask(
    id: 'a',
    title: 'Fix a Chinese 中文 title',
    number: 12,
    status: 'todo',
    projectId: 'p',
    assigneeId: 'u',
    priority: 'high',
    dueDate: '2020-01-01',
    labels: [TaskLabel(id: 'bug', name: 'Bug', color: 'red')],
  );
  test('text matches title case-insensitively, Chinese, #number and ticket id', () {
    for (final text in ['FIX', '中文', '#12', 'KAN-12', ' 12 ']) {
      expect(BoardFilters(text: text).matches(task), isTrue);
    }
    expect(const BoardFilters(text: '13').matches(task), isFalse);
    expect(const BoardFilters(text: 'null').matches(task.copyWith(number: null)), isFalse);
  });
  test('filters intersect across types and union within types', () {
    final filters = BoardFilters(
      text: 'fix',
      assignees: {'u', 'v'},
      priorities: {'low', 'high'},
      labels: {'bug', 'other'},
      overdue: true,
    );
    expect(filters.count, 8);
    expect(filters.matches(task, now: DateTime(2026)), isTrue);
    expect(filters.matches(task.copyWith(priority: 'urgent')), isFalse);
    expect(filters.matches(task.copyWith(labels: <TaskLabel>[])), isFalse);
    expect(filters.matches(task.copyWith(dueDate: null)), isFalse);
    expect(
      const BoardFilters(assignees: {unassignedBoardFilter})
          .matches(task.copyWith(assigneeId: null)),
      isTrue,
    );
    expect(
      const BoardFilters(priorities: {'no-priority'}).matches(task.copyWith(priority: null)),
      isTrue,
    );
    expect(const BoardFilters(text: '   ').active, isFalse);
  });
  test('collections expand without duplicating real statuses and collapse losslessly', () {
    final raw = BoardData(
      id: 'p',
      name: 'P',
      slug: 'p',
      workspaceId: 'w',
      columns: [
        BoardColumn(id: 'todo', slug: 'todo', name: 'To Do', tasks: [task]),
      ],
      plannedTasks: [task.copyWith(id: 'b', status: 'planned')],
      archivedTasks: [task.copyWith(id: 'c', status: 'archived')],
    );
    final expanded = expandBoardCollections(raw, plannedName: 'Planned', archivedName: 'Archived');
    expect(expanded.columns.length, 3);
    expect(collapseBoardCollections(expanded).toJson(), raw.toJson());
    expect(filterBoard(expanded, const BoardFilters()).columns.length, 1);
    expect(
      filterBoard(
        expanded,
        const BoardFilters(),
        showPlanned: true,
        showArchived: true,
      ).columns.length,
      3,
    );
    final move = planBoardMove(expanded, 'b', 'todo', 0)!;
    final saved = collapseBoardCollections(move.after);
    expect(saved.plannedTasks, isEmpty);
    expect(saved.columns.single.tasks!.first.id, 'b');
    expect(collapseBoardCollections(move.rollback(move.after)).toJson(), raw.toJson());
  });
  test('filtered drops preserve hidden tasks in the original ordering', () {
    final tasks = [for (var i = 0; i < 5; i++) task.copyWith(id: '$i', position: i)];
    final full = BoardColumn(id: 'todo', slug: 'todo', name: 'Todo', tasks: tasks);
    final visible = full.copyWith(tasks: [tasks[1], tasks[3]]);
    expect(unfilteredDropIndex(full, visible, 0), 1);
    expect(unfilteredDropIndex(full, visible, 1), 3);
    expect(unfilteredDropIndex(full, visible, 2), 4);
    expect(unfilteredDropIndex(full, full.copyWith(tasks: <BoardTask>[]), 0), 5);
  });
}
