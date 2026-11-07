// The black-box tests' own view of the server: plain HTTP against the Kaneo API, written apart from
// the app's client, so that what the app shows is checked against what the server really holds.
// It also has a proxy the app can sign in through, which can go away, fail or slow down on demand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Settings from `--dart-define-from-file=~/.config/kaneo-app/black-box.env`. Never written to the
/// repository, the evidence or the report.
class Env {
  static const server = String.fromEnvironment('KANEO_BB_SERVER_URL');
  static const workspaceId = String.fromEnvironment('KANEO_BB_WORKSPACE_ID');
  static const apiKey = String.fromEnvironment('KANEO_BB_OWNER_API_KEY');
  static const boardProject = String.fromEnvironment('KANEO_BB_BOARD_PROJECT_ID');
  static const formatsProject = String.fromEnvironment('KANEO_BB_FORMATS_PROJECT_ID');
  static const requiredProject = String.fromEnvironment('KANEO_BB_REQUIRED_FIELD_PROJECT_ID');
  static const emptyProject = String.fromEnvironment('KANEO_BB_EMPTY_PROJECT_ID');

  static const owner = Account(
    String.fromEnvironment('KANEO_BB_OWNER_EMAIL'),
    String.fromEnvironment('KANEO_BB_OWNER_PASSWORD'),
    String.fromEnvironment('KANEO_BB_OWNER_NAME'),
    String.fromEnvironment('KANEO_BB_OWNER_USER_ID'),
  );
  static const member = Account(
    String.fromEnvironment('KANEO_BB_MEMBER_EMAIL'),
    String.fromEnvironment('KANEO_BB_MEMBER_PASSWORD'),
    String.fromEnvironment('KANEO_BB_MEMBER_NAME'),
    String.fromEnvironment('KANEO_BB_MEMBER_USER_ID'),
  );
  static const viewer = Account(
    String.fromEnvironment('KANEO_BB_RESTRICTED_EMAIL'),
    String.fromEnvironment('KANEO_BB_RESTRICTED_PASSWORD'),
    String.fromEnvironment('KANEO_BB_RESTRICTED_NAME'),
    String.fromEnvironment('KANEO_BB_RESTRICTED_USER_ID'),
  );
  static const loner = Account(
    String.fromEnvironment('KANEO_BB_LONER_EMAIL'),
    String.fromEnvironment('KANEO_BB_LONER_PASSWORD'),
    String.fromEnvironment('KANEO_BB_LONER_NAME'),
    String.fromEnvironment('KANEO_BB_LONER_USER_ID'),
  );

  static bool get isLocal => ['localhost', '127.0.0.1', '::1'].contains(Uri.parse(server).host);
}

class Account {
  const Account(this.email, this.password, this.name, this.id);

  final String email;
  final String password;
  final String name;
  final String id;
}

/// A short marker unique to this run, so that what one run makes can be told apart.
final runStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(3);

class ApiException implements Exception {
  ApiException(this.method, this.path, this.status, this.body);

  final String method;
  final String path;
  final int status;
  final Object? body;

  @override
  String toString() => '$method $path -> $status: $body';
}

/// One account's requests, signed in with its password.
class Api {
  Api._(this.base, this._token, this.userId);

  final String base;
  final String? _token;
  final String userId;
  static final HttpClient _http = HttpClient();

  static Future<Api> signIn(Account account, {String? server}) async {
    final base = (server ?? Env.server).replaceAll(RegExp(r'/+$'), '');
    final response = await _send(base, null, 'POST', 'api/auth/sign-in/email', {
      'email': account.email,
      'password': account.password,
    });
    if (response.status != 200) {
      throw ApiException('POST', 'sign-in', response.status, response.body);
    }
    return Api._(base, response.headers.value('set-auth-token'), account.id);
  }

  /// What the server says to a sign-in with [password], as the person would see it.
  static Future<({int status, Object? body})> tryPassword(String email, String password) async {
    final base = Env.server.replaceAll(RegExp(r'/+$'), '');
    final r = await _send(base, null, 'POST', 'api/auth/sign-in/email', {
      'email': email,
      'password': password,
    });
    return (status: r.status, body: r.body);
  }

