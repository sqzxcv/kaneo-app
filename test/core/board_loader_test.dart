import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/fake_kaneo.dart';

void main() {
  late FakeKaneo server;
  late KaneoApi api;

  setUp(() async {
    server = FakeKaneo();
    final i18n = await I18n.load(read: (_) async => null);
    api = KaneoApi(
      ApiClient(
        session: () => const Session(
          serverUrl: FakeKaneo.serverUrl,
          credentialType: CredentialType.apiKey,
          token: FakeKaneo.apiKey,
          userId: FakeKaneo.userId,
          userName: 'Test User',
          userEmail: FakeKaneo.email,
        ),
        i18n: i18n,
        onSessionExpired: (_) {},
        adapter: server,
      ),
      i18n,
    );
  });

  test('follows every page and keeps the columns in order', () async {
    server.boardPageSize = 2;
    final board = await loadFullBoard(api, FakeKaneo.projectId);
    expect(server.requestsTo('api/task/tasks/'), hasLength(3));
    expect(board.columns.map((c) => c.slug), ['to-do', 'in-progress', 'in-review', 'done']);
    final total = board.columns.fold<int>(0, (sum, c) => sum + (c.tasks?.length ?? 0));
    expect(total, 6);
  });

  test('sorts tasks by position and merges labels split across related pages', () async {
    Map<String, Object?> task(String id, double position, List<Map<String, Object?>> labels) => {
      'id': id,
      'projectId': 'p',
      'title': id,
      'number': 1,
      'status': 'to-do',
      'priority': 'low',
      'position': position,
      'createdAt': '2026-11-06T00:00:00Z',
      'labels': labels,
    };
    Map<String, Object?> response(List<Map<String, Object?>> tasks, int relatedPage) => {
      'data': {
        'id': 'p',
        'name': 'P',
        'slug': 'P',
        'workspaceId': 'w',
        'columns': [
          {'id': 'to-do', 'slug': 'to-do', 'name': 'To Do', 'position': 0, 'tasks': tasks},
        ],
        'archivedTasks': <Object?>[],
        'plannedTasks': <Object?>[],
      },
      'pagination': {
        'total': 2,
        'page': 1,
        'pageSize': 100,
        'totalPages': 1,
        'relatedPage': relatedPage,
        'relatedPageSize': 1,
        'relatedTotalPages': 2,
      },
    };
    server.on('api/task/tasks/', (request) {
      final related = int.tryParse(request.query['relatedPage'] ?? '') ?? 1;
      return FakeResponse(
        200,
        related == 1
            ? response([
                task('b', 2, [
                  {'id': 'l1', 'name': 'one', 'color': 'red'},
                ]),
                task('a', 1, const []),
              ], 1)
            : response([
                task('b', 2, [
                  {'id': 'l2', 'name': 'two', 'color': 'blue'},
                ]),
              ], 2),
      );
    });

    final board = await loadFullBoard(api, 'p');
    final tasks = board.columns.single.tasks!;
    expect(tasks.map((t) => t.id), ['a', 'b']);
    expect(tasks.last.labels?.map((l) => l.name), ['one', 'two']);
  });

  test('a failed page fails the whole load', () async {
    server.boardPageSize = 2;
    server.on('api/task/tasks/', (request) {
      if (request.query['page'] == '2') return const FakeResponse(500);
      return const FakeResponse(200, {
        'data': {'id': 'p', 'name': 'P', 'slug': 'P', 'workspaceId': 'w', 'columns': <Object?>[]},
        'pagination': {'total': 3, 'page': 1, 'pageSize': 2, 'totalPages': 2},
      });
    });
    await expectLater(loadFullBoard(api, 'p'), throwsA(isA<ApiError>()));
  });

  group('loadDescription', () {
    test('returns an inline description without another request', () async {
      final task = await api.task('task-2');
      server.requests.clear();
      expect(await loadDescription(api, task), contains('**first**'));
      expect(server.requests, isEmpty);
    });

    test('follows the pages of a deferred description, passing the version', () async {
      server.on('/description', (request) {
        final offset = request.query['offset'];
        return FakeResponse(
          200,
          offset == '0'
              ? {'content': 'Hello ', 'version': 'v1', 'nextOffset': 6}
              : {'content': 'world', 'version': 'v1', 'nextOffset': null},
        );
      });
      final task = Task.fromJson(const {
        'id': 'task-1',
        'title': 't',
        'number': 1,
        'status': 'to-do',
        'priority': 'low',
        'projectId': 'p',
        'createdAt': '2026-11-06T00:00:00Z',
        'descriptionDeferred': true,
      });
      expect(await loadDescription(api, task), 'Hello world');
      expect(server.requests.last.query['version'], 'v1');
    });
  });
}
