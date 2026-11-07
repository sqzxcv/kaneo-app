import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// A hint from the server that something changed. Apart from the positions in a reorder it doesn't
/// carry the change, so whoever gets one reads what they need.
class RealtimeEvent {
  const RealtimeEvent(this.type, [this.data = const {}]);

  /// Null for frames that aren't events: keepalives, and anything that isn't JSON.
  static RealtimeEvent? parse(Object? frame) {
    if (frame is! String) return null;
    final Object? json;
    try {
      json = jsonDecode(frame);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    final type = json['type'];
    if (type is! String || type.isEmpty || type == 'PING' || type == 'pong') return null;
    return RealtimeEvent(type, json);
  }

  final String type;
  final Map<String, dynamic> data;

  /// The server sends an empty id when an event is about no task in particular.
  String? get taskId => _id('taskId');
  String? get sourceTaskId => _id('sourceTaskId');
  String? get targetTaskId => _id('targetTaskId');

  String? _id(String field) {
    final value = data[field];
    return value is String && value.isNotEmpty ? value : null;
  }
}

/// Keeps one socket open between [start] and [stop], and opens a new one when it drops.
///
/// A socket's events only count while it is the current one, so that one closing late, which is common
/// after a quick switch between apps, can't touch the next one or open a second.
class RealtimeConnection {
  RealtimeConnection({
    required this._openSocket,
    required this.onEvent,
    this.onOpen,
    this.onRevoked,
  });

  /// Keeps proxies from closing an idle socket. Cloudflare's limit is 100 seconds.
  static const keepAliveInterval = Duration(seconds: 30);

  /// The longest wait between attempts, and with it how long a recovered network can go unnoticed.
  static const maxRetryDelay = Duration(seconds: 15);

  /// The server closes a socket with these when its credential or its access has ended.
  static const _revokedCodes = {1008, 4001};

  /// The only text the server accepts. It closes the socket on anything else.
  static const _keepAlive = '{"type":"ping"}';

  final WebSocketChannel Function() _openSocket;
  final void Function(RealtimeEvent event) onEvent;

  /// Every time a socket opens. What happened while there was none has to be read again.
  final void Function()? onOpen;

  /// The server ended this socket for its credential or access. The answer to a request will say what
  /// is left, and has the means to act on it.
  final void Function()? onRevoked;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _frames;
  Timer? _keepAliveTimer;
  Timer? _retry;
  int _attempt = 0;

  /// Whether it has a socket, or is waiting to try for one.
  bool get isRunning => _socket != null || _retry != null;

  void start() {
    stop();
    _attempt = 0;
    _connect();
  }

  void stop() {
    _retry?.cancel();
    _retry = null;
    _release();
  }

  void _connect() {
    final WebSocketChannel socket;
    try {
      socket = _openSocket();
    } on Exception {
      _retryLater();
      return;
    }
    _socket = socket;
    _frames = socket.stream.listen(
      (frame) {
        if (!identical(_socket, socket)) return;
        final event = RealtimeEvent.parse(frame);
        if (event != null) onEvent(event);
      },
      onError: (Object _) => _closed(socket),
      onDone: () => _closed(socket),
    );
    socket.ready.then((_) {
      if (!identical(_socket, socket)) return;
      _keepAliveTimer = Timer.periodic(keepAliveInterval, (_) {
        // It has stayed open this long, so the next drop starts counting from the beginning. One the
        // server closes right after opening keeps backing off.
        _attempt = 0;
        try {
          socket.sink.add(_keepAlive);
        } on StateError {
          _closed(socket);
        }
      });
      onOpen?.call();
    }, onError: (Object _) => _closed(socket));
  }

  void _closed(WebSocketChannel socket) {
    if (!identical(_socket, socket)) return;
    final code = socket.closeCode;
    _release();
    if (_revokedCodes.contains(code)) onRevoked?.call();
    _retryLater();
  }

  void _retryLater() {
    final seconds = 1 << min(_attempt, 8);
    _attempt++;
    final delay = Duration(seconds: min(seconds, maxRetryDelay.inSeconds));
    _retry = Timer(delay, () {
      _retry = null;
      _connect();
    });
  }

  void _release() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    unawaited(_frames?.cancel());
    _frames = null;
    final socket = _socket;
    _socket = null;
    // A socket still connecting closes when it gets there, and one that never does has nothing to say.
    unawaited(socket?.sink.close().catchError((Object _) {}));
  }
}
