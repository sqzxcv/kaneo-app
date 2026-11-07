import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/realtime/board_patch.dart';

BoardTask _card(String id, String status, num? position, {String? userId, String? image}) =>
    BoardTask(
      id: id,
      title: id,
      status: status,
      position: position,
      projectId: 'p',
      userId: userId,
      assigneeId: userId,
      assigneeImage: image,
      subtaskCounts: const SubtaskCounts(completed: 1, total: 2),
      labels: const [TaskLabel(id: 'l', name: 'bug', color: 'red')],
    );

BoardData _board({List<BoardTask> todo = const [], List<BoardTask> doing = const []}) => BoardData(
  id: 'p',
  name: 'Project',
  slug: 'prj',
  workspaceId: 'w',
  columns: [
    BoardColumn(id: 'c1', slug: 'to-do', name: 'To do', tasks: todo),
    BoardColumn(id: 'c2', slug: 'doing', name: 'Doing', tasks: doing),
  ],
  plannedTasks: const [],
  archivedTasks: const [],
);

List<String> _ids(BoardData board, int column) => [
  for (final task in board.columns[column].tasks!) task.id,
];

TaskForBoard _read(String id, String status, num position, {String? userId}) => TaskForBoard(
  task: Task(
    id: id,
    projectId: 'p',
    title: 'new',
    status: status,
    position: position,
    userId: userId,
  ),
  subtaskCounts: const SubtaskCounts(completed: 2, total: 2),
);

