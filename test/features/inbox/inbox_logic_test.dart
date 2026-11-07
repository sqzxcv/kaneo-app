import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/inbox/my_tasks_groups.dart';
import 'package:kaneo_app/features/inbox/notification_text.dart';
import 'package:kaneo_app/features/inbox/notifications.dart';

import '../../support/test_app.dart';

InboxNotification _notification({
  String id = 'n',
  String type = 'custom',
  String? title,
  String? content,
  Object? eventData,
  bool? isRead,
  String? resourceId,
  String? resourceType,
  String createdAt = '2026-11-06T12:00:00.000Z',
}) => InboxNotification(
  id: id,
  userId: 'u',
  title: title,
  content: content,
  type: type,
  eventData: eventData,
  isRead: isRead,
  resourceId: resourceId,
  resourceType: resourceType,
  createdAt: createdAt,
);

AssignedTask _task(
  String id, {
  String? dueDate,
  String projectId = 'p1',
  String projectName = 'One',
  String status = 'to-do',
  String? statusName = 'To Do',
}) => AssignedTask(
  id: id,
  projectId: projectId,
  title: id,
  status: status,
  statusName: statusName,
  dueDate: dueDate,
  projectName: projectName,
  projectSlug: 'P',
);

Future<I18n> _english() => I18n.load(read: readCatalogFile);

