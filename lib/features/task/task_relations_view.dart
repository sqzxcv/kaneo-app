import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../board/board_icons.dart';
import 'new_task.dart';
import 'open_task.dart';
import 'task_edits.dart';
import 'task_relations.dart';
import 'task_title.dart';

/// Reads a related task's ticket id. The task doesn't say which project's slug goes with its number.
String Function(RelatedTask other) _tickets(WidgetRef ref, Task task) {
  final workspaceId = task.workspaceId;
  final projects = workspaceId == null ? null : ref.watch(projectsQuery(workspaceId)).value;
  return (other) =>
      ticketId(projects?.where((p) => p.id == other.projectId).firstOrNull?.slug, other.number);
}

/// A way up to the parent, above the title. Nothing while there is none, or none known yet.
class TaskParentLink extends ConsumerWidget {
  const TaskParentLink({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relations = ref.watch(taskRelationsQuery(task.id)).value;
    final parent = relations == null ? null : parentTaskOf(task.id, relations);
    if (parent == null) return const SizedBox.shrink();
    final colors = context.colors;
    final ticket = _tickets(ref, task)(parent);
    final style = TextStyle(fontSize: 12, color: colors.mutedForeground);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('task-parent'),
            borderRadius: BorderRadius.circular(KaneoRadius.sm),
            hoverColor: colors.accent,
            onTap: () => openTask(context, parent.id),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: context.isWide ? 3 : 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.arrowUpRight, size: 12, color: colors.mutedForeground),
                  const SizedBox(width: 6),
                  Text(context.t('tasks:detail.subtaskOf'), style: style),
                  if (ticket.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(ticket, style: style.copyWith(fontFamily: KaneoFonts.mono)),
                  ],
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      parent.title,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.foreground.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A task's subtasks and the tasks linked to it, below its description. Each opens from its row, and
/// comes back to this task when closed.
///
/// Links can only be looked at here. Changing them belongs to the task's extended fields.
class TaskRelationSections extends ConsumerWidget {
  const TaskRelationSections({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = taskRelationsQuery(task.id);
    final value = ref.watch(query);
    ref.listen(savedTaskProvider, (_, saved) {
      if (saved == null || saved.taskId == task.id) return;
      final relations = ref.read(query).value ?? const <TaskRelation>[];
      final shown = relations.any(
        (r) => r.sourceTaskId == saved.taskId || r.targetTaskId == saved.taskId,
      );
      if (shown) ref.read(query.notifier).refresh();
    });
    return AsyncBody(
      value: value,
      onRetry: () => ref.read(query.notifier).refresh(),
      builder: (context, relations) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Subtasks(task: task, subtasks: subtasksOf(task.id, relations)),
          const SizedBox(height: 20),
          _Links(task: task, links: linkedTasksOf(task.id, relations)),
        ],
      ),
    );
  }
}

class _Subtasks extends ConsumerStatefulWidget {
  const _Subtasks({required this.task, required this.subtasks});

  final Task task;
  final List<RelatedTask> subtasks;

  @override
  ConsumerState<_Subtasks> createState() => _SubtasksState();
}

class _SubtasksState extends ConsumerState<_Subtasks> {
  final _title = TextEditingController();
  bool _adding = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _close() => setState(() {
    _adding = false;
    _title.clear();
  });

