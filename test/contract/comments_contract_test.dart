// Checks on a real local Kaneo what comments rely on: a mention made the way the task page makes it
// notifies the other person, only the author can change a comment, someone who can only read can't
// comment at all, and changes to a task show up in its activity. FakeKaneo copies this. Skipped unless
// dev.env is passed:
//
//     flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// It takes two people, so it signs up two new accounts with a workspace of their own, which leaves
// the shared one alone, and deletes them again. Never point it at anything but a local Kaneo.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/markdown/mention_text.dart';
import 'package:kaneo_app/features/task/task_activity.dart';

const _serverUrl = String.fromEnvironment('KANEO_DEV_SERVER_URL');
const _password = 'contract-test-password';

bool get _isLocal {
  final host = Uri.tryParse(_serverUrl)?.host;
  return host == 'localhost' || host == '127.0.0.1';
}

typedef _Person = ({KaneoApi api, String id, String name, String email});

Future<_Person> _signUp(String name, String email) async {
  final i18n = await I18n.load(read: (_) async => null);
  final signUp = await ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {})
      .requestRaw(
        'api/auth/sign-up/email',
        method: 'POST',
        body: {'name': name, 'email': email, 'password': _password},
        serverUrl: _serverUrl,
      );
  expect(signUp.isOk, isTrue, reason: 'Could not sign up: ${signUp.status}');
  final api = KaneoApi(
    ApiClient(
      session: () => Session(
        serverUrl: _serverUrl,
        credentialType: CredentialType.bearer,
        token: signUp.header('set-auth-token')!,
        userId: 'unused',
        userName: 'unused',
        userEmail: 'unused',
      ),
      i18n: i18n,
      onSessionExpired: (_) {},
    ),
    i18n,
  );
  final me = await api.me();
  return (api: api, id: me.id, name: name, email: email);
}

Matcher _refused() => throwsA(isA<ApiError>());

void main() {
  test('comments do what the task page expects', () async {
    expect(_isLocal, isTrue, reason: _serverUrl);
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final author = await _signUp('Ana $stamp', 'c-author-$stamp@kaneo.local');
    addTearDown(() => author.api.deleteUser(password: _password));
    final other = await _signUp('Bo Li $stamp', 'c-other-$stamp@kaneo.local');
    addTearDown(() => other.api.deleteUser(password: _password));

    final workspace = await author.api.createWorkspace(
      name: 'C-comments-$stamp',
      slug: 'c-comments-$stamp',
    );
    addTearDown(() => author.api.deleteWorkspace(workspace.id));
    await author.api.inviteMember(organizationId: workspace.id, email: other.email, role: 'member');
    // The list of invitations for a person is only for verified addresses, and there's no mail here.
    final invitation = (await author.api.fullWorkspace(workspace.id)).invitations!.single;
    await other.api.acceptInvitation(invitation.id);

    final project = await author.api.createProject(
      name: 'C-comments-$stamp',
      workspaceId: workspace.id,
      icon: 'Layout',
      slug: 'C$stamp'.toUpperCase(),
    );
    final columns = await author.api.columns(project.id);
    final task = await author.api.createTask(
      project.id,
      CreateTaskBody(
        title: 'Task',
        description: '',
        priority: priorities.first,
        status: columns.first.slug,
      ),
    );

    // Whoever the page offers to mention can see the task, and is told about the mention.
    final people = await author.api.workspaceMembers(workspace.id, projectId: project.id);
    final person = people.firstWhere((p) => p.id == other.id);
    final mentions = CommentMentions();
    final shown = 'Hi ${mentions.pick(id: person.id, name: mentionName(person))} **look**';
    final saved = mentions.save(shown);
    await author.api.createComment(task.id, saved);

    final notified = await other.api.notifications(workspaceId: workspace.id);
    final mention = notified.singleWhere((n) => n.type == 'task_mention');
    expect(mention.resourceId, task.id);
    expect(mention.userId, other.id);
    expect(
      (await author.api.notifications(workspaceId: workspace.id))
          .where((n) => n.type == 'task_mention'),
      isEmpty,
    );

    // It comes back exactly as sent, and reads the same when opened for editing.
    Future<Activity> comment() async =>
        (await author.api.activities(task.id)).firstWhere((a) => a.type == 'comment');
    var mine = await comment();
    expect(mine.content, saved);
    expect(mine.userId, author.id);
    expect(isCommentEntry(mine), isTrue);
    expect(wasEdited(mine), isFalse);
    final reopened = CommentMentions();
    expect(reopened.show(mine.content!), shown);
    expect(reopened.save(shown), saved);

    // Only the author can change it. The other person can read it and add their own.
    expect(canChangeComment(mine, author.id), isTrue);
    expect(canChangeComment(mine, other.id), isFalse);
    await expectLater(other.api.updateComment(mine.id, 'Not yours'), _refused());
    await expectLater(other.api.deleteComment(mine.id), _refused());
    expect((await comment()).content, saved);
    await other.api.createComment(task.id, 'A reply');
    final seenByOther = await other.api.activities(task.id);
    expect(seenByOther.map((a) => a.content), containsAll([saved, 'A reply']));

    await author.api.updateComment(mine.id, 'Edited');
    final edited = (await author.api.activities(task.id)).firstWhere((a) => a.id == mine.id);
    expect(edited.content, 'Edited');
    expect(wasEdited(edited), isTrue);
    await author.api.deleteComment(mine.id);
    final remaining = await author.api.activities(task.id);
    expect(remaining.where((a) => a.id == mine.id), isEmpty);

    // Newest first, with what the page words its events from. A change is on record straight away.
    await author.api.updatePriority(task.id, 'high');
    await author.api.updateStatus(task.id, columns.last.slug);
    await author.api.updateAssignee(task.id, other.id);
    await author.api.updateDueDate(task.id, '2026-12-01');
    await author.api.updateTitle(task.id, 'Renamed');
    final feed = await author.api.activities(task.id);
    final types = feed.map((a) => a.type).toList();
    expect(
      types,
      containsAll([
        'priority_changed',
        'status_changed',
        'assignee_changed',
        'due_date_changed',
        'title_changed',
      ]),
      reason: 'The server may have answered before writing its record: $types',
    );
    final times = feed.map((a) => DateTime.parse(a.createdAt)).toList();
    for (var i = 1; i < times.length; i++) {
      expect(times[i].isAfter(times[i - 1]), isFalse);
    }
    Map<dynamic, dynamic> data(String type) =>
        feed.firstWhere((a) => a.type == type).eventData! as Map<dynamic, dynamic>;
    expect(data('priority_changed'), containsPair('newPriority', 'high'));
    expect(data('status_changed'), containsPair('newStatus', columns.last.slug));
    expect(data('assignee_changed'), containsPair('newAssignee', other.name));
    expect(data('title_changed'), containsPair('newTitle', 'Renamed'));

    // Someone who can only read isn't allowed to comment, which is why the page offers them nothing.
    final members = await author.api.fullWorkspace(workspace.id);
    final membership = members.members!.firstWhere((m) => m.userId == other.id);
    await author.api.updateMemberRole(workspace.id, membership.id, 'viewer');
    final can = await other.api.workspaceCapabilities(workspace.id);
    expect(can.updateTasks, isFalse);
    await expectLater(other.api.createComment(task.id, 'Not allowed'), _refused());
    expect(await other.api.activities(task.id), isNotEmpty);
  }, skip: _serverUrl.isEmpty ? 'Needs a local Kaneo: see the top of this file.' : false);
}
