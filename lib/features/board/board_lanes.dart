import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';
import 'board_card.dart';
import 'board_icons.dart';
import 'board_data.dart';
import 'board_expansion.dart';
import 'board_hierarchy.dart';
import 'board_motion.dart';
import 'board_move.dart';

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
    this.canCreate = true,
    this.canMove = true,
    this.onMenu,
    this.emptyMessage,
    this.sourceBoard,
    this.onDragging,
  });
  final BoardData board;
  final BoardData? sourceBoard;
  final String? emptyMessage;

  /// Whether the member may create tasks. Without it the columns offer no new ones.
  final bool canCreate;

  /// Whether the member may change tasks. Without it the cards can't be picked up.
  final bool canMove;
  final void Function(BuildContext context, BoardTask task, Offset position)? onMenu;

  /// Moves a dropped card, and completes once the move has saved or failed. The index counts the
  /// destination's cards as they were before the move.
  final Future<void> Function(String id, String status, int index) onMove;

  /// A card was picked up, or let go of.
  final ValueChanged<bool>? onDragging;

  @override
  ConsumerState<BoardLanes> createState() => _BoardLanesState();
}

/// Where a carried card would land: the destination column, and the index among its cards as they
/// were before the move.
typedef _Spot = ({String slug, int index});

typedef _Move = ({String id, String slug, int index});

enum _Kind { card, preview, hidden }

typedef _Item = ({HierarchyRow row, _Kind kind});

class _BoardLanesState extends ConsumerState<BoardLanes> {
  final _horizontal = ScrollController();
  final _viewport = GlobalKey();
  final _vertical = <String, ScrollController>{};
  final _laneKeys = <String, GlobalKey>{};
  Timer? _timer;
  Offset? _pointer;

  /// The card being carried, and where it would land. The board shows it there already, as the
  /// web board does, and the other cards make room.
  String? _dragging;
  _Spot? _spot;

  /// Where the carried card was picked up, where on the card, and how big it is. It stays under the
  /// pointer just where it was taken hold of.
  Offset _liftedAt = Offset.zero;
  Offset _grip = Offset.zero;
  Size _size = Size.zero;

  /// Where the carried card lay: its column, its index there, and the stretch of the column's list
  /// it took up. Whenever the pointer comes back over that stretch, the card goes back there, as on
  /// the web, though other cards have since moved into it.
  ({String column, String slug, int index, double top, double bottom})? _home;

  /// Whether the carried card has gone further than a touch slop. Until then a finger let go of
  /// opens its menu instead, and the board does not scroll at its edges.
  bool _carried = false;

  /// Whether the pointer last to leave a card was lifted, rather than cancelled. It is set as the
  /// pointer leaves, just before the drag that pointer carried ends.
  bool _letGo = false;

  /// Moves dropped but not yet on [BoardLanes.board], shown meanwhile where they were dropped.
  final _pending = <_Move>[];

  /// The card settling into place after a drop, hidden in the board until it gets there.
  String? _landing;
  OverlayEntry? _landingEntry;

