// Opt-in, read-only login smoke test. Supply AUTH_TEST_* from a private file.
// It only signs in, reads the current identity, and signs out its own password session.
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

const _server = String.fromEnvironment('AUTH_TEST_SERVER_URL');
const _email = String.fromEnvironment('AUTH_TEST_EMAIL');
const _password = String.fromEnvironment('AUTH_TEST_PASSWORD');
const _key = String.fromEnvironment('AUTH_TEST_API_KEY');

void main() {
  test('self-hosted live login with bare address, /api, password and API key', () async {
    final i18n = await I18n.load(read: (_) async => null);
    Session? active;
    final client = ApiClient(
      session: () => active,
      i18n: i18n,
      onSessionExpired: (_) => active = null,
    );
    final auth = Authentication(client, i18n);
    try {
      final bare = _server.replaceFirst(RegExp(r'^https://'), '');
      final keySession = await auth.withApiKey(bare, _key);
      expect(keySession.userId.isNotEmpty, isTrue);
      active = await auth.withPassword('${normalizeServerUrl(_server)}/api/', _email, _password);
      expect(active!.userId.isNotEmpty, isTrue);
      final api = KaneoApi(client, i18n);
      expect((await api.me()).id == active!.userId, isTrue);
      await api.signOut();
    } on ApiError catch (error) {
      fail('Login verification failed (HTTP ${error.status ?? 'connection'}).');
    }
  }, skip: _server.isEmpty || _key.isEmpty);
}
