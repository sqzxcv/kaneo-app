import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:kaneo_app/core/core.dart';

import '../realtime/board_sync.dart';
import '../task/open_task.dart';
import 'board_lanes.dart';
import 'board_list.dart';
import 'board_data.dart';
import 'board_move.dart';
import 'board_orientation.dart';
import 'board_filters.dart';
import 'board_toolbar.dart';
import 'board_picker_data.dart';

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  BoardFilters _filters = const BoardFilters();
  bool _listView = false;
  bool _showPlanned = false;
  bool _showArchived = false;
  bool _moving = false;
  bool _menuOpen = false;
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  void didUpdateWidget(BoardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _filters = const BoardFilters();
      _showPlanned = false;
      _showArchived = false;
    }
  }

  BoardData _expanded(BoardData board) => expandBoardCollections(
    board,
    plannedName: context.t('mobile:board.planned'),
    archivedName: context.t('mobile:board.archived'),
  );

  BoardData _visible(BoardData board) => filterBoard(
    _expanded(board),
    _filters,
    showPlanned: _showPlanned,
    showArchived: _showArchived,
  );

  void _moveVisible(String id, String status, int index) {
    final board = ref.read(boardQuery(widget.projectId)).value;
    if (board == null) return;
    final full = _expanded(board).columns.firstWhere((c) => c.slug == status);
    final shown = _visible(board).columns.firstWhere((c) => c.slug == status);
    _move(id, status, unfilteredDropIndex(full, shown, index));
  }

  Future<void> _move(String id, String status, int index) async {
    if (_moving) return;
    final query = boardQuery(widget.projectId);
    final board = ref.read(query).value;
    if (board == null) return;
    final move = planBoardMove(_expanded(board), id, status, index);
    if (move == null) return;
    final subscription = ProviderScope.containerOf(context, listen: false).listen(query, (_, _) {});
    final notifier = ref.read(query.notifier);
    final api = ref.read(kaneoApiProvider);
    setState(() => _moving = true);
    notifier.setData(collapseBoardCollections(move.after));
    final ok = await runAction(context, () async {
      await api.reorderTasks(widget.projectId, move.updates);
      return true;
    });
    if (ok != true) {
      notifier.setData(
        collapseBoardCollections(
          move.rollback(expandBoardCollections(subscription.read().value ?? board)),
        ),
      );
    }
    subscription.close();
    if (mounted) setState(() => _moving = false);
  }

  Future<void> _editCard(
    String id,
    BoardTask Function(BoardTask task) update,
    BoardTask Function(BoardTask current, BoardTask before) undo,
    Future<Task> Function(KaneoApi api) save,
  ) async {
    if (_moving) return;
    final query = boardQuery(widget.projectId);
    final board = ref.read(query).value;
    final before = board == null ? null : boardTasks(board).where((t) => t.id == id).firstOrNull;
    if (board == null || before == null) return;
    final subscription = ProviderScope.containerOf(context, listen: false).listen(query, (_, _) {});
    final notifier = ref.read(query.notifier);
    final api = ref.read(kaneoApiProvider);
    setState(() => _moving = true);
    notifier.setData(updateBoardTask(board, id, update));
    final saved = await runAction(context, () => save(api));
    if (saved == null) {
      notifier.setData(
        updateBoardTask(subscription.read().value ?? board, id, (t) => undo(t, before)),
      );
    }
    subscription.close();
    if (mounted) setState(() => _moving = false);
  }

  Future<void> _menu(BuildContext anchor, BoardTask task, Offset position) async {
    if (_menuOpen) return;
    _menuOpen = true;
    try {
      final action = await showActionMenu(
        anchor,
        position: position,
        items: [
          MenuAction(
            value: 'status',
            label: context.t('mobile:board.moveTo'),
            icon: LucideIcons.arrowRight,
            enabled: !_moving,
          ),
          MenuAction(
            value: 'assignee',
            label: context.t('mobile:board.assignee'),
            icon: LucideIcons.user,
            enabled: !_moving,
          ),
          MenuAction(
            value: 'priority',
            label: context.t('mobile:board.priority'),
            icon: LucideIcons.signal,
            enabled: !_moving,
          ),
          MenuAction(
            value: 'top',
            label: context.t('mobile:board.sendToTopOfColumn'),
            icon: LucideIcons.arrowUpToLine,
            enabled: !_moving,
          ),
          MenuAction(
            value: 'bottom',
            label: context.t('mobile:board.sendToBottomOfColumn'),
            icon: LucideIcons.arrowDownToLine,
            enabled: !_moving,
          ),
          MenuAction(
            value: 'open',
            label: context.t('mobile:board.openTask'),
            icon: LucideIcons.squareArrowOutUpRight,
          ),
        ],
      );
      if (!mounted || !anchor.mounted || action == null) return;
      final raw = ref.read(boardQuery(widget.projectId)).value;
      if (raw == null) return;
      final board = _expanded(raw);
      final current = boardTasks(board).where((t) => t.id == task.id).firstOrNull;
      if (current == null) return;
      switch (action) {
        case 'open':
          openTask(anchor, current.id, projectId: current.projectId);
        case 'top':
          await _move(current.id, current.status, 0);
        case 'bottom':
          final column = board.columns.firstWhere((c) => c.slug == current.status);
          await _move(current.id, current.status, column.tasks?.length ?? 0);
        case 'status':
          final status = await pickStatus(
            anchor,
            columns: boardProjectColumns(board),
            current: current.status,
            position: position,
          );
          if (!mounted || status == null || status == current.status) return;
          final column = board.columns.firstWhere((c) => c.slug == status);
          await _move(current.id, status, column.tasks?.length ?? 0);
        case 'priority':
          final priority = await pickPriority(
            anchor,
            current: current.priority,
            position: position,
          );
          if (!mounted || priority == null || priority == current.priority) return;
          await _editCard(
            current.id,
            (t) => t.copyWith(priority: priority),
            (t, before) => t.copyWith(priority: before.priority),
            (api) => api.updatePriority(current.id, priority),
          );
        case 'assignee':
          final members = await runAction(
            context,
            () => boardPickerData(
              ProviderScope.containerOf(context, listen: false),
              membersQuery((workspaceId: board.workspaceId, projectId: board.id)),
            ),
          );
          if (!mounted || !anchor.mounted || members == null) return;
          final picked = await pickAssignee(
            anchor,
            members: members,
            current: current.assigneeId,
            position: position,
          );
          if (!mounted || picked == null || picked.value == current.assigneeId) return;
          final member = members.where((m) => m.id == picked.value).firstOrNull;
          await _editCard(
            current.id,
            (t) => t.copyWith(
              userId: picked.value,
              assigneeId: picked.value,
              assigneeName: member?.name,
              assigneeImage: member?.image,
            ),
            (t, before) => t.copyWith(
              userId: before.userId,
              assigneeId: before.assigneeId,
              assigneeName: before.assigneeName,
              assigneeImage: before.assigneeImage,
            ),
            (api) => api.updateAssignee(current.id, picked.value),
          );
      }
    } finally {
      _menuOpen = false;
    }
  }

  Future<void> _refresh() async {
    if (_moving) return;
    final query = boardQuery(widget.projectId);
    final relations = projectRelationsQuery(widget.projectId);
    await Future.wait([ref.read(query.notifier).refresh(), ref.read(relations.notifier).refresh()]);
    if (mounted && ref.read(query).hasError) {
      showToast(context, userMessage(context, ref.read(query).error));
    } else if (mounted && ref.read(relations).hasError) {
      showToast(context, userMessage(context, ref.read(relations).error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = boardQuery(widget.projectId);
    final value = ref.watch(query);
    ref.watch(boardSyncProvider(widget.projectId)).saving = () => _moving;
    return BoardOrientation(
      projectId: widget.projectId,
      enabled: !_listView,
      child: Scaffold(
        appBar: BoardToolbar(
          listView: _listView,
          onViewChanged: () => setState(() => _listView = !_listView),
          projectId: widget.projectId,
          board: value.value,
          filters: _filters,
          onFilters: (filters) => setState(() => _filters = filters),
          showPlanned: _showPlanned,
          showArchived: _showArchived,
          onCollections: (planned, archived) => setState(() {
            _showPlanned = planned;
            _showArchived = archived;
          }),
          busy: value.isLoading || _moving,
          wide: context.isWide,
          onRefresh: () {
            if (_refreshKey.currentState != null) {
              _refreshKey.currentState!.show();
            } else {
              _refresh();
            }
          },
        ),
        body: SafeArea(
          top: false,
          child: AsyncBody(
            value: value,
            onRetry: _refresh,
            isEmpty: (board) => board.columns.isEmpty,
            empty: StatusMessage(
              title: context.t('mobile:board.noTasksHere'),
              action: TextButton.icon(
                key: const ValueKey('board-empty-add-task'),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: Text(context.t('mobile:board.addTask')),
                onPressed: () => openNewTask(context, projectId: widget.projectId),
              ),
            ),
            builder: (context, board) => RefreshIndicator(
              key: _refreshKey,
              onRefresh: _refresh,
              notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
              child: _listView
                  ? BoardList(
                      sourceBoard: board,
                      board: _visible(board),
                      onMenu: _menu,
                      emptyMessage: context.t(
                        _filters.active
                            ? 'mobile:board.noTasksMatchTheFilters'
                            : 'mobile:board.noTasksHere',
                      ),
                    )
                  : BoardLanes(
                      sourceBoard: board,
                      key: ValueKey(widget.projectId),
                      board: _visible(board),
                      busy: _moving,
                      onMove: _moveVisible,
                      onMenu: _menu,
                      onDragging: (dragging) =>
                          ref.read(boardSyncProvider(widget.projectId)).dragging = dragging,
                      emptyMessage: _filters.active
                          ? context.t('mobile:board.noTasksMatchTheFilters')
                          : null,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
