// Checks on a real local Kaneo what the new-task form relies on: a task can be created without the
// project's required custom fields, and they get their defaults. FakeKaneo copies this. Skipped
// unless dev.env is passed:
//
//     flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// It creates a temporary project on that server and deletes it again. Never point it at anything
// but a local Kaneo.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/new_task.dart';

const _serverUrl = String.fromEnvironment('KANEO_DEV_SERVER_URL');
const _email = String.fromEnvironment('KANEO_DEV_EMAIL');
const _password = String.fromEnvironment('KANEO_DEV_PASSWORD');
const _workspaceId = String.fromEnvironment('KANEO_DEV_WORKSPACE_ID');

bool get _isLocal {
  final host = Uri.tryParse(_serverUrl)?.host;
  return host == 'localhost' || host == '127.0.0.1';
}

Future<KaneoApi> _signIn() async {
  final i18n = await I18n.load(read: (_) async => null);
  final signIn = await ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {})
      .requestRaw(
        'api/auth/sign-in/email',
        method: 'POST',
        body: {'email': _email, 'password': _password},
        serverUrl: _serverUrl,
      );
  expect(signIn.isOk, isTrue, reason: 'Could not sign in: ${signIn.status}');
  return KaneoApi(
    ApiClient(
      session: () => Session(
        serverUrl: _serverUrl,
        credentialType: CredentialType.bearer,
        token: signIn.header('set-auth-token')!,
        userId: 'unused',
        userName: 'unused',
        userEmail: 'unused',
      ),
      i18n: i18n,
      onSessionExpired: (_) {},
    ),
    i18n,
  );
}

void main() {
  test('a new task needs nothing for required custom fields', () async {
    expect(_isLocal, isTrue, reason: _serverUrl);
    final api = await _signIn();
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final project = await api.createProject(
      name: 'C-new-task-$stamp',
      workspaceId: _workspaceId,
      icon: 'Layout',
      slug: 'CN$stamp',
    );
    addTearDown(() => api.deleteProject(project.id));

    // A required field can't be defined without a default. That is why the form needn't ask.
    await expectLater(
      api.createCustomField(
        projectId: project.id,
        name: 'No default',
        type: 'number',
        required_: true,
      ),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 400)),
    );
    await api.createCustomField(
      projectId: project.id,
      name: 'Team',
      type: 'dropdown',
      required_: true,
      defaultValue: 'Core',
      options: ['Core', 'Web'],
    );

    final columns = await api.columns(project.id);
    final status = initialTaskStatus(columns, null);
    final created = await api.createTask(
      project.id,
      CreateTaskBody(
        title: 'No custom fields sent',
        description: '# As typed\n\n* me  \n',
        priority: 'high',
        status: status,
      ),
    );
    expect(created.status, status);
    expect(created.position, isNotNull);
    expect(created.number, isNotNull);

    final values = await api.taskCustomFieldValues(created.id);
    expect(values.single.fieldName, 'Team');
    expect(values.single.value, 'Core');
    final task = await api.task(created.id);
    expect(task.description, '# As typed\n\n* me  \n');

    // Every status the form offers is accepted: its columns and `planned`.
    final me = await api.me();
    final planned = newTaskStatuses(columns, projectId: project.id, plannedName: 'Planned').first;
    final inPlanned = await api.createTask(
      project.id,
      CreateTaskBody(
        title: 'Planned',
        description: '',
        priority: priorities.first,
        status: planned.slug,
        userId: me.id,
      ),
    );
    expect(inPlanned.status, statusPlanned);
    expect(inPlanned.userId, me.id);

    // A status from elsewhere is refused, so the form has to pick one the project has.
    await expectLater(
      api.createTask(
        project.id,
        const CreateTaskBody(
          title: 'Nowhere',
          description: '',
          priority: 'no-priority',
          status: 'not-a-column',
        ),
      ),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 400)),
    );
  }, skip: _serverUrl.isEmpty ? 'Pass dev.env to run this against a local Kaneo.' : null);
}
