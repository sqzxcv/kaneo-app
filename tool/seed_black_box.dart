// Creates the data the black-box tests (KAN-52) start from, on a local Kaneo, and writes the accounts
// and projects to files outside the repository.
//
//     dart run tool/seed_black_box.dart [server] [output]
//
// The server defaults to http://localhost:1337, and the output to ~/.config/kaneo-app/black-box.env,
// with black-box.json beside it holding every project, column and task id.
//
// Safe to repeat. Accounts, the workspace, members, projects, columns, custom fields, tasks and
// relations are looked up by name first, and only what's missing is made. Nothing that exists is
// changed. Passwords are kept in the output file and read back from it, so keep it: an account made
// earlier can't be signed in to without it.
//
// Everything is named E-... or e-...@kaneo.local, to keep apart from what other tests leave behind.
// Sign-in uses passwords, so the API keys' limit of 100 requests a minute doesn't apply.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Who the black-box tests sign in as.
enum Person {
  owner('OWNER', 'E Owner', 'e-owner@kaneo.local'),
  member('MEMBER', 'E Member', 'e-member@kaneo.local'),

  /// A member with the `viewer` role: may read everything, and change nothing.
  restricted('RESTRICTED', 'E Viewer', 'e-viewer@kaneo.local'),

  /// Belongs to no workspace.
  loner('LONER', 'E Loner', 'e-loner@kaneo.local');

  const Person(this.key, this.name, this.email);

  final String key;
  final String name;
  final String email;
}

const workspaceName = 'E-Black box';
const workspaceSlug = 'e-black-box';

/// The roles [Person.member] and [Person.restricted] get in the workspace.
const memberRoles = {Person.member: 'member', Person.restricted: 'viewer'};

/// One project, found again by its name.
class ProjectSpec {
  const ProjectSpec(this.key, this.name, this.slug);

  final String key;
  final String name;
  final String slug;
}

const boardProject = ProjectSpec('BOARD', 'E-Board', 'EBB');
const formatsProject = ProjectSpec('FORMATS', 'E-Formats', 'EFM');
const requiredFieldProject = ProjectSpec('REQUIRED_FIELD', 'E-Required field', 'ERQ');
const emptyProject = ProjectSpec('EMPTY', 'E-Empty', 'EEM');
const projects = [boardProject, formatsProject, requiredFieldProject, emptyProject];

/// The board's columns, in order. Kaneo makes the last four for every project.
const boardColumns = ['需求池', '已计划', 'To Do', 'In Progress', 'In Review', 'Done'];

/// The column that holds [fullColumnSize] cards, and their titles.
const fullColumn = '需求池';
const fullColumnSize = 100;
String fullColumnTitle(int i) => 'E-卡片 ${i.toString().padLeft(3, '0')}';

/// A task of the board that isn't in the full column, and the column it goes in.
typedef BoardTaskSpec = ({String title, String column});

const boardTasks = <BoardTaskSpec>[
  // Three levels, in one column so that they fold into each other.
  (title: 'E-三层 祖父', column: 'To Do'),
  (title: 'E-三层 父', column: 'To Do'),
  (title: 'E-三层 子', column: 'To Do'),
  // A child in another column than its parent.
  (title: 'E-跨列 父', column: 'To Do'),
  (title: 'E-跨列 子', column: 'In Progress'),
  // One child with two parents.
  (title: 'E-双父 父一', column: 'In Progress'),
  (title: 'E-双父 父二', column: 'In Progress'),
  (title: 'E-双父 子', column: 'In Progress'),
  // Parents all the way round.
  (title: 'E-成环 甲', column: 'In Review'),
  (title: 'E-成环 乙', column: 'In Review'),
  (title: 'E-成环 丙', column: 'In Review'),
];

/// Subtask relations of the board, as (parent, child).
const boardRelations = [
  ('E-三层 祖父', 'E-三层 父'),
  ('E-三层 父', 'E-三层 子'),
  ('E-跨列 父', 'E-跨列 子'),
  ('E-双父 父一', 'E-双父 子'),
  ('E-双父 父二', 'E-双父 子'),
  ('E-成环 甲', 'E-成环 乙'),
  ('E-成环 乙', 'E-成环 丙'),
  ('E-成环 丙', 'E-成环 甲'),
];

