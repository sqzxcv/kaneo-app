import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../shell/workspace_gate.dart';
import '../task/open_task.dart';
import 'my_tasks_groups.dart';

/// From this width a task fits the web app's single line. A wide window can have less than this
/// next to its sidebar.
const double _singleLineMinWidth = 520;

/// Labels only join that line when there is room for them.
const double _labelsMinWidth = 680;
const double _labelsWidth = 120;

/// What I have to do: the tasks assigned to me in the current workspace, grouped.
class MyTasksPage extends ConsumerStatefulWidget {
  const MyTasksPage({super.key});

  @override
  ConsumerState<MyTasksPage> createState() => _MyTasksPageState();
}

class _MyTasksPageState extends ConsumerState<MyTasksPage> {
  MyTasksGrouping _grouping = MyTasksGrouping.dueDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('mobile:myTasks.title')),
        actions: const [_AssignedCount()],
      ),
      body: ContentWidth(
        child: WorkspaceGate(
          builder: (context, workspace) {
            final query = assignedTasksQuery(workspace.id);
            return AsyncBody(
              value: ref.watch(query),
              onRetry: () => ref.read(query.notifier).refresh(),
              isEmpty: (assigned) => assigned.tasks.isEmpty,
              empty: StatusMessage(
                title: context.t('mobile:myTasks.empty.title'),
                message: context.t('mobile:myTasks.empty.message'),
              ),
              builder: (context, assigned) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GroupingButtons(
                    grouping: _grouping,
                    onChanged: (grouping) => setState(() => _grouping = grouping),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => ref.read(query.notifier).refresh(),
                      child: _TaskList(assigned: assigned, grouping: _grouping),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// How many tasks are assigned, once that is known.
class _AssignedCount extends ConsumerWidget {
  const _AssignedCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider).value;
    final assigned = workspace == null ? null : ref.watch(assignedTasksQuery(workspace.id)).value;
    if (assigned == null || assigned.tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 16),
      child: Center(
        child: Text(
          context.t('mobile:myTasks.assigned', {'count': assigned.tasks.length}),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _GroupingButtons extends StatelessWidget {
  const _GroupingButtons({required this.grouping, required this.onChanged});

  final MyTasksGrouping grouping;
  final ValueChanged<MyTasksGrouping> onChanged;

  @override
  Widget build(BuildContext context) {
    ButtonSegment<MyTasksGrouping> segment(MyTasksGrouping value, String labelKey) => ButtonSegment(
      value: value,
      label: Text(context.t(labelKey), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SegmentedButton<MyTasksGrouping>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            segment(MyTasksGrouping.dueDate, 'mobile:myTasks.by.due'),
            segment(MyTasksGrouping.project, 'mobile:myTasks.by.project'),
            segment(MyTasksGrouping.status, 'mobile:myTasks.by.status'),
          ],
          selected: {grouping},
          onSelectionChanged: (selected) => onChanged(selected.single),
        ),
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({required this.assigned, required this.grouping});

  final AssignedTasks assigned;
  final MyTasksGrouping grouping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = I18nScope.of(context);
    final now = ref.read(nowProvider)();
    final groups = groupMyTasks(
      assigned.tasks,
      grouping,
      now: now,
      statusName: (task) => taskStatusName(i18n, task.status, task.statusName),
    );
    final total = assigned.total;
    return ListView(
      children: [
        for (final group in groups) ...[
          _GroupHeader(group: group),
          for (final task in group.tasks)
            _TaskRow(
              key: ValueKey(task.id),
              task: task,
              now: now,
              showProject: grouping != MyTasksGrouping.project,
            ),
        ],
        if (total != null && total > assigned.tasks.length)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.t('mobile:myTasks.showing', {'shown': assigned.tasks.length, 'total': total}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final MyTasksGroup group;

  String _title(BuildContext context) => switch (group.bucket) {
    DueBucket.overdue => context.t('mobile:myTasks.due.overdue'),
    DueBucket.today => context.t('mobile:myTasks.due.today'),
    DueBucket.thisWeek => context.t('mobile:myTasks.due.thisWeek'),
    DueBucket.later => context.t('mobile:myTasks.due.later'),
    DueBucket.none => context.t('mobile:myTasks.due.none'),
    null => group.title ?? '',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.muted.faded(0.4),
        border: Border(bottom: BorderSide(color: c.border.faded(0.5))),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              _title(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium!.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: group.bucket == DueBucket.overdue ? c.destructiveForeground : c.foreground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${group.tasks.length}', style: text.bodySmall),
        ],
      ),
    );
  }
}

/// A task's column icon, by the icon the column chose or else by its status.
IconData _statusIcon(AssignedTask task) =>
    switch (task.statusIcon?.toLowerCase().replaceAll('-', '')) {
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
      _ => switch (task.status) {
        'in-progress' => LucideIcons.circleDot,
        'in-review' => LucideIcons.search,
        'done' => LucideIcons.circleCheck,
        statusPlanned => LucideIcons.circleDashed,
        statusArchived => LucideIcons.archive,
        _ => LucideIcons.circle,
      },
    };

/// The web app's single line when it fits, and otherwise the current app's title over its details.
class _TaskRow extends StatelessWidget {
  const _TaskRow({super.key, required this.task, required this.now, required this.showProject});

  final AssignedTask task;
  final DateTime now;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      button: true,
      child: InkWell(
        onTap: () => openTask(context, task.id, projectId: task.projectId),
        hoverColor: c.accent.faded(0.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border.faded(0.5))),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= _singleLineMinWidth
                ? _singleLine(context, showLabels: constraints.maxWidth >= _labelsMinWidth)
                : _stacked(context),
          ),
        ),
      ),
    );
  }

  Widget _status(BuildContext context) => Tooltip(
    message: taskStatusName(I18nScope.of(context), task.status, task.statusName),
    child: Icon(_statusIcon(task), size: 16, color: context.colors.mutedForeground),
  );

  Widget _due(BuildContext context) {
    final c = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!;
    final overdue = isOverdue(task.dueDate, now: now);
    final today = dueBucket(task.dueDate, now) == DueBucket.today;
    return Text(
      formatDueShort(I18nScope.of(context), task.dueDate, now: now),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(
        color: overdue
            ? c.destructiveForeground
            : today
            ? c.foreground
            : c.mutedForeground,
        fontWeight: overdue || today ? FontWeight.w500 : FontWeight.w400,
      ),
    );
  }

  String get _ticket => ticketId(task.projectSlug, task.number);

  Widget _singleLine(BuildContext context, {required bool showLabels}) {
    final text = Theme.of(context).textTheme;
    final labels = task.labels ?? const <TaskLabel>[];
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(width: 16, child: PriorityIcon(priority: task.priority ?? '')),
            const SizedBox(width: 10),
            _status(context),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Text(
                _ticket,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall!.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
            ),
            if (showLabels && labels.isNotEmpty) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: _labelsWidth,
                child: Row(
                  children: [
                    for (final label in labels.take(2)) Flexible(child: _Label(label: label)),
                  ],
                ),
              ),
            ],
            if (showProject) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 112,
                child: Text(
                  task.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ),
            ],
            const SizedBox(width: 10),
            SizedBox(
              width: 80,
              child: Align(alignment: AlignmentDirectional.centerEnd, child: _due(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stacked(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasPriority = task.priority != null && task.priority != 'no-priority';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: _status(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasPriority) PriorityIcon(priority: task.priority!),
                    if (_ticket.isNotEmpty) Text(_ticket, style: text.bodySmall),
                    if (showProject) Text(task.projectName, style: text.bodySmall),
                    for (final label in task.labels ?? const <TaskLabel>[]) _Label(label: label),
                    if (task.dueDate != null) _due(context),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.label});

  final TaskLabel label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: labelColor(label.color), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
