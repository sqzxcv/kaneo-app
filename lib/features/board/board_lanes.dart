import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';
import 'board_card.dart';
import 'board_icons.dart';
import 'board_data.dart';
import 'board_expansion.dart';
import 'board_hierarchy.dart';

/// A bounded speed at each edge; distance outside the viewport cannot cause a jump.
double boardEdgeScroll(double pointer, double extent) {
  const margin = 48.0;
  if (pointer < margin) return -12 * ((margin - pointer) / margin).clamp(0, 1);
  if (pointer > extent - margin) return 12 * ((pointer - extent + margin) / margin).clamp(0, 1);
  return 0;
}

class BoardLanes extends ConsumerStatefulWidget {
  const BoardLanes({
    super.key,
    required this.board,
    required this.onMove,
    this.busy = false,
    this.onMenu,
    this.emptyMessage,
    this.sourceBoard,
  });
  final BoardData board;
  final BoardData? sourceBoard;
  final String? emptyMessage;
  final bool busy;
  final void Function(BuildContext context, BoardTask task, Offset position)? onMenu;
  final void Function(String id, String status, int index) onMove;

  @override
  ConsumerState<BoardLanes> createState() => _BoardLanesState();
}

class _BoardLanesState extends ConsumerState<BoardLanes> {
  final _horizontal = ScrollController();
  final _viewport = GlobalKey();
  final _vertical = <String, ScrollController>{};
  final _laneKeys = <String, GlobalKey>{};
  Timer? _timer;
  Offset? _pointer;
  String? _dragging;

