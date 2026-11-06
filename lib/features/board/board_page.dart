import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';
import 'board_card.dart';
import 'board_orientation.dart';

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  final _horizontal = ScrollController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final query = boardQuery(widget.projectId);
    await ref.read(query.notifier).refresh();
    if (mounted && ref.read(query).hasError) {
      showToast(context, userMessage(context, ref.read(query).error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = boardQuery(widget.projectId);
    final value = ref.watch(query);
    return BoardOrientation(
      projectId: widget.projectId,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: context.isWide ? 56 : 48,
          leading: IconButton(
            tooltip: context.t('mobile:board.back'),
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  value.value?.name ?? context.t('mobile:board.board'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (value.hasValue) ...[
                const SizedBox(width: 8),
                Text(
                  context.t('app:board.columnCount', {'count': value.requireValue.columns.length}),
                  style: TextStyle(fontSize: 11, color: context.colors.mutedForeground),
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: context.t('mobile:board.refresh'),
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              onPressed: value.isLoading
                  ? null
                  : () {
                      if (_refreshKey.currentState != null) {
                        _refreshKey.currentState!.show();
                      } else {
                        _refresh();
                      }
                    },
            ),
            IconButton(
              tooltip: context.t('mobile:board.newTask'),
              icon: const Icon(LucideIcons.plus, size: 20),
              onPressed: () => openNewTask(context, projectId: widget.projectId),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AsyncBody(
            value: value,
            onRetry: _refresh,
            isEmpty: (board) => board.columns.isEmpty,
            empty: StatusMessage(title: context.t('mobile:board.noTasksHere')),
            builder: (context, board) => RefreshIndicator(
              key: _refreshKey,
              onRefresh: _refresh,
              notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
              child: Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  key: const ValueKey('board-horizontal'),
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final column in board.columns)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: context.isWide ? 300 : 280,
                            child: _BoardColumn(
                              key: ValueKey(column.id),
                              column: column,
                              board: board,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData boardColumnIcon(BoardColumn column) =>
    switch (column.icon?.toLowerCase().replaceAll('-', '')) {
      'circlecheck' || 'checkcircle' || 'checkcircle2' => LucideIcons.circleCheck,
      'circle' => LucideIcons.circle,
      'circledot' => LucideIcons.circleDot,
      'circledashed' => LucideIcons.circleDashed,
      'search' => LucideIcons.search,
      'circlepause' || 'pausecircle' => LucideIcons.circlePause,
      'clock' => LucideIcons.clock,
      'archive' => LucideIcons.archive,
      'inbox' => LucideIcons.inbox,
      'circleplay' || 'playcircle' => LucideIcons.circlePlay,
      'circlex' || 'xcircle' => LucideIcons.circleX,
      _ =>
        column.isFinal == true
            ? LucideIcons.circleCheck
            : switch (column.slug) {
                'in-progress' => LucideIcons.circleDot,
                'in-review' => LucideIcons.search,
                'planned' => LucideIcons.clock,
                _ => LucideIcons.circle,
              },
    };

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({super.key, required this.column, required this.board});
  final BoardColumn column;
  final BoardData board;

  @override
  Widget build(BuildContext context) {
    final tasks = column.tasks ?? const <BoardTask>[];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.boardLane,
        borderRadius: BorderRadius.circular(KaneoRadius.lg),
      ),
      child: Column(
        children: [
          Padding(
            key: ValueKey('column-header-${column.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(boardColumnIcon(column), size: 16, color: context.colors.chipIcon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    column.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.t('app:board.taskCount', {'count': tasks.length}),
                  style: TextStyle(fontSize: 11, color: context.colors.boardId),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: PageStorageKey('column-tasks-${column.id}'),
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: tasks.isEmpty ? 1 : tasks.length,
              itemBuilder: (context, index) => tasks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.t('mobile:board.noTasksHere'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.mutedForeground),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: BoardCard(
                        key: ValueKey('board-card-${tasks[index].id}'),
                        task: tasks[index],
                        projectSlug: board.slug,
                        isFinal: column.isFinal == true,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