/// Files on the public repository, for the pictures and the attachment to point at.
const _files = 'https://raw.githubusercontent.com/sqzxcv/kaneo-app/main';
const imageUrl = '$_files/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';
const attachmentUrl = '$_files/assets/fonts/OFL.txt';
const attachmentSize = 4387;
const embedUrl = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

/// What the Kaneo tags in [formatDescriptions] point at.
class TagTargets {
  const TagTargets({
    required this.memberId,
    required this.memberName,
    required this.taskUrl,
    required this.taskKey,
    required this.taskId,
  });

  final String memberId;
  final String memberName;
  final String taskUrl;
  final String taskKey;
  final String taskId;
}

String _escape(String text) => const HtmlEscape(HtmlEscapeMode.attribute).convert(text);

/// One description for each format the black-box tests look at, by task title. The Kaneo tags are
/// written the way the web editor writes them, from `kaneo/packages/editor/src/`.
Map<String, String> formatDescriptions(TagTargets to) => {
  'E-格式 01 标题': '# 一级标题\n\n## 二级标题\n\n### 三级标题\n\n标题下面的正文。\n',
  'E-格式 02 行内样式':
      '**粗体** *斜体* ~~删除线~~ `行内代码` [链接到 Kaneo](https://kaneo.app)\n\n'
      '同一段里混排：**粗体里有 *斜体*** 和 `code`。\n',
  'E-格式 03 硬换行': '第一行，行尾两个空格  \n第二行，行尾反斜杠\\\n第三行\n',
  'E-格式 04 嵌套无序列表':
      '- 第一层 A\n'
      '  - 第二层 A1\n'
      '    - 第三层 A1a\n'
      '  - 第二层 A2\n'
      '- 第一层 B\n',
  'E-格式 05 有序列表': '1. 第一步\n2. 第二步\n3. 第三步\n',
  'E-格式 06 待办': '- [ ] 没做完的事\n- [x] 做完的事\n- [ ] 另一件没做完的事\n',
  'E-格式 07 嵌套待办':
      '- [ ] 父待办\n'
      '  - [x] 做完的子待办\n'
      '  - [ ] 没做完的子待办\n'
      '- [x] 做完的父待办\n',
  'E-格式 08 引用': '> 第一层引用\n>\n> > 嵌套的引用\n',
  'E-格式 09 代码块':
      '```dart\n'
      'void main() {\n'
      "  print('你好，Kaneo');\n"
      '}\n'
      '```\n',
  'E-格式 10 分割线': '分割线上面\n\n---\n\n分割线下面\n',
  'E-格式 11 表格':
      '| 名称 | 状态 | 数量 |\n'
      '| :--- | :---: | ---: |\n'
      '| 甲 | 进行中 | 1 |\n'
      '| 乙 | 已完成 | 22 |\n',
  'E-格式 12 Markdown 图片': '![应用图标]($imageUrl)\n',
  'E-格式 13 带宽度的 img': '<img src="$imageUrl" alt="缩小的应用图标" width="120" />\n',
  'E-格式 14 kaneo-mention':
      '请 <kaneo-mention id="${_escape(to.memberId)}" label="${_escape(to.memberName)}">'
      '</kaneo-mention> 看一下。\n',
  'E-格式 15 kaneo-attachment':
      '<kaneo-attachment url="${_escape(attachmentUrl)}" filename="OFL.txt" '
      'mime-type="text/plain" size="$attachmentSize" />\n',
  'E-格式 16 kaneo-issue-link':
      '<kaneo-issue-link url="${_escape(to.taskUrl)}" issue-key="${_escape(to.taskKey)}" '
      'task-id="${_escape(to.taskId)}" />\n',
  'E-格式 17 kaneo-embed': '<kaneo-embed url="${_escape(embedUrl)}" mode="embed" />\n',
};

/// A description saved by the old editor, as HTML.
const legacyHtmlTitle = 'E-旧 HTML 描述';
const legacyHtml =
    '<h2>旧编辑器保存的描述</h2>'
    '<p>这是 <strong>HTML</strong>，不是 <em>Markdown</em>。'
    '<a href="https://kaneo.app">一个链接</a></p>'
    '<ul><li><p>第一项</p></li><li><p>第二项</p></li></ul>'
    '<blockquote><p>一段引用</p></blockquote>';

