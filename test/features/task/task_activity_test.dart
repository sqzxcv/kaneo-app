import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/markdown/mention_text.dart';
import 'package:kaneo_app/features/task/task_activity.dart';
import 'package:kaneo_app/features/task/task_activity_view.dart';

import '../../support/test_app.dart';

const _otherId = 'user-2';
const _otherName = 'Second User';
const _commentPath = 'api/activity/comment';

final _section = find.byType(TaskActivitySection);
final _box = find.byKey(const ValueKey('comment-box'));
final _send = find.byKey(const ValueKey('comment-send'));
final _status = find.byKey(const ValueKey('task-status'));

Finder _inSection(Finder finder) => find.descendant(of: _section, matching: finder);
Finder _comment(String id) => find.byKey(ValueKey('task-comment-$id'));
Finder _event(String id) => find.byKey(ValueKey('task-event-$id'));
Finder _editButton(String id) => find.byKey(ValueKey('comment-edit-$id'));
Finder _deleteButton(String id) => find.byKey(ValueKey('comment-delete-$id'));
Finder _field(String id) => find.byKey(ValueKey('comment-field-$id'));
Finder _save(String id) => find.byKey(ValueKey('comment-save-$id'));
Finder _cancel(String id) => find.byKey(ValueKey('comment-cancel-$id'));
Finder _mentionButton(String name) => find.byKey(ValueKey('$name-mention'));
Finder _person(String id) => find.byKey(ValueKey('mention-$id'));
Finder _text(String text) => _inSection(find.text(text));
Finder _rich(String text) => _inSection(find.textContaining(text, findRichText: true));

TextField _textField(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(find.descendant(of: field, matching: find.byType(TextField)));

/// A server with only the comments and events a test adds.
FakeKaneo _quietServer() => FakeKaneo()..activities.clear();

Future<TestApp> _open(WidgetTester tester, Size size, FakeKaneo server) =>
    pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('task-1'));

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: field, matching: find.byType(TextField)), text);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _onlyPost(FakeKaneo server) =>
    server.requestsTo(_commentPath, method: 'POST').single.body as Map<String, dynamic>;

List<String?> _commentsOn(FakeKaneo server, String taskId) => [
  for (final activity in server.activities)
    if (activity['taskId'] == taskId && activity['type'] == 'comment')
      activity['content'] as String?,
];

Future<void> _expectNobodyOffered(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.byType(PopoverRow), findsNothing);
}

