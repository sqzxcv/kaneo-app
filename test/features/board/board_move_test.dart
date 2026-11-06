import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_move.dart';
import 'package:kaneo_app/features/board/board_lanes.dart';

BoardTask task(String id, String status, num position) =>
    BoardTask(id: id, title: id, status: status, position: position, projectId: 'p');
BoardData fixture() => BoardData(
  id: 'p',
  name: 'B',
  slug: 'b',
  workspaceId: 'w',
  archivedTasks: [],
  plannedTasks: [],
  columns: [
    BoardColumn(
      id: 'pool',
      slug: 'pool',
      name: '需求池',
      tasks: [task('a', 'pool', 0), task('b', 'pool', 1), task('c', 'pool', 2)],
    ),
    BoardColumn(id: 'plan', slug: 'plan', name: '已计划', tasks: [task('d', 'plan', 0)]),
    const BoardColumn(id: 'empty', slug: 'empty', name: 'Empty', tasks: []),
  ],
);
List<String> ids(BoardData data, int column) =>
    data.columns[column].tasks!.map((t) => t.id).toList();

void main() {
  test('moving to a custom or empty column updates status and integer position', () {
    final before = fixture();
    final move = planBoardMove(before, 'a', 'plan', 1)!;
    expect(ids(move.after, 0), ['b', 'c']);
    expect(ids(move.after, 1), ['d', 'a']);
    expect(move.updates.single.toJson(), {'id': 'a', 'position': 1, 'status': 'plan'});
    expect(ids(before, 0), ['a', 'b', 'c']);
    expect(ids(planBoardMove(before, 'a', 'empty', 0)!.after, 2), ['a']);
  });

  test('same-column ordering handles first, last, before and after', () {
    expect(ids(planBoardMove(fixture(), 'a', 'pool', 3)!.after, 0), ['b', 'c', 'a']);
    expect(ids(planBoardMove(fixture(), 'c', 'pool', 0)!.after, 0), ['c', 'a', 'b']);
    expect(ids(planBoardMove(fixture(), 'c', 'pool', 1)!.after, 0), ['a', 'c', 'b']);
    expect(planBoardMove(fixture(), 'a', 'pool', 1), isNull);
    expect(planBoardMove(fixture(), 'missing', 'pool', 0), isNull);
    expect(planBoardMove(fixture(), 'a', 'missing', 0), isNull);
  });

  test('rollback restores original order while preserving concurrent edits', () {
    final move = planBoardMove(fixture(), 'a', 'plan', 0)!;
    final edited = move.after.copyWith(
      columns: [
        for (final c in move.after.columns)
          c.copyWith(
            tasks: [
              for (final t in c.tasks!)
                t.id == 'a' ? t.copyWith(title: 'New title', priority: 'urgent') : t,
            ],
          ),
      ],
    );
    final reverted = move.rollback(edited);
    expect(ids(reverted, 0), ['a', 'b', 'c']);
    expect(ids(reverted, 1), ['d']);
    expect(reverted.columns.first.tasks!.first.title, 'New title');
    expect(reverted.columns.first.tasks!.first.priority, 'urgent');
  });

  test('edge scrolling is bounded and stops away from both edges', () {
    expect(boardEdgeScroll(100, 800), 0);
    expect(boardEdgeScroll(1, 800), lessThan(0));
    expect(boardEdgeScroll(799, 800), greaterThan(0));
    expect(boardEdgeScroll(-999, 800), -12);
    expect(boardEdgeScroll(9999, 800), 12);
  });
}
