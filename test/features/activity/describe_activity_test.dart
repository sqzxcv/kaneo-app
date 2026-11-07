import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/activity/describe_activity.dart';

import '../../support/test_app.dart';

WorkspaceActivity _activity(
  String type, {
  Object? eventData,
  String? excerpt,
  String? userName,
  String? externalUserName,
}) => WorkspaceActivity(
  id: 'activity',
  type: type,
  createdAt: '2026-11-06T12:00:00.000Z',
  eventData: eventData,
  excerpt: excerpt,
  userName: userName,
  externalUserName: externalUserName,
  taskId: 'task',
  taskTitle: 'Task',
  projectId: 'project',
  projectSlug: 'DEMO',
);

void main() {
  late I18n i18n;

  setUpAll(() async {
    i18n = await I18n.load(locale: defaultLocale, read: readCatalogFile);
  });

  String describe(String type, {Object? eventData, String? excerpt}) => describeActivity(
    i18n,
    _activity(type, eventData: eventData, excerpt: excerpt),
    now: DateTime(2026, 11, 6),
  );

  group('the sentence', () {
    test('a comment and a new task', () {
      expect(describe('comment', excerpt: 'Words'), 'commented');
      for (final type in ['create', 'created', 'task']) {
        expect(describe(type), 'created this task');
      }
    });

    test('a status change names the columns', () {
      expect(
        describe('status_changed', eventData: {'oldStatus': 'to-do', 'newStatus': 'done'}),
        'changed status from To Do to Done',
      );
      expect(
        describe(
          'status_changed',
          eventData: {
            'oldStatus': 'to-do',
            'oldStatusName': 'To Do',
            'newStatus': 'waiting',
            'newStatusName': 'Waiting on legal',
          },
        ),
        'changed status from To Do to Waiting on legal',
      );
    });

    test('a priority change', () {
      expect(
        describe('priority_changed', eventData: {'oldPriority': 'low', 'newPriority': 'urgent'}),
        'changed priority from Low to Urgent',
      );
    });

    test('an assignee change', () {
      expect(
        describe('assignee_changed', eventData: {'isSelfAssigned': true}),
        'assigned the task to themselves',
      );
      expect(
        describe('assignee_changed', eventData: {'newAssignee': 'Mira'}),
        'assigned the task to Mira',
      );
      expect(describe('unassigned', eventData: const {}), 'unassigned the task');
    });

    test('a due date change', () {
      expect(describe('due_date_changed', eventData: const {}), 'cleared the due date');
      expect(
        describe('due_date_changed', eventData: {'newDueDate': '2026-12-01'}),
        'set due date to Dec 1',
      );
      expect(
        describe(
          'due_date_changed',
          eventData: {'oldDueDate': '2026-12-01', 'newDueDate': '2027-01-02'},
        ),
        'changed due date from Dec 1 to Jan 2, 2027',
      );
    });

    test('a new title', () {
      expect(
        describe('title_changed', eventData: {'oldTitle': 'Old', 'newTitle': 'New'}),
        'changed title from "Old" to "New"',
      );
    });

    test('a move, with the old project hidden when it is out of reach', () {
      expect(
        describe('moved', eventData: {'fromProjectName': 'Web', 'toProjectName': 'App'}),
        'moved task from "Web" to "App"',
      );
      expect(
        describe('moved', eventData: {'toProjectName': 'App'}),
        'moved task from another project to "App"',
      );
    });

    test('an event with no details uses its text, and otherwise says it changed something', () {
      expect(describe('status_changed', excerpt: 'moved it along'), 'moved it along');
      expect(describe('something_new', eventData: const {}), 'updated the task');
      expect(describe('something_new', excerpt: ''), 'updated the task');
    });

    test('follows the language', () async {
      final chinese = await I18n.load(locale: 'zh-CN', read: readCatalogFile);
      expect(
        describeActivity(
          chinese,
          _activity('status_changed', eventData: {'oldStatus': 'to-do', 'newStatus': 'done'}),
        ),
        '将状态从 ${chinese.t('tasks:status.to-do')} 改为 ${chinese.t('tasks:status.done')}',
      );
    });
  });

  group('the actor', () {
    test('is the person, then who it came from outside, then someone', () {
      expect(activityActor(i18n, _activity('task', userName: 'Mira')), 'Mira');
      expect(activityActor(i18n, _activity('task', externalUserName: 'octocat')), 'octocat');
      expect(
        activityActor(i18n, _activity('task', userName: '', externalUserName: 'octocat')),
        'octocat',
      );
      expect(activityActor(i18n, _activity('task')), 'Someone');
    });
  });
}