  void _start(String id) {
    setState(() => _dragging = id);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _scroll());
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    _pointer = null;
    if (mounted) setState(() => _dragging = null);
  }

  void _scroll() {
    final point = _pointer;
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (point == null || box == null) return;
    final local = box.globalToLocal(point);
    _advance(_horizontal, boardEdgeScroll(local.dx, box.size.width));
    for (final entry in _laneKeys.entries) {
      final lane = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (lane == null) continue;
      final position = lane.globalToLocal(point);
      if (position.dx >= 0 && position.dx <= lane.size.width) {
        _advance(_vertical[entry.key]!, boardEdgeScroll(position.dy, lane.size.height));
      }
    }
  }

  void _advance(ScrollController controller, double delta) {
    if (!controller.hasClients || delta == 0) return;
    final next = (controller.offset + delta).clamp(0.0, controller.position.maxScrollExtent);
    if (next != controller.offset) controller.jumpTo(next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _horizontal.dispose();
    for (final controller in _vertical.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _draggable(BoardTask task, double width, Widget child) => Listener(
    onPointerDown: (event) => _pointer = event.position,
    onPointerMove: (event) => _pointer = event.position,
    child: Draggable<String>(
      data: task.id,
      maxSimultaneousDrags: widget.busy ? 0 : 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedbackOffset: const Offset(12, 12),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        child: SizedBox(
          width: width - 16,
          child: BoardCard(task: task, projectSlug: widget.board.slug),
        ),
      ),
      onDragStarted: () => _start(task.id),
      onDragEnd: (_) => _end(),
      child: child,
    ),
  );

  Widget _card(HierarchyRow row, BoardColumn column, double width) {
    final task = row.task;
    final handle = _draggable(
      task,
      width,
      Padding(
        key: ValueKey('drag-handle-${task.id}'),
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: Icon(LucideIcons.gripVertical, size: 20, color: context.colors.chipIcon),
      ),
    );
    final card = Opacity(
      opacity: _dragging == task.id ? 0.35 : 1,
      child: BoardCard(
        key: ValueKey('board-card-${task.id}'),
        task: task,
        hierarchy: row,
        onToggle: () => ref.read(boardExpansionProvider(widget.board.id).notifier).toggle(task.id),
        projectSlug: widget.board.slug,
        isFinal: column.isFinal == true,
        dragHandle: handle,
        onMenu: widget.onMenu,
      ),
    );
    // Touch scrolling and the long-press menu remain available on the card body.
    return defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android
        ? card
        : _draggable(task, width, card);
  }

  @override
  Widget build(BuildContext context) {
    final query = projectRelationsQuery(widget.board.id);
    final relations = ref.watch(query);
    final expanded = ref.watch(boardExpansionProvider(widget.board.id));
    return AsyncBody(
      value: relations,
      onRetry: () => ref.read(query.notifier).refresh(),
      builder: (context, data) => _lanes(data, expanded),
    );
  }

  Widget _lanes(List<TaskRelation> relations, Set<String> expanded) {
    final width = context.isWide ? 300.0 : 280.0;
    return SizedBox(
      key: _viewport,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          key: const ValueKey('board-horizontal'),
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final column in widget.board.columns)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(width: width, child: _column(column, width, relations, expanded)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _column(
    BoardColumn column,
    double width,
    List<TaskRelation> relations,
    Set<String> expanded,
  ) {
    final tasks = column.tasks ?? const <BoardTask>[];
    final rows = buildBoardHierarchy(
      tasks: tasks,
      allTasks: boardTasks(widget.sourceBoard ?? widget.board),
      relations: relations,
      expanded: expanded,
    );
    final taskIndices = {for (final (index, task) in tasks.indexed) task.id: index};
    final controller = _vertical.putIfAbsent(column.id, ScrollController.new);
    final key = _laneKeys.putIfAbsent(column.id, GlobalKey.new);
    return DragTarget<String>(
      key: ValueKey('drop-column-${column.slug}'),
      onWillAcceptWithDetails: (_) => !widget.busy,
      onAcceptWithDetails: (details) => widget.onMove(details.data, column.slug, tasks.length),
      builder: (context, candidates, rejects) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.boardLane,
          borderRadius: BorderRadius.circular(KaneoRadius.lg),
          border: Border.all(
            color: candidates.isNotEmpty ? context.colors.ring : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Padding(
              key: ValueKey('column-header-${column.id}'),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
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
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('add-task-column-${column.slug}'),
                    tooltip: context.t('mobile:board.addTask'),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        openNewTask(context, projectId: widget.board.id, status: column.slug),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                key: key,
                child: ListView.builder(
                  key: PageStorageKey('column-tasks-${column.id}'),
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: rows.isEmpty ? 1 : rows.length,
                  itemBuilder: (context, index) => rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.emptyMessage ?? context.t('mobile:board.noTasksHere'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.colors.mutedForeground),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                key: ValueKey('add-task-empty-${column.slug}'),
                                icon: const Icon(LucideIcons.plus, size: 16),
                                label: Text(context.t('mobile:board.addTask')),
                                onPressed: () => openNewTask(
                                  context,
                                  projectId: widget.board.id,
                                  status: column.slug,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _CardTarget(
                          key: ValueKey('drop-card-${rows[index].task.id}'),
                          enabled: !widget.busy,
                          onDrop: (id, after) => widget.onMove(
                            id,
                            column.slug,
                            taskIndices[rows[index].task.id]! + (after ? 1 : 0),
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: 8,
                              left: rows[index].depth.clamp(0, 6) * 12.0,
                            ),
                            child: _card(
                              rows[index],
                              column,
                              width - rows[index].depth.clamp(0, 6) * 12.0,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTarget extends StatefulWidget {
  const _CardTarget({super.key, required this.enabled, required this.onDrop, required this.child});
  final bool enabled;
  final void Function(String id, bool after) onDrop;
  final Widget child;
  @override
  State<_CardTarget> createState() => _CardTargetState();
}

class _CardTargetState extends State<_CardTarget> {
  bool _after = false;
  bool _isAfter(Offset offset) {
    final box = context.findRenderObject()! as RenderBox;
    return box.globalToLocal(offset).dy > box.size.height / 2;
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (_) => widget.enabled,
    onMove: (details) {
      final after = _isAfter(details.offset);
      if (_after != after) setState(() => _after = after);
    },
    onAcceptWithDetails: (details) => widget.onDrop(details.data, _isAfter(details.offset)),
    builder: (context, candidates, rejects) => DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            width: 2,
            color: candidates.isNotEmpty && !_after ? context.colors.ring : Colors.transparent,
          ),
          bottom: BorderSide(
            width: 2,
            color: candidates.isNotEmpty && _after ? context.colors.ring : Colors.transparent,
          ),
        ),
      ),
      child: widget.child,
    ),
  );
}