  /// A failure leaves the box open with what was typed in it, to try again.
  Future<void> _submit() async {
    final title = singleLineTitle(_title.text);
    if (_busy || title.isEmpty) return;
    // Read before the gap: the task may be gone by the time this finishes.
    final i18n = I18nScope.of(context);
    final tasks = ref.read(newTasksProvider);
    setState(() => _busy = true);
    final linked = await runAction(
      context,
      () => tasks.createSubtask(parent: widget.task, title: title),
    );
    if (linked == false) {
      showGlobalToast(i18n.t('mobile:taskNew.parentFailed'), kind: ToastKind.error);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (linked != null) _close();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final subtasks = widget.subtasks;
    final workspaceId = task.workspaceId;
    // Permissions that haven't loaded count as allowed, because the server has the last word.
    final can = workspaceId == null ? null : ref.watch(capabilitiesQuery(workspaceId)).value;
    final canTick = can?.updateTasks != false;
    final canAdd = canTick && can?.createTasks != false;
    final edits = ref.watch(taskEditsProvider(task.id));
    final tickets = _tickets(ref, task);
    final done = subtasks.where((s) => s.isCompleted == true).length;
    final size = Size(0, context.isWide ? 32 : 40);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskSectionHeader(
          title: context.t('mobile:taskDetail.subtasks.title'),
          meta: subtasks.isEmpty ? null : _Progress(completed: done, total: subtasks.length),
          action: canAdd
              ? IconButton(
                  key: const ValueKey('task-add-subtask'),
                  tooltip: context.t('mobile:taskDetail.subtasks.add'),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tight(Size.square(context.isWide ? 28 : 40)),
                  icon: const Icon(LucideIcons.plus, size: 14),
                  onPressed: () => setState(() => _adding = true),
                )
              : null,
        ),
        for (final subtask in subtasks)
          _SubtaskRow(
            key: ValueKey('task-subtask-${subtask.id}'),
            subtask: subtask,
            ticket: tickets(subtask),
            onDone: canTick ? (done) => edits.setSubtaskDone(subtask, done) : null,
          ),
        if (_adding && canAdd)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('subtask-title'),
                    controller: _title,
                    autofocus: true,
                    readOnly: _busy,
                    style: const TextStyle(fontSize: 13),
                    // As in a task's title: a line break pasted in comes out when saving, as a
                    // space, and Enter still finishes it because the keyboard isn't multiline.
                    minLines: 1,
                    maxLines: null,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: context.t('tasks:subtasks.inputPlaceholder'),
                      // As tall as the buttons beside it.
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: context.isWide ? 7 : 11,
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: _title,
                  builder: (context, _) => FilledButton(
                    key: const ValueKey('subtask-create'),
                    style: FilledButton.styleFrom(minimumSize: size),
                    onPressed: _busy || singleLineTitle(_title.text).isEmpty ? null : _submit,
                    child: Text(context.t('tasks:subtasks.addAction')),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  key: const ValueKey('subtask-cancel'),
                  style: TextButton.styleFrom(minimumSize: size),
                  onPressed: _busy ? null : _close,
                  child: Text(context.t('mobile:common.cancel')),
                ),
              ],
            ),
          )
        else if (subtasks.isEmpty)
          TaskSectionNote(context.t('mobile:taskDetail.subtasks.empty')),
      ],
    );
  }
}

class _SubtaskRow extends StatefulWidget {
  const _SubtaskRow({super.key, required this.subtask, required this.ticket, required this.onDone});

  final RelatedTask subtask;
  final String ticket;
  final Future<void> Function(bool done)? onDone;

  @override
  State<_SubtaskRow> createState() => _SubtaskRowState();
}

class _SubtaskRowState extends State<_SubtaskRow> {
  bool _saving = false;

  /// Ignores another press until this one has settled. If this one fails, the row goes back to how it
  /// was before it, which would overwrite a press made in the meantime.
  Future<void> _tick(bool? done) async {
    if (_saving) return;
    _saving = true;
    try {
      await widget.onDone!(done == true);
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtask = widget.subtask;
    final done = subtask.isCompleted == true;
    final wide = context.isWide;
    return _TaskRow(
      task: subtask,
      ticket: widget.ticket,
      leading: Checkbox(
        key: ValueKey('task-subtask-check-${subtask.id}'),
        value: done,
        semanticLabel: context.t('tasks:subtasks.completeAria'),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: wide ? VisualDensity.compact : VisualDensity.standard,
        onChanged: widget.onDone == null ? null : _tick,
      ),
    );
  }
}

class _Links extends ConsumerWidget {
  const _Links({required this.task, required this.links});

