import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';
import 'board_filters.dart';

class BoardToolbar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const BoardToolbar({
    super.key,
    required this.projectId,
    required this.board,
    required this.filters,
    required this.onFilters,
    required this.showPlanned,
    required this.showArchived,
    required this.onCollections,
    required this.onRefresh,
    required this.busy,
    required this.wide,
    required this.listView,
    required this.onViewChanged,
  });
  final bool listView;
  final VoidCallback onViewChanged;
  final String projectId;
  final BoardData? board;
  final BoardFilters filters;
  final ValueChanged<BoardFilters> onFilters;
  final bool showPlanned;
  final bool showArchived;
  final void Function(bool planned, bool archived) onCollections;
  final VoidCallback onRefresh;
  final bool busy;
  final bool wide;
  @override
  Size get preferredSize => Size.fromHeight(wide ? 56 : 48);
  @override
  ConsumerState<BoardToolbar> createState() => _BoardToolbarState();
}

class _BoardToolbarState extends ConsumerState<BoardToolbar> {
  final _text = TextEditingController();
  bool _search = false;
  bool _choosing = false;
  @override
  void didUpdateWidget(BoardToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.filters.text) _text.text = widget.filters.text;
    if (oldWidget.projectId != widget.projectId) _search = false;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _projects(BuildContext anchor) async {
    final board = widget.board;
    if (board == null || _choosing) return;
    _choosing = true;
    try {
      final projects = await runAction(
        context,
        () => ref.read(projectsQuery(board.workspaceId).future),
      );
      if (!mounted || !anchor.mounted || projects == null) return;
      final picked = await pickOption(
        anchor,
        title: context.t('mobile:board.switchProject'),
        selected: board.id,
        options: [
          for (final p in projects) PickerOption(value: p.id, label: p.name, subtitle: p.slug),
        ],
      );
      if (!mounted || picked == null || picked.value == board.id) return;
      context.go(AppRoutes.board(picked.value));
    } finally {
      _choosing = false;
    }
  }

  Future<void> _filters(BuildContext anchor) async {
    final board = widget.board;
    if (board == null || _choosing) return;
    _choosing = true;
    try {
      final action = await showActionMenu(
        anchor,
        items: [
          MenuAction(
            value: 'assignee',
            label: context.t('mobile:board.assignee'),
            icon: LucideIcons.user,
          ),
          MenuAction(value: 'me', label: context.t('mobile:board.me'), icon: LucideIcons.userCheck),
          MenuAction(
            value: 'priority',
            label: context.t('mobile:board.priority'),
            icon: LucideIcons.signal,
          ),
          MenuAction(
            value: 'labels',
            label: context.t('mobile:board.labels'),
            icon: LucideIcons.tags,
          ),
          MenuAction(
            value: 'overdue',
            label: context.t('mobile:board.overdueOnly'),
            icon: widget.filters.overdue ? LucideIcons.check : LucideIcons.calendar,
          ),
          MenuAction(
            value: 'planned',
            label: context.t(
              widget.showPlanned ? 'mobile:board.hidePlanned' : 'mobile:board.showPlanned',
            ),
            icon: LucideIcons.clock,
          ),
          MenuAction(
            value: 'archived',
            label: context.t(
              widget.showArchived ? 'mobile:board.hideArchived' : 'mobile:board.showArchived',
            ),
            icon: LucideIcons.archive,
          ),
        ],
      );
      if (!mounted || !anchor.mounted || action == null) return;
      switch (action) {
        case 'me':
          final me = ref.read(sessionProvider)?.userId;
          if (me != null) widget.onFilters(widget.filters.copyWith(assignees: {me}));
        case 'overdue':
          widget.onFilters(widget.filters.copyWith(overdue: !widget.filters.overdue));
        case 'planned':
          widget.onCollections(!widget.showPlanned, widget.showArchived);
        case 'archived':
          widget.onCollections(widget.showPlanned, !widget.showArchived);
        case 'assignee':
          final members = await runAction(
            context,
            () => ref.read(
              membersQuery((workspaceId: board.workspaceId, projectId: board.id)).future,
            ),
          );
          if (!mounted || !anchor.mounted || members == null) return;
          final selected = await pickMany(
            anchor,
            title: context.t('mobile:board.assignee'),
            selected: widget.filters.assignees,
            options: [
              PickerOption(
                value: unassignedBoardFilter,
                label: context.t('mobile:board.unassigned'),
              ),
              for (final member in members) PickerOption(value: member.id, label: member.name),
            ],
          );
          if (mounted && selected != null) {
            widget.onFilters(widget.filters.copyWith(assignees: selected));
          }
        case 'priority':
          final selected = await pickMany(
            anchor,
            title: context.t('mobile:board.priority'),
            selected: widget.filters.priorities,
            options: [
              for (final p in priorities) PickerOption(value: p, label: priorityLabel(context, p)),
            ],
          );
          if (mounted && selected != null) {
            widget.onFilters(widget.filters.copyWith(priorities: selected));
          }
        case 'labels':
          final labels = await runAction(
            context,
            () => ref.read(workspaceLabelsQuery(board.workspaceId).future),
          );
          if (!mounted || !anchor.mounted || labels == null) return;
          final selected = await pickLabels(
            anchor,
            labels: labels,
            selectedIds: widget.filters.labels,
          );
          if (mounted && selected != null) {
            widget.onFilters(widget.filters.copyWith(labels: selected));
          }
      }
    } finally {
      _choosing = false;
    }
  }