void main() {
  group('the record', () {
    testBothLayouts('shows every event and comment, oldest first', (tester, size) async {
      final server = _quietServer();
      final ids = [
        server.addActivity('task-1', 'task')['id'],
        server.addComment('task-1', 'The first comment', authorId: _otherId)['id'],
        server.addActivity(
          'task-1',
          'status_changed',
          eventData: {'oldStatus': 'to-do', 'newStatus': 'done'},
        )['id'],
        server.addActivity(
          'task-1',
          'priority_changed',
          authorId: _otherId,
          eventData: {'oldPriority': 'low', 'newPriority': 'high'},
        )['id'],
        server.addComment('task-1', 'The last comment')['id'],
      ];
      for (var i = 0; i < 60; i++) {
        server.addActivity('task-1', 'unassigned');
      }
      await _open(tester, size, server);

      expect(_rich('Test User created this task'), findsOneWidget);
      expect(_rich('Test User changed status from To Do to Done'), findsOneWidget);
      expect(_rich('$_otherName changed priority from Low to High'), findsOneWidget);
      expect(_rich('unassigned the task'), findsNWidgets(60));
      expect(_text('The first comment'), findsOneWidget);
      expect(_text('The last comment'), findsOneWidget);
      expect(_rich(_otherName), findsWidgets);

      double top(int index) => tester
          .getTopLeft(index == 1 || index == 4 ? _comment(ids[index]) : _event(ids[index]))
          .dy;
      for (var i = 1; i < ids.length; i++) {
        expect(top(i), greaterThan(top(i - 1)));
      }
    });

    testBothLayouts('sits below the rest of the task', (tester, size) async {
      await _open(tester, size, FakeKaneo());
      expect(_section, findsOneWidget);
      expect(_text('A first comment.'), findsOneWidget);
    });

    testBothLayouts('asks for the whole record', (tester, size) async {
      final server = FakeKaneo();
      await _open(tester, size, server);
      final request = server.requestsTo('api/activity/task-1', method: 'GET').first;
      expect(request.query, isNot(contains('limit')));
    });

    testBothLayouts('a comment with no words reads as an event', (tester, size) async {
      final server = _quietServer();
      final id = server.addActivity('task-1', 'comment')['id'] as String;
      await _open(tester, size, server);
      expect(_comment(id), findsNothing);
      expect(_event(id), findsOneWidget);
    });

    testBothLayouts('an old event shows the words it was recorded with', (tester, size) async {
      final server = _quietServer();
      final activity = server.addActivity(
        'task-1',
        'assignee_changed',
        content: 'assigned the task to [[user:u9|Old Name]]',
      );
      activity['eventData'] = null;
      await _open(tester, size, server);
      expect(_rich('Test User assigned the task to Old Name'), findsOneWidget);
    });

    testBothLayouts('a person it no longer knows reads as someone', (tester, size) async {
      final server = _quietServer();
      server.addActivity('task-1', 'unassigned', authorId: 'gone');
      await _open(tester, size, server);
      expect(_rich('Someone unassigned the task'), findsOneWidget);
    });

    testBothLayouts('says when there is nothing yet', (tester, size) async {
      final app = await _open(tester, size, _quietServer());
      expect(_text(app.i18n.t('tasks:detail.noActivity')), findsOneWidget);
      expect(_box, findsOneWidget);
    });

    testBothLayouts('shows a spinner while loading', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold('api/activity/task-1');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('task-1'),
        settle: false,
      );
      for (var i = 0; i < 10 && _section.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_inSection(find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(_box, findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
      expect(_inSection(find.byType(CircularProgressIndicator)), findsNothing);
      expect(_text('A first comment.'), findsOneWidget);
    });

    testBothLayouts('a failed load says so and offers to try again', (tester, size) async {
      final server = FakeKaneo()..failNext('api/activity/task-1', status: 500);
      final app = await _open(tester, size, server);
      expect(_text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      expect(_box, findsOneWidget);

      await _press(tester, _text(app.i18n.t('mobile:common.retry')));
      expect(_text('A first comment.'), findsOneWidget);
    });

    testBothLayouts('without access it says so, and offers nothing to do', (tester, size) async {
      final server = FakeKaneo()..fail('api/activity/task-1', status: 403);
      final app = await _open(tester, size, server);
      expect(_text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(_box, findsNothing);
    });

    testBothLayouts('a change made here shows up without opening the task again', (
      tester,
      size,
    ) async {
      final server = _quietServer();
      await _open(tester, size, server);
      await _press(tester, _status);
      await tester.tap(find.widgetWithText(PopoverRow, 'Done'));
      await tester.pumpAndSettle();
      expect(_rich('Test User changed status from To Do to Done'), findsOneWidget);
    });
  });

  group('showing a comment', () {
    testBothLayouts('formats its Markdown', (tester, size) async {
      final server = _quietServer();
      server.addComment('task-1', '# Heading\n\n**bold** and [a link](https://kaneo.test)');
      await _open(tester, size, server);
      expect(_text('Heading'), findsOneWidget);
      expect(_rich('bold and a link'), findsOneWidget);
      expect(_rich('**'), findsNothing);
    });

    testBothLayouts('shows a mention as the name, not the tag', (tester, size) async {
      final server = _quietServer();
      server.addComment('task-1', 'Hi ${mentionTag(_otherId, _otherName)}!');
      await _open(tester, size, server);
      expect(_rich('@$_otherName'), findsWidgets);
      expect(_rich('kaneo-mention'), findsNothing);
    });

    testBothLayouts('copes with a very long name and comment', (tester, size) async {
      final server = _quietServer();
      final name = 'A very long name ' * 8;
      server.members.add({
        'id': 'long',
        'name': name,
        'email': 'long@example.com',
        'image': null,
        'role': 'member',
      });
      server.addComment('task-1', 'word ' * 200, authorId: 'long');
      server.addComment('task-1', 'unbroken' * 80);
      await _open(tester, size, server);
      expect(tester.takeException(), isNull);
      expect(_box, findsOneWidget);
    });

    testBothLayouts('says when it was edited', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Before')['id'] as String;
      final app = await _open(tester, size, server);
      final time = relativeLong(app.i18n, server.activities.single['createdAt'] as String);
      Finder edited() => find.descendant(
        of: _comment(id),
        matching: find.textContaining(
          app.i18n.t('mobile:taskDetail.activity.edited', {'time': time}),
          findRichText: true,
        ),
      );
      expect(edited(), findsNothing);

      await _press(tester, _editButton(id));
      await _type(tester, _field(id), 'After');
      await _press(tester, _save(id));
      expect(edited(), findsOneWidget);
    });
  });

  group('adding a comment', () {
    testBothLayouts('sends it and shows it, and empties the box', (tester, size) async {
      final server = _quietServer();
      await _open(tester, size, server);
      await _type(tester, _box, 'Looks **good**');
      await _press(tester, _send);

      expect(_onlyPost(server), {'taskId': 'task-1', 'comment': 'Looks **good**'});
      expect(_rich('Looks good'), findsOneWidget);
      expect(_textField(tester, _box).controller!.text, isEmpty);
    });

    testBothLayouts('there is nothing to send until there are words', (tester, size) async {
      final server = _quietServer();
      await _open(tester, size, server);
      expect(tester.widget<FilledButton>(_send).onPressed, isNull);
      await _type(tester, _box, ' \n ');
      expect(tester.widget<FilledButton>(_send).onPressed, isNull);
      await _type(tester, _box, 'x');
      expect(tester.widget<FilledButton>(_send).onPressed, isNotNull);
    });

    testBothLayouts('a failure says why and keeps the words', (tester, size) async {
      final server = _quietServer()..failNext(_commentPath, status: 500);
      await _open(tester, size, server);
      await _type(tester, _box, 'Keep me');
      await _press(tester, _send);

      expect(_textField(tester, _box).controller!.text, 'Keep me');
      expect(server.activities, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);

      await _press(tester, _send);
      expect(_commentsOn(server, 'task-1'), ['Keep me']);
      expect(_textField(tester, _box).controller!.text, isEmpty);
    });

    testBothLayouts('can\'t be sent twice while on its way', (tester, size) async {
      final server = _quietServer();
      final gate = server.hold(_commentPath, method: 'POST');
      await _open(tester, size, server);
      await _type(tester, _box, 'Once');
      await tester.ensureVisible(_send);
      await tester.pumpAndSettle();
      await tester.tap(_send);
      await tester.pump();
      expect(tester.widget<FilledButton>(_send).onPressed, isNull);
      expect(_textField(tester, _box).readOnly, isTrue);

      gate.release();
      await tester.pumpAndSettle();
      expect(_commentsOn(server, 'task-1'), ['Once']);
      expect(_textField(tester, _box).readOnly, isFalse);
    });

    testBothLayouts('closing the task while it is on its way still saves it', (tester, size) async {
      final server = _quietServer();
      final gate = server.hold(_commentPath, method: 'POST');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      final card = find.byKey(const ValueKey('board-card-task-1'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      await _type(tester, _box, 'On its way');
      await tester.ensureVisible(_send);
      await tester.pumpAndSettle();
      await tester.tap(_send);
      await tester.pump();

      await tester.tap(find.byTooltip(size == wideSize ? 'Close' : 'Back').last);
      await tester.pumpAndSettle();
      expect(_section, findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(_commentsOn(server, 'task-1'), ['On its way']);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('what is being typed stays when the window changes', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Editing this')['id'] as String;
      await _open(tester, size, server);
      await _type(tester, _box, 'Half a thought');
      await _press(tester, _editButton(id));
      await _type(tester, _field(id), 'Half an edit');

      final other = size == wideSize ? narrowSize : wideSize;
      setWindowSize(tester, other);
      await tester.pumpAndSettle();
      expect(_textField(tester, _box).controller!.text, 'Half a thought');
      expect(_textField(tester, _field(id)).controller!.text, 'Half an edit');
    });
  });

  group('mentioning someone', () {
    testBothLayouts('typing @ offers people, and the pick is saved as a mention', (
      tester,
      size,
    ) async {
      final server = _quietServer();
      await _open(tester, size, server);
      await _type(tester, _box, 'Hi @Sec');
      expect(_person(_otherId), findsOneWidget);
      expect(_person(FakeKaneo.userId), findsNothing);

      await tester.tap(_person(_otherId));
      await tester.pumpAndSettle();
      expect(_textField(tester, _box).controller!.text, 'Hi @$_otherName ');
      await _expectNobodyOffered(tester);

      await tester.enterText(
        find.descendant(of: _box, matching: find.byType(TextField)),
        'Hi @$_otherName look',
      );
      await tester.pumpAndSettle();
      await _press(tester, _send);
      expect(_onlyPost(server)['comment'], 'Hi ${mentionTag(_otherId, _otherName)} look');
      expect(_rich('@$_otherName'), findsWidgets);
    });

    testBothLayouts('the person mentioned gets a notification, and only they do', (
      tester,
      size,
    ) async {
      final server = _quietServer()..notifications.clear();
      await _open(tester, size, server);
      await _type(tester, _box, '@Sec');
      await tester.tap(_person(_otherId));
      await tester.pumpAndSettle();
      await _press(tester, _send);

      expect(server.notifications, isEmpty);
      final notification = server.notificationsToOthers.single;
      expect(notification['userId'], _otherId);
      expect(notification['type'], 'task_mention');
      expect(notification['resourceId'], 'task-1');
    });

    testBothLayouts('mentioning yourself tells nobody', (tester, size) async {
      final server = _quietServer()..notifications.clear();
      await _open(tester, size, server);
      await _type(tester, _box, '@Test');
      await tester.tap(_person(FakeKaneo.userId));
      await tester.pumpAndSettle();
      await _press(tester, _send);
      expect(_onlyPost(server)['comment'], mentionTag(FakeKaneo.userId, 'Test User'));
      expect(server.notifications, isEmpty);
      expect(server.notificationsToOthers, isEmpty);
    });

    testBothLayouts('the button starts a mention, in the text box', (tester, size) async {
      final server = _quietServer();
      await _open(tester, size, server);
      await _type(tester, _box, 'Hi');
      await _press(tester, _mentionButton('comment-box'));
      expect(_textField(tester, _box).controller!.text, 'Hi @');
      expect(_textField(tester, _box).focusNode!.hasFocus, isTrue);
      expect(_person(_otherId), findsOneWidget);
      expect(_person(FakeKaneo.userId), findsOneWidget);
    });

    testBothLayouts('a name typed by hand is just text, and tells nobody', (tester, size) async {
      final server = _quietServer()..notifications.clear();
      await _open(tester, size, server);
      await _type(tester, _box, 'Hi @Nobody');
      await _expectNobodyOffered(tester);
      await _press(tester, _send);
      expect(_onlyPost(server)['comment'], 'Hi @Nobody');
      expect(server.notifications, isEmpty);
      expect(server.notificationsToOthers, isEmpty);
    });

    testBothLayouts('text still being composed is left alone', (tester, size) async {
      await _open(tester, size, _quietServer());
      await _type(tester, _box, '');
      const composing = TextEditingValue(
        text: '@zhang',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 1, end: 6),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pumpAndSettle();
      expect(_textField(tester, _box).controller!.value, composing);
    });

    testBothLayouts('an address offers nobody', (tester, size) async {
      await _open(tester, size, _quietServer());
      await _type(tester, _box, 'mail me@Sec');
      await _expectNobodyOffered(tester);
    });

    testBothLayouts('leaving the box puts the list away', (tester, size) async {
      await _open(tester, size, _quietServer());
      await _type(tester, _box, '@Sec');
      expect(_person(_otherId), findsOneWidget);
      _textField(tester, _box).focusNode!.unfocus();
      await _expectNobodyOffered(tester);
    });

    testBothLayouts('the list opens above the box, clear of a keyboard', (tester, size) async {
      await _open(tester, size, _quietServer());
      await _type(tester, _box, '@');
      expect(
        tester.getBottomLeft(_person(_otherId)).dy,
        lessThanOrEqualTo(tester.getTopLeft(_box).dy),
      );
    });

    testBothLayouts('people load with the task, and it still works if they can\'t', (
      tester,
      size,
    ) async {
      final server = _quietServer()..fail('api/workspace/${FakeKaneo.workspaceId}/members');
      await _open(tester, size, server);
      await _type(tester, _box, 'Hi @Sec');
      await _expectNobodyOffered(tester);
      await _press(tester, _send);
      expect(_onlyPost(server)['comment'], 'Hi @Sec');
    });
  });

  group('editing a comment', () {
    testBothLayouts('saves the new words and shows them', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Befor')['id'] as String;
      await _open(tester, size, server);
      await _press(tester, _editButton(id));
      expect(_textField(tester, _field(id)).controller!.text, 'Befor');
      expect(_editButton(id), findsNothing);
      expect(_deleteButton(id), findsNothing);

      await _type(tester, _field(id), 'After');
      await _press(tester, _save(id));

      expect(_commentsOn(server, 'task-1'), ['After']);
      expect(_field(id), findsNothing);
      expect(_text('After'), findsOneWidget);
      expect(_text('Befor'), findsNothing);
    });

    testBothLayouts('a mention reads as a name, and is kept', (tester, size) async {
      final server = _quietServer();
      final tag = mentionTag(_otherId, _otherName);
      final id = server.addComment('task-1', 'Hi $tag')['id'] as String;
      await _open(tester, size, server);
      await _press(tester, _editButton(id));
      expect(_textField(tester, _field(id)).controller!.text, 'Hi @$_otherName');

      await _type(tester, _field(id), 'Hello @$_otherName');
      await _press(tester, _save(id));
      expect(_commentsOn(server, 'task-1'), ['Hello $tag']);
    });

    testBothLayouts('can add a mention', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Hi')['id'] as String;
      await _open(tester, size, server);
      await _press(tester, _editButton(id));
      await _press(tester, _mentionButton('comment-field-$id'));
      await tester.tap(_person(_otherId));
      await tester.pumpAndSettle();
      await _press(tester, _save(id));
      expect(_commentsOn(server, 'task-1'), ['Hi ${mentionTag(_otherId, _otherName)}']);
    });

    testBothLayouts('changing nothing sends nothing', (tester, size) async {
      final server = _quietServer();
      final source = 'Hi ${mentionTag(_otherId, _otherName)}  \n';
      final id = server.addComment('task-1', source)['id'] as String;
      await _open(tester, size, server);
      await _press(tester, _editButton(id));
      await _press(tester, _save(id));
      expect(server.requestsTo(_commentPath, method: 'PUT'), isEmpty);
      expect(_field(id), findsNothing);
    });

    testBothLayouts('cancelling leaves it as it was, and starts over next time', (
      tester,
      size,
    ) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Original')['id'] as String;
      await _open(tester, size, server);
      await _press(tester, _editButton(id));
      await _type(tester, _field(id), 'Changed my mind');
      await _press(tester, _cancel(id));

      expect(server.requestsTo(_commentPath, method: 'PUT'), isEmpty);
      expect(_text('Original'), findsOneWidget);

      await _press(tester, _editButton(id));
      expect(_textField(tester, _field(id)).controller!.text, 'Original');
    });

    testBothLayouts('can\'t be emptied', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Words')['id'] as String;
      await _open(tester, size, server);
      await _press(tester, _editButton(id));
      await _type(tester, _field(id), '  ');
      expect(tester.widget<FilledButton>(_save(id)).onPressed, isNull);
    });

    testBothLayouts('a failure says why and stays open with the words', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Before')['id'] as String;
      await _open(tester, size, server);
      await _press(tester, _editButton(id));
      await _type(tester, _field(id), 'After');
      server.failNext(_commentPath, status: 500);
      await _press(tester, _save(id));

      expect(_textField(tester, _field(id)).controller!.text, 'After');
      expect(_commentsOn(server, 'task-1'), ['Before']);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('deleting a comment', () {
    Future<void> confirm(WidgetTester tester, TestApp app) async {
      await tester.tap(find.widgetWithText(FilledButton, app.i18n.t('mobile:common.delete')));
      await tester.pumpAndSettle();
    }

    testBothLayouts('asks first, then it is gone', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Bye')['id'] as String;
      final app = await _open(tester, size, server);
      await _press(tester, _deleteButton(id));
      expect(find.text(app.i18n.t('mobile:taskDetail.activity.deleteTitle')), findsOneWidget);
      expect(server.requestsTo(_commentPath, method: 'DELETE'), isEmpty);

      await confirm(tester, app);
      expect(_commentsOn(server, 'task-1'), isEmpty);
      expect(_comment(id), findsNothing);
    });

    testBothLayouts('saying no leaves it', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Stay')['id'] as String;
      final app = await _open(tester, size, server);
      await _press(tester, _deleteButton(id));
      await tester.tap(find.text(app.i18n.t('mobile:common.cancel')));
      await tester.pumpAndSettle();

      expect(server.requestsTo(_commentPath, method: 'DELETE'), isEmpty);
      expect(_comment(id), findsOneWidget);
    });

    testBothLayouts('a failure says why and leaves it', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Stay')['id'] as String;
      final app = await _open(tester, size, server);
      await _press(tester, _deleteButton(id));
      server.failNext(_commentPath, status: 500);
      await confirm(tester, app);

      expect(_comment(id), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.widget<IconButton>(_deleteButton(id)).onPressed, isNotNull);
    });
  });

  group('whose comment it is', () {
    testBothLayouts('your own can be changed, someone else\'s can\'t', (tester, size) async {
      final server = _quietServer();
      final mine = server.addComment('task-1', 'Mine')['id'] as String;
      final theirs = server.addComment('task-1', 'Theirs', authorId: _otherId)['id'] as String;
      await _open(tester, size, server);

      expect(_editButton(mine), findsOneWidget);
      expect(_deleteButton(mine), findsOneWidget);
      expect(_editButton(theirs), findsNothing);
      expect(_deleteButton(theirs), findsNothing);
      expect(_text('Theirs'), findsOneWidget);
    });

    testBothLayouts('nothing appears on someone else\'s with a long press or right-click', (
      tester,
      size,
    ) async {
      final server = _quietServer();
      final theirs = server.addComment('task-1', 'Theirs', authorId: _otherId)['id'] as String;
      await _open(tester, size, server);
      await tester.ensureVisible(_comment(theirs));
      await tester.pumpAndSettle();
      await tester.longPress(_comment(theirs));
      await tester.pumpAndSettle();
      expect(find.byType(PopoverRow), findsNothing);
    });

    testBothLayouts('an imported comment can\'t be changed by who imported it', (
      tester,
      size,
    ) async {
      final server = _quietServer();
      final id =
          server.addComment(
                'task-1',
                'From GitHub',
                externalUserName: 'octocat',
                externalSource: 'github',
              )['id']
              as String;
      await _open(tester, size, server);
      expect(_rich('octocat'), findsOneWidget);
      expect(_editButton(id), findsNothing);
      expect(_deleteButton(id), findsNothing);
    });

    testBothLayouts('without permission to change tasks, there is nothing to do but read', (
      tester,
      size,
    ) async {
      final server = _quietServer()..capabilities['updateTasks'] = false;
      final mine = server.addComment('task-1', 'Mine')['id'] as String;
      await _open(tester, size, server);

      expect(_text('Mine'), findsOneWidget);
      expect(_editButton(mine), findsNothing);
      expect(_deleteButton(mine), findsNothing);
      expect(_box, findsNothing);
      expect(_send, findsNothing);
    });

    testBothLayouts('permissions that can\'t be read leave it to the server', (tester, size) async {
      final server = _quietServer()..fail('capabilities', status: 500);
      final mine = server.addComment('task-1', 'Mine')['id'] as String;
      await _open(tester, size, server);
      expect(_box, findsOneWidget);
      expect(_editButton(mine), findsOneWidget);
    });

    testBothLayouts('a refusal from the server says why', (tester, size) async {
      final server = _quietServer();
      final id = server.addComment('task-1', 'Mine')['id'] as String;
      final app = await _open(tester, size, server);
      // Someone else's now, as far as the server knows.
      server.activities.single['userId'] = _otherId;
      await _press(tester, _deleteButton(id));
      await tester.tap(find.widgetWithText(FilledButton, app.i18n.t('mobile:common.delete')));
      await tester.pumpAndSettle();

      expect(find.text('Comment not found or you are not the author'), findsOneWidget);
      expect(server.activities, hasLength(1));
    });
  });

  group('the rules', () {
    Activity activity({
      String type = 'comment',
      String? content = 'Words',
      String? userId = 'me',
      String? externalSource,
      String createdAt = '2026-11-06T12:00:00.000Z',
      String? updatedAt,
    }) => Activity(
      id: 'a',
      taskId: 't',
      type: type,
      createdAt: createdAt,
      updatedAt: updatedAt,
      userId: userId,
      content: content,
      externalSource: externalSource,
    );

    test('only a comment with words is shown as one', () {
      expect(isCommentEntry(activity()), isTrue);
      expect(isCommentEntry(activity(content: '')), isFalse);
      expect(isCommentEntry(activity(content: null)), isFalse);
      expect(isCommentEntry(activity(type: 'status_changed')), isFalse);
    });

    test('only the author can change a comment', () {
      expect(canChangeComment(activity(), 'me'), isTrue);
      expect(canChangeComment(activity(), 'you'), isFalse);
      expect(canChangeComment(activity(userId: null), null), isFalse);
      expect(canChangeComment(activity(type: 'status_changed'), 'me'), isFalse);
      expect(canChangeComment(activity(externalSource: 'github'), 'me'), isFalse);
    });

    test('edited means the times differ', () {
      expect(wasEdited(activity()), isFalse);
      expect(wasEdited(activity(updatedAt: '2026-11-06T12:00:00.000Z')), isFalse);
      expect(wasEdited(activity(updatedAt: '2026-11-06T12:00:01.000Z')), isTrue);
    });

    test('an imported event goes by the name it came with', () {
      final imported = Activity(
        id: 'a',
        taskId: 't',
        type: 'comment',
        createdAt: '2026-11-06T12:00:00.000Z',
        userId: 'me',
        externalUserName: 'octocat',
        externalSource: 'github',
      );
      expect(feedEntry(imported, userName: 'Me').userName, isNull);
      expect(feedEntry(imported, userName: 'Me').externalUserName, 'octocat');
      expect(feedEntry(activity(), userName: 'Me').userName, 'Me');
    });

    group('people to mention', () {
      const ana = WorkspaceMember(id: '1', name: 'Ana Maria', email: 'a@x.test', role: 'member');
      const bo = WorkspaceMember(id: '2', name: '张三', email: 'b@x.test', role: 'member');
      const unnamed = WorkspaceMember(id: '3', name: ' ', email: 'c@x.test', role: 'member');

      test('are found by any part of the name, in any case', () {
        expect(peopleMatching(const [ana, bo], 'mar'), [ana]);
        expect(peopleMatching(const [ana, bo], '张'), [bo]);
        expect(peopleMatching(const [ana, bo], 'zzz'), isEmpty);
      });

      test('an empty query offers everyone, up to a limit', () {
        expect(peopleMatching(const [ana, bo], ''), [ana, bo]);
        expect(peopleMatching(List.filled(20, ana), ''), hasLength(8));
      });

      test('with no name, go by their address', () {
        expect(mentionName(unnamed), 'c@x.test');
        expect(peopleMatching(const [unnamed], 'c@'), [unnamed]);
      });
    });
  });
}
