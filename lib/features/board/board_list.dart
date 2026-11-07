import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kaneo_app/core/core.dart';

import 'board_list_row.dart';
import 'board_icons.dart';
import 'board_data.dart';
import 'board_hierarchy.dart';
import 'board_expansion.dart';

/// The list shares the board query, status groups, filtering and card actions.
class BoardList extends ConsumerStatefulWidget {
  const BoardList({
    super.key,
    required this.board,
    required this.emptyMessage,
    this.onMenu,
    this.sourceBoard,
  });
  final BoardData board;
  final BoardData? sourceBoard;
  final String emptyMessage;
  final void Function(BuildContext context, BoardTask task, Offset position)? onMenu;

  @override
  ConsumerState<BoardList> createState() => _BoardListState();
}

class _BoardListState extends ConsumerState<BoardList> {
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = projectRelationsQuery(widget.board.id);
    final relations = ref.watch(query);
    final expanded = ref.watch(boardExpansionProvider(widget.board.id));
    return AsyncBody(
      value: relations,
      onRetry: () => ref.read(query.notifier).refresh(),
      builder: (context, data) => _list(context, data, expanded),
    );
  }

  Widget _list(BuildContext context, List<TaskRelation> relations, Set<String> expanded) {
    final all = boardTasks(widget.sourceBoard ?? widget.board);
    final rows = <({BoardColumn column, HierarchyRow? hierarchy, bool empty})>[
      for (final column in widget.board.columns) ...[
        (column: column, hierarchy: null, empty: false),
        if (column.tasks?.isEmpty ?? true) (column: column, hierarchy: null, empty: true),
        for (final row in buildBoardHierarchy(
          tasks: column.tasks ?? <BoardTask>[],
          allTasks: all,
          relations: relations,
          expanded: expanded,
        ))
          (column: column, hierarchy: row, empty: false),
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
        final task = row.hierarchy?.task;
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
          hierarchy: row.hierarchy,
          onToggle: () =>
              ref.read(boardExpansionProvider(widget.board.id).notifier).toggle(task.id),
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
