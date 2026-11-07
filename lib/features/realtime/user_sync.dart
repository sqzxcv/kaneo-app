import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../inbox/notifications.dart';

/// Keeps what belongs to the account up to date while the app is open: the inbox, and whatever comes
/// with access to workspaces and projects. Showing notifications is the background check's work.
///
/// An open board looks after itself, and the inbox has changes of its own to wait for.
class UserSync {
  UserSync._(this._ref);

  /// Several notifications can come at once, each for the same read.
  static const _window = Duration(milliseconds: 300);

  static const _accessChanges = {
    'PROJECT_ACCESS_CHANGED',
    'WORKSPACE_ACCESS_REVOKED',
    'WORKSPACE_RESTORED',
    'USER_ACCESS_REVOKED',
  };

  final Ref _ref;
  Timer? _inbox;
  bool _hasOpened = false;

  void _dispose() => _inbox?.cancel();

  /// What happened while there was no socket can be anything, and the first one has nothing to catch up on.
  void _opened() {
    final first = !_hasOpened;
    _hasOpened = true;
    if (!first) _refreshOpen();
  }

  void _onEvent(RealtimeEvent event) {
    if (event.type == 'NOTIFICATION_CREATED') {
      _inbox ??= Timer(_window, () {
        _inbox = null;
        _refreshInbox();
      });
    } else if (_accessChanges.contains(event.type)) {
      _refreshOpen();
    } else if (event.type == 'WORKSPACE_ACCESS_SYNC') {
      _checkWorkspaces(event.data['workspaceIds']);
    }
  }

  /// Sent as each socket opens, and when the server has been out of touch itself. It only says something
  /// if a workspace on hand is gone. An administrator's list has more in it than they're a member of.
  void _checkWorkspaces(Object? ids) {
    final known = _ref.read(workspacesQuery).value;
    if (ids is! List || known == null) return;
    if (known.any((workspace) => !ids.contains(workspace.id))) _refreshOpen();
  }

  void _refreshOpen() {
    _ref
        .read(openQueriesProvider)
        .refresh(
          where: (key) =>
              !key.startsWith('board/') &&
              !key.startsWith('relations/') &&
              !key.startsWith('notifications/'),
        );
    _refreshInbox();
  }

  void _refreshInbox() {
    final workspace = _ref.read(currentWorkspaceProvider).value;
    if (workspace == null) return;
    unawaited(_ref.read(inboxActionsProvider(workspace.id)).refresh());
    final activity = workspaceActivityQuery(workspace.id);
    if (_ref.read(activity.exists)) unawaited(_ref.read(activity.notifier).refresh());
  }
}

/// Lives as long as the shell that watches it, and reconnects by itself.
final userSyncProvider = Provider.autoDispose<UserSync>((ref) {
  final sync = UserSync._(ref);
  ref.onDispose(sync._dispose);
  connectRealtime(
    ref,
    'api/ws/user',
    onEvent: sync._onEvent,
    onOpen: sync._opened,
    onRevoked: sync._refreshOpen,
  );
  return sync;
});
