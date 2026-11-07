// Runs a background check with the real plugins against the local Kaneo, on a phone or tablet. Needs
// `tool/local_kaneo.sh start` and a device from the queue:
//
//     tool/with_device.sh --boot "iPhone 17" flutter test \
//       integration_test/background_notifications_test.dart -d "iPhone 17" \
//       --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// A simulator can't run a BGTask or answer the system's permission prompt, so the OS starting the
// task and showing the banner are left for a real device.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/notifications/notification_check.dart';
import 'package:kaneo_app/features/notifications/notification_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = String.fromEnvironment('KANEO_DEV_SERVER_URL');

/// The real host, keeping track of what it was given.
class _RecordingHost extends NativeNotificationHost {
  final titles = <String>[];
  final payloads = <String>[];

  @override
  Future<void> show({
    required int id,
    required String title,
    String? body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async {
    await super.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      channelName: channelName,
      channelDescription: channelDescription,
    );
    titles.add(title);
    payloads.add(payload);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the real plugins read the session, schedule the task and post what is new', (
    tester,
  ) async {
    expect(_server, isNotEmpty, reason: 'Pass dev.env with --dart-define-from-file.');
    final i18n = await I18n.load(locale: defaultLocale);
    final session =
        await Authentication(
          ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {}),
          i18n,
        ).withPassword(
          _server,
          const String.fromEnvironment('KANEO_DEV_EMAIL'),
          const String.fromEnvironment('KANEO_DEV_PASSWORD'),
        );
    final api = KaneoApi(
      ApiClient(session: () => session, i18n: i18n, onSessionExpired: (_) {}),
      i18n,
    );
    addTearDown(api.signOut);

    final storage = SecureSessionStorage(key: 'kaneo.test.background');
    await storage.write(session);
    addTearDown(storage.clear);
    expect((await storage.read())?.token, session.token);

    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    addTearDown(() async {
      await prefs.clear();
      for (final MapEntry(:key, :value) in saved.entries) {
        if (value is bool) await prefs.setBool(key, value);
        if (value is String) await prefs.setString(key, value);
      }
    });
    await prefs.clear();
    await prefs.setBool(notificationChecksEnabledKey, true);
    await prefs.setString(languageChoiceKey, defaultLocale);

    final host = _RecordingHost();
    await host.initialize(null);
    expect(await host.launchPayload(), isNull);
    await host.schedule();
    addTearDown(host.unschedule);

    Future<void> check() => runBackgroundCheck(host: host, storage: storage);
    await check();
    expect(host.titles, isEmpty, reason: 'The first check shows no history');

    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final name = 'A-Notifications-$stamp';
    final workspace = await api.createWorkspace(name: name, slug: name.toLowerCase());
    addTearDown(() => api.deleteWorkspace(workspace.id));
    final project = await api.createProject(
      name: name,
      workspaceId: workspace.id,
      icon: 'Layout',
      slug: 'A${stamp.toUpperCase()}',
    );
    addTearDown(() => api.deleteProject(project.id));
    final task = await api.createTask(
      project.id,
      const CreateTaskBody(
        title: 'A-Notification task',
        description: '',
        priority: 'no-priority',
        status: 'to-do',
      ),
    );
    addTearDown(() => api.clearAllNotifications(workspaceId: workspace.id));
    await api.client.request(
      'api/notification',
      method: 'POST',
      body: {
        'title': name,
        'message': 'A real notification',
        'type': 'info',
        'relatedEntityId': task.id,
        'relatedEntityType': 'task',
      },
    );

    await check();
    // Other lines share this account, so theirs can show up too.
    final posted = host.titles.indexOf(name);
    expect(posted, isNonNegative);
    expect(decodeNotice(host.payloads[posted])?.taskId, task.id);
    await host.clear();
  }, skip: !Platform.isIOS && !Platform.isAndroid);
}
