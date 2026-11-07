import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';

/// Marks the unread count in the navigation, in both layouts.
const inboxUnreadKey = ValueKey('inbox-unread');

const int _maxUnreadShown = 99;

bool isUnread(InboxNotification notification) => notification.isRead != true;

int unreadCount(Iterable<InboxNotification> notifications) => notifications.where(isUnread).length;

/// How the navigation writes the unread count.
String unreadLabel(int count) => count > _maxUnreadShown ? '$_maxUnreadShown+' : '$count';

/// The task [notification] is about, or null if it isn't about a task.
String? notificationTaskId(InboxNotification notification) =>
    notification.resourceType == 'task' ? notification.resourceId : null;

/// Splits the inbox the way the current app does, keeping the server's order, newest first.
({List<InboxNotification> today, List<InboxNotification> earlier}) groupNotifications(
  List<InboxNotification> notifications,
  DateTime now,
) {
  final day = startOfDay(now);
  final today = <InboxNotification>[];
  final earlier = <InboxNotification>[];
  for (final notification in notifications) {
    (parseDay(notification.createdAt) == day ? today : earlier).add(notification);
  }
  return (today: today, earlier: earlier);
}

/// The unread count of the current workspace's inbox, for the navigation. Watching it keeps the
/// notifications loaded, so that the count is there on every page. Zero until they arrive.
final inboxUnreadCountProvider = Provider.autoDispose<int>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return 0;
  final notifications = ref.watch(notificationsQuery(workspace.id)).value;
  return notifications == null ? 0 : unreadCount(notifications);
});

/// The changes the inbox of one workspace can make, and its refreshing.
final inboxActionsProvider = Provider.family<InboxActions, String>(InboxActions.new);

/// Every change shows at once, so the count in the navigation drops right away, and goes back if
/// the server refuses it.
class InboxActions {
  InboxActions(this._ref, this._workspaceId);

  final Ref _ref;
  final String _workspaceId;

  /// Changes on their way to the server.
  int _writes = 0;

  late final _query = notificationsQuery(_workspaceId);

  /// Loads again, unless a change is on its way. An answer read now could still have the old state,
  /// and the change loads again when it is done.
  Future<void> refresh() async {
    if (_writes > 0 || !_ref.read(_query.exists)) return;
    await _ref.read(_query.notifier).refresh();
  }

  Future<void> markRead(BuildContext context, InboxNotification notification) => _write(
    context,
    change: (current) => [
      for (final item in current) item.id == notification.id ? item.copyWith(isRead: true) : item,
    ],
    undo: (current) => [
      for (final item in current) item.id == notification.id ? item.copyWith(isRead: false) : item,
    ],
    send: (api) => api.markNotificationRead(notification.id),
  );

  Future<void> markAllRead(BuildContext context) {
    final unread = {
      for (final item in _ref.read(_query).value ?? const <InboxNotification>[])
        if (isUnread(item)) item.id,
    };
    return _write(
      context,
      change: (current) => [for (final item in current) item.copyWith(isRead: true)],
      undo: (current) => [
        for (final item in current) unread.contains(item.id) ? item.copyWith(isRead: false) : item,
      ],
      send: (api) => api.markAllNotificationsRead(workspaceId: _workspaceId),
      success: context.t('mobile:inbox.allCaughtUpToast'),
    );
  }

  Future<void> clear(BuildContext context) {
    final before = _ref.read(_query).value ?? const <InboxNotification>[];
    return _write(
      context,
      change: (_) => const [],
      undo: (_) => before,
      send: (api) => api.clearAllNotifications(workspaceId: _workspaceId),
    );
  }

  Future<void> _write(
    BuildContext context, {
    required List<InboxNotification> Function(List<InboxNotification> current) change,
    required List<InboxNotification> Function(List<InboxNotification> current) undo,
    required Future<void> Function(KaneoApi api) send,
    String? success,
  }) async {
    final api = _ref.read(kaneoApiProvider);
    _writes++;
    _show(change);
    final sent = await runAction(context, () async {
      await send(api);
      return true;
    }, success: success);
    _writes--;
    if (sent != true) _show(undo);
    await refresh();
  }

  void _show(List<InboxNotification> Function(List<InboxNotification> current) update) {
    if (!_ref.read(_query.exists)) return;
    final current = _ref.read(_query).value;
    if (current != null) _ref.read(_query.notifier).setData(update(current));
  }
}
