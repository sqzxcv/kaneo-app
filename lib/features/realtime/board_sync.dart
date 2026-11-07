import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../board/board_data.dart';
import '../task/task_activity.dart';
import '../task/task_edits.dart';
import '../task/task_relations.dart';
import 'board_patch.dart';

/// What the events of one moment add up to.
class _Changes {
  final reorders = <List<PositionUpdate>>[];
  final deleted = <String>{};

  /// Tasks to read again.
  final tasks = <String>{};

  /// Tasks to read the labels of again.
  final labels = <String>{};

  /// Tasks to read the relations of again, if they are open.
  final linked = <String>{};

  /// Tasks to read the comments and the record of again, if they are open.
  final activity = <String>{};

  /// A relation changed on the project, so the hierarchy has to be read again.
  bool relations = false;

  /// The progress of a parent changed, with no word on which. A task read along with it says, if
  /// that task's on the board. Otherwise only the whole board does.
  bool parents = false;

  /// Only reading the whole board will do.
  bool reload = false;

  bool project = false;
  bool members = false;

  bool get isEmpty =>
      reorders.isEmpty &&
      deleted.isEmpty &&
      tasks.isEmpty &&
      labels.isEmpty &&
      linked.isEmpty &&
      activity.isEmpty &&
      !relations &&
      !parents &&
      !reload &&
      !project &&
      !members;

  void add(_Changes other) {
    reorders.insertAll(0, other.reorders);
    deleted.addAll(other.deleted);
    tasks.addAll(other.tasks);
    labels.addAll(other.labels);
    linked.addAll(other.linked);
    activity.addAll(other.activity);
    relations |= other.relations;
    parents |= other.parents;
    reload |= other.reload;
    project |= other.project;
    members |= other.members;
  }
}

/// What was read for one task. No [read] means it no longer exists.
class _Fresh {
  const _Fresh(this.read, this.labels);

  final TaskForBoard? read;
  final List<Label>? labels;
}

/// Keeps an open board, and the tasks open in its project, in step with what happens elsewhere. They
/// all listen to this, which makes one socket for a project, whichever of them opened first.
///
/// Without a board there are only the open tasks to read again. See [_boardOpen].
///
/// Events of one moment are handled together, and each brings only the cards it is about up to date,
/// since a board can be too large to read for every change. Only what can't be known otherwise reads
/// the whole board: a burst of changes, a change to the project itself, or a time without a socket.
///
/// Nothing is applied under something in progress on this device. A card being moved or dragged stays
/// as it is, and what happened meanwhile follows afterwards, so that a read from before a save can't
/// undo that save on screen.
class BoardSync {
  BoardSync._(this._ref, this.projectId);

  /// Short enough not to be seen, and long enough for what one change sets off to arrive together. The
  /// server sends what it has every 100 ms.
  static const _window = Duration(milliseconds: 250);

  /// More tasks than this at once cost more to read one by one than the board would, and the web app
  /// draws the line at the same place.
  static const _maxTasksRead = 4;

  /// Past this, a drag no longer holds things back. It could only be one that lost track of its end.
  static const _longestDrag = Duration(minutes: 1);

  static const _boardChanges = {'TASK_CREATED', 'TASK_DELETED', 'TASK_MOVED', 'TASKS_REORDERED'};

  final Ref _ref;
  final String projectId;

  var _pending = _Changes();
  Timer? _timer;
  bool _working = false;
  bool _disposed = false;
  bool _hasOpened = false;
  DateTime? _dragStarted;

  /// Whether the page has a change to the board on its way to the server.
  bool Function() saving = () => false;

  set dragging(bool value) => _dragStarted = value ? DateTime.now() : null;

  bool get _dragHolds {
    final started = _dragStarted;
    return started != null && DateTime.now().difference(started) < _longestDrag;
  }

  AsyncNotifierProvider<CachedQuery<BoardData>, BoardData> get _query => boardQuery(projectId);

  /// A task can be open with no board around, as from the inbox. Reading the query would load the
  /// whole board then, for nobody, so everything to do with the board asks this first.
  bool get _boardOpen => _ref.read(_query.exists);

  void _dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  /// The first socket usually opens while the board is loading, and so has missed nothing that matters.
  /// A task's opens just after the task was read, which comes to the same. After that there has been a
  /// time without one, and no way to tell what happened in it.
  void _opened() {
    final first = !_hasOpened;
    _hasOpened = true;
    if (!_boardOpen) {
      if (!first) _refreshOpenTasks();
      return;
    }
    if (first && _ref.read(_query).isLoading) return;
    _pending.reload = true;
    _arm();
  }

  void _revoked() {
    if (!_boardOpen) {
      _refreshOpenTasks();
      return;
    }
    _pending.reload = true;
    _arm();
  }

