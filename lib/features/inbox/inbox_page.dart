import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../shell/workspace_gate.dart';
import '../task/open_task.dart';
import 'notification_text.dart';
import 'notifications.dart';

/// From this window width, marking all read says so in words, as in the web app. In many languages
/// those words leave no room for the title on a smaller one.
const double _labelledButtonMinWindow = 900;

/// Who is looking for me: the current workspace's notifications, newest first. A reading column on
/// wide windows, like the web app's, so that the time stays next to what it belongs to.
class InboxPage extends ConsumerWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('mobile:inbox.title')),
        actions: workspace == null ? null : [_InboxButtons(workspaceId: workspace.id)],
      ),
      body: ContentWidth(
        child: WorkspaceGate(
          builder: (context, workspace) => _InboxList(workspaceId: workspace.id),
        ),
      ),
    );
  }
}

class _InboxButtons extends ConsumerWidget {
  const _InboxButtons({required this.workspaceId});

  final String workspaceId;

  Future<void> _clear(BuildContext context, InboxActions actions) async {
    final confirmed = await showConfirm(
      context,
      title: context.t('mobile:inbox.confirmClear.title'),
      message: context.t('mobile:inbox.confirmClear.message'),
      confirmLabel: context.t('mobile:inbox.confirmClear.confirm'),
      destructive: true,
    );
    if (confirmed && context.mounted) await actions.clear(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsQuery(workspaceId)).value ?? const [];
    final actions = ref.watch(inboxActionsProvider(workspaceId));
    final markAllRead = context.t('mobile:inbox.markAllRead');
    final onMarkAllRead = unreadCount(notifications) == 0
        ? null
        : () => actions.markAllRead(context);
    const markAllIcon = Icon(LucideIcons.checkCheck, size: 16);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: markAllRead,
            child: MediaQuery.sizeOf(context).width >= _labelledButtonMinWindow
                ? TextButton.icon(
                    onPressed: onMarkAllRead,
                    icon: markAllIcon,
                    label: Text(markAllRead),
                  )
                : IconButton(onPressed: onMarkAllRead, icon: markAllIcon),
          ),
          IconButton(
            tooltip: context.t('mobile:inbox.clearAll'),
            onPressed: notifications.isEmpty ? null : () => _clear(context, actions),
            icon: const Icon(LucideIcons.trash2, size: 16),
          ),
        ],
      ),
    );
  }
}

class _InboxList extends ConsumerWidget {
  const _InboxList({required this.workspaceId});

  final String workspaceId;

  void _open(BuildContext context, WidgetRef ref, InboxNotification notification) {
    if (isUnread(notification)) {
      unawaited(ref.read(inboxActionsProvider(workspaceId)).markRead(context, notification));
    }
    final taskId = notificationTaskId(notification);
    if (taskId != null) openTaskPage(context, taskId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = notificationsQuery(workspaceId);
    return AsyncBody(
      value: ref.watch(query),
      onRetry: () => ref.read(query.notifier).refresh(),
      isEmpty: (notifications) => notifications.isEmpty,
      empty: StatusMessage(
        title: context.t('mobile:inbox.empty.title'),
        message: context.t('mobile:inbox.empty.message'),
      ),
      builder: (context, notifications) {
        final now = ref.read(nowProvider)();
        final groups = groupNotifications(notifications, now);

        List<Widget> section(String title, List<InboxNotification> items) => [
          if (items.isNotEmpty) _GroupTitle(title: title),
          for (final notification in items)
            _NotificationRow(
              key: ValueKey(notification.id),
              notification: notification,
              now: now,
              onTap: () => _open(context, ref, notification),
            ),
        ];

        return RefreshIndicator(
          onRefresh: () => ref.read(inboxActionsProvider(workspaceId)).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: [
              ...section(context.t('mobile:inbox.today'), groups.today),
              ...section(
                context.t(groups.today.isEmpty ? 'mobile:inbox.recent' : 'mobile:inbox.earlier'),
                groups.earlier,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// A row of the web app's inbox.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    super.key,
    required this.notification,
    required this.now,
    required this.onTap,
  });

  final InboxNotification notification;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i18n = I18nScope.of(context);
    final text = Theme.of(context).textTheme;
    final unread = isUnread(notification);
    final words = describeNotification(i18n, notification);
    return Semantics(
      container: true,
      button: true,
      label: unread ? context.t('notifications:inbox.unread') : null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KaneoRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: c.accent.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NotificationIcon(type: notification.type),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              words.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium!.copyWith(
                                fontSize: 13,
                                color: unread ? c.foreground : c.foreground.withValues(alpha: 0.8),
                                fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            relativeShort(i18n, notification.createdAt, now: now),
                            style: text.bodySmall,
                          ),
                          const SizedBox(width: 8),
                          // Always takes its place, so that times line up across rows.
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: unread ? c.info : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      if (words.content != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          words.content!,
                          maxLines: context.isWide ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium!.copyWith(
                            fontSize: 13,
                            color: c.mutedForeground.withValues(alpha: unread ? 1 : 0.8),
                          ),
                        ),
                      ],
                    ],
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

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overdue = type == 'task_overdue';
    final icon = switch (type) {
      'task_mention' => LucideIcons.atSign,
      'task_comment' => LucideIcons.messageSquare,
      'task_assignee_changed' => LucideIcons.userRound,
      'task_status_changed' => LucideIcons.history,
      'task_created' => LucideIcons.squarePlus,
      'due_date_reminder' => LucideIcons.calendarClock,
      'task_overdue' => LucideIcons.calendarX,
      'time_entry_created' => LucideIcons.timer,
      _ => LucideIcons.bell,
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: overdue ? c.destructive.withValues(alpha: 0.1) : c.muted,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: overdue ? c.destructiveForeground : c.mutedForeground),
    );
  }
}
