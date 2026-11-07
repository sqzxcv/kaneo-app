import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_kaneo.dart';

const _session = Session(
  serverUrl: FakeKaneo.serverUrl,
  credentialType: CredentialType.apiKey,
  token: FakeKaneo.apiKey,
  userId: FakeKaneo.userId,
  userName: 'Test User',
  userEmail: FakeKaneo.email,
);

Future<ProviderContainer> _container(FakeKaneo server, {Directory? cacheRoot}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      i18nProvider.overrideWithValue(await I18n.load(read: (_) async => null)),
      httpAdapterProvider.overrideWithValue(server),
      sessionStorageProvider.overrideWithValue(MemorySessionStorage(_session)),
      initialSessionProvider.overrideWithValue(_session),
      cacheRootProvider.overrideWithValue(cacheRoot),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('MemoryCacheStore', () {
    test('keeps, removes and clears values', () async {
      final store = MemoryCacheStore();
      await store.write('a', {'x': 1});
      expect(store.peek('a'), {'x': 1});
      expect(await store.read('a'), {'x': 1});
      await store.remove('a');
      expect(store.peek('a'), isNull);
      await store.write('b', 1);
      await store.clear();
      expect(await store.read('b'), isNull);
    });
  });

  group('FileCacheStore', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('kaneo-cache');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
    });

    test('a new store reads what an earlier one wrote', () async {
      await FileCacheStore(directory).write('board/1', {'name': 'Demo'});
      final later = FileCacheStore(directory);
      expect(later.peek('board/1'), isNull);
      expect(await later.read('board/1'), {'name': 'Demo'});
      expect(later.peek('board/1'), {'name': 'Demo'});
    });

    test('keys with a path separator stay in one directory', () async {
      await FileCacheStore(directory).write('board/1', 1);
      expect(await directory.list().length, 1);
      expect(directory.listSync().single, isA<File>());
    });

    test('a corrupt file is a cache miss', () async {
      await File('${directory.path}/a.json').writeAsString('{not json');
      expect(await FileCacheStore(directory).read('a'), isNull);
    });

    test('remove and clear delete the files', () async {
      final store = FileCacheStore(directory);
      await store.write('a', 1);
      await store.write('b', 2);
      await store.remove('a');
      expect(await FileCacheStore(directory).read('a'), isNull);
      await store.clear();
      expect(await FileCacheStore(directory).read('b'), isNull);
      expect(await directory.exists(), isFalse);
    });
  });

  group('CachedQuery', () {
    test('the first load fetches and stores the result', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      final workspaces = await container.read(workspacesQuery.future);
      expect(workspaces.single.id, FakeKaneo.workspaceId);
      await _settle();
      expect(container.read(cacheStoreProvider).peek('workspaces'), isNotNull);
    });

    test('shows cached data at once, then replaces it with the refresh', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      await container.read(cacheStoreProvider).write('workspaces', [
        {'id': 'old', 'name': 'Old', 'slug': 'old'},
      ]);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);

      expect(container.read(workspacesQuery).requireValue.single.id, 'old');
      await _settle();
      expect(container.read(workspacesQuery).requireValue.single.id, FakeKaneo.workspaceId);
    });

    test('keeps the data on screen while refreshing', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await container.read(workspacesQuery.future);

      final gate = server.hold('api/workspace');
      final refresh = container.read(workspacesQuery.notifier).refresh();
      await _settle();
      final during = container.read(workspacesQuery);
      expect(during.isLoading, isTrue);
      expect(during.hasValue, isTrue);
      gate.release();
      await refresh;
      expect(container.read(workspacesQuery).isLoading, isFalse);
    });

    test('a failed refresh keeps the data and reports the error', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await container.read(workspacesQuery.future);

      server.failNext('api/workspace', status: 500);
      await container.read(workspacesQuery.notifier).refresh();
      final state = container.read(workspacesQuery);
      expect(state.hasError, isTrue);
      expect(state.requireValue.single.id, FakeKaneo.workspaceId);
    });

    test('with nothing cached a failure is an error state', () async {
      final server = FakeKaneo()..fail('api/workspace', status: 500);
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await _settle();
      final state = container.read(workspacesQuery);
      expect(state.hasError, isTrue);
      expect(state.hasValue, isFalse);
    });

    test('data in an old shape is a cache miss', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      await container.read(cacheStoreProvider).write('workspaces', {'not': 'a list'});
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      final workspaces = await container.read(workspacesQuery.future);
      expect(workspaces.single.id, FakeKaneo.workspaceId);
    });

    test('setData updates the state and the cache', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await container.read(workspacesQuery.future);
      container.read(workspacesQuery.notifier).setData(const []);
      expect(container.read(workspacesQuery).requireValue, isEmpty);
      await _settle();
      expect(container.read(cacheStoreProvider).peek('workspaces'), isEmpty);
    });

    test('a refresh overtaken by setData does not undo it', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await container.read(workspacesQuery.future);

      final gate = server.hold('api/workspace');
      final refresh = container.read(workspacesQuery.notifier).refresh();
      await _settle();
      container.read(workspacesQuery.notifier).setData(const []);
      gate.release();
      await refresh;
      await _settle();

      expect(container.read(workspacesQuery).requireValue, isEmpty);
      expect(container.read(workspacesQuery).isLoading, isFalse);
      expect(container.read(cacheStoreProvider).peek('workspaces'), isEmpty);
    });

    test('forgetting keeps what is on screen, and it does not come back from the cache', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await container.read(workspacesQuery.future);
      await _settle();

      container.read(workspacesQuery.notifier).forget();
      await _settle();
      expect(container.read(workspacesQuery).requireValue, isNotEmpty);
      expect(container.read(cacheStoreProvider).peek('workspaces'), isNull);
    });

    test('a refresh overtaken by forgetting does not remember it again', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await container.read(workspacesQuery.future);

      final gate = server.hold('api/workspace');
      final refresh = container.read(workspacesQuery.notifier).refresh();
      await _settle();
      container.read(workspacesQuery.notifier).forget();
      gate.release();
      await refresh;
      await _settle();
      expect(container.read(cacheStoreProvider).peek('workspaces'), isNull);
    });

    test('a slow refresh overtaken by a newer one does not replace its answer', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      addTearDown(sub.close);
      await container.read(workspacesQuery.future);
      final notifier = container.read(workspacesQuery.notifier);

      // The first request answers last, with what it read before the second one.
      final answers = ['Newest', 'Stale'];
      server.on('api/workspace', (request) {
        return FakeResponse(200, [
          {...server.workspaces.first, 'name': answers.removeAt(0)},
        ]);
      });
      server.latency = const Duration(milliseconds: 100);
      final first = notifier.refresh();
      await _settle();
      server.latency = Duration.zero;
      await notifier.refresh();
      expect(container.read(workspacesQuery).requireValue.single.name, 'Newest');

      await first;
      await _settle();
      expect(answers, isEmpty);
      expect(container.read(workspacesQuery).requireValue.single.name, 'Newest');
      final cached = container.read(cacheStoreProvider).peek('workspaces')! as List;
      expect((cached.single as Map)['name'], 'Newest');
    });

    test('a refresh still fills the cache when its page closed meanwhile', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      await container.read(workspacesQuery.future);

      final gate = server.hold('api/workspace');
      final refresh = container.read(workspacesQuery.notifier).refresh();
      await _settle();
      sub.close();
      await _settle();
      server.workspaces.first['name'] = 'Renamed';
      gate.release();
      await refresh;
      await _settle();

      final cached = container.read(cacheStoreProvider).peek('workspaces')! as List;
      expect((cached.single as Map)['name'], 'Renamed');
    });

    test('accounts do not share a cache directory', () async {
      final root = await Directory.systemTemp.createTemp('kaneo-cache-root');
      addTearDown(() => root.delete(recursive: true));
      final server = FakeKaneo();
      final container = await _container(server, cacheRoot: root);
      final first = container.read(cacheStoreProvider) as FileCacheStore;
      await container
          .read(sessionProvider.notifier)
          .signIn(
            const Session(
              serverUrl: FakeKaneo.serverUrl,
              credentialType: CredentialType.apiKey,
              token: 'k',
              userId: 'someone-else',
              userName: 'Other',
              userEmail: 'o@example.com',
            ),
          );
      final second = container.read(cacheStoreProvider) as FileCacheStore;
      expect(second.directory.path, isNot(first.directory.path));
    });

    test('signing out forgets the cached data', () async {
      final server = FakeKaneo();
      final container = await _container(server);
      final sub = container.listen(workspacesQuery, (_, _) {});
      await container.read(workspacesQuery.future);
      await _settle();
      final store = container.read(cacheStoreProvider);
      expect(store.peek('workspaces'), isNotNull);
      sub.close();
      await container.read(sessionProvider.notifier).signOut();
      expect(store.peek('workspaces'), isNull);
    });

    test('the current workspace is the remembered one, otherwise the first', () async {
      final server = FakeKaneo();
      server.workspaces.add({
        'id': 'workspace-2',
        'name': 'Second',
        'slug': 'second',
        'role': 'member',
      });
      final container = await _container(server);
      final sub = container.listen(currentWorkspaceProvider, (_, _) {});
      addTearDown(sub.close);
      await _settle();
      expect(container.read(currentWorkspaceProvider).requireValue?.id, FakeKaneo.workspaceId);
      await container.read(selectedWorkspaceIdProvider.notifier).select('workspace-2');
      await _settle();
      expect(container.read(currentWorkspaceProvider).requireValue?.id, 'workspace-2');
      await container.read(selectedWorkspaceIdProvider.notifier).select('gone');
      await _settle();
      expect(container.read(currentWorkspaceProvider).requireValue?.id, FakeKaneo.workspaceId);
    });
  });
}