  void _onEvent(RealtimeEvent event) {
    final id = event.taskId;
    // The pages of a board being read can miss a task when tasks come, go or trade places meanwhile.
    if (_boardChanges.contains(event.type) && _boardOpen && _ref.read(_query).isLoading) {
      _pending.reload = true;
    }
    switch (event.type) {
      case 'TASK_UPDATED':
      case 'TASK_CREATED':
      case 'TASK_MOVED':
        if (id == null) {
          _pending.reload = true;
        } else {
          _pending.tasks.add(id);
        }
        if (event.type == 'TASK_MOVED') _pending.relations = true;
      case 'TASK_DELETED':
        if (id == null) {
          _pending.reload = true;
        } else {
          _pending.deleted.add(id);
        }
        _pending.relations = true;
      case 'TASK_LABEL_UPDATED':
        if (id != null) _pending.labels.add(id);
      case 'TASKS_REORDERED':
        final reorder = _reorderIn(event);
        if (reorder == null) {
          _pending.reload = true;
        } else {
          _pending.reorders.add(reorder);
        }
      case 'TASK_RELATION_UPDATED':
        final ends = {event.taskId, event.sourceTaskId, event.targetTaskId}.nonNulls;
        if (ends.isEmpty) {
          _pending.parents = true;
        } else {
          _pending.relations = true;
          _pending.tasks.addAll(ends);
          _pending.linked.addAll(ends);
        }
      case 'COMMENT_UPDATED':
        if (id != null) _pending.activity.add(id);
      case 'PROJECT_UPDATED':
      case 'PROJECT_MOVED':
        _pending.project = true;
        _pending.reload = true;
      case 'PROJECT_MEMBERS_UPDATED':
        _pending.members = true;
      default:
        return;
    }
    _arm();
  }

  List<PositionUpdate>? _reorderIn(RealtimeEvent event) {
    try {
      return [
        for (final task in event.data['tasks'] as List)
          PositionUpdate.fromJson((task as Map).cast<String, dynamic>()),
      ];
    } on TypeError {
      return null;
    }
  }

