// Local-only live auth checks. Creates and removes its own D- project; never edits shared data.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

const _server = String.fromEnvironment('KANEO_DEV_SERVER_URL');
const _key = String.fromEnvironment('KANEO_DEV_API_KEY');
const _email = String.fromEnvironment('KANEO_DEV_EMAIL');
const _password = String.fromEnvironment('KANEO_DEV_PASSWORD');
const _workspace = String.fromEnvironment('KANEO_DEV_WORKSPACE_ID');

void main() {
  test(
    'local password/API key login, authenticated reads, sockets, and invalidated token',
    () async {
      expect(['localhost', '127.0.0.1', '::1'].contains(Uri.parse(_server).host), isTrue);
      final i18n = await I18n.load(read: (_) async => null);
      Session? active;
      final client = ApiClient(
        session: () => active,
        i18n: i18n,
        onSessionExpired: (_) => active = null,
      );
      final auth = Authentication(client, i18n);
      final passwordSession = await auth.withPassword('$_server/api/', _email, _password);
      expect(passwordSession.credentialType, CredentialType.bearer);
      expect(passwordSession.userId.isNotEmpty, isTrue);
      active = passwordSession;
      final api = KaneoApi(client, i18n);
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase();
      final project = await api.createProject(
        name: 'D-Auth-$stamp',
        workspaceId: _workspace,
        icon: 'Layout',
        slug: 'D$stamp',
      );
      addTearDown(() async {
        active = passwordSession;
        await api.deleteProject(project.id);
        await api.signOut();
      });

      final keySession = await auth.withApiKey(_server, _key);
      expect(keySession.userId == passwordSession.userId, isTrue);
      active = keySession;
      expect((await loadFullBoard(api, project.id)).name, project.name);
      await api.notifications(workspaceId: _workspace);
      final projectSocket = connectAuthenticatedSocket(keySession, 'api/ws/${project.id}');
      final userSocket = connectAuthenticatedSocket(keySession, 'api/ws/user');
      addTearDown(() async {
        await projectSocket.sink.close();
        await userSocket.sink.close();
      });
      final changed = Completer<void>();
      final subscription = projectSocket.stream.listen((raw) {
        final message = jsonDecode(raw as String) as Map;
        if ((message['type'] as String).contains('TASK') && !changed.isCompleted) {
          changed.complete();
        }
      });
      addTearDown(subscription.cancel);
      final userEvents = userSocket.stream.listen((_) {});
      addTearDown(userEvents.cancel);
      await Future.wait([projectSocket.ready, userSocket.ready]);
      active = passwordSession;
      await api.createTask(
        project.id,
        const CreateTaskBody(
          title: 'D-Auth socket check',
          status: 'to-do',
          description: '',
          priority: 'no-priority',
        ),
      );
      await changed.future.timeout(const Duration(seconds: 10));

      await expectLater(
        auth.withPassword(_server, _email, 'intentionally-wrong-local-password'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      await expectLater(auth.withApiKey(_server, 'invalid-local-key'), throwsA(isA<ApiError>()));
      final disposable = await auth.withPassword(_server, _email, _password);
      active = disposable;
      await api.signOut();
      await expectLater(api.me(), throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)));
      expect(active, isNull);
    },
    skip: _server.isEmpty || _key.isEmpty,
  );
}
