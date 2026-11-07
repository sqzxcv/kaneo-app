import 'package:flutter/material.dart';
import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';
import 'board_icons.dart';

/// Shares the board's data and filters; KAN-31 adds the full editable list fields.
class BoardList extends StatelessWidget {
  const BoardList({super.key, required this.board, required this.emptyMessage, this.onMenu});
  final BoardData board;
  final String emptyMessage;
  final void Function(BuildContext context, BoardTask task, Offset position)? onMenu;

  @override
  Widget build(BuildContext context) {
    final rows = <({BoardColumn column, BoardTask? task, bool empty})>[
      for (final column in board.columns) ...[
        (column: column, task: null, empty: false),
        if (column.tasks?.isEmpty ?? true) (column: column, task: null, empty: true),
        for (final task in column.tasks ?? <BoardTask>[])
          (column: column, task: task, empty: false),
      ],
    ];
    return ListView.builder(
      key: PageStorageKey('board-list-${board.id}'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.empty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(emptyMessage, style: TextStyle(color: context.colors.mutedForeground)),
          );
        }
        final task = row.task;
        if (task == null) {
          return ListTile(
            dense: true,
            tileColor: context.colors.boardLane,
            leading: Icon(boardColumnIcon(row.column), size: 16),
            title: Text(row.column.name),
            trailing: Text(
              context.t('app:board.taskCount', {'count': row.column.tasks?.length ?? 0}),
            ),
          );
        }
        return GestureDetector(
          key: ValueKey('list-task-${task.id}'),
          onSecondaryTapDown: (details) => onMenu?.call(context, task, details.globalPosition),
          onLongPressStart: (details) => onMenu?.call(context, task, details.globalPosition),
          child: ListTile(
            title: Text(task.title),
            subtitle: Text(ticketId(board.slug, task.number)),
            onTap: () => openTask(context, task.id, projectId: task.projectId),
          ),
        );
      },
    );
  }
}
