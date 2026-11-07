import '../../core/core.dart';
import '../board/board_data.dart';
import '../task/task_edits.dart' show boardWithoutCard;

num _rank(BoardTask task) => task.position ?? double.maxFinite;

/// [tasks] with [card] after those that don't come later than it. The rest stay exactly in their
/// order, unlike after a sort, so cards with equal positions don't trade places.
List<BoardTask> _placed(List<BoardTask> tasks, BoardTask card) {
  final next = tasks.indexWhere((t) => _rank(t) > _rank(card));
  return [...tasks]..insert(next < 0 ? tasks.length : next, card);
}

bool _hasPlace(BoardData board, String status) =>
    status == statusPlanned ||
    status == statusArchived ||
    board.columns.any((c) => c.slug == status);

/// [board] without the card [id]. The same board if it isn't there.
BoardData boardWithoutTask(BoardData board, String id) =>
    boardTasks(board).any((t) => t.id == id) ? boardWithoutCard(board, id) : board;

/// [board] with [card] where its status and position put it, in place of the card it had for that
/// task. The same board if nothing would change, and null if its status has nowhere to show, which
/// means the board is out of date.
BoardData? boardWithCard(BoardData board, BoardTask card) {
  if (!_hasPlace(board, card.status)) return null;
  final current = boardTasks(board).where((t) => t.id == card.id).firstOrNull;
  if (current != null && current.status == card.status && current.position == card.position) {
    return _sameCard(current, card) ? board : updateBoardTask(board, card.id, (_) => card);
  }
  final rest = boardWithoutTask(board, card.id);
  final inColumn = rest.columns.any((c) => c.slug == card.status);
  return rest.copyWith(
    columns: [
      for (final c in rest.columns)
        c.slug == card.status ? c.copyWith(tasks: _placed(c.tasks ?? const [], card)) : c,
    ],
    plannedTasks: !inColumn && card.status == statusPlanned
        ? _placed(rest.plannedTasks, card)
        : rest.plannedTasks,
    archivedTasks: !inColumn && card.status == statusArchived
        ? _placed(rest.archivedTasks, card)
        : rest.archivedTasks,
  );
}

bool _sameCard(BoardTask a, BoardTask b) => a.toJson().toString() == b.toJson().toString();

/// [board] with the positions and statuses of a reorder, which the event carries in full. The same
/// board if it already shows them, as it does after its own move. Null if the reorder names a task or
/// a status it doesn't know, which means the board is out of date.
BoardData? boardWithReorder(BoardData board, List<PositionUpdate> changes) {
  final cards = {for (final task in boardTasks(board)) task.id: task};
  var next = board;
  for (final change in changes) {
    final card = cards[change.id];
    if (card == null) return null;
    final moved = boardWithCard(
      next,
      card.copyWith(position: change.position, status: change.status ?? card.status),
    );
    if (moved == null) return null;
    next = moved;
  }
  return next;
}

/// [board] with the progress of [parent], if it shows that task.
BoardData boardWithParentCounts(BoardData board, ParentSubtaskCounts parent) {
  final card = boardTasks(board).where((t) => t.id == parent.taskId).firstOrNull;
  if (card == null) return board;
  final same =
      card.subtaskCounts?.completed == parent.counts.completed &&
      card.subtaskCounts?.total == parent.counts.total;
  if (same) return board;
  return updateBoardTask(board, parent.taskId, (t) => t.copyWith(subtaskCounts: parent.counts));
}

/// The card for a task read from the server, starting from the card [board] has for it, because a
/// read of one task leaves out what only the board's own read carries. [labels] replaces what the
/// card shows, if read too. A change of assignee takes the picture from another card with that person
/// or else from [memberImage], and there's no picture until the board is next read otherwise.
BoardTask cardFromRead(
  BoardData board,
  TaskForBoard read, {
  List<Label>? labels,
  String? Function(String userId)? memberImage,
}) {
  final task = read.task;
  final card = boardTasks(board).where((t) => t.id == task.id).firstOrNull;
  final userId = task.userId;
  final String? image;
  if (userId == null) {
    image = null;
  } else if (userId == card?.userId) {
    image = card?.assigneeImage;
  } else {
    image =
        boardTasks(board).where((t) => t.userId == userId).firstOrNull?.assigneeImage ??
        memberImage?.call(userId);
  }
  return BoardTask(
    id: task.id,
    title: task.title,
    number: task.number ?? card?.number,
    description: task.description ?? card?.description,
    status: task.status,
    priority: task.priority,
    startDate: task.startDate,
    dueDate: task.dueDate,
    position: task.position ?? card?.position,
    createdAt: task.createdAt ?? card?.createdAt,
    userId: userId,
    assigneeId: task.assigneeId ?? userId,
    assigneeName: task.assigneeName,
    assigneeImage: image,
    projectId: task.projectId,
    subtaskCounts: read.subtaskCounts ?? card?.subtaskCounts,
    labels: labels == null ? card?.labels : cardLabels(labels),
  );
}

List<TaskLabel> cardLabels(List<Label> labels) => [
  for (final label in labels) TaskLabel(id: label.id, name: label.name, color: label.color),
];