  static Future<_Response> _send(
    String base,
    String? token,
    String method,
    String path,
    Object? body,
  ) async {
    final request = await _http.openUrl(method, Uri.parse('$base/$path'));
    request.headers.set('accept', 'application/json');
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? parsed = text;
    try {
      parsed = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      parsed = text;
    }
    return _Response(response.statusCode, parsed, response.headers);
  }

  Future<dynamic> call(String method, String path, [Object? body]) async {
    for (var attempt = 0; ; attempt++) {
      final r = await _send(base, _token, method, path, body);
      if (r.status == 429 && attempt < 5) {
        await Future<void>.delayed(const Duration(seconds: 3));
        continue;
      }
      if (r.status < 200 || r.status >= 300) throw ApiException(method, path, r.status, r.body);
      return r.body;
    }
  }

  Future<dynamic> get(String path) => call('GET', path);

  // --- Reading ---

  /// Every task of [projectId]'s board, from every page, each with the column it is in. Planned and
  /// archived tasks have `status` planned and archived.
  Future<List<Map<String, dynamic>>> boardTasks(String projectId) async {
    final all = <Map<String, dynamic>>[];
    for (var page = 1, pages = 1; page <= pages; page++) {
      final body = await get('api/task/tasks/$projectId?page=$page&limit=100') as Map;
      pages = ((body['pagination'] as Map?)?['totalPages'] as num?)?.toInt() ?? 1;
      final data = body['data'] as Map;
      for (final column in (data['columns'] as List).cast<Map>()) {
        for (final t in ((column['tasks'] as List?) ?? const []).cast<Map>()) {
          all.add({...t.cast<String, dynamic>(), 'status': column['slug']});
        }
      }
      for (final key in ['plannedTasks', 'archivedTasks']) {
        for (final t in ((data[key] as List?) ?? const []).cast<Map>()) {
          all.add(t.cast<String, dynamic>());
        }
      }
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> columns(String projectId) async {
    final list = (await get('api/column/$projectId') as List).cast<Map>();
    final sorted = [for (final c in list) c.cast<String, dynamic>()]
      ..sort((a, b) => (a['position'] as num).compareTo(b['position'] as num));
    return sorted;
  }

  Future<Map<String, dynamic>> task(String id) async =>
      (await get('api/task/$id') as Map).cast<String, dynamic>();

  /// The description as stored, from every page of it.
  Future<String> description(String id) async {
    final text = StringBuffer();
    String? version;
    int? offset = 0;
    while (offset != null) {
      final query = 'offset=$offset${version == null ? '' : '&version=$version'}';
      final body = await get('api/task/$id/description?$query') as Map;
      text.write(body['content'] ?? '');
      version = body['version']?.toString();
      offset = (body['nextOffset'] as num?)?.toInt();
    }
    return text.toString();
  }

  Future<List<Map<String, dynamic>>> notifications([String? workspaceId]) async {
    final body = await get(
      'api/notification${workspaceId == null ? '' : '?workspaceId=$workspaceId'}',
    );
    final list = body is Map ? (body['notifications'] ?? body['data']) as List : body as List;
    return [for (final n in list.cast<Map>()) n.cast<String, dynamic>()];
  }

  Future<List<Map<String, dynamic>>> comments(String taskId) async => [
    for (final c in (await get('api/comment/$taskId') as List).cast<Map>()) c.cast(),
  ];

  Future<List<Map<String, dynamic>>> labels(String workspaceId) async => [
    for (final l in (await get('api/label/workspace/$workspaceId') as List).cast<Map>()) l.cast(),
  ];

  Future<List<Map<String, dynamic>>> taskLabels(String taskId) async => [
    for (final l in (await get('api/label/task/$taskId') as List).cast<Map>()) l.cast(),
  ];

  Future<List<Map<String, dynamic>>> relations(String taskId) async => [
    for (final r in (await get('api/task-relation/$taskId') as List).cast<Map>()) r.cast(),
  ];

  // --- Writing ---

  Future<Map<String, dynamic>> createProject(String name, {String? workspaceId}) async {
    final slug = 'Q${Random().nextInt(1 << 30).toRadixString(36).toUpperCase()}';
    final made = await call('POST', 'api/project', {
      'name': name,
      'workspaceId': workspaceId ?? Env.workspaceId,
      'icon': 'Layout',
      'slug': slug.substring(0, min(slug.length, 6)),
    });
    return (made as Map).cast();
  }

  Future<void> deleteProject(String id) => call('DELETE', 'api/project/$id');

  Future<Map<String, dynamic>> createTask(
    String projectId,
    String title, {
    required String status,
    String description = '',
    String priority = 'no-priority',
    String? userId,
    String? dueDate,
  }) async {
    final made = await call('POST', 'api/task/$projectId', {
      'title': title,
      'description': description,
      'priority': priority,
      'status': status,
      'userId': ?userId,
      'dueDate': ?dueDate,
    });
    return (made as Map).cast();
  }

  Future<void> setStatus(String id, String status) =>
      call('PUT', 'api/task/status/$id', {'status': status});
  Future<void> setTitle(String id, String title) =>
      call('PUT', 'api/task/title/$id', {'title': title});
  Future<void> setPriority(String id, String priority) =>
      call('PUT', 'api/task/priority/$id', {'priority': priority});
  Future<void> setAssignee(String id, String? userId) =>
      call('PUT', 'api/task/assignee/$id', {'userId': userId});
  Future<void> setDescription(String id, String description) =>
      call('PUT', 'api/task/description/$id', {'description': description});
  Future<void> deleteTask(String id) => call('DELETE', 'api/task/$id');

  Future<Map<String, dynamic>> addLabel(String taskId, String name, String color) async =>
      ((await call('POST', 'api/label', {
        'name': name,
        'color': color,
        'workspaceId': Env.workspaceId,
        'taskId': taskId,
      })) as Map).cast();

  Future<void> deleteLabel(String id) => call('DELETE', 'api/label/$id');

  Future<void> relate(String source, String target, String type) => call(
    'POST',
    'api/task-relation',
    {'sourceTaskId': source, 'targetTaskId': target, 'relationType': type},
  );

  Future<Map<String, dynamic>> comment(String taskId, String content) async =>
      ((await call('POST', 'api/comment/$taskId', {'content': content})) as Map).cast();

  /// A notification for this account, as the server makes for activity.
  Future<void> notify(String title, {String? taskId, String type = 'info'}) => call(
    'POST',
    'api/notification',
    {
      'title': title,
      'message': 'From the black-box tests',
      'type': type,
      if (taskId != null) ...{'relatedEntityId': taskId, 'relatedEntityType': 'task'},
      if (taskId == null) ...{'relatedEntityId': Env.workspaceId, 'relatedEntityType': 'workspace'},
    },
  );

  /// Ends every session of this account, the app's among them.
  Future<void> revokeAllSessions() => call('POST', 'api/auth/revoke-sessions', {});
}

class _Response {
  const _Response(this.status, this.body, this.headers);

  final int status;
  final Object? body;
  final HttpHeaders headers;
}

/// A project of this run's own, with Kaneo's four columns, removed again afterwards.
class Scratch {
  Scratch._(this.api, this.project, this.columns);

  final Api api;
  final Map<String, dynamic> project;
  final List<Map<String, dynamic>> columns;

  String get id => project['id'] as String;
  String get name => project['name'] as String;
  String slugOf(int column) => columns[column]['slug'] as String;
  String nameOf(int column) => columns[column]['name'] as String;

  /// [extraColumns] are added after Kaneo's four, to make the board wider than any screen.
  static Future<Scratch> make(Api api, String what, {List<String> extraColumns = const []}) async {
    final project = await api.createProject('E-Q $what $runStamp');
    final id = project['id'] as String;
    for (final name in extraColumns) {
      await api.call('POST', 'api/column/$id', {'name': name});
    }
    final columns = await api.columns(id);
    return Scratch._(api, project, columns);
  }

  /// The tasks of [column], in the server's order.
  Future<List<String>> titlesIn(int column) async {
    final tasks = (await api.boardTasks(id)).where((t) => t['status'] == slugOf(column)).toList()
      ..sort((a, b) => (a['position'] as num? ?? 0).compareTo(b['position'] as num? ?? 0));
    return [for (final t in tasks) t['title'] as String];
  }

  Future<Map<String, dynamic>> task(
    String title, {
    int column = 0,
    String priority = 'no-priority',
    String? userId,
    String? dueDate,
    String description = '',
  }) => api.createTask(
    id,
    title,
    status: slugOf(column),
    priority: priority,
    userId: userId,
    dueDate: dueDate,
    description: description,
  );

  Future<void> remove() async {
    try {
      await api.deleteProject(id);
    } catch (_) {}
  }
}

/// What the proxy does with requests.
enum ProxyMode { pass, fail500 }

/// Stands between the app and the server. The app signs in through [url]; the tests can then take
/// the server away ([down]), make it fail with 500 or answer slowly.
class Proxy {
  Proxy([String? upstream])
    : upstream = Uri.parse((upstream ?? Env.server).replaceAll(RegExp(r'/+$'), ''));

  final Uri upstream;
  HttpServer? _server;
  int _port = 0;
  ProxyMode mode = ProxyMode.pass;

  /// Requests whose path contains this fail when [mode] is [ProxyMode.fail500]. Empty fails all.
  String failPattern = '';
  String? failMethod;
  Duration delay = Duration.zero;
  final _sockets = <WebSocket>{};
  final _http = HttpClient()..autoUncompress = false;

  /// Requests seen, as `METHOD path`.
  final requests = <String>[];

  String get url => 'http://127.0.0.1:$_port';
  bool get isUp => _server != null;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    _port = _server!.port;
    _server!.listen(_handle);
  }

  /// The server is gone, as when the network is: connections are refused and open sockets close.
  Future<void> down() async {
    await _server?.close(force: true);
    _server = null;
    for (final s in _sockets.toList()) {
      await s.close(WebSocketStatus.goingAway);
    }
    _sockets.clear();
  }

  Future<void> up() async {
    if (_server != null) return;
    for (var i = 0; i < 20; i++) {
      try {
        await start();
        return;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw StateError('The proxy could not listen on $_port again');
  }

  Future<void> close() async {
    await down();
    _http.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.toString();
    requests.add('${request.method} ${request.uri.path}');
    try {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await _socket(request);
        return;
      }
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (mode == ProxyMode.fail500 &&
          path.contains(failPattern) &&
          (failMethod == null || failMethod == request.method)) {
        await request.drain<void>();
        request.response
          ..statusCode = 500
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'message': 'Internal Server Error'}));
        await request.response.close();
        return;
      }
      final target = upstream.replace(
        path: request.uri.path,
        query: request.uri.hasQuery ? request.uri.query : null,
      );
      final out = await _http.openUrl(request.method, target);
      out.followRedirects = false;
      request.headers.forEach((name, values) {
        if (name == 'host') return;
        for (final v in values) {
          out.headers.add(name, v, preserveHeaderCase: true);
        }
      });
      await out.addStream(request);
      final back = await out.close();
      request.response.statusCode = back.statusCode;
      back.headers.forEach((name, values) {
        if (name == 'transfer-encoding') return;
        for (final v in values) {
          request.response.headers.add(name, v, preserveHeaderCase: true);
        }
      });
      await request.response.addStream(back);
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = 502;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _socket(HttpRequest request) async {
    final target = upstream.replace(
      scheme: upstream.scheme == 'https' ? 'wss' : 'ws',
      path: request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    );
    final headers = <String, dynamic>{};
    for (final name in ['authorization', 'cookie', 'x-api-key', 'origin']) {
      final v = request.headers.value(name);
      if (v != null) headers[name] = v;
    }
    final protocols = request.headers['sec-websocket-protocol']
        ?.expand((v) => v.split(','))
        .map((v) => v.trim())
        .toList();
    final WebSocket upstreamSocket;
    try {
      upstreamSocket = await WebSocket.connect(
        target.toString(),
        headers: headers,
        protocols: protocols,
      );
    } catch (_) {
      request.response.statusCode = 502;
      await request.response.close();
      return;
    }
    final downstream = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: protocols == null || protocols.isEmpty ? null : (p) => p.first,
    );
    _sockets
      ..add(downstream)
      ..add(upstreamSocket);
    downstream.listen(
      upstreamSocket.add,
      onDone: () => upstreamSocket.close(),
      onError: (_) => upstreamSocket.close(),
    );
    upstreamSocket.listen(
      downstream.add,
      onDone: () => downstream.close(),
      onError: (_) => downstream.close(),
    );
  }
}

/// Waits until [check] holds, or throws [what] after [timeout].
Future<T> eventually<T>(
  String what,
  Future<T?> Function() check, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  Object? last;
  while (true) {
    try {
      final value = await check();
      if (value != null && value != false) return value;
    } catch (e) {
      last = e;
    }
    if (DateTime.now().isAfter(end)) {
      throw StateError('Never happened: $what${last == null ? '' : ' (last error: $last)'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}
