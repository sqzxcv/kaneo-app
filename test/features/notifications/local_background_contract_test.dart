// Run with the private local dev.env. It owns every workspace, project and notification it creates,
// and never marks the shared development account's notifications as read.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/notifications/notification_check.dart';
import 'package:kaneo_app/features/notifications/notification_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_notification_host.dart';

const _server = String.fromEnvironment('KANEO_DEV_SERVER_URL');

void main() {
  test('a real notification reaches the background check and leads to its task', () async {
    expect(['localhost', '127.0.0.1'].contains(Uri.parse(_server).host), isTrue);
    final i18n = await I18n.load(read: (_) async => null);
    final client = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
    final session = await Authentication(client, i18n).withPassword(
      _server,
      const String.fromEnvironment('KANEO_DEV_EMAIL'),
      const String.fromEnvironment('KANEO_DEV_PASSWORD'),
    );
    final api = KaneoApi(
      ApiClient(session: () => session, i18n: i18n, onSessionExpired: (_) {}),
      i18n,
    );
    addTearDown(api.signOut);

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

    SharedPreferences.setMockInitialValues({
      notificationChecksEnabledKey: true,
      languageChoiceKey: 'en-US',
    });
    final host = FakeNotificationHost();
    Future<void> check() => runBackgroundCheck(
      host: host,
      storage: MemorySessionStorage(session),
      catalogs: (_) async => null,
    );

    await check();
    expect(host.notices, isEmpty, reason: 'The first check shows no history');

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
    final notice = host.notices.singleWhere((n) => n.title == name);
    expect(notice.body, 'A real notification');
    final payload = decodeNotice(notice.payload)!;
    expect(payload.account, accountScope(session));
    expect(payload.taskId, task.id);

    final count = host.notices.length;
    await check();
    expect(host.notices.where((n) => n.title == name), hasLength(1));
    expect(host.notices.length, greaterThanOrEqualTo(count));
  }, skip: _server.isEmpty);
}
