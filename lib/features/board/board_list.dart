import 'package:flutter/material.dart';
import 'package:kaneo_app/core/core.dart';

import 'board_list_row.dart';
import 'board_icons.dart';

/// The list shares the board query, status groups, filtering and card actions.
class BoardList extends StatefulWidget {
  const BoardList({super.key, required this.board, required this.emptyMessage, this.onMenu});
  final BoardData board;
  final String emptyMessage;
  final void Function(BuildContext context, BoardTask task, Offset position)? onMenu;

  @override
  State<BoardList> createState() => _BoardListState();
}

class _BoardListState extends State<BoardList> {
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = <({BoardColumn column, BoardTask? task, bool empty})>[
      for (final column in widget.board.columns) ...[
        (column: column, task: null, empty: false),
        if (column.tasks?.isEmpty ?? true) (column: column, task: null, empty: true),
        for (final task in column.tasks ?? <BoardTask>[])
          (column: column, task: task, empty: false),
      ],
    ];
    final wide = context.isWide;
    Widget list() => ListView.builder(
      key: PageStorageKey('board-list-${widget.board.id}'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.empty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.emptyMessage,
              style: TextStyle(color: context.colors.mutedForeground),
            ),
          );
        }
        final task = row.task;
        if (task == null) {
          return ListTile(
            key: ValueKey('list-group-${row.column.slug}'),
            dense: true,
            tileColor: context.colors.boardLane,
            leading: Icon(boardColumnIcon(row.column), size: 16),
            title: Text(row.column.name),
            trailing: Text(
              context.t('app:board.taskCount', {'count': row.column.tasks?.length ?? 0}),
            ),
          );
        }
        return BoardListRow(
          key: ValueKey('list-task-${task.id}'),
          task: task,
          projectSlug: widget.board.slug,
          wide: wide,
          isFinal: row.column.isFinal == true,
          onMenu: widget.onMenu,
        );
      },
    );
    if (!wide) return list();
    return LayoutBuilder(
      builder: (context, bounds) => Scrollbar(
        controller: _horizontal,
        notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: bounds.maxWidth < 800 ? 800 : bounds.maxWidth,
            height: bounds.maxHeight,
            child: list(),
          ),
        ),
      ),
    );
  }
}
