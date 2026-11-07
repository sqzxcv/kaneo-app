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

/// The current time. Tests replace it to move past midnight.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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

  /// Production sign-in must reach secure storage before the account becomes active.
  /// A storage failure is shown instead of promising a session that disappears on relaunch.
  Future<void> signInPersistently(Session session) async {
    await ref.read(sessionStorageProvider).write(session);
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
    final session = state;
    if (session != null) await ref.read(cacheStoresProvider).forAccount(session).clear();
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
    onServerReach: (reached) => ref.read(serverReachableProvider.notifier).report(reached),
    adapter: ref.watch(httpAdapterProvider),
  );
});

/// Whether the signed-in server answered the last request made to it. Pages keep showing what they
/// last loaded when it doesn't, so this is what can tell the person that it may be out of date.
final serverReachableProvider = NotifierProvider<ServerReachable, bool>(ServerReachable.new);

class ServerReachable extends Notifier<bool> {
  @override
  bool build() {
    // Another account or server starts with nothing known against it.
    ref.watch(sessionProvider);
    return true;
  }

  void report(bool reached) => state = reached;
}

/// Every Kaneo endpoint. Use `ref.read(kaneoApiProvider)` for writes and `lib/core/data/queries.dart`
/// for reads.
final kaneoApiProvider = Provider<KaneoApi>((ref) {
  return KaneoApi(ref.watch(apiClientProvider), ref.watch(i18nProvider));
});

/// One cache per account, so accounts never share one.
class CacheStores {
  CacheStores(this._root);

  final Directory? _root;
  final Map<String, CacheStore> _stores = {};

  CacheStore forAccount(Session session) {
    final scope = Uri.encodeComponent('${session.serverUrl}|${session.userId}');
    final root = _root;
    return _stores.putIfAbsent(
      scope,
      () => root == null ? MemoryCacheStore() : FileCacheStore(Directory('${root.path}/$scope')),
    );
  }
}

/// Separate from [cacheStoreProvider] so that [SessionController] can clear a cache: a provider
/// cannot read another one that depends on it.
final cacheStoresProvider = Provider<CacheStores>(
  (ref) => CacheStores(ref.watch(cacheRootProvider)),
);

/// The cache of the signed-in account.
final cacheStoreProvider = Provider<CacheStore>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return MemoryCacheStore();
  return ref.watch(cacheStoresProvider).forAccount(session);
});

/// The app's cache directory, or null when the platform has none.
Future<Directory?> defaultCacheRoot() async {
  try {
    return Directory('${(await getApplicationCacheDirectory()).path}/kaneo-queries');
  } on Exception {
    return null;
  }
}
