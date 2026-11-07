// Checks on a real local Kaneo that a description comes back exactly as the app sent it, so that
// the web app sees only what was edited. Skipped unless dev.env is passed:
//
//     flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
//
// It creates a temporary project on that server and deletes it again. Never point it at anything
// but a local Kaneo.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

const _serverUrl = String.fromEnvironment('KANEO_DEV_SERVER_URL');
const _email = String.fromEnvironment('KANEO_DEV_EMAIL');
const _password = String.fromEnvironment('KANEO_DEV_PASSWORD');
const _workspaceId = String.fromEnvironment('KANEO_DEV_WORKSPACE_ID');

bool get _isLocal {
  final host = Uri.tryParse(_serverUrl)?.host;
  return host == 'localhost' || host == '127.0.0.1';
}

/// Things a Markdown editor or a server tends to rewrite.
const _source =
    '# 标题  \r\n'
    '\r\n'
    'Two spaces then a break  \n'
    '* star\n'
    '- dash\n'
    '+ plus\n'
    '\n'
    '1) paren\n'
    '\n'
    '- [x] done\n'
    '- [ ] todo\n'
    '\n'
    '<kaneo-mention id="u1" label="Ana"></kaneo-mention> and '
    '<kaneo-attachment url="https://files.test/a.pdf" filename="a.pdf" '
    'mime-type="application/pdf" size="2048" />\n'
    '<kaneo-issue-link url="https://k.test/task/t1" issue-key="KAN-1" task-id="t1" />\n'
    '<kaneo-embed url="https://www.youtube.com/watch?v=abc123" mode="embed" />\n'
    '\n'
    '<img src="https://files.test/d.png" alt="D" width="320" />\n'
    '\n'
    '| a | b |\n'
    '|---|:-:|\n'
    '| 1 | 2 |\n'
    '\n'
    '```dart\n'
    '\tfinal x = "y";  \n'
    '```\n'
    '\n'
    '<h2>Old HTML</h2><p>Text <strong>bold</strong></p>\n'
    '\n'
    '__bold__ *em* \\*escaped\\* &amp; non breaking 🙂 é "quotes" -- dashes\n'
    '\n'
    '\n'
    'The end\n'
    '\n';

void main() {
  test('a description comes back exactly as it was sent', () async {
    expect(_isLocal, isTrue, reason: _serverUrl);
    final i18n = await I18n.load(read: (_) async => null);
    final signIn = await ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {})
        .requestRaw(
          'api/auth/sign-in/email',
          method: 'POST',
          body: {'email': _email, 'password': _password},
          serverUrl: _serverUrl,
        );
    expect(signIn.isOk, isTrue, reason: 'Could not sign in: ${signIn.status}');
    final api = KaneoApi(
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

    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final project = await api.createProject(
      name: 'C-description-$stamp',
      workspaceId: _workspaceId,
      icon: 'Layout',
      slug: 'CD$stamp',
    );
    addTearDown(() => api.deleteProject(project.id));
    final columns = await api.columns(project.id);
    final task = await api.createTask(
      project.id,
      CreateTaskBody(
        title: 'Round trip',
        description: '',
        priority: 'low',
        status: columns.first.slug,
      ),
    );

    Future<String> stored() async => loadDescription(api, await api.task(task.id));

    await api.updateDescription(task.id, _source);
    expect(await stored(), _source);

    // The app sends the whole text, so an edit is the old text with one change in it.
    final edited = _source.replaceFirst('- dash', '- dashes');
    await api.updateDescription(task.id, edited);
    expect(await stored(), edited);

    final board = await loadFullBoard(api, project.id);
    final card = board.columns
        .expand((c) => c.tasks ?? const <BoardTask>[])
        .firstWhere((t) => t.id == task.id);
    expect(card.description, edited, reason: 'What the web app reads for its board.');

    // Larger than the 64 KiB a board response carries, and larger than one description page.
    final large = '$edited${'一行文字 🙂\r\n' * 12000}';
    await api.updateDescription(task.id, large);
    expect(await stored(), large);
    final page = await api.descriptionPage(task.id, 0);
    expect(page.nextOffset, isNotNull, reason: 'The text must span pages for this to mean much.');

    await api.updateDescription(task.id, '');
    expect(await stored(), '');
  }, skip: _email.isEmpty ? 'Needs dev.env' : null);
}
