import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/core.dart';
import '../inbox/notification_text.dart';
import '../inbox/notifications.dart';

/// Set while the app is on screen. The background task runs in an isolate of its own, so this is
/// how it knows. Android can run it with the app open, and what arrives then is already in view.
const notificationForegroundKey = 'kaneo.notifications.foreground';

const _seenKey = 'kaneo.notifications.seen';

const _appName = 'Kaneo';

/// At most this many notifications from one check, as the current app has it.
const int _maxPosted = 5;

/// The server lists the 50 newest. Remembering more keeps an old one from counting as new when
/// deleting newer ones brings it back into that list.
const int _maxRemembered = 200;

/// The OS boundary. Tests replace this while exercising the actual account and routing logic.
abstract class NotificationHost {
  /// [onTap] is left out by the background task, which has no pages to open.
  Future<void> initialize(void Function(String? payload)? onTap);

  /// The payload of the notification whose tap launched the app, if one did.
  Future<String?> launchPayload();

  Future<bool> requestPermission();

  /// Has the OS run the background check from now on. The same as before if it already does.
  Future<void> schedule();

  Future<void> unschedule();

  Future<void> show({
    required int id,
    required String title,
    String? body,
    required String payload,
    required String channelName,
    required String channelDescription,
  });

  /// Removes everything this app has showing.
  Future<void> clear();
}

/// Which account a notification and what was seen belong to.
String accountScope(Session session) => '${session.serverUrl}|${session.userId}';

bool sameLogin(Session? a, Session? b) =>
    a?.token == b?.token && a?.serverUrl == b?.serverUrl && a?.userId == b?.userId;

/// What a tap on a notification needs. The account is there so that a notification still showing
/// can't open anything once someone else is signed in.
String encodeNotice(String account, String? taskId) =>
    jsonEncode({'account': account, 'taskId': taskId});

({String account, String? taskId})? decodeNotice(String? payload) {
  if (payload == null) return null;
  try {
    final notice = jsonDecode(payload);
    if (notice is! Map) return null;
    final account = notice['account'];
    final taskId = notice['taskId'];
    if (account is! String || (taskId != null && taskId is! String)) return null;
    return (account: account, taskId: taskId as String?);
  } on FormatException {
    return null;
  }
}

/// Past the cap, the oldest fold into one summary rather than being dropped. [fresh] goes from old
/// to new.
({int hidden, List<InboxNotification> shown}) foldBacklog(List<InboxNotification> fresh) {
  if (fresh.length <= _maxPosted) return (hidden: 0, shown: fresh);
  final kept = _maxPosted - 1;
  return (hidden: fresh.length - kept, shown: fresh.sublist(fresh.length - kept));
}

/// One look at the inbox, from the background task or from the app. What has been seen is kept per
/// account in the preferences, because each background run starts from nothing.
class NotificationCheck {
  const NotificationCheck({
    required this.prefs,
    required this.i18n,
    required this.host,
    required this.readSession,
    required this.load,
  });

  final SharedPreferences prefs;
  final I18n i18n;
  final NotificationHost host;
  final Future<Session?> Function() readSession;
  final Future<List<InboxNotification>> Function(Session session) load;

  /// Shows what is new since the last check. With [post] false it only takes note of it, for when
  /// the app itself is showing it.
  ///
  /// The first check for an account does the same, so that the history is never replayed.
  Future<void> run({required bool post}) async {
    final session = await _activeSession();
    if (session == null) return;
    final notifications = await load(session);
    // Signing out, switching accounts or turning this off during the request drops the answer.
    if (!sameLogin(session, await _activeSession())) return;

    final current = notifications.where((n) => n.userId == session.userId).toList();
    final account = accountScope(session);
    final seen = _seen(account);
    await _remember(account, current, seen);
    if (!post || seen == null) return;

    final fresh = current.where((n) => isUnread(n) && !seen.contains(n.id)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final backlog = foldBacklog(fresh);
    if (backlog.hidden > 0) {
      await _show(
        session,
        // The oldest is only ever part of the summary, which leaves its id free.
        id: fresh.first.id.hashCode,
        title: _appName,
        body: i18n.t('mobile:background.summary', {'count': backlog.hidden}),
      );
    }
    for (final notification in backlog.shown) {
      final text = describeNotification(i18n, notification);
      await _show(
        session,
        id: notification.id.hashCode,
        title: text.title.isEmpty ? _appName : text.title,
        body: text.content,
        taskId: notificationTaskId(notification),
      );
    }
  }

  /// Forgets what was seen, so that the next check starts over.
  Future<void> forget() => prefs.remove(_seenKey);

  /// Who this is checking for, or null when notifications are off or no one is signed in.
  Future<Session?> _activeSession() async {
    // Another isolate may have changed them. Each isolate otherwise keeps its own copy.
    await prefs.reload();
    if (prefs.getBool(notificationChecksEnabledKey) != true) return null;
    return readSession();
  }

  Future<void> _show(
    Session session, {
    required int id,
    required String title,
    String? body,
    String? taskId,
  }) async {
    if (!sameLogin(session, await _activeSession())) return;
    await host.show(
      id: id,
      title: title,
      body: body,
      payload: encodeNotice(accountScope(session), taskId),
      channelName: i18n.t('mobile:background.channelName'),
      channelDescription: i18n.t('mobile:background.channelDescription'),
    );
  }

  /// The ids seen for [account], or null if it hasn't been checked yet.
  Set<String>? _seen(String account) {
    final raw = prefs.getString(_seenKey);
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map || saved['account'] != account) return null;
      return (saved['ids'] as List).cast<String>().toSet();
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _remember(String account, List<InboxNotification> current, Set<String>? seen) =>
      prefs.setString(
        _seenKey,
        jsonEncode({
          'account': account,
          'ids': {...current.map((n) => n.id), ...?seen}.take(_maxRemembered).toList(),
        }),
      );
}
