import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/kaneo_api.dart';
import 'api/models.dart' show CurrentUser;
import 'cache/cache_store.dart';
import 'config/dev_config.dart';
import 'i18n/i18n.dart';
import 'session/session.dart';
import 'ui/toast.dart';

/// Set by `bootstrap()`, or by the test harness.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// Set by `bootstrap()`, or by the test harness.
final i18nProvider = Provider<I18n>((ref) => throw UnimplementedError());

final sessionStorageProvider = Provider<SessionStorage>((ref) => SecureSessionStorage());

final devConfigProvider = Provider<DevConfig>((ref) => DevConfig.fromEnvironment());

/// Tests replace this with the fake server.
final httpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// Where the file cache lives. Null keeps the cache in memory, which is what tests want.
final cacheRootProvider = Provider<Directory?>((ref) => null);

/// The session the app starts with, read before the first frame.
final initialSessionProvider = Provider<Session?>((ref) => null);

/// The signed-in account, or null. The router sends everyone without one to the login page.
final sessionProvider = NotifierProvider<SessionController, Session?>(SessionController.new);

class SessionController extends Notifier<Session?> {
  @override
  Session? build() => ref.watch(initialSessionProvider);

  /// Signs in. KAN-23's login form ends here too.
  Future<void> signIn(Session session) async {
    await _store(session);
    state = session;
  }

  /// Signs out and forgets everything cached for this account.
  Future<void> signOut() async {
    await _clear();
    state = null;
  }

  /// A request came back 401. Goes to the login page and says why.
  void expire(Session expired) {
    if (state?.token != expired.token) return;
    unawaited(_clear());
    state = null;
    showGlobalToast(
      ref.read(i18nProvider).t('mobile:errors.sessionExpired'),
      kind: ToastKind.error,
    );
  }

  /// Signs in with the server and API key from `dev.env`. See [DevConfig].
  Future<void> devSignIn() async {
    final config = ref.read(devConfigProvider);
    if (!config.isConfigured) return;
    final serverUrl = normalizeServerUrl(config.serverUrl);
    final body = await ref
        .read(apiClientProvider)
        .request(
          'api/user/me',
          serverUrl: serverUrl,
          credentials: ApiCredentials(CredentialType.apiKey, config.apiKey),
        );
    final user = CurrentUser.fromJson((body as Map).cast<String, dynamic>());
    await signIn(
      Session(
        serverUrl: serverUrl,
        credentialType: CredentialType.apiKey,
        token: config.apiKey,
        userId: user.id,
        userName: user.name,
        userEmail: user.email,
      ),
    );
  }

  // Secure storage can be unavailable, for example on a Linux desktop without a secret service.
  // The session then lasts until the app exits, and sign-in still works.
  Future<void> _store(Session session) async {
    try {
      await ref.read(sessionStorageProvider).write(session);
    } on Exception {
      return;
    }
  }

  Future<void> _clear() async {
    await ref.read(cacheStoreProvider).clear();
    try {
      await ref.read(sessionStorageProvider).clear();
    } on Exception {
      return;
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    session: () => ref.read(sessionProvider),
    i18n: ref.watch(i18nProvider),
    onSessionExpired: (expired) => ref.read(sessionProvider.notifier).expire(expired),
    adapter: ref.watch(httpAdapterProvider),
  );
});

/// Every Kaneo endpoint. Use `ref.read(kaneoApiProvider)` for writes and `lib/core/data/queries.dart`
/// for reads.
final kaneoApiProvider = Provider<KaneoApi>((ref) {
  return KaneoApi(ref.watch(apiClientProvider), ref.watch(i18nProvider));
});

/// The cache of the signed-in account. Accounts never share one.
final cacheStoreProvider = Provider<CacheStore>((ref) {
  final session = ref.watch(sessionProvider.select((s) => s == null ? null : _cacheScope(s)));
  final root = ref.watch(cacheRootProvider);
  if (session == null || root == null) return MemoryCacheStore();
  return FileCacheStore(Directory('${root.path}/$session'));
});

String _cacheScope(Session session) =>
    Uri.encodeComponent('${session.serverUrl}|${session.userId}');

/// The app's cache directory, or null when the platform has none.
Future<Directory?> defaultCacheRoot() async {
  try {
    return Directory('${(await getApplicationCacheDirectory()).path}/kaneo-queries');
  } on Exception {
    return null;
  }
}
