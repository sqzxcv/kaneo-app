import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kaneo_app/core/core.dart';

import '../task/open_task.dart';
import 'board_hierarchy.dart';

class BoardListRow extends StatelessWidget {
  const BoardListRow({
    super.key,
    required this.task,
    required this.projectSlug,
    required this.wide,
    this.isFinal = false,
    this.onMenu,
    this.hierarchy,
    this.onToggle,
  });
  final BoardTask task;
  final HierarchyRow? hierarchy;
  final VoidCallback? onToggle;
  final String projectSlug;
  final bool wide;
  final bool isFinal;
  final void Function(BuildContext context, BoardTask task, Offset position)? onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = formatDueShort(I18nScope.of(context), task.dueDate);
    final late = isOverdue(task.dueDate);
    final priorityColor = switch (task.priority) {
      'urgent' => colors.priorityUrgent,
      'high' => colors.priorityHigh,
      'medium' => colors.priorityMedium,
      'low' => colors.priorityLow,
      _ => colors.chipMuted,
    };
    final labels = task.labels ?? <TaskLabel>[];
    final counts = task.subtaskCounts;
    final onMenu = this.onMenu;
    return MenuGestures(
      onMenu: onMenu == null ? null : (position) => onMenu(context, task, position),
      child: Material(
        color: colors.background,
        child: InkWell(
          onTap: () => openTask(context, task.id, projectId: task.projectId),
          child: Container(
            constraints: BoxConstraints(minHeight: wide ? 46 : 58),
            padding: EdgeInsets.only(
              left:
                  (wide ? 16 : 12) +
                  (hierarchy?.depth ?? 0).clamp(0, wide ? 6 : 3) * (wide ? 16 : 12),
              right: wide ? 16 : 12,
              top: 8,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (hierarchy != null)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: hierarchy!.childCount == 0
                            ? null
                            : IconButton(
                                key: ValueKey('expand-task-${task.id}'),
                                tooltip: context.t(
                                  hierarchy!.expanded
                                      ? 'app:board.collapseChildren'
                                      : 'app:board.expandChildren',
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: onToggle,
                                icon: Icon(
                                  hierarchy!.expanded
                                      ? LucideIcons.chevronDown
                                      : LucideIcons.chevronRight,
                                  size: 16,
                                ),
                              ),
                      ),
                    if (wide) ...[
                      Tooltip(
                        message: priorityLabel(context, task.priority),
                        child: Icon(
                          task.priority == 'urgent'
                              ? LucideIcons.triangleAlert
                              : task.priority == null || task.priority == 'no-priority'
                              ? LucideIcons.ellipsis
                              : LucideIcons.signal,
                          size: 16,
                          color: priorityColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    SizedBox(
                      width: wide ? 78 : 64,
                      child: Text(
                        ticketId(projectSlug, task.number),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KaneoFonts.mono,
                          fontSize: 11,
                          color: colors.boardId,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              task.title,
                              maxLines: wide ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isFinal ? colors.boardTitleDone : colors.boardTitle,
                              ),
                            ),
                          ),
                          // On every window, as on the board's cards (KAN-68).
                          if ((counts?.total ?? 0) > 0) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: context.t('mobile:taskDetail.subtasks.title'),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.listChecks, size: 14, color: colors.chipMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${counts?.completed ?? 0}/${counts!.total}',
                                    style: TextStyle(fontSize: 11, color: colors.chipMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (wide && labels.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 224),
                        child: Tooltip(
                          message: labels.map((label) => label.name).join(', '),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final label in labels.take(2))
                                Flexible(
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: colors.chipBorder),
                                      borderRadius: BorderRadius.circular(KaneoRadius.sm),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.tag,
                                          size: 11,
                                          color: labelColor(label.color),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            label.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colors.chipForeground,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (labels.length > 2)
                                Text(
                                  ' +${labels.length - 2}',
                                  style: TextStyle(fontSize: 11, color: colors.chipMuted),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (wide) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: wide ? 110 : 82,
                        child: Text(
                          date,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: late && !isFinal ? colors.dueOverdue : colors.chipMuted,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Tooltip(
                      message: task.assigneeName ?? context.t('mobile:board.unassigned'),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: task.assigneeId == null
                            ? colors.avatarUnassigned
                            : colors.avatar,
                        foregroundColor: colors.avatarForeground,
                        child: task.assigneeId == null && task.assigneeName == null
                            ? const Icon(LucideIcons.user, size: 14)
                            : Text(
                                initials(task.assigneeName),
                                style: const TextStyle(fontSize: 10),
                              ),
                      ),
                    ),
                  ],
                ),
                if (!wide && late && date.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      date,
                      style: TextStyle(
                        fontSize: 11,
                        color: isFinal ? colors.chipMuted : colors.dueOverdue,
                      ),
                    ),
                  ),
                if (hierarchy?.parentTitles.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 4),
                    child: Text(
                      '${context.t('mobile:taskDetail.subtasks.parent')}: ${hierarchy!.parentTitles.join(', ')}',
                      key: ValueKey('parent-titles-${task.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colors.mutedForeground),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
