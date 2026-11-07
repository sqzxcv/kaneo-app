import '../../core/core.dart';
import '../inbox/my_tasks_groups.dart' show taskStatusName;

/// Who did it, or the web app's stand-in for an event that names no one.
String activityActor(I18n i18n, WorkspaceActivity activity) {
  for (final name in [activity.userName, activity.externalUserName]) {
    if (name != null && name.isNotEmpty) return name;
  }
  return i18n.t('mobile:activity.someone');
}

/// What the person did, phrased to follow their name, in the web app's wording.
String describeActivity(I18n i18n, WorkspaceActivity activity, {DateTime? now}) {
  final raw = activity.eventData;
  final data = raw is Map ? raw.cast<String, Object?>() : null;

  String text(String key) => '${data?[key] ?? ''}';
  String date(String key) => _eventDate(i18n, text(key), now);
  String status(String slug, String name) =>
      taskStatusName(i18n, text(slug), text(name).isEmpty ? null : text(name));

  switch (activity.type) {
    case 'comment':
      return i18n.t('workspace:home.activity.commented');
    case 'create' || 'created' || 'task':
      return i18n.t('activity:created');
    case 'unassigned':
      return i18n.t('activity:unassigned');
  }
  if (data != null) {
    switch (activity.type) {
      case 'status_changed':
        return i18n.t('activity:changedStatus', {
          'from': status('oldStatus', 'oldStatusName'),
          'to': status('newStatus', 'newStatusName'),
        });
      case 'priority_changed':
        return i18n.t('activity:changedPriority', {
          'from': _priority(i18n, text('oldPriority')),
          'to': _priority(i18n, text('newPriority')),
        });
      case 'assignee_changed':
        return data['isSelfAssigned'] == true
            ? i18n.t('activity:assignedToSelf')
            : i18n.t('activity:assignedTo', {'name': text('newAssignee')});
      case 'due_date_changed':
        if (text('newDueDate').isEmpty) return i18n.t('activity:clearedDueDate');
        return text('oldDueDate').isEmpty
            ? i18n.t('activity:setDueDate', {'date': date('newDueDate')})
            : i18n.t('activity:changedDueDate', {
                'from': date('oldDueDate'),
                'to': date('newDueDate'),
              });
      case 'title_changed':
        return i18n.t('activity:changedTitle', {'from': text('oldTitle'), 'to': text('newTitle')});
      case 'moved':
        return text('fromProjectName').isEmpty
            ? i18n.t('activity:movedFromOtherProject', {'to': text('toProjectName')})
            : i18n.t('activity:moved', {
                'from': text('fromProjectName'),
                'to': text('toProjectName'),
              });
    }
  }

  // Events recorded before they had details only have their English text.
  final excerpt = activity.excerpt;
  return excerpt == null || excerpt.isEmpty ? i18n.t('workspace:home.activity.updated') : excerpt;
}

String _priority(I18n i18n, String value) {
  final key = 'tasks:priority.$value';
  final label = i18n.t(key);
  return label == key ? value : label;
}

String _eventDate(I18n i18n, String value, DateTime? now) {
  final day = parseDay(value);
  return day == null ? value : formatDay(i18n, day, now: now);
}
