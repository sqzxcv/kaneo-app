import 'kaneo_api.dart';
import 'models.dart';

List<TaskLabel> _mergeLabels(List<TaskLabel>? a, List<TaskLabel>? b) {
  final byId = <String, TaskLabel>{};
  for (final label in [...?a, ...?b]) {
    byId[label.id] = label;
  }
  return byId.values.toList();
}

void _appendTo(Map<String, BoardTask> target, List<BoardTask>? tasks) {
  for (final task in tasks ?? const <BoardTask>[]) {
    final prior = target[task.id];
    target[task.id] = prior == null
        ? task
        : prior.copyWith(labels: _mergeLabels(prior.labels, task.labels));
  }
}

/// Loads every page of a board. The API pages tasks (100 at most) and, per task page, pages the
/// related labels separately; both are followed to completion and merged by id.
Future<BoardData> loadFullBoard(KaneoApi api, String projectId) async {
  final first = await api.board(projectId, page: 1);
  final columnMeta = <String, BoardColumn>{};
  final columnTasks = <String, Map<String, BoardTask>>{};
  final archived = <String, BoardTask>{};
  final planned = <String, BoardTask>{};

  void merge(BoardData data) {
    for (final column in data.columns) {
      columnMeta.putIfAbsent(column.id, () => column.copyWith(tasks: const <BoardTask>[]));
      _appendTo(columnTasks.putIfAbsent(column.id, () => {}), column.tasks);
    }
    _appendTo(archived, data.archivedTasks);
    _appendTo(planned, data.plannedTasks);
  }

  Future<void> loadRelated(int page, int? relatedTotal) async {
    for (var related = 2; related <= (relatedTotal ?? 1); related++) {
      merge((await api.board(projectId, page: page, relatedPage: related)).data);
    }
  }

  merge(first.data);
  await loadRelated(1, first.pagination?.relatedTotalPages);
  for (var page = 2; page <= (first.pagination?.totalPages ?? 1); page++) {
    final next = await api.board(projectId, page: page);
    merge(next.data);
    await loadRelated(page, next.pagination?.relatedTotalPages);
  }

  int byPosition(BoardTask a, BoardTask b) =>
      (a.position ?? double.maxFinite).compareTo(b.position ?? double.maxFinite);

  final columns = columnMeta.values.toList()
    ..sort((a, b) => (a.position ?? 0).compareTo(b.position ?? 0));
  return first.data.copyWith(
    columns: [
      for (final meta in columns)
        meta.copyWith(
          tasks: (columnTasks[meta.id]?.values.toList() ?? <BoardTask>[])..sort(byPosition),
        ),
    ],
    archivedTasks: archived.values.toList(),
    plannedTasks: planned.values.toList(),
  );
}

/// Reads a task description, following description pages when the detail view defers a large body.
Future<String> loadDescription(KaneoApi api, Task task) async {
  if (task.descriptionDeferred != true) return task.description ?? '';
  final text = StringBuffer();
  int? offset = 0;
  String? version;
  while (offset != null) {
    final page = await api.descriptionPage(task.id, offset, version: version);
    version = page.version;
    text.write(page.content);
    offset = page.nextOffset;
  }
  return text.toString();
}
