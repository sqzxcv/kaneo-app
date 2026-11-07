import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../../support/test_app.dart';

const _feed = 'api/activity/workspace/';
const _comment = 'A first comment.';
const _new = 'Written meanwhile.';

void _go(TestApp app, String location) => app.container.read(routerProvider).go(location);

/// Lets requests that aren't held through, without waiting for anything else to finish.
Future<void> _letRequestsThrough(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<TestApp> _open(WidgetTester tester, FakeKaneo server, Size size) =>
    pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.activity);

void main() {
  group('the feed', () {
    testBothLayouts('says who did what, to which task and when', (tester, size) async {
      final server = FakeKaneo();
      server.activities.insert(0, {
        ...server.activities.first,
        'id': 'status-change',
        'type': 'status_changed',
        'taskId': 'task-3',
        'eventData': {'oldStatus': 'to-do', 'newStatus': 'done'},
      });
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.activity,
        overrides: [nowProvider.overrideWithValue(() => DateTime.utc(2026, 11, 6, 15))],
      );
      expect(
        inPage(find.text('Test User changed status from To Do to Done', findRichText: true)),
        findsOneWidget,
      );
      expect(inPage(find.text('Test User commented', findRichText: true)), findsOneWidget);
      expect(inPage(find.text(_comment)), findsOneWidget);
      expect(inPage(find.text('DEMO-3')), findsWidgets);
      expect(inPage(find.text('Review the board layout')), findsWidgets);
      expect(inPage(find.text(app.i18n.t('mobile:time.hoursAgo', {'count': 3}))), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('the excerpt only goes with comments', (tester, size) async {
      final server = FakeKaneo();
      server.activities.insert(0, {
        ...server.activities.first,
        'id': 'old-event',
        'type': 'something_old',
        'eventData': null,
        'content': 'renamed it long ago',
      });
      await _open(tester, server, size);
      expect(
        inPage(find.text('Test User renamed it long ago', findRichText: true)),
        findsOneWidget,
      );
      expect(inPage(find.text('renamed it long ago')), findsNothing);
    });

    testBothLayouts('a comment reads as plain words, not as the markup it is kept in', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.addComment('task-2', 'About **this** one');
      await _open(tester, server, size);
      expect(inPage(find.text('About this one')), findsOneWidget);
    });

    testWidgets('stays a reading column on a wide window', (tester) async {
      await _open(tester, FakeKaneo(), wideSize);
      expect(tester.getSize(inPage(find.byType(ListView))).width, contentMaxWidth);
    });

    testBothLayouts('a long title does not push the time off the row', (tester, size) async {
      final server = FakeKaneo();
      server.addTask(title: 'A very long title ' * 30);
      await _open(tester, server, size);
      expect(tester.takeException(), isNull);
    });
  });

  group('opening a task', () {
    testBothLayouts('any entry opens its task', (tester, size) async {
      final app = await _open(tester, FakeKaneo(), size);
      await tester.tap(inPage(find.text('Review the board layout')));
      await tester.pumpAndSettle();
      expect(taskOpen('task-3'), findsOneWidget);

      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(taskOpen('task-3'), findsNothing);
    });

    testBothLayouts('a comment opens the task it is on', (tester, size) async {
      await _open(tester, FakeKaneo(), size);
      await tester.tap(inPage(find.text(_comment)));
      await tester.pumpAndSettle();
      expect(taskOpen('task-1'), findsOneWidget);
    });

    testBothLayouts('closing the task looks again, with the entries still there', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      await tester.tap(inPage(find.text(_comment)));
      await tester.pumpAndSettle();
      final before = server.requestsTo(_feed).length;

      server.addComment('task-2', _new);
      final gate = server.hold(_feed);
      app.container.read(routerProvider).pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(inPage(find.text(_comment)), findsOneWidget);
      expect(inPage(find.text(_new)), findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text(_new)), findsOneWidget);
      expect(server.requestsTo(_feed).length, before + 1);
    });
  });

  group('coming back to the page', () {
    testBothLayouts('shows what was there at once, then what is new', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      expect(inPage(find.text(_comment)), findsOneWidget);
      _go(app, AppRoutes.myTasks);
      await tester.pumpAndSettle();
      expect(inPage(find.text(_comment)), findsNothing);

      server.addComment('task-2', _new);
      final before = server.requestsTo(_feed).length;
      final gate = server.hold(_feed);
      _go(app, AppRoutes.activity);
      await tester.pump();
      expect(inPage(find.text(_comment)), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _letRequestsThrough(tester);
      expect(inPage(find.text(_new)), findsNothing);
      expect(server.requestsTo(_feed).length, before + 1);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text(_new)), findsOneWidget);
      expect(inPage(find.text(_comment)), findsOneWidget);
    });

    testBothLayouts('keeps what was there when looking again fails', (tester, size) async {
      final server = FakeKaneo();
      final app = await _open(tester, server, size);
      _go(app, AppRoutes.myTasks);
      await tester.pumpAndSettle();

      server.fail(_feed, status: 500);
      _go(app, AppRoutes.activity);
      await tester.pumpAndSettle();
      expect(inPage(find.text(_comment)), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsNothing);
    });
  });

  group('the other states', () {
    testBothLayouts('waiting for the first answer', (tester, size) async {
      final server = FakeKaneo();
      final gate = server.hold(_feed);
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.activity,
        settle: false,
      );
      await _letRequestsThrough(tester);
      expect(inPage(find.byType(CircularProgressIndicator)), findsOneWidget);

      gate.release();
      await tester.pumpAndSettle();
      expect(inPage(find.text(_comment)), findsOneWidget);
    });

    testBothLayouts('a failure says so, and retrying gets the feed', (tester, size) async {
      final server = FakeKaneo()..failNext(_feed, status: 500);
      final app = await _open(tester, server, size);
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);

      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(inPage(find.text(_comment)), findsOneWidget);
    });

    testBothLayouts('no permission says so, with nothing to retry', (tester, size) async {
      final server = FakeKaneo()..fail(_feed, status: 403);
      final app = await _open(tester, server, size);
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
    });

    testBothLayouts('nothing has happened', (tester, size) async {
      final app = await _open(tester, FakeKaneo.empty(), size);
      expect(find.text(app.i18n.t('mobile:activity.empty')), findsOneWidget);
    });
  });
}
