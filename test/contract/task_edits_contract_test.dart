// Checks on a real local Kaneo what task editing relies on: which fields a full update clears, and
// that a change of status keeps a task's position. FakeKaneo copies this. Skipped unless dev.env is
// passed:
//
//     flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// It creates a temporary project on that server and deletes it again. Never point it at anything
// but a local Kaneo.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/task_edits.dart';

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
  test('editing a task does what the app expects', () async {
    expect(_isLocal, isTrue, reason: _serverUrl);
    final api = await _signIn();
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final project = await api.createProject(
      name: 'C-task-edits-$stamp',
      workspaceId: _workspaceId,
      icon: 'Layout',
      slug: 'CE$stamp',
    );
    addTearDown(() => api.deleteProject(project.id));
    final columns = await api.columns(project.id);
    final me = await api.me();
    final due = toApiDate(DateTime(2031, 3, 10));
    final start = toApiDate(DateTime(2031, 3, 1));
    const description = '# Keep\n\n* me  \n';
    final created = await api.createTask(
      project.id,
      CreateTaskBody(
        title: 'Edits',
        description: description,
        priority: 'high',
        status: columns.first.slug,
        userId: me.id,
        dueDate: due,
      ),
    );

    UpdateTaskBody whole(Task task, {String? startDate}) => UpdateTaskBody(
      title: task.title,
      startDate: startDate,
      dueDate: task.dueDate,
      priority: task.priority ?? priorities.first,
      status: task.status,
      projectId: task.projectId,
      position: (task.position ?? 0).floor(),
      userId: task.userId,
    );

    // The detail view says which workspace the task is in. The app relies on it for everything.
    var task = await api.task(created.id);
    expect(task.workspaceId, _workspaceId);

    // A full update sets the start date and keeps what it repeats, and what it leaves out.
    await api.updateTask(task.id, whole(task, startDate: start));
    task = await api.task(task.id);
    expect(parseDay(task.startDate), DateTime(2031, 3, 1));
    expect(parseDay(task.dueDate), DateTime(2031, 3, 10));
    expect(task.userId, me.id);
    expect(task.assigneeName, isNotNull);
    expect(task.priority, 'high');
    expect(task.description, description);

    // Leaving the start date out clears it, and only it.
    await api.updateTask(task.id, whole(task));
    task = await api.task(task.id);
    expect(task.startDate, isNull);
    expect(parseDay(task.dueDate), DateTime(2031, 3, 10));
    expect(task.description, description);

    // A start date after the due date is refused, with a reason.
    await expectLater(
      api.updateTask(task.id, whole(task, startDate: toApiDate(DateTime(2031, 4, 1)))),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 400)),
    );

    // Clearing the due date and the assignee.
    await api.updateDueDate(task.id, null);
    await api.updateAssignee(task.id, null);
    task = await api.task(task.id);
    expect(task.dueDate, isNull);
    expect(task.userId, isNull);
    expect(task.assigneeName, isNull);

    // A change of status keeps the position, which is where the app puts the card meanwhile.
    final position = task.position;
    await api.updateStatus(task.id, columns[1].slug);
    expect((await api.task(task.id)).position, position);
    await api.updateStatus(task.id, statusArchived);
    expect((await api.task(task.id)).status, statusArchived);
    final board = await loadFullBoard(api, project.id);
    expect([for (final t in board.archivedTasks) t.id], [task.id]);
    await api.updateStatus(task.id, statusPlanned);
    expect([for (final t in (await loadFullBoard(api, project.id)).plannedTasks) t.id], [task.id]);

    // Labels: the workspace label is offered, the task's copy is what gets removed.
    final label = await api.createLabel(
      name: 'C-label-$stamp',
      color: 'blue',
      workspaceId: _workspaceId,
    );
    addTearDown(() => api.deleteLabel(label.id));
    await api.attachLabel(label.id, task.id);
    final attached = await api.taskLabels(task.id);
    expect(attached.single.name, label.name);
    expect(attached.single.id, isNot(label.id));
    final offered = taskLabelOptions(await api.workspaceLabels(_workspaceId), task.id);
    expect(selectedLabelIds(attached, offered), contains(label.id));
    final changes = labelChanges(
      attached: attached,
      options: offered,
      selected: selectedLabelIds(attached, offered)..remove(label.id),
    );
    expect(changes.attach, isEmpty);
    expect(changes.detach, [attached.single.id]);
    await api.detachLabel(changes.detach.single);
    expect(await api.taskLabels(task.id), isEmpty);
  }, skip: _serverUrl.isEmpty ? 'Pass dev.env to run this against a local Kaneo.' : null);
}
