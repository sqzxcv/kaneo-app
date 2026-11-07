import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/core.dart';
import '../task/open_task.dart';
import 'notification_check.dart';
import 'notification_host.dart';

/// Asks the OS to allow notifications. The switch on the account page goes through this on every
/// platform.
final notificationPermissionProvider = Provider<Future<bool> Function()>((ref) {
  if (ref.watch(isDesktopProvider)) {
    return ref.watch(desktopHostProvider).requestNotificationPermission;
  }
  if (ref.watch(backgroundChecksSupportedProvider)) {
    return ref.watch(notificationHostProvider).requestPermission;
  }
  return () async => true;
});

/// The app's side of the background check: keeps it scheduled for whoever is signed in with the
/// switch on, and opens what gets tapped. Nothing here shows a notification.
class NotificationRuntime {
  NotificationRuntime({
    required this.host,
    required this.prefs,
    required this.check,
    required this.open,
    required this.rememberPermission,
    required this._session,
    required this._enabled,
  });

  final NotificationHost host;
  final SharedPreferences prefs;
  final NotificationCheck check;
  final Future<void> Function(String? taskId) open;
  final Future<void> Function(bool allowed) rememberPermission;

  Session? _session;
  bool _enabled;
  bool _started = false;
  bool _disposed = false;
  int _generation = 0;

  Future<void> start() async {
    try {
      await host.initialize(activate);
      if (_disposed) return;
      _started = true;
      activate(await host.launchPayload());
    } on Exception {
      return;
    }
    await _apply();
  }

  Future<void> setSession(Session? session) async {
    if (sameLogin(_session, session)) return;
    _session = session;
    await _apply(accountChanged: true);
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    await _apply();
  }

  /// Follows the app on and off the screen. What arrived while it was on screen isn't news later,
  /// so that gets noted as it leaves.
  Future<void> setForeground(bool foreground) async {
    try {
      await prefs.setBool(notificationForegroundKey, foreground);
      if (!foreground && _enabled && _session != null) await check.run(post: false);
    } on Exception {
      return;
    }
  }

  /// Opens what a tapped notification is about, if it's for the account signed in now.
  void activate(String? payload) {
    final notice = decodeNotice(payload);
    final session = _session;
    if (notice == null ||
        session == null ||
        !_enabled ||
        _disposed ||
        notice.account != accountScope(session)) {
      return;
    }
    unawaited(open(notice.taskId));
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }

  Future<void> _apply({bool accountChanged = false}) async {
    final generation = ++_generation;
    if (!_started || _disposed) return;
    bool current() => generation == _generation;
    try {
      if (accountChanged) {
        await host.clear();
        await check.forget();
        if (!current()) return;
      }
      if (_session == null) {
        await host.unschedule();
        return;
      }
      // The first signed-in launch asks the OS once, as the desktop apps do. Later launches respect
      // the switch, including an explicit denial or opt-out.
      if (!prefs.containsKey(notificationChecksEnabledKey)) {
        final allowed = await host.requestPermission();
        if (current()) await rememberPermission(allowed);
        return;
      }
      if (!_enabled) {
        await host.unschedule();
        await host.clear();
        await check.forget();
        return;
      }
      await host.schedule();
      if (current()) await check.run(post: false);
    } on Exception {
      // Offline, or the OS said no. The next launch or change tries again.
    }
  }
}

/// Tied to the router's lifetime, as the desktop runtime is. Null on the desktop apps.
final notificationRuntimeProvider = Provider.autoDispose.family<NotificationRuntime?, GoRouter>((
  ref,
  router,
) {
  if (!ref.watch(backgroundChecksSupportedProvider)) return null;
  final prefs = ref.watch(prefsProvider);
  final host = ref.watch(notificationHostProvider);
  final runtime = NotificationRuntime(
    host: host,
    prefs: prefs,
    session: ref.read(sessionProvider),
    enabled: ref.read(notificationChecksEnabledProvider),
    check: NotificationCheck(
      prefs: prefs,
      i18n: ref.watch(i18nProvider),
      host: host,
      readSession: () async => ref.mounted ? ref.read(sessionProvider) : null,
      load: (_) => ref.read(kaneoApiProvider).notifications(),
    ),
    open: (taskId) async {
      if (taskId == null) {
        router.go(AppRoutes.inbox);
        return;
      }
      final navigator = router.routerDelegate.navigatorKey;
      // A tap that launched the app can get here before the first frame.
      if (navigator.currentContext == null) await WidgetsBinding.instance.endOfFrame;
      final context = navigator.currentContext;
      if (context != null && context.mounted) openTaskPage(context, taskId);
    },
    rememberPermission: (allowed) =>
        ref.read(notificationChecksEnabledProvider.notifier).setEnabled(allowed),
  );
  ref.listen(sessionProvider, (_, session) => unawaited(runtime.setSession(session)));
  ref.listen(
    notificationChecksEnabledProvider,
    (_, enabled) => unawaited(runtime.setEnabled(enabled)),
  );
  // iOS can start the app without showing it, so this doesn't assume it's on screen yet.
  unawaited(
    prefs.setBool(
      notificationForegroundKey,
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    ),
  );
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.resumed) unawaited(runtime.setForeground(true));
      if (state == AppLifecycleState.paused) unawaited(runtime.setForeground(false));
    },
  );
  ref.onDispose(() {
    lifecycle.dispose();
    runtime.dispose();
  });
  unawaited(runtime.start());
  return runtime;
});