/// A description longer than the 64 KB a board sends whole, so it comes in pages.
const longTitle = 'E-超长描述';
const longEnd = '超长描述到这里结束。';
String longDescription() {
  final text = StringBuffer('# 超长描述\n\n');
  for (var i = 1; i <= 1200; i++) {
    if (i % 100 == 1) text.write('## 第 ${(i ~/ 100) + 1} 部分\n\n');
    text.write('第 ${i.toString().padLeft(4, '0')} 段：这段文字用来检查超长描述的分页加载、滚动和编辑。\n\n');
  }
  text.write('$longEnd\n');
  return text.toString();
}

const requiredFieldName = 'E-必填文本';
const requiredFieldDefault = '默认值';
const requiredFieldTaskTitle = 'E-填了必填字段的任务';

/// Reads `KEY=value` lines.
Map<String, String> readEnv(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (line.contains('=') && !line.trimLeft().startsWith('#'))
      line.substring(0, line.indexOf('=')).trim(): line.substring(line.indexOf('=') + 1),
};

String writeEnv(Map<String, String> values) =>
    '${[for (final MapEntry(:key, :value) in values.entries) '$key=$value'].join('\n')}\n';

String _randomPassword() {
  final random = Random.secure();
  return 'E-${base64Url.encode(List.generate(15, (_) => random.nextInt(256)))}';
}

class _Response {
  const _Response(this.status, this.body, this.headers);

  final int status;
  final Object? body;
  final HttpHeaders headers;

  bool get ok => status >= 200 && status < 300;
}

/// Requests as one account, or as nobody.
class _Client {
  _Client(this._http, this.base, [this.token]);

  final HttpClient _http;
  final String base;
  final String? token;

  Future<_Response> send(String method, String path, [Object? body]) async {
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
    final response = await send(method, path, body);
    if (!response.ok) {
      throw StateError('$method $path failed (${response.status}): ${response.body}');
    }
    return response.body;
  }
}

class _SignedIn {
  _SignedIn(this.person, this.password, this.id, this.client);

  final Person person;
  final String password;
  final String id;
  final _Client client;
}

/// What this run made, and what it found already there.
class _Tally {
  final made = <String, int>{};
  final kept = <String, int>{};

  void add(String what, {required bool created}) =>
      (created ? made : kept).update(what, (n) => n + 1, ifAbsent: () => 1);

  @override
  String toString() {
    String list(Map<String, int> counts) => counts.isEmpty
        ? 'nothing'
        : [for (final MapEntry(:key, :value) in counts.entries) '$value $key'].join(', ');
    return 'made ${list(made)}; already there: ${list(kept)}';
  }
}

class _Seeder {
  _Seeder(this.base, this.saved);

  final String base;
  final Map<String, String> saved;
  final _http = HttpClient();
  final tally = _Tally();
  late final _Client anonymous = _Client(_http, base);

  Future<_SignedIn> signIn(Person person) async {
    final password = saved['KANEO_BB_${person.key}_PASSWORD'] ?? _randomPassword();
    final credentials = {'email': person.email, 'password': password};
    var response = await anonymous.send('POST', 'api/auth/sign-in/email', credentials);
    final created = !response.ok;
    if (created) {
      response = await anonymous.send('POST', 'api/auth/sign-up/email', {
        ...credentials,
        'name': person.name,
      });
    }
    if (!response.ok) {
      throw StateError(
        '${person.email} exists, but not with the password in the output file, which may be gone. '
        'Delete the account, or seed an empty Kaneo. Server said ${response.status}: '
        '${response.body}',
      );
    }
    tally.add('accounts', created: created);
    final token = response.headers.value('set-auth-token');
    final user = (response.body! as Map)['user'] as Map;
    return _SignedIn(person, password, user['id'] as String, _Client(_http, base, token));
  }

  Future<String> workspace(_SignedIn owner) async {
    final existing = (await owner.client.call('GET', 'api/workspace') as List).cast<Map>();
    final found = existing.where((w) => w['slug'] == workspaceSlug).firstOrNull;
    tally.add('workspaces', created: found == null);
    if (found != null) return found['id'] as String;
    final made = await owner.client.call('POST', 'api/auth/organization/create', {
      'name': workspaceName,
      'slug': workspaceSlug,
    });
    return made['id'] as String;
  }

