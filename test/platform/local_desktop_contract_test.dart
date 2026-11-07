// Run with the private local dev.env. Native delivery is tested separately on macOS.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import 'fake_desktop_host.dart';
import 'local_desktop_fixture.dart';

void main() {
  test('real local assignment becomes a desktop notice that opens the exact task', () async {
    final i18n = await I18n.load(read: (_) async => null);
    final fixture = await createDesktopFixture(i18n);
    final host = FakeDesktopHost();
    final opened = <String?>[];
    final runtime = DesktopRuntime(
      host: host,
      load: () => fixture.ownerApi.notifications(workspaceId: fixture.project.workspaceId),
      open: opened.add,
      hasPreference: () => true,
      rememberPermission: (_) async {},
      actionLabel: 'Open',
      fallbackBody: 'New activity',
      summary: (n) => '$n notifications',
      onUnavailable: () => fail('Desktop runtime unavailable'),
      pollInterval: const Duration(days: 1),
    );
    addTearDown(runtime.dispose);
    await runtime.setSession(fixture.owner);
    await runtime.setEnabled(true);
    await runtime.start();
    expect(host.notices, isEmpty);
    final task = await fixture.actorApi.createTask(
      fixture.project.id,
      CreateTaskBody(
        title: 'D-Desktop notification test',
        description: '',
        priority: 'no-priority',
        status: 'to-do',
        userId: fixture.owner.userId,
      ),
    );
    await runtime.check();
    expect(host.notices, hasLength(1));
    expect(host.notices.single.body, task.title);
    await runtime.activate(host.notices.single.payload);
    expect(opened, [task.id]);
    await runtime.setSession(null);
    expect(host.notices, isEmpty);
  }, skip: desktopTestServer.isEmpty);
}
