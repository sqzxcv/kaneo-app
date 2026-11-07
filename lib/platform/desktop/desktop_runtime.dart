import 'dart:async';
import 'dart:math';

import '../../core/api/models.dart';
import '../../core/session/session.dart';
import 'desktop_host.dart';

/// Polls only while this desktop app is alive. There is no tray service or background process.
class DesktopRuntime {
  DesktopRuntime({
    required this.host,
    required this.load,
    required this.open,
    required this.hasPreference,
    required this.rememberPermission,
    required this.actionLabel,
    required this.fallbackBody,
    required this.summary,
    required this.onUnavailable,
    this.pollInterval = const Duration(seconds: 30),
  });

  final DesktopHost host;
  final Future<List<InboxNotification>> Function() load;
  final void Function(String? taskId) open;
  final bool Function() hasPreference;
  final Future<void> Function(bool allowed) rememberPermission;
  final String actionLabel;
  final String fallbackBody;
  final String Function(int count) summary;
  final void Function() onUnavailable;
  final Duration pollInterval;
  final _nonce = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  final Map<String, String?> _routes = {};
  Session? _session;
  Set<String>? _seen;
  Timer? _timer;
  bool _initialized = false;
  bool _disposed = false;
  bool _enabled = false;
  bool? _permission;
  int _generation = 0;
  int _noticeId = 0;
  int? _checking;
  Future<void> _osOperations = Future.value();

  Future<void> start() async {
    try {
      await host.configureWindow();
      await host.initializeNotifications((payload) => unawaited(activate(payload)), actionLabel);
      if (_disposed) return;
      _initialized = true;
      await _restart();
    } on Exception {
      if (!_disposed) onUnavailable();
    }
  }

  Future<void> setSession(Session? session) async {
    if (_session?.token == session?.token &&
        _session?.serverUrl == session?.serverUrl &&
        _session?.userId == session?.userId) {
      return;
    }
    _session = session;
    await _restart();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    // Recheck native settings when the user opts in again after changing OS permissions.
    if (!enabled) _permission = null;
    await _restart();
  }

  bool _current(int generation) => !_disposed && generation == _generation && _session != null;

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _osOperations.then((_) => action());
    _osOperations = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _restart() async {
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    _routes.clear();
    _seen = null;
    if (!_initialized || _disposed) return;
    try {
      await _serialize(host.clearNotices);
      if (!_current(generation)) return;
      // The first signed-in desktop launch asks the OS once. Later launches respect the
      // shared notification switch, including an explicit denial or opt-out.
      if (!hasPreference()) {
        _permission = await host.requestNotificationPermission();
        if (!_current(generation)) return;
        await rememberPermission(_permission!);
        return; // The enabled provider restarts us when permission was granted.
      }
      if (!_enabled) return;
      _permission ??= await host.requestNotificationPermission();
      if (!_current(generation) || _permission != true) return;
      await check();
      if (!_current(generation)) return;
      _timer = Timer.periodic(pollInterval, (_) => unawaited(check()));
    } on Exception {
      if (_current(generation)) onUnavailable();
    }
  }

  /// Also exposed for a refresh event and integration tests; never overlaps a check for this login.
  Future<void> check() async {
    final generation = _generation;
    final user = _session;
    if (!_initialized ||
        !_enabled ||
        _permission != true ||
        user == null ||
        _disposed ||
        _checking == generation) {
      return;
    }
    _checking = generation;
    try {
      final notifications = await load();
      if (!_current(generation)) return;
      final current = notifications.where((n) => n.userId == user.userId).toList();
      final seen = _seen;
      _seen = {...?seen, ...current.map((n) => n.id)};
      if (seen == null) {
        return; // Do not replay existing unread notices on launch or account switch.
      }
      final unread = current.where((n) => n.isRead != true && !seen.contains(n.id)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (unread.length > 5) {
        await _show(generation, title: 'Kaneo', body: summary(unread.length - 4));
      }
      for (final notice in unread.length > 5 ? unread.skip(unread.length - 4) : unread) {
        await _show(
          generation,
          title: notice.title?.trim().isNotEmpty == true ? notice.title! : 'Kaneo',
          body: notice.content ?? fallbackBody,
          taskId: notice.resourceType == 'task' ? notice.resourceId : null,
        );
      }
    } on Exception {
      // Network, permission and revoked-session handling belongs to ApiClient. A later tick retries.
    } finally {
      if (_checking == generation) _checking = null;
    }
  }

  Future<void> _show(int generation, {required String title, String? body, String? taskId}) =>
      _serialize(() async {
        if (!_current(generation) || !_enabled) return;
        final id = ++_noticeId;
        final payload = '$_nonce:$generation:$id';
        _routes[payload] = taskId;
        await host.showNotice(id: id, title: title, body: body, payload: payload);
      });

  Future<void> activate(String? payload) async {
    if (payload == null ||
        !_routes.containsKey(payload) ||
        !_enabled ||
        _session == null ||
        _disposed) {
      return;
    }
    final generation = _generation;
    final taskId = _routes[payload];
    await host.foregroundWindow();
    if (_current(generation) && _routes.containsKey(payload)) open(taskId);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _routes.clear();
    if (_initialized) unawaited(_serialize(host.clearNotices).catchError((Object _) {}));
  }
}
