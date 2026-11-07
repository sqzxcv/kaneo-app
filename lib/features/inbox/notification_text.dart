import '../../core/core.dart';

/// What a notification says, in the web app's wording.
typedef NotificationText = ({String title, String? content});

/// The types the server's own events raise. They store their details rather than their text, so
/// that they read in the language of whoever opens them.
const Set<String> _eventTypes = {
  'task_created',
  'workspace_created',
  'task_status_changed',
  'task_assignee_changed',
  'time_entry_created',
  'task_mention',
  'task_comment',
  'due_date_reminder',
  'task_overdue',
};

const int _minutesPerHour = 60;
const int _minutesPerDay = 1440;

NotificationText describeNotification(I18n i18n, InboxNotification notification) {
  final type = notification.type;
  final data = notification.eventData;
  final fallback = (
    title: notification.title ?? _displayCase(type),
    content: _orNull(notification.content),
  );
  if (data is! Map || !_eventTypes.contains(type)) return fallback;

  final args = data.cast<String, Object?>();
  final content = switch (type) {
    'task_status_changed' => i18n.t('notifications:events.$type.content', {
      ...args,
      'oldStatus': _statusLabel(i18n, args['oldStatus']),
      'newStatus': _statusLabel(i18n, args['newStatus']),
    }),
    'time_entry_created' => i18n.t(
      args['taskTitle'] == null
          ? 'notifications:events.$type.contentWithoutTask'
          : 'notifications:events.$type.contentWithTask',
      args,
    ),
    'due_date_reminder' => i18n.t('notifications:events.$type.content', {
      ...args,
      'leadTime': _leadTime(i18n, args['leadTimeMinutes']),
    }),
    _ => i18n.t('notifications:events.$type.content', args),
  };
  return (
    title: i18n.t('notifications:events.$type.title', args).trim(),
    content: _orNull(content.trim()),
  );
}

String? _orNull(String? text) => text == null || text.isEmpty ? null : text;

String _statusLabel(I18n i18n, Object? status) {
  final slug = '${status ?? ''}';
  final key = 'tasks:status.$slug';
  final label = i18n.t(key);
  return label == key ? _displayCase(slug) : label;
}

String _leadTime(I18n i18n, Object? value) {
  final minutes = value is num ? value.toInt() : _minutesPerDay;
  if (minutes % _minutesPerDay == 0) {
    return i18n.t('notifications:reminderLeadTime.days', {'count': minutes ~/ _minutesPerDay});
  }
  if (minutes % _minutesPerHour == 0) {
    return i18n.t('notifications:reminderLeadTime.hours', {'count': minutes ~/ _minutesPerHour});
  }
  return i18n.t('notifications:reminderLeadTime.minutes', {'count': minutes});
}

/// `task_overdue` as `Task overdue`.
String _displayCase(String value) {
  final words = value.replaceAll(RegExp('[-_]'), ' ');
  return words.isEmpty ? words : '${words[0].toUpperCase()}${words.substring(1)}';
}
