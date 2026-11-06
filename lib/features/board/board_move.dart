import 'package:kaneo_app/core/core.dart';

class BoardMove {
  const BoardMove(this.before, this.after, this.updates);
  final BoardData before;
  final BoardData after;
  final List<PositionUpdate> updates;

  /// Undo only the positions/statuses changed by this request. Keep concurrent title/label edits.
  BoardData rollback(BoardData current) {
    final old = {
      for (final c in before.columns)
        for (final t in c.tasks ?? <BoardTask>[]) t.id: t,
    };
    final changed = {for (final u in updates) u.id: u};
    final tasks = <BoardTask>[];
    for (final column in current.columns) {
      for (final task in column.tasks ?? <BoardTask>[]) {
        final update = changed[task.id];
        final prior = old[task.id];
        tasks.add(
          update != null &&
                  prior != null &&
                  task.position == update.position &&
                  task.status == (update.status ?? prior.status)
              ? task.copyWith(status: prior.status, position: prior.position)
              : task,
        );
      }
    }
    return current.copyWith(
      columns: [
        for (final column in current.columns)
          column.copyWith(
            tasks: tasks.where((t) => t.status == column.slug).toList()
              ..sort((a, b) => (a.position ?? 0).compareTo(b.position ?? 0)),
          ),
      ],
    );
  }
}

/// Insert at [index] in the destination's original order. The API requires integer positions.
BoardMove? planBoardMove(BoardData board, String taskId, String status, int index) {
  final all = {
    for (final c in board.columns)
      for (final t in c.tasks ?? <BoardTask>[]) t.id: t,
  };
  final task = all[taskId];
  final destination = board.columns.where((c) => c.slug == status).firstOrNull;
  if (task == null || destination == null) return null;
  final tasks = [...?destination.tasks];
  var insertion = index.clamp(0, tasks.length);
  final fromIndex = tasks.indexWhere((t) => t.id == taskId);
  if (fromIndex >= 0) {
    tasks.removeAt(fromIndex);
    if (fromIndex < insertion) insertion--;
    if (fromIndex == insertion) return null;
  }
  tasks.insert(insertion, task.copyWith(status: status));
  final positioned = [for (final (i, task) in tasks.indexed) task.copyWith(position: i)];
  final updates = <PositionUpdate>[
    for (final task in positioned)
      if (all[task.id]?.position != task.position || all[task.id]?.status != task.status)
        PositionUpdate(
          id: task.id,
          position: task.position!,
          status: all[task.id]?.status != task.status ? task.status : null,
        ),
  ];
  return BoardMove(
    board,
    board.copyWith(
      columns: [
        for (final column in board.columns)
          if (column.slug == status)
            column.copyWith(tasks: positioned)
          else if (column.slug == task.status)
            column.copyWith(tasks: column.tasks?.where((t) => t.id != taskId).toList())
          else
            column,
      ],
    ),
    updates,
  );
}
