import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One request the fake received, for asserting what a page sent.
class FakeRequest {
  const FakeRequest(this.method, this.path, this.query, this.headers, this.body);

  final String method;

  /// Without the leading slash, such as `api/task/assigned`.
  final String path;
  final Map<String, String> query;
  final Map<String, Object?> headers;

  /// The decoded JSON body, or null.
  final Object? body;

  @override
  String toString() => '$method $path $query';
}

/// What a test wants a route to answer instead of the normal response.
class FakeResponse {
  const FakeResponse(this.status, [this.body, this.headers = const {}]);

  final int status;
  final Object? body;
  final Map<String, String> headers;
}

/// Keeps matching requests waiting, which is how a test sees a page's loading state.
class FakeGate {
  FakeGate(this._method, this._pattern);

  final String? _method;
  final Pattern _pattern;
  final Completer<void> _released = Completer<void>();

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _Override {
  _Override(this.method, this.pattern, this.respond, this.remaining);

  final String? method;
  final Pattern pattern;
  final FakeResponse Function(FakeRequest request) respond;
  int? remaining;
}

typedef _Handler = Object? Function(FakeRequest request, List<String> params);

class _Route {
  _Route(this.method, this.pattern, this.handler);

  final String method;
  final RegExp pattern;
  final _Handler handler;
}

class _NotFound implements Exception {
  const _NotFound(this.message);

  final String message;
}

/// An in-memory Kaneo server for tests. It answers every route in `KaneoApi` with the JSON shapes of
/// the real server, keeps what is written to it, and can be told to fail.
///
///     final server = FakeKaneo();
///     await pumpKaneoApp(tester, server: server);
///     server.failNext('api/task/tasks/', status: 500);
///
/// It plugs in underneath Dio through `httpAdapterProvider`, so the whole client runs for real.
/// `test/contract/` checks these shapes against a local Kaneo.
class FakeKaneo implements HttpClientAdapter {
  FakeKaneo() {
    _registerRoutes();
    _seed();
  }

  /// A server with the account and workspace, but no projects or tasks.
  factory FakeKaneo.empty() => FakeKaneo()..clearProjects();

  static const serverUrl = 'https://kaneo.test';
  static const apiKey = 'fake-api-key';
  static const sessionToken = 'fake-session-token';
  static const email = 'test@example.com';
  static const password = 'correct-password';
  static const userId = 'user-1';
  static const workspaceId = 'workspace-1';
  static const projectId = 'project-1';
  static const secondProjectId = 'project-2';

  /// Every request so far, in order.
  final List<FakeRequest> requests = [];

  /// Added to every response.
  Duration latency = Duration.zero;

  /// Makes requests fail the way they do when the server cannot be reached.
  bool unreachable = false;

  /// Makes every credential invalid, as when a key is revoked. Requests then get 401.
  bool credentialsRevoked = false;

  /// Tasks per board page. Lower it to test paging.
  int boardPageSize = 100;

  // The server's records, as JSON. Tests may read and change them directly.
  Map<String, dynamic> user = {};
  Map<String, dynamic> instanceConfig = {};
  Map<String, dynamic> capabilities = {};
  Map<String, dynamic> notificationPreferences = {};
  final List<Map<String, dynamic>> workspaces = [];
  final List<Map<String, dynamic>> members = [];
  final List<Map<String, dynamic>> invitations = [];
  final List<Map<String, dynamic>> projects = [];
  final List<Map<String, dynamic>> columns = [];
  final List<Map<String, dynamic>> tasks = [];
  final List<Map<String, dynamic>> labels = [];
  final List<Map<String, dynamic>> relations = [];
  final List<Map<String, dynamic>> activities = [];
  final List<Map<String, dynamic>> timeEntries = [];
  final List<Map<String, dynamic>> externalLinks = [];
  final List<Map<String, dynamic>> customFields = [];
  final List<Map<String, dynamic>> customFieldValues = [];
  final List<Map<String, dynamic>> notifications = [];

  /// What the server sent to other people, such as someone mentioned in a comment. They aren't in the
  /// inbox of whoever is signed in.
  final List<Map<String, dynamic>> notificationsToOthers = [];

  final List<_Route> _routes = [];
  final List<_Override> _overrides = [];
  final List<(FakeGate, Completer<void>)> _gates = [];
  int _nextId = 1000;

  // --- Telling it what to do ---

  /// The next [times] requests whose path contains [pattern] get [status].
  void failNext(Pattern pattern, {int status = 500, Object? body, String? method, int times = 1}) {
    _overrides.add(_Override(method, pattern, (_) => FakeResponse(status, body), times));
  }

  /// Every request whose path contains [pattern] gets [status], until [clearOverrides].
  void fail(Pattern pattern, {int status = 500, Object? body, String? method}) {
    _overrides.add(_Override(method, pattern, (_) => FakeResponse(status, body), null));
  }

  /// Answers requests whose path contains [pattern] with [respond], until [clearOverrides].
  void on(Pattern pattern, FakeResponse Function(FakeRequest request) respond, {String? method}) {
    _overrides.add(_Override(method, pattern, respond, null));
  }

  void clearOverrides() => _overrides.clear();

  /// Holds requests whose path contains [pattern] until the gate's `release()`.
  FakeGate hold(Pattern pattern, {String? method}) {
    final gate = FakeGate(method, pattern);
    _gates.add((gate, gate._released));
    return gate;
  }

  /// The requests whose path contains [pattern].
  List<FakeRequest> requestsTo(Pattern pattern, {String? method}) => [
    for (final request in requests)
      if (request.path.contains(pattern) && (method == null || request.method == method)) request,
  ];

  // --- Filling it with data ---

  void clearProjects() {
    projects.clear();
    columns.clear();
    tasks.clear();
    relations.clear();
    activities.clear();
    labels.clear();
    notifications.clear();
    notificationsToOthers.clear();
  }

  /// Adds a project with Kaneo's four default columns.
  Map<String, dynamic> addProject({String? id, required String name, required String slug}) {
    final projectId = id ?? _id('project');
    final project = <String, dynamic>{
      'id': projectId,
      'workspaceId': workspaceId,
      'slug': slug,
      'icon': 'Layout',
      'name': name,
      'description': null,
      'createdAt': _now,
      'isPublic': false,
      'archivedAt': null,
      'lastTaskNumber': 0,
      'position': projects.length,
      'backgroundVersion': null,
    };
    projects.add(project);
    for (final (index, (columnName, columnSlug, isFinal)) in const [
      ('To Do', 'to-do', false),
      ('In Progress', 'in-progress', false),
      ('In Review', 'in-review', false),
      ('Done', 'done', true),
    ].indexed) {
      columns.add(<String, dynamic>{
        'id': _id('column'),
        'projectId': projectId,
        'name': columnName,
        'slug': columnSlug,
        'position': index,
        'icon': null,
        'color': null,
        'isFinal': isFinal,
        'createdAt': _now,
        'updatedAt': _now,
      });
    }
    return project;
  }

