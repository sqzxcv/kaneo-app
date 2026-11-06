import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';
import 'board_lanes.dart';
import 'board_move.dart';
import 'board_orientation.dart';

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  bool _moving = false;
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  Future<void> _move(String id, String status, int index) async {
    if (_moving) return;
    final query = boardQuery(widget.projectId);
    final board = ref.read(query).value;
    if (board == null) return;
    final move = planBoardMove(board, id, status, index);
    if (move == null) return;
    final subscription = ProviderScope.containerOf(context, listen: false).listen(query, (_, _) {});
    final notifier = ref.read(query.notifier);
    final api = ref.read(kaneoApiProvider);
    setState(() => _moving = true);
    notifier.setData(move.after);
    final ok = await runAction(context, () async {
      await api.reorderTasks(widget.projectId, move.updates);
      return true;
    });
    if (ok != true) {
      notifier.setData(move.rollback(subscription.read().value ?? move.after));
    }
    subscription.close();
    if (mounted) setState(() => _moving = false);
  }

  Future<void> _refresh() async {
    if (_moving) return;
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
              onPressed: value.isLoading || _moving
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
              child: BoardLanes(board: board, busy: _moving, onMove: _move),
            ),
          ),
        ),
      ),
    );
  }
}