  void _arm() {
    if (_disposed) return;
    _timer ??= Timer(_window, _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    if (_disposed || _working || _pending.isEmpty) return;
    if (_boardOpen && (saving() || _dragHolds || _ref.read(_query).isLoading)) {
      _arm();
      return;
    }
    final changes = _pending;
    _pending = _Changes();
    // A read now could still have the state from before the save, and the event for that save follows.
    for (final id in changes.tasks.where(_isSaving).toList()) {
      changes.tasks.remove(id);
      _pending.tasks.add(id);
      // That event goes with this task, whose read will say what it needs to.
      _pending.parents |= changes.parents;
      changes.parents = false;
    }
    _working = true;
    try {
      await _apply(changes);
    } finally {
      _working = false;
      if (!_pending.isEmpty) _arm();
    }
  }

  bool _isSaving(String taskId) {
    final edits = taskEditsProvider(taskId);
    return _ref.read(edits.exists) && _ref.read(edits).saving;
  }

  Future<void> _apply(_Changes changes) async {
    final reads = {...changes.tasks}..removeAll(changes.deleted);
    final labels = {...changes.labels}..removeAll(changes.deleted);
    if (!_boardOpen) {
      if (changes.reload) _refreshOpenTasks();
      _refreshOpenDetails(changes, reads, labels);
      return;
    }
    final notifier = _ref.read(_query.notifier);
    final current = _ref.read(_query).value;
    final reload =
        changes.reload ||
        current == null ||
        reads.length + labels.length > _maxTasksRead ||
        // Nothing here says whose progress it was, as when a child in another project changed.
        (changes.parents && reads.isEmpty && changes.reorders.isEmpty);
    if (reload) {
      await _loadBoard(notifier);
    } else {
      final revision = notifier.revision;
      final fresh = Map.fromEntries(
        (await Future.wait([
          for (final id in {...reads, ...labels})
            _read(id, current, task: reads.contains(id), labels: labels.contains(id)),
        ])).nonNulls,
      );
      if (_disposed) return;
      // The board closed under an open task meanwhile, so what was read is of no use to it.
      if (!_boardOpen) {
        _refreshOpenDetails(changes, reads, labels);
        return;
      }
      // A change on this device got ahead of these reads, or the board was read again meanwhile.
      if (notifier.revision != revision) {
        _pending.add(changes);
        return;
      }
      final board = _ref.read(_query).requireValue;
      final next = _changedBoard(board, changes, fresh);
      if (next == null) {
        await _loadBoard(notifier);
      } else {
        if (!identical(next, board)) notifier.setData(next);
        if (changes.relations) _refreshIfOpen(projectRelationsQuery(projectId));
      }
    }
    if (_disposed) return;
    _refreshOpenDetails(changes, reads, labels);
  }

  Future<void> _loadBoard(CachedQuery<BoardData> notifier) {
    _refreshIfOpen(projectRelationsQuery(projectId));
    return notifier.refresh();
  }

  /// Null if it can't be read for any other reason than the task being gone. The board is read then,
  /// to find out what's going on, and to show the answer if it is that access has ended.
  Future<MapEntry<String, _Fresh>?> _read(
    String id,
    BoardData board, {
    required bool task,
    required bool labels,
  }) async {
    final api = _ref.read(kaneoApiProvider);
    try {
      final read = task ? await api.taskForBoard(id) : null;
      final isNew =
          read != null &&
          read.task.projectId == projectId &&
          !boardTasks(board).any((t) => t.id == id);
      return MapEntry(id, _Fresh(read, labels || isNew ? await api.taskLabels(id) : null));
    } on ApiError catch (error) {
      if (error.status == 404) return MapEntry(id, const _Fresh(null, null));
      _pending.reload = true;
      return null;
    }
  }

  /// [board] with [changes] and what was read for them. Null if the board turns out to be out of date.
  BoardData? _changedBoard(BoardData board, _Changes changes, Map<String, _Fresh> fresh) {
    var next = board;
    for (final reorder in changes.reorders) {
      final moved = boardWithReorder(next, reorder);
      if (moved == null) return null;
      next = moved;
    }
    for (final id in changes.deleted) {
      next = boardWithoutTask(next, id);
    }
    for (final MapEntry(key: id, value: result) in fresh.entries) {
      final read = result.read;
      if (read != null && read.task.projectId == projectId) {
        final placed = boardWithCard(
          next,
          cardFromRead(next, read, labels: result.labels, memberImage: _memberImage),
        );
        if (placed == null) return null;
        next = placed;
        for (final parent in read.parentSubtaskCounts) {
          next = boardWithParentCounts(next, parent);
        }
      } else if (changes.tasks.contains(id)) {
        // It's gone, or has moved to another project.
        next = boardWithoutTask(next, id);
      } else if (result.labels != null && boardTasks(next).any((t) => t.id == id)) {
        final card = boardTasks(next).firstWhere((t) => t.id == id);
        next = boardWithCard(next, card.copyWith(labels: cardLabels(result.labels!))) ?? next;
      }
    }
    return next;
  }

  String? _memberImage(String userId) {
    final board = _ref.read(_query).value;
    if (board == null) return null;
    final members = membersQuery((workspaceId: board.workspaceId, projectId: projectId));
    if (!_ref.read(members.exists)) return null;
    return _ref.read(members).value?.where((m) => m.id == userId).firstOrNull?.image;
  }

  /// There's no telling what happened to the tasks that are open, in this project or another, so
  /// they all read again. One that's being saved has an event of its own to come.
  void _refreshOpenTasks() {
    _ref
        .read(openQueriesProvider)
        .refresh(
          where: (key) => key.startsWith('task/')
              ? !_isSaving(key.substring('task/'.length))
              : key.startsWith('task-labels/') ||
                    key.startsWith('task-relations/') ||
                    key.startsWith('task-activities/'),
        );
  }

  /// A task that's open, and whatever else is showing this project's data.
  void _refreshOpenDetails(_Changes changes, Set<String> reads, Set<String> labels) {
    for (final id in reads) {
      if (!_isSaving(id)) _refreshIfOpen(taskQuery(id));
      // The lists that show a summary of this task beside another one.
      _ref.read(savedTaskProvider.notifier).saved(id);
    }
    for (final id in labels) {
      _refreshIfOpen(taskLabelsQuery(id));
    }
    // A change to a task goes on its record too.
    for (final id in {...reads, ...changes.activity}) {
      _refreshIfOpen(taskActivitiesQuery(id));
    }
    for (final id in changes.linked) {
      _refreshIfOpen(taskRelationsQuery(id));
    }
    // These are looked for by key, because a task on its own doesn't have the board's workspace.
    final open = _ref.read(openQueriesProvider);
    if (changes.project) {
      _refreshIfOpen(columnsQuery(projectId));
      open.refresh(where: (key) => key.startsWith('projects/') || key.startsWith('projects-all/'));
    }
    if (changes.members) {
      open.refresh(where: (key) => key.startsWith('members/') && key.endsWith('/$projectId'));
    }
  }

  void _refreshIfOpen<T>(AsyncNotifierProvider<CachedQuery<T>, T> query) {
    if (_ref.read(query.exists)) unawaited(_ref.read(query.notifier).refresh());
  }
}

/// Lives as long as a board page or an open task of the project watches it, and reconnects by itself.
final boardSyncProvider = Provider.autoDispose.family<BoardSync, String>((ref, projectId) {
  final sync = BoardSync._(ref, projectId);
  ref.onDispose(sync._dispose);
  connectRealtime(
    ref,
    'api/ws/$projectId',
    onEvent: sync._onEvent,
    onOpen: sync._opened,
    onRevoked: sync._revoked,
  );
  return sync;
});
