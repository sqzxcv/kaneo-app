import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/core.dart';
import 'notification_check.dart';

/// The background task, on both platforms. iOS also needs it in `Info.plist` and `AppDelegate`.
const notificationCheckTask = 'app.kaneo.kaneoApp.notificationCheck';

/// How often the OS is asked to run it. Android's minimum, and iOS treats it as a hint.
const notificationCheckInterval = Duration(minutes: 15);

const _androidChannelId = 'kaneo_activity';

/// iOS and Android. The desktop apps have `DesktopRuntime`, which checks while they run. A test
/// runs on neither, unless it replaces this.
final backgroundChecksSupportedProvider = Provider<bool>(
  (_) => Platform.isIOS || Platform.isAndroid,
);

final notificationHostProvider = Provider<NotificationHost>((_) => NativeNotificationHost());

class NativeNotificationHost implements NotificationHost {
  final _notifications = FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize(void Function(String? payload)? onTap) async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (response) => onTap(response.payload),
    );
  }

  @override
  Future<String?> launchPayload() async {
    final launch = await _notifications.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true ? launch?.notificationResponse?.payload : null;
  }

  @override
  Future<bool> requestPermission() async {
    final allowed = Platform.isIOS
        ? await _notifications
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true)
        : await _notifications
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
    return allowed ?? false;
  }

  @override
  Future<void> schedule() async {
    await Workmanager().initialize(notificationCheckDispatcher);
    await Workmanager().registerPeriodicTask(
      notificationCheckTask,
      notificationCheckTask,
      frequency: notificationCheckInterval,
      // The app takes note of what's there as it goes to the background, so there's no need for one
      // right away. iOS would otherwise be free to run it at once on every launch.
      initialDelay: notificationCheckInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  @override
  Future<void> unschedule() => Workmanager().cancelByUniqueName(notificationCheckTask);

  @override
  Future<void> show({
    required int id,
    required String title,
    String? body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) => _notifications.show(
    id: id,
    title: title,
    body: body,
    payload: payload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        channelName,
        channelDescription: channelDescription,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );

  @override
  Future<void> clear() => _notifications.cancelAll();
}

/// What the OS starts for the background task, without the app or anything from `bootstrap()`.
@pragma('vm:entry-point')
void notificationCheckDispatcher() {
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBackgroundCheck();
    } on Exception {
      // Offline, a rejected token, or a device that hasn't been unlocked since it started. The next
      // run tries again, and returning failure would only have Android retry sooner than that.
    }
    return true;
  });
}

/// One run of the background task. A rejected token is left for the app to deal with when it opens.
///
/// The parameters are for tests.
Future<void> runBackgroundCheck({
  @visibleForTesting NotificationHost? host,
  @visibleForTesting SessionStorage? storage,
  @visibleForTesting HttpClientAdapter? adapter,
  @visibleForTesting CatalogReader? catalogs,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (prefs.getBool(notificationChecksEnabledKey) != true ||
      prefs.getBool(notificationForegroundKey) == true) {
    return;
  }

  final i18n = await I18n.load(
    locale: activeLocale(prefs.getString(languageChoiceKey) ?? systemLanguage),
    read: catalogs,
  );
  final notifications = host ?? NativeNotificationHost();
  await notifications.initialize(null);

  Session? session;
  final api = KaneoApi(
    ApiClient(session: () => session, i18n: i18n, onSessionExpired: (_) {}, adapter: adapter),
    i18n,
  );
  await NotificationCheck(
    prefs: prefs,
    i18n: i18n,
    host: notifications,
    readSession: (storage ?? SecureSessionStorage()).read,
    load: (current) {
      session = current;
      return api.notifications();
    },
  ).run(post: true);
}
