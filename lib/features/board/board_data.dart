import 'package:kaneo_app/core/core.dart';

Iterable<BoardTask> boardTasks(BoardData board) =>
    board.columns.expand((c) => c.tasks ?? <BoardTask>[]);

BoardData updateBoardTask(BoardData board, String id, BoardTask Function(BoardTask) update) =>
    board.copyWith(
      columns: [
        for (final column in board.columns)
          column.copyWith(
            tasks: [
              for (final task in column.tasks ?? <BoardTask>[]) task.id == id ? update(task) : task,
            ],
          ),
      ],
    );

List<ProjectColumn> boardProjectColumns(BoardData board) => [
  for (final c in board.columns)
    ProjectColumn(
      id: c.id,
      projectId: board.id,
      name: c.name,
      slug: c.slug,
      icon: c.icon,
      position: c.position,
      isFinal: c.isFinal,
    ),
];
