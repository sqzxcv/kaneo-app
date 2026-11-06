import 'dart:math';

import 'package:web_socket_channel/io.dart';

import '../core/api/api_client.dart';
import '../core/session/session.dart';

/// A fresh identity makes changes from another client of this account visible to this socket.
Uri authenticatedSocketUrl(Session session, String path) {
  final server = Uri.parse(session.serverUrl);
  final windowId = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16)).join();
  return server.replace(
    scheme: server.scheme == 'https' ? 'wss' : 'ws',
    path: '${server.path}/${path.replaceFirst(RegExp(r'^/+'), '')}',
    queryParameters: {'windowId': 'flutter-$windowId'},
  );
}

/// Native WebSockets use the same bearer/API key headers as HTTP; tokens never go in the URL.
/// The caller owns stream handling, keepalive, reconnects and closing on session/lifecycle changes.
IOWebSocketChannel connectAuthenticatedSocket(Session session, String path) =>
    IOWebSocketChannel.connect(
      authenticatedSocketUrl(session, path),
      headers: credentialHeaders(session.credentialType, session.token),
      connectTimeout: const Duration(seconds: 15),
    );