  Widget _searchField() => TextField(
    key: const ValueKey('board-search'),
    controller: _text,
    decoration: InputDecoration(
      isDense: true,
      hintText: context.t('mobile:board.filterTasks'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    onChanged: (text) => widget.onFilters(widget.filters.copyWith(text: text)),
  );

  Widget _button({
    Key? key,
    required String tooltip,
    required IconData icon,
    VoidCallback? onPressed,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    icon: Icon(icon, size: 18),
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 40, height: 44),
    padding: EdgeInsets.zero,
  );

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: widget.wide ? 56 : 48,
    leadingWidth: 40,
    leading: _button(
      tooltip: context.t('mobile:board.back'),
      icon: LucideIcons.arrowLeft,
      onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
    ),
    titleSpacing: 0,
    title: _search && !widget.wide
        ? _searchField()
        : Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (anchor) => TextButton(
                    onPressed: widget.board == null ? null : () => _projects(anchor),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.board?.name ?? context.t('mobile:board.board'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(LucideIcons.chevronDown, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.wide && widget.board != null && !widget.filters.active)
                Text(
                  context.t('app:board.columnCount', {'count': widget.board!.columns.length}),
                  style: TextStyle(fontSize: 11, color: context.colors.mutedForeground),
                ),
              if (widget.wide) ...[
                const SizedBox(width: 16),
                SizedBox(width: 210, child: _searchField()),
              ],
            ],
          ),
    actions: [
      _button(
        tooltip: context.t(widget.listView ? 'mobile:board.boardView' : 'mobile:board.listView'),
        icon: widget.listView ? LucideIcons.columns3 : LucideIcons.list,
        onPressed: widget.onViewChanged,
      ),
      if (!widget.wide)
        _button(
          key: const ValueKey('board-search-toggle'),
          tooltip: context.t('mobile:board.filterTasks'),
          icon: _search ? LucideIcons.chevronLeft : LucideIcons.search,
          onPressed: () => setState(() => _search = !_search),
        ),
      Builder(
        builder: (anchor) => _button(
          tooltip: widget.filters.active
              ? context.t('mobile:board.filterTasksActive', {'count': widget.filters.count})
              : context.t('mobile:board.filters'),
          icon: LucideIcons.listFilter,
          onPressed: widget.board == null ? null : () => _filters(anchor),
        ),
      ),
      if (widget.filters.active) ...[
        Text(
          '${widget.filters.count}',
          key: const ValueKey('filter-count'),
          style: const TextStyle(fontSize: 11),
        ),
        _button(
          tooltip: context.t('mobile:board.reset'),
          icon: LucideIcons.x,
          onPressed: () => widget.onFilters(const BoardFilters()),
        ),
      ],
      _button(
        tooltip: context.t('mobile:board.refresh'),
        icon: LucideIcons.refreshCw,
        onPressed: widget.busy ? null : widget.onRefresh,
      ),
      _button(
        tooltip: context.t('mobile:board.newTask'),
        icon: LucideIcons.plus,
        onPressed: () => openNewTask(context, projectId: widget.projectId),
      ),
    ],
  );
}