  Future<void> join(_SignedIn owner, String workspaceId, _SignedIn person, String role) async {
    Future<Map?> membership() async {
      final full = await owner.client.call(
        'GET',
        'api/auth/organization/get-full-organization?organizationId=$workspaceId',
      );
      return ((full['members'] as List?) ?? const [])
          .cast<Map>()
          .where((m) => m['userId'] == person.id)
          .firstOrNull;
    }

    var member = await membership();
    tally.add('members', created: member == null);
    if (member == null) {
      // Resending hands back the invitation an earlier, cut-off run made. The invitee's own list of
      // invitations only shows to verified emails, which local accounts don't have.
      final invitation = await owner.client.call('POST', 'api/auth/organization/invite-member', {
        'organizationId': workspaceId,
        'email': person.person.email,
        'role': role,
        'resend': true,
      });
      await person.client.call('POST', 'api/auth/organization/accept-invitation', {
        'invitationId': invitation['id'],
      });
      member = await membership();
      if (member == null) throw StateError('${person.person.email} did not join');
    }
    if (member['role'] != role) {
      await owner.client.call('POST', 'api/auth/organization/update-member-role', {
        'organizationId': workspaceId,
        'memberId': member['id'],
        'role': role,
      });
    }
  }

  Future<Map> project(_Client client, String workspaceId, ProjectSpec spec) async {
    final existing = (await client.call('GET', 'api/project?workspaceId=$workspaceId') as List)
        .cast<Map>();
    final found = existing.where((p) => p['name'] == spec.name).firstOrNull;
    tally.add('projects', created: found == null);
    if (found != null) return found;
    return await client.call('POST', 'api/project', {
      'name': spec.name,
      'workspaceId': workspaceId,
      'icon': 'Layout',
      'slug': spec.slug,
    });
  }

  /// Adds the columns [boardColumns] has and the project doesn't, and puts them in that order.
  Future<List<Map>> columns(_Client client, String projectId, List<String> names) async {
    Future<List<Map>> read() async =>
        (await client.call('GET', 'api/column/$projectId') as List).cast<Map>();
    var current = await read();
    for (final name in names) {
      final exists = current.any((c) => c['name'] == name);
      tally.add('columns', created: !exists);
      if (!exists) await client.call('POST', 'api/column/$projectId', {'name': name});
    }
    current = (await read())
      ..sort((a, b) => (a['position'] as num).compareTo(b['position'] as num));
    final order = [
      for (final name in names) current.firstWhere((c) => c['name'] == name),
      ...current.where((c) => !names.contains(c['name'])),
    ];
    final positions = [for (final (i, c) in order.indexed) (c['id'] as String, i)];
    if (positions.any((p) => current.firstWhere((c) => c['id'] == p.$1)['position'] != p.$2)) {
      await client.call('PUT', 'api/column/reorder/$projectId', {
        'columns': [
          for (final (id, position) in positions) {'id': id, 'position': position},
        ],
      });
    }
    return order;
  }

  /// Every task of a project by title, from every page of its board.
  Future<Map<String, Map>> tasks(_Client client, String projectId) async {
    final byTitle = <String, Map>{};
    for (var page = 1, pages = 1; page <= pages; page++) {
      final body = await client.call('GET', 'api/task/tasks/$projectId?page=$page&limit=100');
      pages = ((body['pagination'] as Map?)?['totalPages'] as num?)?.toInt() ?? 1;
      final data = body['data'] as Map;
      for (final task in [
        for (final column in (data['columns'] as List).cast<Map>())
          ...((column['tasks'] as List?) ?? const []),
        ...((data['plannedTasks'] as List?) ?? const []),
        ...((data['archivedTasks'] as List?) ?? const []),
      ].cast<Map>()) {
        byTitle.putIfAbsent(task['title'] as String, () => task);
      }
    }
    return byTitle;
  }

  /// Makes the task unless [existing] has one by that title. Either way, returns it.
  Future<Map> task(
    _Client client,
    String projectId,
    Map<String, Map> existing,
    String title, {
    required String status,
    String description = '',
    List<Map<String, String>>? customFields,
  }) async {
    final found = existing[title];
    tally.add('tasks', created: found == null);
    if (found != null) return found;
    final made = await client.call('POST', 'api/task/$projectId', {
      'title': title,
      'description': description,
      'priority': 'no-priority',
      'status': status,
      'customFields': ?customFields,
    }) as Map;
    existing[title] = made;
    return made;
  }