  /// The pointers that drag a card once they have moved a little. A finger or pen scrolls the board
  /// then, so it picks a card up with a long press instead.
  static const _mice = {PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
  static final _fingers = PointerDeviceKind.values.toSet().difference(_mice);

  void _start(String id) {
    widget.onDragging?.call(true);
    setState(() {
      _dragging = id;
      _spot = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _scroll());
  }

  void _end() {
    widget.onDragging?.call(false);
    _home = null;
    _timer?.cancel();
    _timer = null;
    _pointer = null;
    if (mounted) {
      setState(() {
        _dragging = null;
        _spot = null;
      });
    }
  }

  void _scroll() {
    final point = _pointer;
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (point == null || box == null || !_carried) return;
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
    _landingEntry?.remove();
    _horizontal.dispose();
    for (final controller in _vertical.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Sends the carried card back where it lay, if [pointer] is over that place.
  bool _backHome(Offset pointer) {
    final home = _home;
    final lane = _laneKeys[home?.column]?.currentContext?.findRenderObject() as RenderBox?;
    final scroll = _vertical[home?.column];
    if (home == null || lane == null || scroll == null || !scroll.hasClients) return false;
    final local = lane.globalToLocal(pointer);
    final along = local.dy + scroll.offset;
    if (local.dx < 0 || local.dx > lane.size.width || along < home.top || along > home.bottom) {
      return false;
    }
    _aim(home.slug, home.index);
    return true;
  }

  /// Shows the carried card landing at [spot].
  void _aim(String slug, int index) {
    final spot = (slug: slug, index: index);
    if (_dragging == null || _spot == spot) return;
    setState(() => _spot = spot);
  }

  /// The pointer carrying a card, from where its drag puts the card.
  Offset _pointerAt(DragTargetDetails<String> details) => details.offset + _grip;

  void _drop(String id, _Spot spot) {
    final move = (id: id, slug: spot.slug, index: spot.index);
    setState(() => _pending.add(move));
    widget.onMove(id, spot.slug, spot.index).whenComplete(() {
      if (mounted) setState(() => _pending.remove(move));
    });
  }

  /// The board's own drawing of [id]'s card, where it is now.
  Rect? _cardRect(String id) {
    final key = ValueKey('board-card-$id');
    RenderBox? found;
    void visit(Element element) {
      if (found != null) return;
      final box = element.renderObject;
      if (element.widget.key == key && box is RenderBox && box.attached && box.hasSize) {
        found = box;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    final box = found;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  /// Lets [card], let go of at [from], settle into its place on the board.
  void _land(String id, Rect from, Widget card) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    setState(() => _landing = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _landing != id) return;
      final to = _cardRect(id);
      if (to == null) {
        setState(() => _landing = null);
        return;
      }
      _landingEntry?.remove();
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => CardLanding(
          from: from,
          to: to,
          onDone: () {
            entry.remove();
            if (_landingEntry == entry) _landingEntry = null;
            if (mounted && _landing == id) setState(() => _landing = null);
          },
          child: card,
        ),
      );
      _landingEntry = entry;
      Overlay.of(context).insert(entry);
    });
  }

  /// Picks [task] up from [child] with a pointer of [devices]: once it has moved a little, or once
  /// held still for [delay]. When the drag ends, [onEnd] learns whether the card was carried away.
  Widget _draggable(
    HierarchyRow row,
    BoardColumn column,
    int? index,
    double width,
    Widget child, {
    required Set<PointerDeviceKind> devices,
    Duration? delay,
    ValueChanged<bool>? onEnd,
  }) {
    final task = row.task;
    // Drawn as on the board, so that it does not change as it is picked up.
    final card = SizedBox(
      width: width - 16,
      child: BoardCard(
        task: task,
        hierarchy: row,
        onToggle: () {},
        projectSlug: widget.board.slug,
        isFinal: column.isFinal == true,
      ),
    );
    return _CardDraggable(
      devices: devices,
      delay: delay,
      data: task.id,
      // One card at a time: a second finger on another card leaves it be.
      maxSimultaneousDrags: _dragging == null || _dragging == task.id ? 1 : 0,
      // The card stays under the pointer just where it was taken hold of.
      dragAnchorStrategy: (draggable, context, position) {
        final box = context.findRenderObject()! as RenderBox;
        _liftedAt = position;
        _grip = box.globalToLocal(position);
        _size = box.size;
        _carried = false;
        final top = RenderAbstractViewport.maybeOf(box)?.getOffsetToReveal(box, 0).offset;
        _home = top == null || index == null
            ? null
            : (
                column: column.id,
                slug: column.slug,
                index: index,
                top: top,
                bottom: top + box.size.height,
              );
        return _grip;
      },
      feedback: LiftedCard(child: card),
      onDragStarted: () => _start(task.id),
      onDragUpdate: (details) {
        _pointer = details.globalPosition;
        if ((details.globalPosition - _liftedAt).distance > kTouchSlop) _carried = true;
      },
      onDragEnd: (details) {
        final spot = _spot;
        final carried = _carried;
        final finger = delay != null;
        _end();
        if (_letGo && spot != null && (carried || !finger)) _drop(task.id, spot);
        _land(task.id, details.offset & _size, card);
        onEnd?.call(carried);
      },
      child: child,
    );
  }

  /// Lets a mouse drag [card] once it has moved a little, and a finger or pen after a long press,
  /// because moving at once they scroll the board. A long press let go of where it started opens
  /// the card's menu, as it does on a card that can't move.
  Widget _liftable(HierarchyRow row, BoardColumn column, int? index, double width, Widget card) =>
      Listener(
        onPointerUp: (_) => _letGo = true,
        onPointerCancel: (_) => _letGo = false,
        child: _draggable(
          row,
          column,
          index,
          width,
          devices: _mice,
          Builder(
            builder: (anchor) => _draggable(
              row,
              column,
              index,
              width,
              devices: _fingers,
              delay: kLongPressTimeout,
              onEnd: (carried) {
                if (_letGo && !carried) widget.onMenu?.call(anchor, row.task, _liftedAt);
              },
              card,
            ),
          ),
        ),
      );

  Widget _card(HierarchyRow row, BoardColumn column, int? index, double width) {
    final task = row.task;
    final card = Opacity(
      opacity: _landing == task.id
          ? 0
          : _dragging == task.id
          ? 0.6
          : 1,
      child: BoardCard(
        key: ValueKey('board-card-${task.id}'),
        task: task,
        hierarchy: row,
        onToggle: () => ref.read(boardExpansionProvider(widget.board.id).notifier).toggle(task.id),
        projectSlug: widget.board.slug,
        isFinal: column.isFinal == true,
        onMenu: widget.onMenu,
        lifts: widget.canMove,
      ),
    );
    return widget.canMove ? _liftable(row, column, index, width, card) : card;
  }

  /// Where the carried card would land, drawn faintly, as the web board draws it.
  Widget _placeholder(HierarchyRow row, BoardColumn column) => IgnorePointer(
    child: Opacity(
      opacity: 0.6,
      child: BoardCard(
        key: ValueKey('board-card-preview-${row.task.id}'),
        task: row.task,
        hierarchy: row,
        projectSlug: widget.board.slug,
        isFinal: column.isFinal == true,
      ),
    ),
  );

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
    var base = widget.board;
    for (final move in _pending) {
      base = planBoardMove(base, move.id, move.slug, move.index)?.after ?? base;
    }
    final dragging = _dragging;
    final spot = _spot;
    final preview = dragging == null || spot == null
        ? null
        : planBoardMove(base, dragging, spot.slug, spot.index);
    final shown = preview?.after ?? base;
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
              for (final (index, column) in shown.columns.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: width,
                    child: _column(
                      column,
                      base.columns[index],
                      width,
                      relations,
                      expanded,
                      moved: preview == null ? null : dragging,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _column(
    BoardColumn column,
    BoardColumn base,
    double width,
    List<TaskRelation> relations,
    Set<String> expanded, {
    String? moved,
  }) {
    final tasks = column.tasks ?? const <BoardTask>[];
    final baseTasks = base.tasks ?? const <BoardTask>[];
    final allTasks = boardTasks(widget.sourceBoard ?? widget.board);
    final baseIndex = {for (final (index, task) in baseTasks.indexed) task.id: index};
    final items = <_Item>[
      for (final row in buildBoardHierarchy(
        tasks: tasks,
        allTasks: allTasks,
        relations: relations,
        expanded: expanded,
      ))
        (row: row, kind: row.task.id == moved ? _Kind.preview : _Kind.card),
    ];
    // A card carried away from here stays built where it was, out of sight: its drag ends through
    // it.
    if (moved != null && baseIndex.containsKey(moved)) {
      final rows = buildBoardHierarchy(
        tasks: baseTasks,
        allTasks: allTasks,
        relations: relations,
        expanded: expanded,
      );
      final at = rows.indexWhere((row) => row.task.id == moved);
      if (at >= 0) items.insert(math.min(at, items.length), (row: rows[at], kind: _Kind.hidden));
    }
    final keys = [
      for (final item in items)
        item.kind == _Kind.preview
            ? 'drop-card-preview-${item.row.task.id}'
            : 'drop-card-${item.row.task.id}',
    ];
    final indexOf = {for (final (index, key) in keys.indexed) key: index};
    final controller = _vertical.putIfAbsent(column.id, ScrollController.new);
    final key = _laneKeys.putIfAbsent(column.id, GlobalKey.new);
    return DragTarget<String>(
      key: ValueKey('drop-column-${column.slug}'),
      // Off the cards: past the last one, the card goes last. In the header it stays where it was
      // shown, if that is this column.
      onMove: (details) {
        final pointer = _pointerAt(details);
        if (_backHome(pointer)) return;
        final lane = key.currentContext?.findRenderObject() as RenderBox?;
        final inHeader = lane != null && lane.globalToLocal(pointer).dy < 0;
        if (inHeader && _spot?.slug == column.slug) return;
        _aim(column.slug, baseTasks.length);
      },
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
                  if (widget.canCreate) ...[
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
                  ] else
                    // Keeps the header as tall, and the count as far from the edge, as the button.
                    const SizedBox(width: 8, height: 32),
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
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: items.isEmpty ? 1 : items.length,
                  // Cards keep their state as the carried card moves between them.
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indexOf[key.value] : null,
                  itemBuilder: (context, index) => items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.emptyMessage ?? context.t('mobile:board.noTasksHere'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.colors.mutedForeground),
                              ),
                              if (widget.canCreate) ...[
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
                            ],
                          ),
                        )
                      : _item(items[index], keys[index], column, baseIndex, width),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    _Item item,
    String key,
    BoardColumn column,
    Map<String, int> baseIndex,
    double width,
  ) {
    final row = item.row;
    final id = row.task.id;
    final indent = row.depth.clamp(0, 6) * 12.0;
    // The margins belong to the card's target, so that the pointer is always over one.
    Widget spaced(Widget card) =>
        Padding(padding: EdgeInsets.fromLTRB(8 + indent, 0, 8, 8), child: card);
    if (item.kind == _Kind.preview) {
      return _CardTarget(
        key: ValueKey(key),
        onHover: (box, details) => _backHome(_pointerAt(details)),
        child: SlideOnReflow(hitWhereLaidOut: true, child: spaced(_placeholder(row, column))),
      );
    }
    // A carried card shown elsewhere stays here out of sight. Its widgets stay the same as it hides,
    // so that the drag it carries goes on.
    final hidden = item.kind == _Kind.hidden;
    final at = baseIndex[id];
    return _KeepWhileDragging(
      key: ValueKey(key),
      keep: id == _dragging,
      child: Offstage(
        offstage: hidden,
        child: _CardTarget(
          onHover: id == _dragging || at == null
              ? null
              : (box, details) {
                  final pointer = _pointerAt(details);
                  if (_backHome(pointer)) return;
                  final after = box.globalToLocal(pointer).dy > box.size.height / 2;
                  _aim(column.slug, at + (after ? 1 : 0));
                },
          child: SlideOnReflow(
            hitWhereLaidOut: _dragging != null,
            child: spaced(_card(row, column, at, width - indent)),
          ),
        ),
      ),
    );
  }
}

/// Where a carried card is over another, to land before or after it.
class _CardTarget extends StatelessWidget {
  const _CardTarget({super.key, this.onHover, required this.child});

  /// Told where the carried card is over this one. Null for the carried card in its own place.
  final void Function(RenderBox box, DragTargetDetails<String> details)? onHover;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onMove: (details) => onHover?.call(context.findRenderObject()! as RenderBox, details),
    builder: (context, candidates, rejects) => child,
  );
}

/// Keeps a card built while it is carried, even when its list scrolls it away: the drag reports
/// its end only through the card it started from.
class _KeepWhileDragging extends StatefulWidget {
  const _KeepWhileDragging({super.key, required this.keep, required this.child});
  final bool keep;
  final Widget child;

  @override
  State<_KeepWhileDragging> createState() => _KeepWhileDraggingState();
}

class _KeepWhileDraggingState extends State<_KeepWhileDragging> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keep;

  @override
  void didUpdateWidget(_KeepWhileDragging oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keep != widget.keep) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// A card's [Draggable] that only pointers of [devices] pick up: once they have moved a little, or
/// once held still for [delay], with the click [LongPressDraggable] gives.
class _CardDraggable extends Draggable<String> {
  const _CardDraggable({
    required this.devices,
    this.delay,
    required super.data,
    required super.feedback,
    required super.child,
    super.maxSimultaneousDrags,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
  });

  final Set<PointerDeviceKind> devices;
  final Duration? delay;

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) {
    final delay = this.delay;
    if (delay == null) {
      return _DistanceMultiDragGestureRecognizer(supportedDevices: devices)..onStart = onStart;
    }
    return DelayedMultiDragGestureRecognizer(delay: delay, supportedDevices: devices)
      ..onStart = (position) {
        final drag = onStart(position);
        if (drag != null) HapticFeedback.selectionClick();
        return drag;
      };
  }
}

/// Starts a drag once the pointer has moved 8 pixels, as the web board's mouse does, so that a
/// click that wobbles a little still opens the card.
class _DistanceMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _DistanceMultiDragGestureRecognizer({super.supportedDevices}) : super(debugOwner: null);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _DistancePointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'distance multidrag';
}

class _DistancePointerState extends MultiDragPointerState {
  _DistancePointerState(super.initialPosition, super.kind, super.gestureSettings);

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > 8) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) => starter(initialPosition);
}
