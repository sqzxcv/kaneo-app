import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';

class BoardCard extends StatelessWidget {
  const BoardCard({
    super.key,
    required this.task,
    required this.projectSlug,
    this.isFinal = false,
    this.dragHandle,
    this.onMenu,
  });

  final BoardTask task;
  final String projectSlug;
  final bool isFinal;
  final Widget? dragHandle;
  final void Function(BuildContext context, BoardTask task, Offset position)? onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = task.subtaskCounts;
    final due = formatDueShort(I18nScope.of(context), task.dueDate);
    final priorityColor = switch (task.priority) {
      'urgent' => colors.priorityUrgent,
      'high' => colors.priorityHigh,
      'medium' => colors.priorityMedium,
      'low' => colors.priorityLow,
      _ => colors.chipMuted,
    };
    return GestureDetector(
      onSecondaryTapDown: onMenu == null
          ? null
          : (details) => onMenu!(context, task, details.globalPosition),
      onLongPressStart: onMenu == null
          ? null
          : (details) => onMenu!(context, task, details.globalPosition),
      child: Material(
        color: isFinal ? colors.boardCardDone : colors.boardCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KaneoRadius.lg),
          side: BorderSide(color: isFinal ? colors.boardCardDoneBorder : colors.boardCardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openTask(context, task.id, projectId: task.projectId),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ?dragHandle,
                    Expanded(
                      child: Text(
                        ticketId(projectSlug, task.number),
                        style: TextStyle(
                          fontFamily: KaneoFonts.mono,
                          fontSize: 11,
                          color: colors.boardId,
                        ),
                      ),
                    ),
                    if (task.assigneeId != null || task.assigneeName != null)
                      Tooltip(
                        message: task.assigneeName ?? context.t('mobile:board.assignee'),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: colors.avatar,
                          foregroundColor: colors.avatarForeground,
                          child: Text(
                            initials(task.assigneeName),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  task.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isFinal ? colors.boardTitleDone : colors.boardTitle,
                  ),
                ),
                if ((task.priority != null && task.priority != 'no-priority') ||
                    due.isNotEmpty ||
                    (task.labels?.isNotEmpty ?? false) ||
                    (count?.total ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (task.priority != null && task.priority != 'no-priority')
                        _Chip(
                          icon: LucideIcons.signal,
                          text: priorityLabel(context, task.priority),
                          color: priorityColor,
                        ),
                      if (due.isNotEmpty)
                        _Chip(
                          icon: LucideIcons.calendar,
                          text: due,
                          color: !isFinal && isOverdue(task.dueDate)
                              ? colors.dueOverdue
                              : colors.chipMuted,
                        ),
                      for (final label in task.labels ?? const <TaskLabel>[])
                        _Chip(
                          icon: LucideIcons.tag,
                          text: label.name,
                          color: labelColor(label.color),
                        ),
                      if ((count?.total ?? 0) > 0)
                        _Chip(
                          icon: LucideIcons.listChecks,
                          text: '${count?.completed ?? 0}/${count!.total}',
                          color: colors.chipMuted,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 250),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: context.colors.chipBorder),
      borderRadius: BorderRadius.circular(KaneoRadius.sm),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      ],
    ),
  );
}