  Map<String, dynamic> addTask({
    String? id,
    String projectId = projectId,
    required String title,
    String description = '',
    String status = 'to-do',
    String priority = 'no-priority',
    String? assigneeId = userId,
    String? startDate,
    String? dueDate,
  }) {
    final project = projects.firstWhere((p) => p['id'] == projectId);
    final number = (project['lastTaskNumber'] as int) + 1;
    project['lastTaskNumber'] = number;
    final task = <String, dynamic>{
      'id': id ?? _id('task'),
      'title': title,
      'number': number,
      'description': description,
      'status': status,
      'priority': priority,
      'startDate': startDate,
      'dueDate': dueDate,
      'recurrence': null,
      'position': tasks.where((t) => t['projectId'] == projectId && t['status'] == status).length,
      'createdAt': _now,
      'userId': assigneeId,
      'projectId': projectId,
    };
    tasks.add(task);
    _logActivity(task['id'] as String, 'created');
    return task;
  }

  Map<String, dynamic> addLabel(String name, {String color = 'red', String? taskId}) {
    final label = <String, dynamic>{
      'id': _id('label'),
      'name': name,
      'color': color,
      'createdAt': _now,
      'updatedAt': _now,
      'deletionStartedAt': null,
      'taskId': taskId,
      'workspaceId': workspaceId,
    };
    labels.add(label);
    return label;
  }

  Map<String, dynamic> addRelation(String sourceTaskId, String targetTaskId, [String? type]) {
    final relation = <String, dynamic>{
      'id': _id('relation'),
      'sourceTaskId': sourceTaskId,
      'targetTaskId': targetTaskId,
      'relationType': type ?? 'subtask',
      'createdAt': _now,
    };
    relations.add(relation);
    return relation;
  }

  /// A comment by [authorId], by default the signed-in user. [externalSource] makes it an imported
  /// one, where [externalUserName] wrote it and [authorId] imported it.
  Map<String, dynamic> addComment(
    String taskId,
    String content, {
    String authorId = userId,
    String? externalUserName,
    String? externalSource,
  }) => _logActivity(
    taskId,
    'comment',
    content: content,
    authorId: authorId,
    externalUserName: externalUserName,
    externalSource: externalSource,
  );

  /// Something that happened on a task, as the server records it.
  Map<String, dynamic> addActivity(
    String taskId,
    String type, {
    String? content,
    Map<String, Object?>? eventData,
    String authorId = userId,
  }) => _logActivity(taskId, type, content: content, eventData: eventData, authorId: authorId);

  Map<String, dynamic> addNotification({
    String type = 'task_assigned',
    String? title,
    String? content,
    Map<String, Object?> eventData = const {},
    String? resourceId,
    String resourceType = 'task',
    bool isRead = false,
  }) {
    final notification = <String, dynamic>{
      'id': _id('notification'),
      'userId': userId,
      'title': title,
      'content': content,
      'type': type,
      'eventData': eventData,
      'isRead': isRead,
      'resourceId': resourceId,
      'resourceType': resourceType,
      'createdAt': _now,
      'updatedAt': _now,
    };
    notifications.add(notification);
    return notification;
  }

  void _seed() {
    user = {
      'id': userId,
      'name': 'Test User',
      'email': email,
      'image': null,
      'role': 'admin',
      'managedProfileFields': <String>[],
    };
    instanceConfig = {
      'isCloud': false,
      'instanceName': 'Kaneo',
      'disableRegistration': false,
      'disablePasswordRegistration': false,
      'disableEmailOtpSignIn': false,
      'disableWorkspaceCreation': false,
      'disabledIntegrations': <String>[],
      'isDemoMode': false,
      'hasSmtp': false,
      'hasImageUploads': false,
      'hasGithubSignIn': false,
      'hasGoogleSignIn': false,
      'hasDiscordSignIn': false,
      'hasCustomOAuth': false,
      'hasGuestAccess': true,
      'disableLoginForm': false,
      'customOAuthName': null,
      'customOAuthAutoLogin': false,
      'customOAuthLogoutUrl': null,
      'customOAuthManagedProfileFields': <String>[],
      'customOAuthAccountUrl': null,
      'billingEnabled': false,
    };
    capabilities = {
      for (final name in const [
        'manageProjects',
        'createProjects',
        'updateProjects',
        'shareProjects',
        'deleteProjects',
        'updateTasks',
        'createTasks',
        'deleteTasks',
        'assignTasks',
        'createLabels',
        'updateLabels',
        'deleteLabels',
        'manageWorkspace',
        'manageSettings',
        'deleteWorkspace',
        'inviteUsers',
        'manageTeam',
        'updateMembers',
        'removeMembers',
      ])
        name: true,
    };
    notificationPreferences = {
      'emailAddress': null,
      'emailEnabled': false,
      'ntfyEnabled': false,
      'ntfyConfigured': false,
      'ntfyServerUrl': null,
      'ntfyTopic': null,
      'ntfyTokenConfigured': false,
      'maskedNtfyToken': null,
      'gotifyEnabled': false,
      'gotifyConfigured': false,
      'gotifyServerUrl': null,
      'gotifyTokenConfigured': false,
      'maskedGotifyToken': null,
      'webhookEnabled': false,
      'webhookConfigured': false,
      'webhookUrl': null,
      'webhookSecretConfigured': false,
      'maskedWebhookSecret': null,
      'taskAssignmentEnabled': true,
      'taskCommentEnabled': true,
      'taskStatusChangeEnabled': true,
      'dueDateReminderEnabled': true,
      'dueDateReminderLeadTimeMinutes': 1440,
      'workspaces': <Object?>[],
      'createdAt': null,
      'updatedAt': null,
    };
    workspaces.add({
      'id': workspaceId,
      'name': 'Test Workspace',
      'slug': 'test-workspace',
      'logo': null,
      'description': null,
      'createdAt': _now,
      'role': 'owner',
    });
    members.addAll([
      {'id': userId, 'name': 'Test User', 'email': email, 'image': null, 'role': 'owner'},
      {
        'id': 'user-2',
        'name': 'Second User',
        'email': 'second@example.com',
        'image': null,
        'role': 'member',
      },
    ]);

    addProject(id: projectId, name: 'Demo', slug: 'DEMO');
    addProject(id: secondProjectId, name: 'Second project', slug: 'SEC');

    final parent = addTask(id: 'task-1', title: 'Set up the project', priority: 'high');
    final child = addTask(
      id: 'task-2',
      title: 'Write the first description',
      description: 'Write the **first** description\n\n- [ ] a checklist item',
      priority: 'medium',
    );
    addTask(id: 'task-3', title: 'Review the board layout', status: 'in-progress', priority: 'low');
    final labeled = addTask(
      id: 'task-4',
      title: 'Fix the drag preview',
      status: 'in-progress',
      priority: 'urgent',
    );
    addTask(id: 'task-5', title: 'Ship the beta', status: 'in-review', priority: 'high');
    addTask(id: 'task-6', title: 'Celebrate', status: 'done', assigneeId: null);

    addLabel('bug');
    addLabel('bug', taskId: labeled['id'] as String);
    addRelation(parent['id'] as String, child['id'] as String);
    addComment(parent['id'] as String, 'A first comment.');
    addNotification(
      title: 'Assigned to you',
      content: 'Fix the drag preview',
      resourceId: labeled['id'] as String,
    );
    addNotification(
      type: 'workspace_created',
      eventData: {'workspaceName': 'Test Workspace'},
      resourceId: workspaceId,
      resourceType: 'workspace',
      isRead: true,
    );
  }