void main() {
  group('boardWithCard', () {
    test('changes a card in place when it stays where it is', () {
      final board = _board(
        todo: [_card('a', 'to-do', 1), _card('b', 'to-do', 1), _card('c', 'to-do', 1)],
      );
      final next = boardWithCard(board, _card('b', 'to-do', 1).copyWith(title: 'changed'))!;
      expect(_ids(next, 0), ['a', 'b', 'c']);
      expect(next.columns[0].tasks![1].title, 'changed');
    });

    test('hands back the same board when nothing changes', () {
      final board = _board(todo: [_card('a', 'to-do', 1)]);
      expect(boardWithCard(board, _card('a', 'to-do', 1)), same(board));
    });

    test('moves a card to the column of its status, at its position', () {
      final board = _board(
        todo: [_card('a', 'to-do', 0)],
        doing: [_card('b', 'doing', 0), _card('c', 'doing', 2)],
      );
      final next = boardWithCard(board, _card('a', 'doing', 1))!;
      expect(_ids(next, 0), isEmpty);
      expect(_ids(next, 1), ['b', 'a', 'c']);
    });

    test('moves a card within its column by position', () {
      final board = _board(
        todo: [_card('a', 'to-do', 0), _card('b', 'to-do', 1), _card('c', 'to-do', 2)],
      );
      expect(_ids(boardWithCard(board, _card('a', 'to-do', 5))!, 0), ['b', 'c', 'a']);
    });

    test('adds a card it did not have, and leaves cards of equal position in their order', () {
      final ties = [for (final (i, id) in 'abcdefgh'.split('').indexed) _card(id, 'to-do', i ~/ 8)];
      final next = boardWithCard(_board(todo: ties), _card('z', 'to-do', 0))!;
      expect(_ids(next, 0), [...'abcdefgh'.split(''), 'z']);
    });

    test('a card with no position goes last', () {
      final board = _board(todo: [_card('a', 'to-do', 5)]);
      expect(_ids(boardWithCard(board, _card('b', 'to-do', null))!, 0), ['a', 'b']);
    });

    test('takes planned and archived tasks off the columns', () {
      final board = _board(todo: [_card('a', 'to-do', 0)]);
      final planned = boardWithCard(board, _card('a', statusPlanned, 0))!;
      expect(_ids(planned, 0), isEmpty);
      expect(planned.plannedTasks.map((t) => t.id), ['a']);
      final archived = boardWithCard(planned, _card('a', statusArchived, 0))!;
      expect(archived.plannedTasks, isEmpty);
      expect(archived.archivedTasks.map((t) => t.id), ['a']);
    });

    test('says so when a status has nowhere to show', () {
      expect(
        boardWithCard(_board(todo: [_card('a', 'to-do', 0)]), _card('a', 'new-column', 0)),
        isNull,
      );
    });
  });

  group('boardWithReorder', () {
    final board = _board(
      todo: [_card('a', 'to-do', 0), _card('b', 'to-do', 1), _card('c', 'to-do', 2)],
      doing: [_card('d', 'doing', 0)],
    );

    test('puts every card named where the event says', () {
      final next = boardWithReorder(board, const [
        PositionUpdate(id: 'c', position: 0),
        PositionUpdate(id: 'a', position: 1),
        PositionUpdate(id: 'b', position: 2, status: 'doing'),
        PositionUpdate(id: 'd', position: 0),
      ])!;
      expect(_ids(next, 0), ['c', 'a']);
      expect(_ids(next, 1), ['d', 'b']);
    });

    test('hands back the same board when it already shows the reorder', () {
      expect(
        boardWithReorder(board, const [
          PositionUpdate(id: 'a', position: 0, status: 'to-do'),
          PositionUpdate(id: 'b', position: 1),
        ]),
        same(board),
      );
    });

    test('says so when it names a task or a status the board does not know', () {
      expect(boardWithReorder(board, const [PositionUpdate(id: 'x', position: 0)]), isNull);
      expect(
        boardWithReorder(board, const [PositionUpdate(id: 'a', position: 0, status: 'new')]),
        isNull,
      );
    });
  });

  group('boardWithoutTask', () {
    test('takes the card off wherever it is', () {
      final board = _board(todo: [_card('a', 'to-do', 0), _card('b', 'to-do', 1)]);
      expect(_ids(boardWithoutTask(board, 'a'), 0), ['b']);
    });

    test('hands back the same board when it was not there', () {
      final board = _board(todo: [_card('a', 'to-do', 0)]);
      expect(boardWithoutTask(board, 'x'), same(board));
    });
  });

  group('boardWithParentCounts', () {
    final board = _board(todo: [_card('a', 'to-do', 0)]);

    test('updates the progress of the parent', () {
      final next = boardWithParentCounts(
        board,
        const ParentSubtaskCounts(taskId: 'a', counts: SubtaskCounts(completed: 2, total: 2)),
      );
      expect(next.columns[0].tasks!.single.subtaskCounts!.completed, 2);
    });

    test('hands back the same board when the progress is the same, or the parent elsewhere', () {
      expect(
        boardWithParentCounts(
          board,
          const ParentSubtaskCounts(taskId: 'a', counts: SubtaskCounts(completed: 1, total: 2)),
        ),
        same(board),
      );
      expect(
        boardWithParentCounts(
          board,
          const ParentSubtaskCounts(taskId: 'x', counts: SubtaskCounts(completed: 1, total: 2)),
        ),
        same(board),
      );
    });
  });

  group('cardFromRead', () {
    test('takes the fields of the task, and keeps what only a board read carries', () {
      final board = _board(
        todo: [_card('a', 'to-do', 0, userId: 'u', image: 'u.png')],
      );
      final card = cardFromRead(board, _read('a', 'doing', 3, userId: 'u'));
      expect(card.title, 'new');
      expect(card.status, 'doing');
      expect(card.position, 3);
      expect(card.subtaskCounts!.completed, 2);
      expect(card.labels!.single.name, 'bug');
      expect(card.assigneeImage, 'u.png');
    });

    test('replaces the labels when they were read too', () {
      final board = _board(todo: [_card('a', 'to-do', 0)]);
      final card = cardFromRead(
        board,
        _read('a', 'to-do', 0),
        labels: const [Label(id: 'n', name: 'new', color: 'blue')],
      );
      expect(card.labels!.single.name, 'new');
    });

    test('a new assignee brings the picture from another card, or from the members, or none', () {
      final board = _board(
        todo: [_card('a', 'to-do', 0, userId: 'u', image: 'u.png')],
        doing: [_card('b', 'doing', 0, userId: 'v', image: 'v.png')],
      );
      expect(cardFromRead(board, _read('a', 'to-do', 0, userId: 'v')).assigneeImage, 'v.png');
      expect(
        cardFromRead(
          board,
          _read('a', 'to-do', 0, userId: 'w'),
          memberImage: (id) => '$id.png',
        ).assigneeImage,
        'w.png',
      );
      expect(cardFromRead(board, _read('a', 'to-do', 0, userId: 'w')).assigneeImage, isNull);
      expect(cardFromRead(board, _read('a', 'to-do', 0)).assigneeImage, isNull);
    });

    test('makes a card for a task the board did not have', () {
      final card = cardFromRead(_board(), _read('new', 'to-do', 1));
      expect(card.id, 'new');
      expect(card.labels, isNull);
    });
  });
}
