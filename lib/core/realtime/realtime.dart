import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../platform/authenticated_socket.dart';
import '../providers.dart';
import '../session/session.dart';
import 'realtime_connection.dart';

/// A network that goes away closes nothing, so this is how a dead socket is noticed: an answer to a
/// ping is due within this time, which makes it twice this at most.
const realtimePingInterval = Duration(seconds: 10);

typedef RealtimeSocketFactory = WebSocketChannel Function(Session session, String path);

/// How a connection reaches the server. Tests replace it with `FakeKaneo.connectSocket`.
final realtimeSocketProvider = Provider<RealtimeSocketFactory>(
  (_) =>
      (session, path) =>
          connectAuthenticatedSocket(session, path, pingInterval: realtimePingInterval),
);

/// Keeps [path] connected for as long as something listens to [ref], for the signed-in account, while
/// the app is in the foreground. A new credential gets a new socket.
///
/// A page covered by another keeps listening, so it stays up to date for when it shows again.
///
/// The operating system takes sockets away from an app in the background, so it gives them up, and
/// [onOpen] is what brings it back up to date on its return.
void connectRealtime(
  Ref ref,
  String path, {
  required void Function(RealtimeEvent event) onEvent,
  void Function()? onOpen,
  void Function()? onRevoked,
}) {
  var session = ref.read(sessionProvider);
  final open = ref.read(realtimeSocketProvider);
  final connection = RealtimeConnection(
    openSocket: () => open(session!, path),
    onEvent: onEvent,
    onOpen: onOpen,
    onRevoked: onRevoked,
  );
  var listeners = 0;
  void follow() {
    if (session == null ||
        listeners == 0 ||
        _inBackground(WidgetsBinding.instance.lifecycleState)) {
      connection.stop();
    } else if (!connection.isRunning) {
      connection.start();
    }
  }

  ref.listen(sessionProvider.select((s) => (s?.serverUrl, s?.userId, s?.token)), (_, _) {
    session = ref.read(sessionProvider);
    connection.stop();
    follow();
  });
  final lifecycle = AppLifecycleListener(onStateChange: (_) => follow());
  ref.onAddListener(() {
    listeners++;
    follow();
  });
  ref.onRemoveListener(() {
    listeners--;
    follow();
  });
  ref.onDispose(() {
    lifecycle.dispose();
    connection.stop();
  });
}

/// iOS can start the app without showing it, which isn't taken to mean it's on screen.
bool _inBackground(AppLifecycleState? state) =>
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached;
