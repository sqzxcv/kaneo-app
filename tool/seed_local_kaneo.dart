// Creates the developer account, API key and sample data on the local Kaneo, then writes dev.env.
//
// Run through `tool/local_kaneo.sh seed`. Safe to repeat: a working dev.env is left as it is.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _email = 'dev@kaneo.local';

class _Api {
  _Api(this.base);

  final String base;
  final _client = HttpClient();
  String? bearer;
  String? apiKey;

  Future<({int status, Object? body, HttpHeaders headers})> send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final request = await _client.openUrl(method, Uri.parse('$base/$path'));
    request.headers.set('accept', 'application/json');
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (apiKey != null) request.headers.set('x-api-key', apiKey!);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? parsed = text;
    try {
      parsed = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      parsed = text;
    }
    return (status: response.statusCode, body: parsed, headers: response.headers);
  }

  Future<dynamic> ok(String method, String path, [Object? body]) async {
    final result = await send(method, path, body);
    if (result.status < 200 || result.status >= 300) {
      throw StateError('$method $path failed (${result.status}): ${result.body}');
    }
    return result.body;
  }

  void close() => _client.close(force: true);
}

Map<String, String> _readEnv(File file) {
  if (!file.existsSync()) return {};
  return {
    for (final line in file.readAsLinesSync())
      if (line.contains('=') && !line.startsWith('#'))
        line.substring(0, line.indexOf('=')): line.substring(line.indexOf('=') + 1),
  };
}

String _randomPassword() {
  final random = Random.secure();
  return base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
}

Future<void> main(List<String> args) async {
  final base = args[0];
  final envFile = File(args[1]);
  final api = _Api(base);
  try {
    final existing = _readEnv(envFile);
    final existingKey = existing['KANEO_DEV_API_KEY'];
    if (existingKey != null) {
      api.apiKey = existingKey;
      if ((await api.send('GET', 'api/user/me')).status == 200) {
        stdout.writeln('Already seeded. Using ${envFile.path}');
        return;
      }
      api.apiKey = null;
    }

    final password = existing['KANEO_DEV_PASSWORD'] ?? _randomPassword();
    var auth = await api.send('POST', 'api/auth/sign-up/email', {
      'name': 'Kaneo Dev',
      'email': _email,
      'password': password,
    });
    if (auth.status >= 300) {
      auth = await api.send('POST', 'api/auth/sign-in/email', {
        'email': _email,
        'password': password,
      });
    }
    if (auth.status >= 300) {
      throw StateError(
        '$_email exists with another password and dev.env is gone. Reset the local database: '
        'tool/local_kaneo.sh stop, then delete ~/.local/share/kaneo-app/pgdata and run setup again.',
      );
    }
    api.bearer = auth.headers.value('set-auth-token');

    final key = await api.ok('POST', 'api/auth/api-key/create', {'name': 'flutter-dev'});
    final apiKey = key['key'] as String;

    final workspaces = await api.ok('GET', 'api/workspace') as List;
    final workspaceId = workspaces.isNotEmpty
        ? workspaces.first['id'] as String
        : (await api.ok('POST', 'api/auth/organization/create', {
                'name': 'Dev Workspace',
                'slug': 'dev-workspace',
              }))['id']
              as String;
    await api.ok('POST', 'api/auth/organization/set-active', {'organizationId': workspaceId});

    final me = await api.ok('GET', 'api/user/me');
    final projectId = await _seedProject(api, workspaceId, me['id'] as String);

    await envFile.parent.create(recursive: true);
    await envFile.writeAsString(
      'KANEO_DEV_SERVER_URL=$base\n'
      'KANEO_DEV_API_KEY=$apiKey\n'
      'KANEO_DEV_EMAIL=$_email\n'
      'KANEO_DEV_PASSWORD=$password\n'
      'KANEO_DEV_WORKSPACE_ID=$workspaceId\n'
      'KANEO_DEV_PROJECT_ID=$projectId\n',
    );
    await Process.run('chmod', ['600', envFile.path]);
    stdout.writeln('Seeded. Wrote ${envFile.path}');
  } finally {
    api.close();
  }
}

Future<String> _seedProject(_Api api, String workspaceId, String userId) async {
  final projects = await api.ok('GET', 'api/project?workspaceId=$workspaceId') as List;
  if (projects.isNotEmpty) return projects.first['id'] as String;

  final project = await api.ok('POST', 'api/project', {
    'name': 'Demo',
    'workspaceId': workspaceId,
    'icon': 'Layout',
    'slug': 'DEMO',
  });
  final projectId = project['id'] as String;
  await api.ok('POST', 'api/project', {
    'name': 'Second project',
    'workspaceId': workspaceId,
    'icon': 'Layout',
    'slug': 'SEC',
  });

  final columns = await api.ok('GET', 'api/column/$projectId') as List;
  final slugs = [for (final c in columns) c['slug'] as String];

  final label = await api.ok('POST', 'api/label', {
    'name': 'bug',
    'color': 'red',
    'workspaceId': workspaceId,
  });

  final ids = <String>[];
  final tasks = [
    ('Set up the project', 'high', 0),
    ('Write the **first** description\n\n- [ ] a checklist item', 'medium', 0),
    ('Review the board layout', 'low', 1),
    ('Fix the drag preview', 'urgent', 1),
    ('Ship the beta', 'high', 2),
    ('Celebrate', 'no-priority', slugs.length - 1),
  ];
  for (final (title, priority, column) in tasks) {
    final task = await api.ok('POST', 'api/task/$projectId', {
      'title': title.split('\n').first,
      'description': title,
      'priority': priority,
      'status': slugs[column],
      'userId': userId,
    });
    ids.add(task['id'] as String);
  }

  await api.ok('PUT', 'api/label/${label['id']}/task', {'taskId': ids[3]});
  await api.ok('POST', 'api/task-relation', {
    'sourceTaskId': ids[0],
    'targetTaskId': ids[1],
    'relationType': 'subtask',
  });
  await api.ok('POST', 'api/activity/comment', {
    'taskId': ids[0],
    'comment': 'A first comment from the seed script.',
  });
  return projectId;
}