  Future<void> relations(_Client client, String projectId, Map<String, Map> byTitle) async {
    final existing = (await client.call('GET', 'api/task-relation/project/$projectId') as List)
        .cast<Map>();
    for (final (parent, child) in boardRelations) {
      final source = byTitle[parent]!['id'];
      final target = byTitle[child]!['id'];
      final exists = existing.any(
        (r) =>
            r['relationType'] == 'subtask' &&
            r['sourceTaskId'] == source &&
            r['targetTaskId'] == target,
      );
      tally.add('relations', created: !exists);
      if (exists) continue;
      final response = await client.send('POST', 'api/task-relation', {
        'sourceTaskId': source,
        'targetTaskId': target,
        'relationType': 'subtask',
      });
      // 409: the same pair the other way round, which the server counts as the same relation.
      if (!response.ok && response.status != 409) {
        throw StateError(
          'Relation $parent -> $child failed (${response.status}): ${response.body}',
        );
      }
    }
  }

  Future<Map> requiredField(_Client client, String projectId) async {
    Future<Map?> find() async =>
        ((await client.call('GET', 'api/custom-field/project/$projectId')) as List)
            .cast<Map>()
            .where((f) => f['name'] == requiredFieldName)
            .firstOrNull;
    final found = await find();
    tally.add('custom fields', created: found == null);
    if (found != null) return found;
    await client.call('POST', 'api/custom-field', {
      'projectId': projectId,
      'name': requiredFieldName,
      'type': 'text',
      'required': true,
      // The server wants one for a required field, and fills it in for tasks made without a value.
      'defaultValue': requiredFieldDefault,
    });
    return (await find())!;
  }

  /// An API key of the owner's, for signing in with one. Kept if it still works.
  Future<String> apiKey(_SignedIn owner) async {
    final saved = this.saved['KANEO_BB_OWNER_API_KEY'];
    if (saved != null) {
      final request = await _http.openUrl('GET', Uri.parse('$base/api/user/me'));
      request.headers.set('x-api-key', saved);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == 200) {
        tally.add('API keys', created: false);
        return saved;
      }
    }
    tally.add('API keys', created: true);
    final key = await owner.client.call('POST', 'api/auth/api-key/create', {'name': 'e-black-box'});
    return key['key'] as String;
  }

  void close() => _http.close(force: true);
}

