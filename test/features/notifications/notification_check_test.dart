import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/notifications/notification_check.dart';
import 'package:kaneo_app/features/notifications/notification_host.dart';

InboxNotification _notification(int index) => InboxNotification(
  id: 'n$index',
  userId: 'user',
  type: 'task_created',
  createdAt: '2026-11-06T12:00:${index.toString().padLeft(2, '0')}.000Z',
);

List<InboxNotification> _notifications(int count) => [
  for (var i = 0; i < count; i++) _notification(i),
];

void main() {
  group('foldBacklog', () {
    test('leaves up to five alone', () {
      for (final count in [0, 1, 5]) {
        final backlog = foldBacklog(_notifications(count));
        expect(backlog.hidden, 0);
        expect(backlog.shown, hasLength(count));
      }
    });

    test('past five, keeps the four newest and folds the rest', () {
      final backlog = foldBacklog(_notifications(6));
      expect(backlog.hidden, 2);
      expect(backlog.shown.map((n) => n.id), ['n2', 'n3', 'n4', 'n5']);
    });

    test('counts everything it folds', () {
      final backlog = foldBacklog(_notifications(50));
      expect(backlog.hidden, 46);
      expect(backlog.shown, hasLength(4));
    });
  });

  group('the payload of a notification', () {
    test('comes back as it went in', () {
      final withTask = decodeNotice(encodeNotice('account', 'task-1'))!;
      expect(withTask.account, 'account');
      expect(withTask.taskId, 'task-1');
      expect(decodeNotice(encodeNotice('account', null))!.taskId, isNull);
    });

    test('is ignored when it is not one of ours', () {
      for (final payload in [
        null,
        '',
        'not json',
        '[]',
        '{}',
        '{"account":1}',
        '{"account":"a","taskId":2}',
      ]) {
        expect(decodeNotice(payload), isNull, reason: '$payload');
      }
    });
  });

  group('sameLogin', () {
    const session = Session(
      serverUrl: 'https://a.example',
      credentialType: CredentialType.apiKey,
      token: 'token',
      userId: 'user',
      userName: 'User',
      userEmail: 'user@example.invalid',
    );

    test('tells accounts, servers and tokens apart', () {
      expect(sameLogin(session, session), isTrue);
      expect(sameLogin(null, null), isTrue);
      expect(sameLogin(session, null), isFalse);
      for (final other in [
        const Session(
          serverUrl: 'https://b.example',
          credentialType: CredentialType.apiKey,
          token: 'token',
          userId: 'user',
          userName: 'User',
          userEmail: 'user@example.invalid',
        ),
        const Session(
          serverUrl: 'https://a.example',
          credentialType: CredentialType.apiKey,
          token: 'other',
          userId: 'user',
          userName: 'User',
          userEmail: 'user@example.invalid',
        ),
        const Session(
          serverUrl: 'https://a.example',
          credentialType: CredentialType.apiKey,
          token: 'token',
          userId: 'other',
          userName: 'User',
          userEmail: 'user@example.invalid',
        ),
      ]) {
        expect(sameLogin(session, other), isFalse);
      }
    });

    test('an account is its server and user', () {
      expect(accountScope(session), 'https://a.example|user');
    });
  });

  group('what iOS is told', () {
    test('the background task is declared where iOS looks for it', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<string>$notificationCheckTask</string>'));
      expect(plist, contains('<string>fetch</string>'));
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(delegate, contains('"$notificationCheckTask"'));
      expect(delegate, contains('${notificationCheckInterval.inMinutes} * 60'));
    });

    test('the session can be read while the phone is locked', () {
      expect(SecureSessionStorage.iOSOptions.toMap()['accessibility'], 'first_unlock');
    });
  });
}