  final Task task;
  final List<LinkedTask> links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = _tickets(ref, task);
    final slot = context.isWide ? 32.0 : 40.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskSectionHeader(title: context.t('mobile:taskDetail.relations.title')),
        for (final link in links)
          _TaskRow(
            key: ValueKey('task-link-${link.kind.name}-${link.task.id}'),
            task: link.task,
            ticket: tickets(link.task),
            tag: _LinkTag(link.kind),
            leading: SizedBox.square(
              dimension: slot,
              child: Icon(
                boardColumnIcon(
                  BoardColumn(
                    id: link.task.status,
                    slug: link.task.status,
                    name: link.task.status,
                    isFinal: link.task.isCompleted,
                  ),
                ),
                size: 14,
                color: context.colors.mutedForeground,
              ),
            ),
          ),
        if (links.isEmpty) TaskSectionNote(context.t('mobile:taskDetail.relations.empty')),
      ],
    );
  }
}

/// A line of its own for another task. Pressing it opens that task.
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    super.key,
    required this.task,
    required this.ticket,
    required this.leading,
    this.tag,
  });

  final RelatedTask task;
  final String ticket;
  final Widget leading;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final wide = context.isWide;
    final done = task.isCompleted == true;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(KaneoRadius.md),
        hoverColor: colors.accent,
        onTap: () => openTask(context, task.id),
        child: Padding(
          padding: const EdgeInsets.only(right: 8, top: 1, bottom: 1),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 2),
              if (wide && ticket.isNotEmpty) ...[
                SizedBox(
                  width: 52,
                  child: Text(
                    ticket,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: KaneoFonts.mono,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  task.title,
                  maxLines: wide ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: done ? colors.mutedForeground : colors.foreground,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: colors.mutedForeground,
                  ),
                ),
              ),
              if (tag != null) ...[const SizedBox(width: 8), tag!],
              if (task.assigneeName != null) ...[
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 9,
                  backgroundColor: colors.avatar,
                  foregroundColor: colors.avatarForeground,
                  child: Text(initials(task.assigneeName), style: const TextStyle(fontSize: 8)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkTag extends StatelessWidget {
  const _LinkTag(this.kind);

  final TaskLinkKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground, icon, label) = switch (kind) {
      TaskLinkKind.blockedBy => (
        colors.destructive.withValues(alpha: 0.08),
        colors.destructiveForeground,
        LucideIcons.ban,
        'mobile:taskDetail.relations.blockedBy',
      ),
      TaskLinkKind.blocks => (
        colors.warning.withValues(alpha: 0.1),
        colors.warningForeground,
        LucideIcons.octagonAlert,
        'mobile:taskDetail.relations.blocks',
      ),
      TaskLinkKind.related => (
        colors.accent,
        colors.mutedForeground,
        LucideIcons.link2,
        'mobile:taskDetail.relations.related',
      ),
    };
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 5),
          Text(
            context.t(label),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: foreground),
          ),
        ],
      ),
    );
  }
}

class TaskSectionHeader extends StatelessWidget {
  const TaskSectionHeader({super.key, required this.title, this.meta, this.action});

  final String title;
  final Widget? meta;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.colors.foreground,
            ),
          ),
          if (meta != null) ...[const SizedBox(width: 8), meta!],
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

class TaskSectionNote extends StatelessWidget {
  const TaskSectionNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, style: TextStyle(fontSize: 12, color: context.colors.mutedForeground)),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: context.t('tasks:subtasks.progress', {'completed': completed, 'total': total}),
      child: Row(
        key: const ValueKey('task-subtask-progress'),
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size.square(14),
            painter: _ProgressRing(
              fraction: completed / total,
              track: colors.border,
              color: completed == total ? colors.successForeground : colors.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$completed/$total',
            style: TextStyle(
              fontSize: 12,
              color: colors.mutedForeground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends CustomPainter {
  const _ProgressRing({required this.fraction, required this.track, required this.color});

  final double fraction;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final circle = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(circle, 0, 2 * math.pi, false, paint..color = track);
    if (fraction == 0) return;
    canvas.drawArc(
      circle,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      paint
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ProgressRing old) =>
      old.fraction != fraction || old.track != track || old.color != color;
}
