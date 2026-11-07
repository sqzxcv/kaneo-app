// Local-only notification fixture. It owns every workspace, project and temporary account it
// creates; never changes the shared development account's preferences or existing tasks.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

const desktopTestServer = String.fromEnvironment('KANEO_DEV_SERVER_URL');

Future<
  ({
    KaneoApi ownerApi,
    KaneoApi actorApi,
    Project project,
    Session owner,
    Session actor,
    String actorPassword,
  })
>
createDesktopFixture(I18n i18n) async {
  expect(['localhost', '127.0.0.1'].contains(Uri.parse(desktopTestServer).host), isTrue);
  final anonymous = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
  final auth = Authentication(anonymous, i18n);
  final owner = await auth.withPassword(
    desktopTestServer,
    const String.fromEnvironment('KANEO_DEV_EMAIL'),
    const String.fromEnvironment('KANEO_DEV_PASSWORD'),
  );
  final ownerApi = KaneoApi(
    ApiClient(session: () => owner, i18n: i18n, onSessionExpired: (_) {}),
    i18n,
  );
  addTearDown(ownerApi.signOut);
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final workspace = await ownerApi.createWorkspace(
    name: 'D-Desktop-$stamp',
    slug: 'd-desktop-$stamp',
  );
  addTearDown(() => ownerApi.deleteWorkspace(workspace.id));
  final project = await ownerApi.createProject(
    name: 'D-Desktop-$stamp',
    workspaceId: workspace.id,
    icon: 'Layout',
    slug: 'D${stamp.toUpperCase()}',
  );
  addTearDown(() => ownerApi.deleteProject(project.id));
  addTearDown(() => ownerApi.clearAllNotifications(workspaceId: workspace.id));
  final email = 'd-desktop-$stamp@example.invalid';
  final password = 'D-test-$stamp-password';
  await anonymous.request(
    'api/auth/sign-up/email',
    serverUrl: desktopTestServer,
    method: 'POST',
    body: {'name': 'D desktop test', 'email': email, 'password': password},
  );
  final actor = await auth.withPassword(desktopTestServer, email, password);
  final actorApi = KaneoApi(
    ApiClient(session: () => actor, i18n: i18n, onSessionExpired: (_) {}),
    i18n,
  );
  addTearDown(() => actorApi.deleteUser(password: password));
  expect(actor.userId, isNot(owner.userId));
  // Unverified local accounts cannot list pending invitations. Use the freshly created invite
  // ID exactly as the emailed invitation link would; acceptance still authenticates the actor.
  final invitation = await ownerApi.client.request(
    'api/auth/organization/invite-member',
    method: 'POST',
    body: {'organizationId': workspace.id, 'email': email, 'role': 'member'},
  ) as Map<String, dynamic>;
  await actorApi.acceptInvitation(invitation['id'] as String);
  return (
    ownerApi: ownerApi,
    actorApi: actorApi,
    project: project,
    owner: owner,
    actor: actor,
    actorPassword: password,
  );
}
