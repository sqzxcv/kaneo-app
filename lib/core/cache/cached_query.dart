import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../providers.dart';

/// What a [CachedQuery] loads and how it is stored.
class QuerySpec<T> {
  const QuerySpec({
    required this.key,
    required this.fetch,
    required this.encode,
    required this.decode,
  });

  /// Unique within the signed-in account, such as `board/<projectId>`.
  final String key;
  final Future<T> Function(Ref ref) fetch;
  final Object? Function(T value) encode;
  final T Function(Object? json) decode;
}

/// Shows the cached data at once, then refreshes in the background.
///
/// When the refresh fails, the cached data stays on screen and `state.hasError` is set. When there
/// is nothing cached, the failure is an ordinary error state. Use `AsyncBody` to render it.
class CachedQuery<T> extends AsyncNotifier<T> {
  CachedQuery(this._spec);

  final QuerySpec<T> _spec;

  int _latestLoad = 0;

  @override
  FutureOr<T> build() {
    final store = ref.watch(cacheStoreProvider);
    final remembered = store.peek(_spec.key);
    if (remembered != null) {
      final value = _tryDecode(remembered);
      if (value != null) {
        scheduleMicrotask(refresh);
        return value.value;
      }
    }
    return _firstLoad();
  }

  Future<T> _firstLoad() async {
    final stored = await ref.read(cacheStoreProvider).read(_spec.key);
    final value = stored == null ? null : _tryDecode(stored);
    if (value != null) {
      scheduleMicrotask(refresh);
      return value.value;
    }
    return _fetchAndStore();
  }

  ({T value})? _tryDecode(Object json) {
    try {
      return (value: _spec.decode(json));
    } on TypeError {
      return null; // Written by an older app version. Treat as a cache miss.
    }
  }

  Future<T> _fetchAndStore() async {
    final store = ref.read(cacheStoreProvider);
    final fresh = await _spec.fetch(ref);
    unawaited(store.write(_spec.key, _spec.encode(fresh)));
    return fresh;
  }

  /// Loads again while the current data stays visible. Never throws; check `state.hasError`.
  ///
  /// Only the latest load counts. One that a newer load or [setData] has overtaken is dropped, so
  /// that an answer read before a change can't undo that change on screen or in the cache.
  Future<void> refresh() async {
    if (!ref.mounted) return;
    final load = ++_latestLoad;
    final store = ref.read(cacheStoreProvider);
    state = AsyncLoading<T>();
    try {
      final fresh = await _spec.fetch(ref);
      if (load != _latestLoad) return;
      unawaited(store.write(_spec.key, _spec.encode(fresh)));
      if (ref.mounted) state = AsyncData(fresh);
    } catch (error, stack) {
      if (load == _latestLoad && ref.mounted) state = AsyncError<T>(error, stack);
    }
  }

  /// Replaces the data right away, such as for an optimistic update, and remembers it.
  void setData(T value) {
    _latestLoad++;
    state = AsyncData(value);
    unawaited(ref.read(cacheStoreProvider).write(_spec.key, _spec.encode(value)));
  }

  /// Stops remembering the data, for something that no longer exists, so that it can't show again
  /// from the cache. A page still open on it keeps what it has until it closes.
  void forget() {
    _latestLoad++;
    unawaited(ref.read(cacheStoreProvider).remove(_spec.key));
  }
}

/// Requests fail for reasons a retry a moment later will not fix, and the UI offers its own retry.
Duration? _noRetry(int count, Object error) => null;

/// A cached query for each [A], released when no page is using it.
AsyncNotifierProviderFamily<CachedQuery<T>, T, A> cachedQueryFamily<T, A>(
  QuerySpec<T> Function(A arg) spec,
) => AsyncNotifierProvider.autoDispose.family<CachedQuery<T>, T, A>(
  (arg) => CachedQuery<T>(spec(arg)),
  retry: _noRetry,
);

/// A cached query with no arguments, released when no page is using it.
AsyncNotifierProvider<CachedQuery<T>, T> cachedQuery<T>(QuerySpec<T> spec) =>
    AsyncNotifierProvider.autoDispose<CachedQuery<T>, T>(
      () => CachedQuery<T>(spec),
      retry: _noRetry,
    );