  // --- The adapter ---

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = FakeRequest(
      options.method,
      options.uri.path.replaceFirst(RegExp(r'^/+'), ''),
      options.uri.queryParameters,
      options.headers,
      options.data is String ? jsonDecode(options.data as String) : options.data,
    );
    requests.add(request);

    if (unreachable) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'The fake server is unreachable.',
      );
    }
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    for (final (gate, released) in List.of(_gates)) {
      if (_matches(gate._method, gate._pattern, request)) await released.future;
    }

    final response = _respond(request);
    final text = response.body == null
        ? ''
        : response.body is String
        ? response.body as String
        : jsonEncode(response.body);
    return ResponseBody.fromString(
      text,
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final entry in response.headers.entries) entry.key: [entry.value],
      },
    );
  }

  bool _matches(String? method, Pattern pattern, FakeRequest request) =>
      (method == null || method == request.method) && request.path.contains(pattern);

  FakeResponse _respond(FakeRequest request) {
    for (final override in _overrides) {
      if (!_matches(override.method, override.pattern, request)) continue;
      final remaining = override.remaining;
      if (remaining != null) {
        if (remaining == 1) {
          _overrides.remove(override);
        } else {
          override.remaining = remaining - 1;
        }
      }
      return override.respond(request);
    }

    final open = request.path == 'api/config' || request.path == 'api/auth/sign-in/email';
    if (!open && !_authorized(request)) return _error(401, 'Unauthorized', 'UNAUTHORIZED');

    for (final route in _routes) {
      if (route.method != request.method) continue;
      final match = route.pattern.firstMatch(request.path);
      if (match == null) continue;
      final params = [for (var i = 1; i <= match.groupCount; i++) match.group(i)!];
      try {
        final result = route.handler(request, params);
        return result is FakeResponse ? result : FakeResponse(200, result);
      } on _NotFound catch (error) {
        return _error(404, error.message, 'NOT_FOUND');
      } catch (error) {
        // Dio would report anything thrown here as an unreachable server, which hides the mistake.
        return _error(500, 'FakeKaneo failed on $request: $error', 'FAKE_FAILED');
      }
    }
    return _error(404, 'Not found', 'NOT_FOUND');
  }

  bool _authorized(FakeRequest request) {
    if (credentialsRevoked) return false;
    final headers = request.headers;
    return headers['x-api-key'] == apiKey || headers['Authorization'] == 'Bearer $sessionToken';
  }

  FakeResponse _error(int status, String message, String code) =>
      FakeResponse(status, {'message': message, 'code': code});

  // --- Helpers for the routes ---

  String get _now => DateTime.utc(2026, 11, 6, 12).toIso8601String();

  String _id(String prefix) => '$prefix-${_nextId++}';

  Map<String, dynamic> _body(FakeRequest request) =>
      (request.body as Map?)?.cast<String, dynamic>() ?? {};

  Map<String, dynamic> _find(List<Map<String, dynamic>> records, String id, String what) =>
      records.firstWhere((r) => r['id'] == id, orElse: () => throw _NotFound('$what not found'));

  /// A comment of the signed-in user. The server treats anyone else's as not there.
  Map<String, dynamic> _ownComment(String activityId) =>
      activities
          .where((a) => a['id'] == activityId && a['type'] == 'comment' && a['userId'] == userId)
          .firstOrNull ??
      (throw const _NotFound('Comment not found or you are not the author'));

  Map<String, dynamic> _member(String? id) =>
      members.firstWhere((m) => m['id'] == id, orElse: () => const {'name': null, 'image': null});

  Map<String, dynamic> _logActivity(
    String taskId,
    String type, {
    String? content,
    Map<String, Object?>? eventData,
    String authorId = userId,
    String? externalUserName,
    String? externalSource,
  }) {
    final activity = <String, dynamic>{
      'id': _id('activity'),
      'taskId': taskId,
      'type': type,
      'createdAt': _now,
      'updatedAt': _now,
      'userId': authorId,
      'content': content,
      'eventData': eventData ?? (type == 'comment' ? null : <String, Object?>{}),
      'externalUserName': externalUserName,
      'externalUserAvatar': null,
      'externalSource': externalSource,
      'externalUrl': null,
    };
    activities.insert(0, activity);
    return activity;
  }

  List<Map<String, dynamic>> _taskLabels(String taskId) => [
    for (final label in labels)
      if (label['taskId'] == taskId) label,
  ];

  /// A task as `GET api/task/:id` returns it.
  Map<String, dynamic> _taskDetail(Map<String, dynamic> task) {
    final assignee = _member(task['userId'] as String?);
    return {
      ...task,
      'columnId': columns
          .where((c) => c['projectId'] == task['projectId'] && c['slug'] == task['status'])
          .firstOrNull?['id'],
      'assigneeName': assignee['name'],
      'assigneeId': task['userId'],
      'workspaceId': workspaceId,
    };
  }

  /// A task as it appears on a board.
  Map<String, dynamic> _boardTask(Map<String, dynamic> task) {
    final assignee = _member(task['userId'] as String?);
    final children = relations.where(
      (r) => r['sourceTaskId'] == task['id'] && r['relationType'] == 'subtask',
    );
    final finalSlugs = {
      for (final column in columns)
        if (column['projectId'] == task['projectId'] && column['isFinal'] == true) column['slug'],
    };
    return {
      ...task,
      'descriptionDeferred': false,
      'assigneeName': assignee['name'],
      'assigneeId': task['userId'],
      'assigneeImage': assignee['image'],
      'subtaskCounts': {
        'completed': children.where((relation) {
          final child = tasks.where((t) => t['id'] == relation['targetTaskId']).firstOrNull;
          return child != null && finalSlugs.contains(child['status']);
        }).length,
        'total': children.length,
      },
      'labels': [
        for (final label in _taskLabels(task['id'] as String))
          {'id': label['id'], 'name': label['name'], 'color': label['color']},
      ],
      'externalLinks': [
        for (final link in externalLinks)
          if (link['taskId'] == task['id']) link,
      ],
    };
  }

  int _byPosition(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (a['position'] as num).compareTo(b['position'] as num);

  Map<String, dynamic> _board(FakeRequest request, String projectId) {
    final project = _find(projects, projectId, 'Project');
    final projectColumns = columns.where((c) => c['projectId'] == projectId).toList()
      ..sort(_byPosition);
    final all = tasks.where((t) => t['projectId'] == projectId).toList()..sort(_byPosition);
    final pageSize = boardPageSize;
    final page = int.tryParse(request.query['page'] ?? '') ?? 1;
    final pageTasks = all.skip((page - 1) * pageSize).take(pageSize).toList();
    final totalPages = all.isEmpty ? 1 : (all.length / pageSize).ceil();

    List<Map<String, dynamic>> inStatus(String status) => [
      for (final task in pageTasks)
        if (task['status'] == status) _boardTask(task),
    ];

    return {
      'data': {
        'id': project['id'],
        'name': project['name'],
        'slug': project['slug'],
        'icon': project['icon'],
        'description': project['description'],
        'descriptionDeferred': false,
        'isPublic': project['isPublic'],
        'workspaceId': project['workspaceId'],
        'backgroundVersion': project['backgroundVersion'],
        'columns': [
          for (final column in projectColumns)
            {
              'id': column['slug'],
              'slug': column['slug'],
              'name': column['name'],
              'position': column['position'],
              'icon': column['icon'],
              'isFinal': column['isFinal'],
              'tasks': inStatus(column['slug'] as String),
            },
        ],
        'archivedTasks': inStatus('archived'),
        'plannedTasks': inStatus('planned'),
      },
      'pagination': {
        'total': all.length,
        'page': page,
        'pageSize': pageSize,
        'totalPages': totalPages,
        'relatedPage': int.tryParse(request.query['relatedPage'] ?? '') ?? 1,
        'relatedPageSize': 100,
        'relatedTotalPages': 1,
      },
    };
  }

  Map<String, dynamic> _projectWithStatistics(Map<String, dynamic> project) {
    final own = tasks.where((t) => t['projectId'] == project['id']).toList();
    final finalSlugs = {
      for (final column in columns)
        if (column['projectId'] == project['id'] && column['isFinal'] == true) column['slug'],
    };
    final done = own.where((t) => finalSlugs.contains(t['status'])).length;
    return {
      ...project,
      'statistics': {
        'totalTasks': own.length,
        'completionPercentage': own.isEmpty ? 0 : (done * 100 / own.length).round(),
        'dueDate': null,
      },
      'archivedTasks': <Object?>[],
      'plannedTasks': <Object?>[],
      'columns': <Object?>[],
    };
  }

  Map<String, dynamic>? _projectOfTask(Map<String, dynamic> task) =>
      projects.where((p) => p['id'] == task['projectId']).firstOrNull;

  /// Whether the inbox of [workspaceId] lists [notification]. Like the server, this goes by where
  /// its task or workspace is now. Ones that point to nothing here show in every workspace, which
  /// keeps tests with made-up resources simple.
  bool _notificationIn(Map<String, dynamic> notification, String workspaceId) {
    final resource = notification['resourceId'];
    if (resource == null) return true;
    if (notification['resourceType'] == 'workspace') return resource == workspaceId;
    final task = tasks.where((t) => t['id'] == resource).firstOrNull;
    final project = task == null ? null : _projectOfTask(task);
    return project == null || project['workspaceId'] == workspaceId;
  }

  Map<String, dynamic> _assigned(FakeRequest request) {
    final workspace = request.query['workspaceId'];
    final mine = [
      for (final task in tasks)
        if (task['userId'] == userId &&
            (workspace == null || _projectOfTask(task)?['workspaceId'] == workspace))
          task,
    ];
    return {
      'tasks': [
        for (final task in mine)
          () {
            final project = projects.firstWhere((p) => p['id'] == task['projectId']);
            final column = columns
                .where((c) => c['projectId'] == project['id'] && c['slug'] == task['status'])
                .firstOrNull;
            return {
              'id': task['id'],
              'projectId': task['projectId'],
              'number': task['number'],
              'title': task['title'],
              'status': task['status'],
              'statusName': column?['name'],
              'statusIcon': null,
              'priority': task['priority'],
              'dueDate': task['dueDate'],
              'projectName': project['name'],
              'projectSlug': project['slug'],
              'projectIcon': project['icon'],
              'labels': [
                for (final label in _taskLabels(task['id'] as String))
                  {'id': label['id'], 'name': label['name'], 'color': label['color']},
              ],
            };
          }(),
      ],
      'total': mine.length,
    };
  }

  Map<String, dynamic> _relatedTask(String id) {
    final task = _find(tasks, id, 'Task');
    final finalSlugs = {
      for (final column in columns)
        if (column['projectId'] == task['projectId'] && column['isFinal'] == true) column['slug'],
    };
    return {
      'id': task['id'],
      'title': task['title'],
      'status': task['status'],
      'isCompleted': finalSlugs.contains(task['status']),
      'priority': task['priority'],
      'number': task['number'],
      'projectId': task['projectId'],
      'userId': task['userId'],
      'assigneeName': _member(task['userId'] as String?)['name'],
    };
  }

  Map<String, dynamic> _workspaceActivity(Map<String, dynamic> activity) {
    final task = _find(tasks, activity['taskId'] as String, 'Task');
    final project = projects.firstWhere((p) => p['id'] == task['projectId']);
    final author = _member(activity['userId'] as String?);
    return {
      'id': activity['id'],
      'type': activity['type'],
      'createdAt': activity['createdAt'],
      'eventData': activity['eventData'],
      'userId': activity['userId'],
      'userName': author['name'],
      'userImage': author['image'],
      'externalUserName': null,
      'externalUserAvatar': null,
      'taskId': task['id'],
      'taskTitle': task['title'],
      'taskNumber': task['number'],
      'projectId': project['id'],
      'projectSlug': project['slug'],
      'excerpt': activity['content'],
    };
  }

  /// Finds what the real server finds, scored and limited the same way. What differs between result
  /// kinds is there too: comments and other activity name their task only by ticket id.
  Map<String, dynamic> _search(FakeRequest request) {
    final query = (request.query['q'] ?? '').toLowerCase();
    final type = request.query['type'] ?? 'all';
    final limit = int.parse(request.query['limit'] ?? '20');
    bool has(Object? text) => '${text ?? ''}'.toLowerCase().contains(query);
    bool wanted(String kind) => type == 'all' || type == kind;
    final workspaceName = workspaces.first['name'];

    final results = <Map<String, dynamic>?>[
      if (wanted('tasks'))
        for (final task in tasks)
          if (has(task['title']) || has(task['description']))
            () {
              final project = projects.firstWhere((p) => p['id'] == task['projectId']);
              return <String, dynamic>{
                'id': task['id'],
                'type': 'task',
                'title': task['title'],
                'description': task['description'],
                'projectId': project['id'],
                'projectName': project['name'],
                'projectSlug': project['slug'],
                'workspaceId': workspaceId,
                'workspaceName': workspaceName,
                'userId': task['userId'],
                'userName': _member(task['userId'] as String?)['name'],
                'createdAt': task['createdAt'],
                'relevanceScore': has(task['title']) ? 3 : 2,
                'taskNumber': task['number'],
                'priority': task['priority'],
                'status': task['status'],
              };
            }(),
      if (wanted('projects'))
        for (final project in projects)
          if (has(project['name']) || has(project['description']))
            {
              'id': project['id'],
              'type': 'project',
              'title': project['name'],
              if (project['description'] != null) 'description': project['description'],
              'projectId': project['id'],
              'projectSlug': project['slug'],
              'workspaceId': workspaceId,
              'workspaceName': workspaceName,
              'createdAt': project['createdAt'],
              'relevanceScore': has(project['name']) ? 3 : 2,
            },
      if (wanted('workspaces'))
        for (final workspace in workspaces)
          if (has(workspace['name']))
            {
              'id': workspace['id'],
              'type': 'workspace',
              'title': workspace['name'],
              'workspaceId': workspace['id'],
              'workspaceName': workspace['name'],
              'createdAt': _now,
              'relevanceScore': 3,
            },
      if (type == 'all' || type == 'comments' || type == 'activities')
        for (final activity in activities)
          if (type != 'comments' || activity['type'] == 'comment')
            () {
              final task = tasks.firstWhere((t) => t['id'] == activity['taskId']);
              final inContent = has(activity['content']);
              if (!inContent && !has(task['title'])) return null;
              final project = projects.firstWhere((p) => p['id'] == task['projectId']);
              final isComment = activity['type'] == 'comment';
              return <String, dynamic>{
                'id': activity['id'],
                'type': isComment ? 'comment' : 'activity',
                'title': '${isComment ? 'Comment' : activity['type']} on ${task['title']}',
                if (activity['content'] != null) 'content': activity['content'],
                'projectId': project['id'],
                'projectName': project['name'],
                'projectSlug': project['slug'],
                'workspaceId': workspaceId,
                'workspaceName': workspaceName,
                'userId': activity['userId'],
                'userName': _member(activity['userId'] as String?)['name'],
                'createdAt': activity['createdAt'],
                'relevanceScore': inContent ? 2 : 1,
                'taskNumber': task['number'],
              };
            }(),
    ].nonNulls.toList();

    results.sort((a, b) {
      final byScore = (b['relevanceScore'] as int).compareTo(a['relevanceScore'] as int);
      return byScore != 0
          ? byScore
          : (b['createdAt'] as String).compareTo(a['createdAt'] as String);
    });
    return {
      'results': results.take(limit).toList(),
      'totalCount': results.length,
      'searchQuery': request.query['q'],
    };
  }

  Map<String, dynamic> _fullOrganization(String id) {
    final workspace = _find(workspaces, id, 'Workspace');
    return {
      'name': workspace['name'],
      'slug': workspace['slug'],
      'logo': workspace['logo'],
      'createdAt': workspace['createdAt'],
      'metadata': null,
      'description': workspace['description'],
      'id': workspace['id'],
      'invitations': invitations,
      'members': [
        for (final member in members)
          {
            'organizationId': id,
            'userId': member['id'],
            'role': member['role'],
            'createdAt': _now,
            'id': 'membership-${member['id']}',
            'user': {
              'id': member['id'],
              'name': member['name'],
              'email': member['email'],
              'image': member['image'],
            },
          },
      ],
      'teams': [
        {
          'name': workspace['name'],
          'memberCount': members.length,
          'organizationId': id,
          'createdAt': _now,
          'updatedAt': _now,
          'id': 'team-1',
        },
      ],
    };
  }

  // --- The routes ---

  void _route(String method, String path, _Handler handler) {
    final pattern = RegExp('^${path.replaceAllMapped(RegExp(r':\w+'), (_) => r'([^/]+)')}\$');
    _routes.add(_Route(method, pattern, handler));
  }

  /// Changes one field of a task and returns the task.
  _Handler _setTaskField(String field) => (request, params) {
    final task = _find(tasks, params[0], 'Task');
    task[field] = _body(request)[field];
    return _taskDetail(task);
  };

  void _registerRoutes() {
    _route('GET', 'api/config', (request, params) => instanceConfig);
    _route('POST', 'api/auth/sign-in/email', (request, params) {
      final body = _body(request);
      if (body['email'] != email || body['password'] != password) {
        return _error(401, 'Invalid email or password', 'INVALID_EMAIL_OR_PASSWORD');
      }
      return FakeResponse(
        200,
        {'redirect': false, 'token': sessionToken, 'user': user},
        {'set-auth-token': sessionToken},
      );
    });

    // User
    _route('GET', 'api/user/me', (request, params) => user);
    _route('POST', 'api/auth/update-user', (request, params) {
      user.addAll(_body(request));
      return {'status': true};
    });
    _route('POST', 'api/auth/change-password', (request, params) {
      return {'token': sessionToken, 'user': user};
    });
    _route('PUT', 'api/user/avatar', (request, params) {
      user['image'] = '/api/asset/avatar-1';
      return {'id': 'avatar-1', 'url': user['image']};
    });
    _route('DELETE', 'api/user/avatar', (request, params) {
      user['image'] = null;
      return {'success': true};
    });
    _route('POST', 'api/auth/sign-out', (request, params) => {'success': true});
    _route(
      'POST',
      'api/auth/delete-user',
      (request, params) => {'success': true, 'message': 'User deleted'},
    );

    // Workspaces
    _route('GET', 'api/workspace', (request, params) => workspaces);
    _route('GET', 'api/auth/organization/list', (request, params) => workspaces);
    _route('GET', 'api/workspace/:id/capabilities', (request, params) => capabilities);
    _route('GET', 'api/workspace/:id/members', (request, params) => members);
    _route('POST', 'api/auth/organization/has-permission', (request, params) {
      return {'success': true, 'error': null};
    });
    _route('POST', 'api/auth/organization/create', (request, params) {
      final body = _body(request);
      final workspace = <String, dynamic>{
        'id': _id('workspace'),
        'name': body['name'],
        'slug': body['slug'],
        'logo': null,
        'description': null,
        'createdAt': _now,
        'role': 'owner',
      };
      workspaces.add(workspace);
      return workspace;
    });
    _route('POST', 'api/auth/organization/update', (request, params) {
      final body = _body(request);
      final workspace = _find(workspaces, body['organizationId'] as String, 'Workspace');
      workspace.addAll((body['data'] as Map).cast<String, dynamic>());
      return workspace;
    });
    _route('POST', 'api/auth/organization/delete', (request, params) {
      workspaces.removeWhere((w) => w['id'] == _body(request)['organizationId']);
      return {'success': true};
    });
    _route('POST', 'api/auth/organization/leave', (request, params) {
      workspaces.removeWhere((w) => w['id'] == _body(request)['organizationId']);
      return {'success': true};
    });
    _route('POST', 'api/auth/organization/set-active', (request, params) => {'success': true});
    _route('GET', 'api/auth/organization/get-full-organization', (request, params) {
      return _fullOrganization(request.query['organizationId'] ?? '');
    });
    _route('GET', 'api/auth/organization/list-roles', (request, params) {
      return [
        for (final role in const ['viewer', 'member', 'admin', 'owner'])
          {
            'organizationId': request.query['organizationId'],
            'role': role,
            'permission': {
              for (final resource in const [
                'organization',
                'member',
                'invitation',
                'team',
                'ac',
                'project',
                'task',
                'label',
                'workspace',
              ])
                resource: const ['read'],
            },
            'createdAt': _now,
            'updatedAt': _now,
            'id': 'role-$role',
          },
      ];
    });
    _route('POST', 'api/auth/organization/invite-member', (request, params) {
      final body = _body(request);
      final invitation = <String, dynamic>{
        'id': _id('invitation'),
        'organizationId': body['organizationId'],
        'email': body['email'],
        'role': body['role'],
        'status': 'pending',
        'expiresAt': _now,
        'createdAt': _now,
      };
      invitations.add(invitation);
      return invitation;
    });
    _route('POST', 'api/auth/organization/cancel-invitation', (request, params) {
      invitations.removeWhere((i) => i['id'] == _body(request)['invitationId']);
      return {'success': true};
    });
    _route('POST', 'api/auth/organization/remove-member', (request, params) {
      final id = _body(request)['memberIdOrEmail'];
      members.removeWhere((m) => m['id'] == id || m['email'] == id);
      return {'success': true};
    });
    _route('POST', 'api/auth/organization/update-member-role', (request, params) {
      final body = _body(request);
      _find(members, body['memberId'] as String, 'Member')['role'] = body['role'];
      return {'success': true};
    });
    _route('GET', 'api/invitation/pending', (request, params) {
      return [
        for (final invitation in invitations)
          {
            'id': invitation['id'],
            'email': invitation['email'],
            'workspaceId': invitation['organizationId'],
            'workspaceName': workspaces.first['name'],
            'inviterName': user['name'],
            'expiresAt': invitation['expiresAt'],
            'createdAt': invitation['createdAt'],
            'status': invitation['status'],
          },
      ];
    });
    _route('POST', 'api/auth/organization/accept-invitation', (request, params) {
      invitations.removeWhere((i) => i['id'] == _body(request)['invitationId']);
      return {'success': true};
    });
    _route('POST', 'api/auth/organization/reject-invitation', (request, params) {
      invitations.removeWhere((i) => i['id'] == _body(request)['invitationId']);
      return {'success': true};
    });

    // Projects
    _route('GET', 'api/project', (request, params) {
      final includeArchived = request.query['includeArchived'] == 'true';
      return [
        for (final project in projects)
          if (project['workspaceId'] == request.query['workspaceId'] &&
              (includeArchived || project['archivedAt'] == null))
            _projectWithStatistics(project),
      ];
    });
    _route('POST', 'api/project', (request, params) {
      final body = _body(request);
      return addProject(name: body['name'] as String, slug: body['slug'] as String)..addAll(body);
    });
    _route('GET', 'api/project/:id', (request, params) => _find(projects, params[0], 'Project'));
    _route('PUT', 'api/project/:id/archive', (request, params) {
      _find(projects, params[0], 'Project')['archivedAt'] = _now;
      return {'success': true};
    });
    _route('PUT', 'api/project/:id/unarchive', (request, params) {
      _find(projects, params[0], 'Project')['archivedAt'] = null;
      return {'success': true};
    });
    _route('PUT', 'api/project/:id/move', (request, params) {
      _find(projects, params[0], 'Project')['workspaceId'] = _body(request)['workspaceId'];
      return {'success': true};
    });
    _route('PUT', 'api/project/:id', (request, params) {
      return _find(projects, params[0], 'Project')..addAll(_body(request));
    });
    _route('DELETE', 'api/project/:id', (request, params) {
      final project = _find(projects, params[0], 'Project');
      projects.remove(project);
      tasks.removeWhere((t) => t['projectId'] == project['id']);
      columns.removeWhere((c) => c['projectId'] == project['id']);
      return project;
    });

    // Tasks. Routes with a fixed second segment come before `api/task/:id`.
    _route('GET', 'api/task/tasks/:projectId', (request, params) => _board(request, params[0]));
    _route('GET', 'api/task/assigned', (request, params) => _assigned(request));
    _route('GET', 'api/task/by-ticket-id/:ticket', (request, params) {
      final parts = Uri.decodeComponent(params[0]).split('-');
      final project = projects
          .where((p) => (p['slug'] as String).toUpperCase() == parts.first.toUpperCase())
          .firstOrNull;
      final task = tasks
          .where((t) => t['projectId'] == project?['id'] && '${t['number']}' == parts.lastOrNull)
          .firstOrNull;
      if (task == null) throw const _NotFound('Task not found');
      return _taskDetail(task);
    });
    _route('PUT', 'api/task/title/:id', _setTaskField('title'));
    _route('PUT', 'api/task/description/:id', _setTaskField('description'));
    _route('PUT', 'api/task/status/:id', (request, params) {
      final task = _find(tasks, params[0], 'Task');
      final oldStatus = task['status'];
      task['status'] = _body(request)['status'];
      _logActivity(
        task['id'] as String,
        'status_changed',
        eventData: {'oldStatus': oldStatus, 'newStatus': task['status']},
      );
      return _taskDetail(task);
    });
    _route('PUT', 'api/task/priority/:id', _setTaskField('priority'));
    _route('PUT', 'api/task/due-date/:id', _setTaskField('dueDate'));
    _route('PUT', 'api/task/assignee/:id', _setTaskField('userId'));
    _route('PUT', 'api/task/move/:id', (request, params) {
      final body = _body(request);
      final task = _find(tasks, params[0], 'Task');
      final sourceId = task['projectId'] as String;
      final destinationId = body['destinationProjectId'] as String;
      if (destinationId == sourceId) {
        return _error(400, 'Task is already in that project', 'BAD_REQUEST');
      }
      final destination = _find(projects, destinationId, 'Project');
      // Like the server, this takes a column asked for, or else the one with the task's status, or
      // else the first. The task gets a number in the project it joins, and a place at the end.
      final workflow = columns.where((c) => c['projectId'] == destinationId).toList()
        ..sort(_byPosition);
      final slugs = [for (final column in workflow) column['slug'] as String];
      if (slugs.isEmpty) {
        return _error(400, 'Destination project does not have a workflow', 'BAD_REQUEST');
      }
      final requested = body['destinationStatus'] as String?;
      if (requested != null && !slugs.contains(requested)) {
        return _error(
          400,
          'Selected status is not valid for the destination project',
          'BAD_REQUEST',
        );
      }
      final oldStatus = task['status'] as String;
      final status = requested ?? (slugs.contains(oldStatus) ? oldStatus : slugs.first);
      final number = (destination['lastTaskNumber'] as int) + 1;
      destination['lastTaskNumber'] = number;
      task.addAll({
        'projectId': destinationId,
        'status': status,
        'number': number,
        'position': tasks
            .where((t) => t['projectId'] == destinationId && t['status'] == status)
            .length,
      });
      _logActivity(
        task['id'] as String,
        'moved',
        eventData: {
          'fromProjectId': sourceId,
          'fromProjectName': _find(projects, sourceId, 'Project')['name'],
          'toProjectId': destinationId,
          'toProjectName': destination['name'],
          'oldStatus': oldStatus,
          'newStatus': status,
        },
      );
      return {
        'task': _taskDetail(task),
        'sourceProjectId': sourceId,
        'destinationProjectId': destinationId,
      };
    });
    _route('POST', 'api/task/duplicate/:id', (request, params) {
      final source = _find(tasks, params[0], 'Task');
      final sourceId = source['id'] as String;
      final parents = [
        for (final relation in relations)
          if (relation['targetTaskId'] == sourceId && relation['relationType'] == 'subtask')
            relation['sourceTaskId'] as String,
      ];
      if (parents.isNotEmpty && capabilities['updateTasks'] != true) {
        return _error(403, 'Duplicating parent links requires task:update permission', 'FORBIDDEN');
      }
      final copy = addTask(
        projectId: source['projectId'] as String,
        title: source['title'] as String,
        description: source['description'] as String,
        status: source['status'] as String,
        priority: source['priority'] as String,
        assigneeId: source['userId'] as String?,
        startDate: source['startDate'] as String?,
        dueDate: source['dueDate'] as String?,
      );
      final copyId = copy['id'] as String;
      // Like the server, the copy has the labels and the parents, and not the subtasks.
      for (final label in _taskLabels(sourceId)) {
        addLabel(label['name'] as String, color: label['color'] as String, taskId: copyId);
      }
      for (final parent in parents) {
        addRelation(parent, copyId);
      }
      return _taskDetail(copy);
    });
    _route('POST', 'api/task/reorder', (request, params) {
      for (final item in (_body(request)['tasks'] as List).cast<Map<String, dynamic>>()) {
        final task = _find(tasks, item['id'] as String, 'Task');
        task['position'] = item['position'];
        if (item['status'] != null) task['status'] = item['status'];
      }
      return {'success': true};
    });
    _route('PUT', 'api/task/image-upload/:id', (request, params) {
      return {
        'key': 'upload-${params[0]}',
        'uploadUrl': '$serverUrl/upload/${params[0]}',
        'headers': {'Content-Type': _body(request)['contentType']},
      };
    });
    _route('POST', 'api/task/image-upload/:id/finalize', (request, params) {
      return {'id': 'asset-${params[0]}', 'url': '/api/asset/asset-${params[0]}'};
    });
    _route('GET', 'api/task/:id/description', (request, params) {
      final task = _find(tasks, params[0], 'Task');
      final offset = int.tryParse(request.query['offset'] ?? '') ?? 0;
      final description = task['description'] as String;
      return {
        'content': description.substring(offset),
        'version': '${description.hashCode}',
        'nextOffset': null,
      };
    });
    _route('GET', 'api/task/:id', (request, params) {
      return _taskDetail(_find(tasks, params[0], 'Task'));
    });
    _route('POST', 'api/task/:projectId', (request, params) {
      _find(projects, params[0], 'Project');
      final body = _body(request);
      // Like the server, this takes only a column of the project or a status every project has.
      final status = body['status'] as String? ?? 'to-do';
      final valid = {
        for (final column in columns)
          if (column['projectId'] == params[0]) column['slug'],
        'planned',
        'archived',
      };
      if (!valid.contains(status)) {
        return _error(400, 'Invalid status "$status".', 'BAD_REQUEST');
      }
      // Like the server, this fills in a required custom field left out with its default. It is
      // refused only when there is no default, which a field can't be defined without.
      final provided = {
        for (final field in body['customFields'] as List? ?? const [])
          (field as Map)['fieldId']: field['value'],
      };
      final fields = [
        for (final field in customFields)
          if (field['projectId'] == params[0]) field,
      ];
      for (final field in fields) {
        final hasDefault = (field['defaultValue'] as String? ?? '').trim().isNotEmpty;
        if (field['required'] == true && !provided.containsKey(field['id']) && !hasDefault) {
          return _error(
            400,
            'Custom field "${field['name']}" is required to create a task.',
            'BAD_REQUEST',
          );
        }
      }
      final task = addTask(
        projectId: params[0],
        title: body['title'] as String,
        description: body['description'] as String? ?? '',
        status: status,
        priority: body['priority'] as String? ?? 'no-priority',
        assigneeId: body['userId'] as String?,
        startDate: body['startDate'] as String?,
        dueDate: body['dueDate'] as String?,
      );
      for (final field in fields) {
        final value =
            provided[field['id']] ?? (field['required'] == true ? field['defaultValue'] : null);
        if (value == null) continue;
        customFieldValues.add({
          'id': _id('field-value'),
          'taskId': task['id'],
          'fieldId': field['id'],
          'value': value,
          'fieldName': field['name'],
          'fieldType': field['type'],
        });
      }
      return _taskDetail(task);
    });
    _route('PUT', 'api/task/:id', (request, params) {
      // Like the server, this replaces the whole task, so an optional field left out is cleared.
      return _taskDetail(
        _find(tasks, params[0], 'Task')
          ..addAll({'startDate': null, 'dueDate': null, 'userId': null})
          ..addAll(_body(request)),
      );
    });
    _route('DELETE', 'api/task/:id', (request, params) {
      final task = _find(tasks, params[0], 'Task');
      final id = task['id'];
      tasks.remove(task);
      // Like the server, this takes everything that hangs off the task with it.
      relations.removeWhere((r) => r['sourceTaskId'] == id || r['targetTaskId'] == id);
      labels.removeWhere((l) => l['taskId'] == id);
      activities.removeWhere((a) => a['taskId'] == id);
      externalLinks.removeWhere((l) => l['taskId'] == id);
      customFieldValues.removeWhere((v) => v['taskId'] == id);
      return task;
    });

    // Columns
    _route('PUT', 'api/column/reorder/:projectId', (request, params) {
      for (final item in (_body(request)['columns'] as List).cast<Map<String, dynamic>>()) {
        _find(columns, item['id'] as String, 'Column')['position'] = item['position'];
      }
      return {'success': true};
    });
    _route('GET', 'api/column/:projectId', (request, params) {
      return columns.where((c) => c['projectId'] == params[0]).toList()..sort(_byPosition);
    });
    _route('POST', 'api/column/:projectId', (request, params) {
      final body = _body(request);
      final column = <String, dynamic>{
        'id': _id('column'),
        'projectId': params[0],
        'name': body['name'],
        'slug': (body['name'] as String).toLowerCase().replaceAll(' ', '-'),
        'position': columns.where((c) => c['projectId'] == params[0]).length,
        'icon': null,
        'color': null,
        'isFinal': body['isFinal'] ?? false,
        'createdAt': _now,
        'updatedAt': _now,
      };
      columns.add(column);
      return column;
    });
    _route('PUT', 'api/column/:id', (request, params) {
      return _find(columns, params[0], 'Column')..addAll(_body(request));
    });
    _route('DELETE', 'api/column/:id', (request, params) {
      final column = _find(columns, params[0], 'Column');
      columns.remove(column);
      return column;
    });

    // Activity and comments
    _route('GET', 'api/activity/workspace/:id', (request, params) {
      return [for (final activity in activities) _workspaceActivity(activity)];
    });
    _route('POST', 'api/activity/comment', (request, params) {
      final body = _body(request);
      final taskId = body['taskId'] as String;
      final content = body['comment'] as String;
      final task = _find(tasks, taskId, 'Task');
      final comment = addComment(taskId, content);
      // The server only notifies when a comment is created, and never the author.
      final mentioned = RegExp(
        r'<kaneo-mention[^>]*\bid="([^"]+)"',
        caseSensitive: false,
      ).allMatches(content).map((match) => match[1]!).toSet()..remove(userId);
      for (final id in mentioned) {
        notificationsToOthers.add({
          'id': _id('notification'),
          'userId': id,
          'title': null,
          'content': null,
          'type': 'task_mention',
          'eventData': {
            'taskTitle': task['title'],
            'mentionerName': _member(userId)['name'],
            'projectId': task['projectId'],
            'workspaceId': workspaceId,
          },
          'isRead': false,
          'resourceId': taskId,
          'resourceType': 'task',
          'createdAt': _now,
          'updatedAt': _now,
        });
      }
      return comment;
    });
    _route('PUT', 'api/activity/comment', (request, params) {
      final body = _body(request);
      return _ownComment(body['activityId'] as String)
        ..['content'] = body['comment']
        ..['updatedAt'] = DateTime.utc(2026, 11, 6, 13).toIso8601String();
    });
    _route('DELETE', 'api/activity/comment', (request, params) {
      final comment = _ownComment(_body(request)['activityId'] as String);
      activities.remove(comment);
      return comment;
    });
    _route('GET', 'api/activity/:taskId', (request, params) {
      return [
        for (final activity in activities)
          if (activity['taskId'] == params[0]) activity,
      ];
    });

    // Labels
    _route('GET', 'api/label/workspace/:id', (request, params) => labels);
    _route('GET', 'api/label/task/:taskId', (request, params) => _taskLabels(params[0]));
    _route('POST', 'api/label', (request, params) {
      final body = _body(request);
      return addLabel(
        body['name'] as String,
        color: body['color'] as String,
        taskId: body['taskId'] as String?,
      );
    });
    _route('PUT', 'api/label/:id/task', (request, params) {
      final label = _find(labels, params[0], 'Label');
      return addLabel(
        label['name'] as String,
        color: label['color'] as String,
        taskId: _body(request)['taskId'] as String?,
      );
    });
    _route('DELETE', 'api/label/:id/task', (request, params) {
      final label = _find(labels, params[0], 'Label');
      labels.remove(label);
      return label;
    });
    _route('PUT', 'api/label/:id', (request, params) {
      return _find(labels, params[0], 'Label')..addAll(_body(request));
    });
    _route('DELETE', 'api/label/:id', (request, params) {
      final label = _find(labels, params[0], 'Label');
      labels.remove(label);
      return label;
    });

    // Time
    _route('GET', 'api/time-entry/task/:taskId', (request, params) {
      return [
        for (final entry in timeEntries)
          if (entry['taskId'] == params[0]) entry,
      ];
    });
    _route('POST', 'api/time-entry', (request, params) {
      final entry = <String, dynamic>{
        'id': _id('time-entry'),
        'userId': userId,
        'userName': user['name'],
        'endTime': null,
        'duration': 0,
        'description': null,
        ..._body(request),
      };
      timeEntries.add(entry);
      return entry;
    });
    _route('PUT', 'api/time-entry/:id', (request, params) {
      return _find(timeEntries, params[0], 'Time entry')..addAll(_body(request));
    });

    // Relations and links
    _route('GET', 'api/task-relation/project/:id', (request, params) {
      final ids = {
        for (final task in tasks)
          if (task['projectId'] == params[0]) task['id'],
      };
      return [
        for (final relation in relations)
          if (ids.contains(relation['sourceTaskId']) && ids.contains(relation['targetTaskId']))
            relation,
      ];
    });
    _route('POST', 'api/task-relation', (request, params) {
      final body = _body(request);
      return addRelation(
        body['sourceTaskId'] as String,
        body['targetTaskId'] as String,
        body['relationType'] as String,
      );
    });
    _route('GET', 'api/task-relation/:taskId', (request, params) {
      return [
        for (final relation in relations)
          if (relation['sourceTaskId'] == params[0] || relation['targetTaskId'] == params[0])
            {
              ...relation,
              'sourceTask': _relatedTask(relation['sourceTaskId'] as String),
              'targetTask': _relatedTask(relation['targetTaskId'] as String),
            },
      ];
    });
    _route('DELETE', 'api/task-relation/:id', (request, params) {
      final relation = _find(relations, params[0], 'Relation');
      relations.remove(relation);
      return relation;
    });
    _route('GET', 'api/external-link/task/:taskId', (request, params) {
      return [
        for (final link in externalLinks)
          if (link['taskId'] == params[0]) link,
      ];
    });
    _route('POST', 'api/external-link/task/:taskId', (request, params) {
      final body = _body(request);
      final link = <String, dynamic>{
        'id': _id('link'),
        'taskId': params[0],
        'integrationId': null,
        'resourceType': 'link',
        'externalId': body['url'],
        'url': body['url'],
        'title': body['title'],
      };
      externalLinks.add(link);
      return link;
    });
    _route('DELETE', 'api/external-link/task/:taskId/:id', (request, params) {
      final link = _find(externalLinks, params[1], 'Link');
      externalLinks.remove(link);
      return link;
    });

    // Custom fields
    _route('GET', 'api/custom-field/project/:id', (request, params) {
      return [
        for (final field in customFields)
          if (field['projectId'] == params[0]) field,
      ];
    });
    _route('GET', 'api/custom-field/task/:id', (request, params) {
      return [
        for (final value in customFieldValues)
          if (value['taskId'] == params[0]) value,
      ];
    });
    _route('POST', 'api/custom-field', (request, params) {
      final field = <String, dynamic>{
        'id': _id('field'),
        'position': customFields.length,
        ..._body(request),
      };
      customFields.add(field);
      return field;
    });
    _route('PUT', 'api/custom-field/value', (request, params) {
      final body = _body(request);
      final field = _find(customFields, body['fieldId'] as String, 'Field');
      customFieldValues.removeWhere(
        (v) => v['taskId'] == body['taskId'] && v['fieldId'] == body['fieldId'],
      );
      final value = <String, dynamic>{
        'id': _id('field-value'),
        'taskId': body['taskId'],
        'fieldId': body['fieldId'],
        'value': body['value'],
        'fieldName': field['name'],
        'fieldType': field['type'],
      };
      customFieldValues.add(value);
      return value;
    });
    _route('DELETE', 'api/custom-field/:id', (request, params) {
      final field = _find(customFields, params[0], 'Field');
      customFields.remove(field);
      return field;
    });

    // Notifications
    _route('GET', 'api/notification', (request, params) {
      final workspace = request.query['workspaceId'];
      return [
        for (final notification in notifications)
          if (workspace == null || _notificationIn(notification, workspace)) notification,
      ];
    });
    _route('PATCH', 'api/notification/read-all', (request, params) {
      final workspace = request.query['workspaceId'];
      for (final notification in notifications) {
        if (workspace == null || _notificationIn(notification, workspace)) {
          notification['isRead'] = true;
        }
      }
      return {'success': true};
    });
    _route('DELETE', 'api/notification/clear-all', (request, params) {
      final workspace = request.query['workspaceId'];
      notifications.removeWhere((n) => workspace == null || _notificationIn(n, workspace));
      return {'success': true};
    });
    _route('PATCH', 'api/notification/:id/read', (request, params) {
      return _find(notifications, params[0], 'Notification')..['isRead'] = true;
    });
    _route('GET', 'api/notification-preferences', (request, params) => notificationPreferences);
    _route('PUT', 'api/notification-preferences', (request, params) {
      return notificationPreferences..addAll(_body(request));
    });

    // Search
    _route('GET', 'api/search', (request, params) => _search(request));
  }
}
