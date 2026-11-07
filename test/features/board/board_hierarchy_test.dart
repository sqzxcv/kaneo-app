import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_expansion.dart';
import 'package:kaneo_app/features/board/board_hierarchy.dart';
import 'package:shared_preferences/shared_preferences.dart';

BoardTask task(String id, {String status = 'todo'}) =>
    BoardTask(id: id, title: 'Title $id', status: status, projectId: 'p');
TaskRelation edge(String parent, String child, {String type = 'subtask'}) => TaskRelation(
  id: '$parent-$child',
  sourceTaskId: parent,
  targetTaskId: child,
  relationType: type,
);
List<HierarchyRow> rows(
  List<BoardTask> tasks,
  List<TaskRelation> relations, {
  Set<String> expanded = const {},
  List<BoardTask>? all,
}) => buildBoardHierarchy(
  tasks: tasks,
  allTasks: all ?? tasks,
  relations: relations,
  expanded: expanded,
);

void main() {
  test('same-status children are hidden until each ancestor is expanded', () {
    final tasks = [task('a'), task('b'), task('c')];
    final relations = [edge('a', 'b'), edge('b', 'c')];
    expect(rows(tasks, relations).map((r) => r.task.id), ['a']);
    final first = rows(tasks, relations, expanded: {'a'});
    expect(first.map((r) => r.task.id), ['a', 'b']);
    expect(first.map((r) => r.depth), [0, 1]);
    final all = rows(tasks, relations, expanded: {'a', 'b'});
    expect(all.map((r) => r.task.id), ['a', 'b', 'c']);
    expect(all.map((r) => r.depth), [0, 1, 2]);
    expect(rows(tasks, relations, expanded: {'b'}).map((r) => r.task.id), ['a']);
  });
  test('cross-status and filtered parents cannot hide a child', () {
    final parent = task('a');
    final child = task('b', status: 'doing');
    final cross = rows([parent, child], [edge('a', 'b')]);
    expect(cross.length, 2);
    expect(cross.last.depth, 0);
    expect(cross.last.parentTitles, ['Title a']);
    final filtered = rows([task('b')], [edge('a', 'b')], all: [parent, task('b')]);
    expect(filtered.single.parentTitles, ['Title a']);
    expect(filtered.single.depth, 0);
  });
  test('multi-parent diamonds choose one stable parent and never duplicate rows', () {
    final tasks = [task('a'), task('b'), task('c'), task('d')];
    final relations = [edge('b', 'c'), edge('a', 'c'), edge('c', 'd'), edge('a', 'c')];
    expect(rows(tasks, relations).map((r) => r.task.id), ['a', 'b']);
    final result = rows(tasks, relations, expanded: {'a', 'b', 'c'});
    expect(result.map((r) => r.task.id), ['a', 'c', 'd', 'b']);
    expect(result.map((r) => r.task.id).toSet().length, 4);
  });
  test(
    'cycles expose a root and remain finite, self edges and other relation kinds are ignored',
    () {
      final tasks = [task('a'), task('b'), task('c'), task('d')];
      final relations = [
        edge('a', 'b'),
        edge('b', 'c'),
        edge('c', 'a'),
        edge('d', 'd'),
        edge('a', 'd', type: 'blocks'),
      ];
      expect(rows(tasks, relations).map((r) => r.task.id), ['a', 'd']);
      expect(rows(tasks, relations, expanded: {'a', 'b', 'c', 'd'}).map((r) => r.task.id), [
        'a',
        'b',
        'c',
        'd',
      ]);
    },
  );
  test('deep cyclic graphs use bounded rows and no recursion', () {
    final tasks = [for (var i = 0; i < 3000; i++) task('$i')];
    final relations = [for (var i = 1; i < 3000; i++) edge('${i - 1}', '$i'), edge('2999', '0')];
    final result = rows(tasks, relations, expanded: tasks.map((t) => t.id).toSet());
    expect(result.length, 3000);
    expect(result.last.depth, 2999);
  });
  test('expansion is stored per project and restored by a fresh provider container', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make() =>
        ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    final first = make();
    final subscription = first.listen(boardExpansionProvider('one'), (_, _) {});
    await first.read(boardExpansionProvider('one').notifier).toggle('a');
    expect(first.read(boardExpansionProvider('two')), isEmpty);
    expect(prefs.getStringList(boardExpansionKey('one')), ['a']);
    subscription.close();
    first.dispose();
    final later = make();
    addTearDown(later.dispose);
    final keep = later.listen(boardExpansionProvider('one'), (_, _) {});
    addTearDown(keep.close);
    expect(later.read(boardExpansionProvider('one')), {'a'});
    await later.read(boardExpansionProvider('one').notifier).toggle('a');
    expect(prefs.getStringList(boardExpansionKey('one')), isEmpty);
  });
}
