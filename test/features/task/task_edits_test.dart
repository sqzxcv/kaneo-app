import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_data.dart';
import 'package:kaneo_app/features/task/task_edits.dart';
import 'package:kaneo_app/features/task/task_panel.dart';

const _project = 'p1';

BoardTask _card(String id, String status, num position) => BoardTask(
  id: id,
  title: id,
  status: status,
  position: position,
  projectId: _project,
  userId: 'u1',
  assigneeId: 'u1',
  assigneeName: 'Ana',
  assigneeImage: 'ana.png',
  labels: const [TaskLabel(id: 'l1', name: 'bug', color: 'red')],
  subtaskCounts: const SubtaskCounts(completed: 1, total: 2),
);

BoardColumn _column(String slug, List<BoardTask> tasks) =>
    BoardColumn(id: slug, slug: slug, name: slug, tasks: tasks);

BoardData _board() => BoardData(
  id: _project,
  name: 'Project',
  slug: 'prj',
  workspaceId: 'w1',
  columns: [
    _column('to-do', [_card('a', 'to-do', 0), _card('b', 'to-do', 3)]),
    _column('done', [_card('c', 'done', 1), _card('d', 'done', 5)]),
  ],
  plannedTasks: [_card('p', statusPlanned, 0)],
  archivedTasks: const [],
);

Task _task(String id, String status, {num position = 0}) => Task(
  id: id,
  projectId: _project,
  title: id,
  status: status,
  position: position,
  userId: 'u1',
  assigneeId: 'u1',
  assigneeName: 'Ana',
);

List<String> _ids(List<BoardTask>? tasks) => [for (final t in tasks!) t.id];

Label _label(String id, String name, {String? taskId, String? deleting}) =>
    Label(id: id, name: name, color: 'red', taskId: taskId, deletionStartedAt: deleting);

