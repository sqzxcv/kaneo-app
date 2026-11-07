// Checks on a real local Kaneo what a task's subtasks and links rely on: a subtask is created and
// linked the way the task page does it, ticking it off is what the server calls completed, and each
// relation reads the same from both ends. FakeKaneo copies this. Skipped unless dev.env is passed:
//
//     flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// It creates a temporary project on that server and deletes it again. Never point it at anything
// but a local Kaneo.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/task/new_task.dart';
import 'package:kaneo_app/features/task/task_relations.dart';

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
  test('subtasks and links do what the task page expects', () async {
    expect(_isLocal, isTrue, reason: _serverUrl);
    final api = await _signIn();
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final project = await api.createProject(
      name: 'C-relations-$stamp',
      workspaceId: _workspaceId,
      icon: 'Layout',
      slug: 'C$stamp',
    );
    addTearDown(() => api.deleteProject(project.id));
    final columns = await api.columns(project.id);

    Future<Task> create(String title, String status) => api.createTask(
      project.id,
      CreateTaskBody(title: title, description: '', priority: priorities.first, status: status),
    );

    final open = initialTaskStatus(columns, null);
    final parent = await create('Parent', open);
    final subtask = await create('Subtask', open);
    final other = await create('Other', open);
    final planned = await create('Planned subtask', statusPlanned);
    expect(subtask.userId, isNull);
    expect(planned.status, statusPlanned);

    await api.createRelation(parent.id, subtask.id, relationSubtask);
    await api.createRelation(parent.id, planned.id, relationSubtask);
    await api.createRelation(parent.id, other.id, relationBlocks);

    var relations = await api.relations(parent.id);
    expect(
      subtasksOf(parent.id, relations).map((t) => t.id),
      unorderedEquals([subtask.id, planned.id]),
    );
    expect(subtasksOf(parent.id, relations).map((t) => t.isCompleted), [false, false]);
    expect(linkedTasksOf(parent.id, relations).single.kind, TaskLinkKind.blocks);
    expect(parentTaskOf(parent.id, relations), isNull);

    final ofSubtask = await api.relations(subtask.id);
    expect(parentTaskOf(subtask.id, ofSubtask)?.id, parent.id);
    expect(subtasksOf(subtask.id, ofSubtask), isEmpty);
    expect(linkedTasksOf(subtask.id, ofSubtask), isEmpty);

    final ofOther = await api.relations(other.id);
    expect(linkedTasksOf(other.id, ofOther).single.kind, TaskLinkKind.blockedBy);
    expect(linkedTasksOf(other.id, ofOther).single.task.id, parent.id);

    // The status ticking off picks is what the server calls completed, and undoing it isn't.
    await api.updateStatus(subtask.id, completionStatus(columns, done: true)!);
    relations = await api.relations(parent.id);
    expect(
      subtasksOf(parent.id, relations).firstWhere((t) => t.id == subtask.id).isCompleted,
      isTrue,
    );
    final board = await api.board(project.id);
    final card = board.data.columns.expand((c) => c.tasks!).firstWhere((t) => t.id == parent.id);
    expect(card.subtaskCounts?.completed, 1);
    expect(card.subtaskCounts?.total, 2);

    await api.updateStatus(subtask.id, completionStatus(columns, done: false)!);
    relations = await api.relations(parent.id);
    expect(
      subtasksOf(parent.id, relations).firstWhere((t) => t.id == subtask.id).isCompleted,
      isFalse,
    );
  }, skip: _serverUrl.isEmpty ? 'Pass dev.env to run this against a local Kaneo.' : null);
}