Future<void> main(List<String> args) async {
  final base = (args.isNotEmpty ? args[0] : 'http://localhost:1337').replaceAll(RegExp(r'/+$'), '');
  final home = Platform.environment['HOME']!;
  final envFile = File(args.length > 1 ? args[1] : '$home/.config/kaneo-app/black-box.env');
  final jsonFile = File('${envFile.path.replaceAll(RegExp(r'\.env$'), '')}.json');
  final host = Uri.parse(base).host;
  if (!['localhost', '127.0.0.1', '::1'].contains(host)) {
    stderr.writeln('Local Kaneo only, not $host.');
    exit(2);
  }

  final seeder = _Seeder(base, envFile.existsSync() ? readEnv(envFile.readAsStringSync()) : {});
  try {
    final people = {for (final person in Person.values) person: await seeder.signIn(person)};
    // The passwords first, so that a run cut off after this can still sign in next time.
    await envFile.parent.create(recursive: true);
    await envFile.writeAsString(
      writeEnv({
        ...seeder.saved,
        for (final signedIn in people.values)
          'KANEO_BB_${signedIn.person.key}_PASSWORD': signedIn.password,
      }),
    );
    await Process.run('chmod', ['600', envFile.path]);
    final owner = people[Person.owner]!;
    final api = owner.client;
    final workspaceId = await seeder.workspace(owner);
    for (final MapEntry(key: person, value: role) in memberRoles.entries) {
      await seeder.join(owner, workspaceId, people[person]!, role);
    }

    final made = <ProjectSpec, Map>{};
    for (final spec in projects) {
      made[spec] = await seeder.project(api, workspaceId, spec);
    }
    String idOf(ProjectSpec spec) => made[spec]!['id'] as String;

    // The board: six columns, one of them full, and every shape of parents and children.
    final board = idOf(boardProject);
    final columns = await seeder.columns(api, board, boardColumns);
    String slugOf(String column) =>
        columns.firstWhere((c) => c['name'] == column)['slug'] as String;
    final boardTasksByTitle = await seeder.tasks(api, board);
    for (var i = 1; i <= fullColumnSize; i++) {
      await seeder.task(
        api,
        board,
        boardTasksByTitle,
        fullColumnTitle(i),
        status: slugOf(fullColumn),
      );
    }
    for (final spec in boardTasks) {
      await seeder.task(api, board, boardTasksByTitle, spec.title, status: slugOf(spec.column));
    }
    await seeder.relations(api, board, boardTasksByTitle);

    // Descriptions.
    final formats = idOf(formatsProject);
    final formatColumns = await seeder.columns(api, formats, const []);
    final todo = formatColumns.first['slug'] as String;
    final linked = boardTasksByTitle['E-三层 祖父']!;
    final number = linked['number'];
    final descriptions = {
      ...formatDescriptions(
        TagTargets(
          memberId: people[Person.member]!.id,
          memberName: Person.member.name,
          taskUrl:
              'http://localhost:5173/dashboard/workspace/$workspaceId/project/$board/task/'
              '${linked['id']}',
          taskKey: '${made[boardProject]!['slug'] ?? boardProject.slug}-$number',
          taskId: linked['id'] as String,
        ),
      ),
      legacyHtmlTitle: legacyHtml,
      longTitle: longDescription(),
    };
    final formatTasksByTitle = await seeder.tasks(api, formats);
    for (final MapEntry(key: title, value: description) in descriptions.entries) {
      await seeder.task(
        api,
        formats,
        formatTasksByTitle,
        title,
        status: todo,
        description: description,
      );
    }

    // A required custom field, with one task that has it filled.
    final requiredId = idOf(requiredFieldProject);
    final field = await seeder.requiredField(api, requiredId);
    final requiredColumns = await seeder.columns(api, requiredId, const []);
    final requiredTasksByTitle = await seeder.tasks(api, requiredId);
    await seeder.task(
      api,
      requiredId,
      requiredTasksByTitle,
      requiredFieldTaskTitle,
      status: requiredColumns.first['slug'] as String,
      customFields: [
        {'fieldId': field['id'] as String, 'value': '已填写'},
      ],
    );

    final apiKey = await seeder.apiKey(owner);

    final env = <String, String>{
      'KANEO_BB_SERVER_URL': base,
      for (final signedIn in people.values) ...{
        'KANEO_BB_${signedIn.person.key}_EMAIL': signedIn.person.email,
        'KANEO_BB_${signedIn.person.key}_PASSWORD': signedIn.password,
        'KANEO_BB_${signedIn.person.key}_NAME': signedIn.person.name,
        'KANEO_BB_${signedIn.person.key}_USER_ID': signedIn.id,
      },
      'KANEO_BB_OWNER_API_KEY': apiKey,
      'KANEO_BB_WORKSPACE_ID': workspaceId,
      for (final spec in projects) 'KANEO_BB_${spec.key}_PROJECT_ID': idOf(spec),
    };
    final manifest = {
      'server': base,
      'workspace': {'id': workspaceId, 'name': workspaceName, 'slug': workspaceSlug},
      'accounts': {
        for (final signedIn in people.values)
          signedIn.person.name: {
            'email': signedIn.person.email,
            'userId': signedIn.id,
            'role': switch (signedIn.person) {
              Person.owner => 'owner',
              Person.loner => null,
              final other => memberRoles[other],
            },
          },
      },
      'projects': {
        for (final spec in projects)
          spec.name: {'id': idOf(spec), 'slug': made[spec]!['slug'] ?? spec.slug},
      },
      'boardColumns': [
        for (final c in columns) {'name': c['name'], 'slug': c['slug'], 'id': c['id']},
      ],
      'boardRelations': [
        for (final (parent, child) in boardRelations) {'parent': parent, 'child': child},
      ],
      'requiredField': {
        'id': field['id'],
        'name': requiredFieldName,
        'type': 'text',
        'default': requiredFieldDefault,
      },
      'tasks': {
        for (final (spec, byTitle) in [
          (boardProject, boardTasksByTitle),
          (formatsProject, formatTasksByTitle),
          (requiredFieldProject, requiredTasksByTitle),
        ])
          spec.name: {
            for (final MapEntry(key: title, value: task) in byTitle.entries)
              title: {'id': task['id'], 'number': task['number'], 'status': task['status']},
          },
      },
    };

    await envFile.parent.create(recursive: true);
    await envFile.writeAsString(writeEnv(env));
    await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    await Process.run('chmod', ['600', envFile.path, jsonFile.path]);
    stdout.writeln('Black-box data on $base: ${seeder.tally}.');
    stdout.writeln('Wrote ${envFile.path} and ${jsonFile.path}');
  } finally {
    seeder.close();
  }
}