void main() {
  group('boardWithTask', () {
    test('copies the edited fields and keeps what a task does not carry', () {
      final board = boardWithTask(
        _board(),
        _task(
          'a',
          'to-do',
        ).copyWith(title: 'New', priority: 'high', startDate: '2027-01-01', dueDate: '2027-01-02'),
      );
      final card = board.columns.first.tasks!.first;
      expect(card.title, 'New');
      expect(card.priority, 'high');
      expect(card.startDate, '2027-01-01');
      expect(card.dueDate, '2027-01-02');
      expect(card.labels!.single.name, 'bug');
      expect(card.subtaskCounts!.total, 2);
      expect(card.assigneeImage, 'ana.png');
      expect(_ids(board.columns.first.tasks), ['a', 'b']);
    });

    test('clears what the task has cleared', () {
      final board = boardWithTask(
        _board(),
        _task('a', 'to-do').copyWith(userId: null, assigneeId: null, assigneeName: null),
      );
      final card = board.columns.first.tasks!.first;
      expect(card.userId, isNull);
      expect(card.assigneeName, isNull);
      expect(card.assigneeImage, isNull);
    });

    test('takes the new picture when the assignee changes', () {
      final board = boardWithTask(
        _board(),
        _task('a', 'to-do').copyWith(userId: 'u2', assigneeId: 'u2', assigneeName: 'Bo'),
        assigneeImage: 'bo.png',
      );
      expect(board.columns.first.tasks!.first.assigneeImage, 'bo.png');
    });

    test('moves the card to the column of its status, by position', () {
      final board = boardWithTask(_board(), _task('b', 'done', position: 3));
      expect(_ids(board.columns[0].tasks), ['a']);
      expect(_ids(board.columns[1].tasks), ['c', 'b', 'd']);
      expect(board.columns[1].tasks![1].status, 'done');
    });

    test('moves the card in and out of planned and archived', () {
      final archived = boardWithTask(_board(), _task('a', statusArchived));
      expect(_ids(archived.columns[0].tasks), ['b']);
      expect(_ids(archived.archivedTasks), ['a']);

      final back = boardWithTask(_board(), _task('p', 'to-do', position: 1));
      expect(back.plannedTasks, isEmpty);
      expect(_ids(back.columns[0].tasks), ['a', 'p', 'b']);
    });

    test('a column called planned is where planned tasks go', () {
      final board = _board();
      final withColumn = board.copyWith(
        columns: [...board.columns, _column(statusPlanned, const [])],
        plannedTasks: const [],
      );
      final moved = boardWithTask(withColumn, _task('a', statusPlanned));
      expect(_ids(moved.columns.last.tasks), ['a']);
      expect(moved.plannedTasks, isEmpty);
    });

    test('a status with nowhere to go leaves the card where it is', () {
      final board = boardWithTask(_board(), _task('a', 'gone'));
      expect(_ids(board.columns[0].tasks), ['a', 'b']);
      expect(board.columns[0].tasks!.first.status, 'gone');
    });

    test('a task that is not on the board changes nothing', () {
      final board = _board();
      expect(identical(boardWithTask(board, _task('x', 'to-do')), board), isTrue);
    });
  });

  group('boardWithoutCard', () {
    test('takes the card out of its column and leaves the others', () {
      final board = boardWithoutCard(_board(), 'a');
      expect(_ids(board.columns.first.tasks), ['b']);
      expect(_ids(board.columns.last.tasks), ['c', 'd']);
      expect(_ids(board.plannedTasks), ['p']);
    });

    test('takes a planned card out too', () {
      expect(boardWithoutCard(_board(), 'p').plannedTasks, isEmpty);
    });

    test('leaves a board without the card as it was', () {
      final board = boardWithoutCard(_board(), 'missing');
      expect(boardTasks(board).map((t) => t.id), boardTasks(_board()).map((t) => t.id));
    });
  });

  group('revertTaskEdit', () {
    test('undoes the edit and keeps a later one', () {
      final before = _task('a', 'to-do');
      final after = before.copyWith(priority: 'high');
      final current = after.copyWith(title: 'Later', dueDate: '2027-01-01');
      final reverted = revertTaskEdit(current, before: before, after: after);
      expect(reverted.priority, before.priority);
      expect(reverted.title, 'Later');
      expect(reverted.dueDate, '2027-01-01');
    });

    test('puts back a cleared field and an assignee in full', () {
      final before = _task('a', 'to-do').copyWith(startDate: '2027-01-01');
      final after = before.copyWith(
        startDate: null,
        userId: null,
        assigneeId: null,
        assigneeName: null,
      );
      final reverted = revertTaskEdit(after, before: before, after: after);
      expect(reverted.startDate, '2027-01-01');
      expect(reverted.userId, 'u1');
      expect(reverted.assigneeName, 'Ana');
    });
  });

  group('taskLabelOptions', () {
    test('offers one per name and prefers the workspace label', () {
      final options = taskLabelOptions([
        _label('copy', 'bug', taskId: 't1'),
        _label('bug', 'bug'),
        _label('ui', 'ui'),
      ], 't1');
      expect([for (final o in options) o.id], ['bug', 'ui']);
    });

    test('leaves out other tasks\' copies and labels being deleted', () {
      final options = taskLabelOptions([
        _label('other', 'theirs', taskId: 't2'),
        _label('gone', 'old', deleting: '2027-01-01'),
        _label('gone-copy', 'old', taskId: 't1'),
        _label('mine', 'only here', taskId: 't1'),
      ], 't1');
      expect([for (final o in options) o.id], ['mine']);
    });
  });

  group('labelChanges', () {
    final options = [_label('bug', 'bug'), _label('ui', 'ui')];
    final attached = [_label('bug-copy', 'bug', taskId: 't1')];

    test('matches copies by name', () {
      expect(selectedLabelIds(attached, options), {'bug'});
    });

    test('the same selection changes nothing', () {
      expect(labelChanges(attached: attached, options: options, selected: {'bug'}).isEmpty, isTrue);
    });

    test('attaches workspace labels and detaches the task\'s copies', () {
      final changes = labelChanges(attached: attached, options: options, selected: {'ui'});
      expect(changes.attach, ['ui']);
      expect(changes.detach, ['bug-copy']);
    });

    test('attaches a label created while picking', () {
      final changes = labelChanges(attached: attached, options: options, selected: {'bug', 'new'});
      expect(changes.attach, ['new']);
      expect(changes.detach, isEmpty);
    });

    test('keeps a label on the task that was not offered', () {
      final changes = labelChanges(
        attached: [
          ...attached,
          _label('legacy-copy', 'legacy', taskId: 't1'),
        ],
        options: options,
        selected: const {},
      );
      expect(changes.detach, ['bug-copy']);
    });
  });

  test('a panel leaves part of the page in view, down to the smallest wide window', () {
    expect(taskPanelWidth(1102), 896);
    expect(taskPanelWidth(760), 664);
    expect(taskPanelWidth(504), 408);
    expect(taskPanelWidth(336), 320);
    expect(taskPanelWidth(300), 300);
  });
}