void main() {
  group('notifications', () {
    test('missing isRead counts as unread, like in the current app', () {
      expect(isUnread(_notification()), isTrue);
      expect(isUnread(_notification(isRead: false)), isTrue);
      expect(isUnread(_notification(isRead: true)), isFalse);
      expect(unreadCount([_notification(), _notification(isRead: true)]), 1);
    });

    test('the count stops growing at 99+, like in the web app', () {
      expect(unreadLabel(1), '1');
      expect(unreadLabel(99), '99');
      expect(unreadLabel(100), '99+');
    });

    test('only a notification about a task has a task to open', () {
      expect(notificationTaskId(_notification(resourceType: 'task', resourceId: 't')), 't');
      expect(notificationTaskId(_notification(resourceType: 'workspace', resourceId: 'w')), isNull);
      expect(notificationTaskId(_notification(resourceId: 't')), isNull);
      expect(notificationTaskId(_notification(resourceType: 'task')), isNull);
    });

    test('groups by the local calendar day and keeps the order', () {
      final now = DateTime(2026, 11, 6, 15);
      String at(DateTime time) => time.toUtc().toIso8601String();
      final groups = groupNotifications([
        _notification(id: 'late today', createdAt: at(DateTime(2026, 11, 6, 14))),
        _notification(id: 'start of today', createdAt: at(DateTime(2026, 11, 6))),
        _notification(id: 'end of yesterday', createdAt: at(DateTime(2026, 11, 5, 23, 59))),
        _notification(id: 'last week', createdAt: at(DateTime(2026, 10, 30))),
      ], now);
      expect(groups.today.map((n) => n.id), ['late today', 'start of today']);
      expect(groups.earlier.map((n) => n.id), ['end of yesterday', 'last week']);
    });
  });

  group('what a notification says', () {
    test('every event the server raises reads as a sentence', () async {
      final i18n = await _english();
      final cases = {
        'task_created': {'taskTitle': 'Fix it'},
        'workspace_created': {'workspaceName': 'Team'},
        'task_status_changed': {
          'taskTitle': 'Fix it',
          'oldStatus': 'to-do',
          'newStatus': 'in-progress',
        },
        'task_assignee_changed': {'taskTitle': 'Fix it'},
        'time_entry_created': {'taskTitle': 'Fix it'},
        'task_mention': {'taskTitle': 'Fix it', 'mentionerName': 'Ann'},
        'task_comment': {'taskTitle': 'Fix it', 'commenterName': 'Ann', 'commentPreview': 'Hello'},
        'due_date_reminder': {'taskTitle': 'Fix it', 'leadTimeMinutes': 1440},
        'task_overdue': {'taskTitle': 'Fix it'},
      };
      cases.forEach((type, data) {
        final text = describeNotification(i18n, _notification(type: type, eventData: data));
        expect(text.title, isNot(contains('notifications:')), reason: type);
        expect(text.title, isNot(contains('{{')), reason: type);
        expect(text.content, isNotNull, reason: type);
        expect(text.content, isNot(contains('notifications:')), reason: type);
        expect(text.content, isNot(contains('{{')), reason: type);
      });
    });

    test('fills in the details', () async {
      final i18n = await _english();
      final mention = describeNotification(
        i18n,
        _notification(
          type: 'task_mention',
          eventData: {'mentionerName': 'Ann', 'taskTitle': 'Fix it'},
        ),
      );
      expect(mention.title, 'Ann mentioned you');
      expect(mention.content, 'Ann mentioned you in: Fix it');
    });

    test('statuses read in words, and an unknown one still reads', () async {
      final i18n = await _english();
      final text = describeNotification(
        i18n,
        _notification(
          type: 'task_status_changed',
          eventData: {'taskTitle': 'Fix it', 'oldStatus': 'in-review', 'newStatus': 'on-hold'},
        ),
      );
      expect(text.content, contains('"In Review"'));
      expect(text.content, contains('"On hold"'));
    });

    test('a reminder says how long is left, in the largest whole unit', () async {
      final i18n = await _english();
      String? lead(int minutes) => describeNotification(
        i18n,
        _notification(
          type: 'due_date_reminder',
          eventData: {'taskTitle': 'T', 'leadTimeMinutes': minutes},
        ),
      ).content;
      expect(lead(1440), 'T is due in 1 day');
      expect(lead(2880), 'T is due in 2 days');
      expect(lead(120), 'T is due in 2 hours');
      expect(lead(45), 'T is due in 45 minutes');
    });

    test('time tracking on no task still reads', () async {
      final i18n = await _english();
      final text = describeNotification(
        i18n,
        _notification(type: 'time_entry_created', eventData: {'taskTitle': null}),
      );
      expect(text.content, 'Time tracking started on a task');
    });

    test('follows the language', () async {
      final i18n = await I18n.load(locale: 'zh-CN', read: readCatalogFile);
      final text = describeNotification(
        i18n,
        _notification(type: 'task_overdue', eventData: {'taskTitle': 'T'}),
      );
      expect(text.title, i18n.t('notifications:events.task_overdue.title'));
      expect(text.title, isNot('Task overdue'));
    });

    test('anything else shows its own text, or at least its type', () async {
      final i18n = await _english();
      final own = describeNotification(
        i18n,
        _notification(type: 'custom', title: 'Hello', content: 'World', eventData: {'a': 1}),
      );
      expect(own.title, 'Hello');
      expect(own.content, 'World');
      final bare = describeNotification(i18n, _notification(type: 'build_failed', content: ''));
      expect(bare.title, 'Build failed');
      expect(bare.content, isNull);
    });

    test('a known type without details falls back too', () async {
      final i18n = await _english();
      final text = describeNotification(
        i18n,
        _notification(type: 'task_created', title: 'Hello', eventData: 'not a map'),
      );
      expect(text.title, 'Hello');
    });
  });

  group('due-date groups', () {
    final now = DateTime(2026, 11, 6, 15);

    test('go by the calendar day', () {
      expect(dueBucket(null, now), DueBucket.none);
      expect(dueBucket('2026-11-05', now), DueBucket.overdue);
      expect(dueBucket('2026-11-06', now), DueBucket.today);
      expect(dueBucket('2026-11-07', now), DueBucket.thisWeek);
      expect(dueBucket('2026-11-12', now), DueBucket.thisWeek);
      expect(dueBucket('2026-11-13', now), DueBucket.later);
    });

    test('a due date earlier today is today, not overdue', () {
      final morning = DateTime(2026, 11, 6, 8).toUtc().toIso8601String();
      expect(dueBucket(morning, now), DueBucket.today);
    });

    test('a week across the end of a month', () {
      final end = DateTime(2026, 11, 30);
      expect(dueBucket('2026-12-06', end), DueBucket.thisWeek);
      expect(dueBucket('2026-12-07', end), DueBucket.later);
    });
  });

  group('grouping my tasks', () {
    final now = DateTime(2026, 11, 6, 15);
    List<MyTasksGroup> group(List<AssignedTask> tasks, MyTasksGrouping by) =>
        groupMyTasks(tasks, by, now: now, statusName: (t) => t.statusName ?? t.status);

    test('by due date, in a fixed order and without empty groups', () {
      final groups = group([
        _task('none'),
        _task('later', dueDate: '2026-12-01'),
        _task('today', dueDate: '2026-11-06'),
        _task('overdue', dueDate: '2026-11-01'),
      ], MyTasksGrouping.dueDate);
      expect(groups.map((g) => g.bucket), [
        DueBucket.overdue,
        DueBucket.today,
        DueBucket.later,
        DueBucket.none,
      ]);
      expect(groups.map((g) => g.tasks.single.id), ['overdue', 'today', 'later', 'none']);
    });

    test('by project, the one with the most pressing work first', () {
      final groups = group([
        _task('a', projectId: 'p2', projectName: 'Two'),
        _task('b', projectId: 'p1', projectName: 'One'),
        _task('c', projectId: 'p2', projectName: 'Two'),
      ], MyTasksGrouping.project);
      expect(groups.map((g) => g.title), ['Two', 'One']);
      expect(groups.first.tasks.map((t) => t.id), ['a', 'c']);
    });

    test('two projects with the same name stay apart', () {
      final groups = group([
        _task('a', projectId: 'p1', projectName: 'Same'),
        _task('b', projectId: 'p2', projectName: 'Same'),
      ], MyTasksGrouping.project);
      expect(groups, hasLength(2));
    });

    test('by status, with the same column of different projects together', () {
      final groups = group([
        _task('a', projectId: 'p1', status: 'in-progress', statusName: 'In Progress'),
        _task('b', projectId: 'p2', status: 'to-do', statusName: 'To Do'),
        _task('c', projectId: 'p2', status: 'in-progress', statusName: 'In Progress'),
      ], MyTasksGrouping.status);
      expect(groups.map((g) => g.title), ['In Progress', 'To Do']);
      expect(groups.first.tasks.map((t) => t.id), ['a', 'c']);
    });
  });

  group('status names', () {
    test('default columns follow the language, and named ones keep their name', () async {
      final i18n = await I18n.load(locale: 'zh-CN', read: readCatalogFile);
      final toDo = i18n.t('tasks:status.to-do');
      expect(toDo, isNot('To Do'));
      expect(taskStatusName(i18n, 'to-do', 'To Do'), toDo);
      expect(taskStatusName(i18n, 'to-do', 'Backlog'), 'Backlog');
      expect(taskStatusName(i18n, 'custom', 'Waiting'), 'Waiting');
    });

    test('without a column name', () async {
      final i18n = await _english();
      expect(taskStatusName(i18n, 'planned', null), 'Planned');
      expect(taskStatusName(i18n, 'archived', null), 'Archived');
      expect(taskStatusName(i18n, 'waiting', null), 'waiting');
    });
  });
}
