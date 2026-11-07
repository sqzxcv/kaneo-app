import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/test_app.dart';
import 'fake_desktop_host.dart';

InboxNotification notice(
  String id, {
  String userId = FakeKaneo.userId,
  bool isRead = false,
  String? taskId = 'task-1',
}) => InboxNotification(
  id: id,
  userId: userId,
  title: 'Notice $id',
  content: 'Task changed',
  type: 'task_assigned',
  resourceId: taskId,
  resourceType: taskId == null ? 'workspace' : 'task',
  isRead: isRead,
  createdAt: '2026-11-06T12:00:00Z',
);

void main() {
  test('desktop minimum keeps the shorter side above the wide breakpoint', () {
    expect(usableDesktopWindowSize(const Size(300, 300)), minimumDesktopWindowSize);
    expect(usableDesktopWindowSize(const Size(1400, 1000)), const Size(1400, 1000));
    expect(usableDesktopWindowSize(const Size(1400, 300)), const Size(1400, 700));
    expect(minimumDesktopWindowSize.shortestSide - 100, greaterThanOrEqualTo(600));
  });

  late FakeDesktopHost host;
  late DesktopRuntime runtime;
  late List<InboxNotification> data;
  late List<String?> opened;
  late bool preference;
  late int errors;
  Future<List<InboxNotification>> Function()? pendingLoad;

  setUp(() {
    host = FakeDesktopHost();
    data = [notice('existing')];
    opened = [];
    preference = true;
    errors = 0;
    pendingLoad = null;
    runtime = DesktopRuntime(
      host: host,
      load: () async => pendingLoad != null ? pendingLoad!() : data,
      open: opened.add,
      hasPreference: () => preference,
      rememberPermission: (allowed) async {
        preference = true;
        await runtime.setEnabled(allowed);
      },
      actionLabel: 'Open',
      fallbackBody: 'New activity',
      summary: (n) => '$n new notifications',
      onUnavailable: () => errors++,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(runtime.dispose);
  });

  Future<void> start({bool enabled = true}) async {
    await runtime.setSession(testSession);
    await runtime.setEnabled(enabled);
    await runtime.start();
  }

  test('first batch establishes a baseline; new unread notices show and open their task', () async {
    await start();
    expect(host.notices, isEmpty);
    data = [...data, notice('new')];
    await runtime.check();
    expect(host.notices.single.title, 'Notice new');
    expect(host.notices.single.payload, isNot(contains(testSession.token)));
    await runtime.activate(host.notices.single.payload);
    expect(opened, ['task-1']);
    expect(host.foregrounds, 1);
    await runtime.check();
    expect(host.notices, hasLength(1));
  });

  test('first launch asks native permission once and remembers the answer', () async {
    preference = false;
    await start(enabled: false);
    expect(preference, isTrue);
    expect(host.permissionRequests, 1);
    data = [...data, notice('new')];
    await runtime.check();
    expect(host.notices, hasLength(1));
  });

  test('denied permissions and an explicit off switch do not poll or prompt repeatedly', () async {
    var loads = 0;
    pendingLoad = () async {
      loads++;
      return data;
    };
    await start(enabled: false);
    await runtime.check();
    expect(loads, 0);
    expect(host.permissionRequests, 0);
    host.allowed = false;
    await runtime.setEnabled(true);
    await runtime.check();
    expect(loads, 0);
    expect(host.permissionRequests, 1);
  });

  test('opting in again rechecks permission after the user changes OS settings', () async {
    host.allowed = false;
    await start();
    expect(host.permissionRequests, 1);
    await runtime.setEnabled(false);
    host.allowed = true;
    await runtime.setEnabled(true);
    expect(host.permissionRequests, 2);
    data = [...data, notice('after-grant')];
    await runtime.check();
    expect(host.notices.single.title, 'Notice after-grant');
  });

  test('read notices and notifications for another user are never shown', () async {
    await start();
    data = [...data, notice('read', isRead: true), notice('other', userId: 'someone-else')];
    await runtime.check();
    expect(host.notices, isEmpty);
  });

  test('structured server events show the task title when legacy text is absent', () async {
    await start();
    data = [
      ...data,
      notice('structured').copyWith(content: null, eventData: {'taskTitle': 'Release checklist'}),
    ];
    await runtime.check();
    expect(host.notices.single.body, 'Release checklist');
  });

  test('large batches become a summary and four recent notifications', () async {
    await start();
    data = [...data, for (var i = 0; i < 9; i++) notice('new-$i')];
    await runtime.check();
    expect(host.notices, hasLength(5));
    expect(host.notices.first.body, '5 new notifications');
    await runtime.activate(host.notices.first.payload);
    expect(opened, [null]);
  });

  test('late responses and clicks from a signed-out account are discarded', () async {
    await start();
    data = [...data, notice('shown')];
    await runtime.check();
    final oldPayload = host.notices.single.payload;
    final delayed = Completer<List<InboxNotification>>();
    pendingLoad = () => delayed.future;
    final check = runtime.check();
    await runtime.setSession(null);
    delayed.complete([notice('late')]);
    await check;
    await runtime.activate(oldPayload);
    expect(host.notices, isEmpty);
    expect(opened, isEmpty);
  });

  test('account switch establishes a fresh baseline and clears notifications', () async {
    await start();
    data = [...data, notice('shown')];
    await runtime.check();
    final payload = host.notices.single.payload;
    const other = Session(
      serverUrl: FakeKaneo.serverUrl,
      credentialType: CredentialType.apiKey,
      token: 'another-key',
      userId: 'other',
      userName: 'Other',
      userEmail: 'other@example.com',
    );
    data = [notice('other-old', userId: 'other')];
    await runtime.setSession(other);
    await runtime.activate(payload);
    expect(host.notices, isEmpty);
    expect(opened, isEmpty);
    data = [...data, notice('other-new', userId: 'other')];
    await runtime.check();
    expect(host.notices.single.title, 'Notice other-new');
  });

  test('disabling checks cancels displayed notices and rejects pending clicks', () async {
    await start();
    data = [...data, notice('shown')];
    await runtime.check();
    final payload = host.notices.single.payload;
    await runtime.setEnabled(false);
    await runtime.activate(payload);
    await runtime.check();
    expect(host.notices, isEmpty);
    expect(opened, isEmpty);
  });

  test('network errors retain the baseline and recover on the next check', () async {
    await start();
    pendingLoad = () async => throw const ApiError('offline');
    await runtime.check();
    pendingLoad = null;
    data = [...data, notice('after-reconnect')];
    await runtime.check();
    expect(host.notices.single.title, 'Notice after-reconnect');
    expect(errors, 0);
  });

  test('overlapping checks for the same login only load once', () async {
    await start();
    var loads = 0;
    final gate = Completer<List<InboxNotification>>();
    pendingLoad = () {
      loads++;
      return gate.future;
    };
    final first = runtime.check();
    await runtime.check();
    expect(loads, 1);
    gate.complete(data);
    await first;
  });
}
