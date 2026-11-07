// Local C-line acceptance: walks the acceptance criteria of KAN-7, KAN-8 and KAN-9 in a real device
// process, against a local Kaneo. Run only through tool/with_device.sh with dev.env:
//
//     FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=app.kaneo.kaneoApp.CTest tool/with_device.sh \
//       flutter test integration_test/task_acceptance_test.dart -d macos \
//       --dart-define-from-file=$HOME/.config/kaneo-app/dev.env --dart-define=TASK_TEST_DEVICE=macos
//
// It signs up two accounts of its own, with a workspace and projects named C-..., and never touches
// the shared development account. Each criterion is recorded separately, so that one failure doesn't
// hide the rest. Screenshots are rendered inside the app, and go with results.json into
// TASK_TEST_EVIDENCE where a simulator can reach it, otherwise the app's documents.
//
// Text goes in through the test text input, so input methods and the on-screen keyboard aren't
// covered here. Links aren't opened and nothing is shared, because those leave the app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/core/ui/calendar.dart';
import 'package:kaneo_app/features/inbox/notifications.dart';
import 'package:kaneo_app/features/markdown/markdown_view.dart';
import 'package:kaneo_app/features/markdown/mention_text.dart';
import 'package:kaneo_app/features/shell/app_shell.dart' show shellPageKey;
import 'package:kaneo_app/features/task/new_task_page.dart';
import 'package:kaneo_app/features/task/task_description.dart';
import 'package:kaneo_app/features/task/task_panel.dart';
import 'package:kaneo_app/features/task/task_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

const _device = String.fromEnvironment('TASK_TEST_DEVICE', defaultValue: 'device');
const _evidenceOverride = String.fromEnvironment('TASK_TEST_EVIDENCE');
const _server = String.fromEnvironment('KANEO_DEV_SERVER_URL');
const _password = 'c-acceptance-password';

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _card(String id) => _key('board-card-$id');
Finder _row(String id) => _key('list-task-$id');
Finder _taskOpen(String id) => find.byWidgetPredicate((w) => w is TaskView && w.taskId == id);
Finder _in(Finder scope, Finder finder) => find.descendant(of: scope, matching: finder);
Finder _field(String key) => _in(_key(key), find.byType(TextField));
Finder _inColumn(String slug, Finder finder) => _in(_key('drop-column-$slug'), finder);
final _description = find.byType(TaskDescription);
final _descriptionField = _in(_description, find.byType(TextField));
final _panel = find.byKey(taskPanelKey);

class _Person {
  const _Person(this.name, this.email, this.session, this.api);

  final String name;
  final String email;
  final Session session;
  final KaneoApi api;

  String get id => session.userId;
}

Future<_Person> _signUp(I18n i18n, String name, String email) async {
  final anonymous = ApiClient(session: () => null, i18n: i18n, onSessionExpired: (_) {});
  await anonymous.request(
    'api/auth/sign-up/email',
    serverUrl: _server,
    method: 'POST',
    body: {'name': name, 'email': email, 'password': _password},
  );
  final session = await Authentication(anonymous, i18n).withPassword(_server, email, _password);
  final api = KaneoApi(
    ApiClient(session: () => session, i18n: i18n, onSessionExpired: (_) {}),
    i18n,
  );
  return _Person(name, email, session, api);
}

/// Drives the app, and records what happens.
class _Run {
  _Run(this.t);

  final WidgetTester t;
  final capture = GlobalKey();
  ProviderContainer? _container;
  late Directory evidence;
  late _Person me;
  late _Person other;
  late Workspace workspace;
  final clipboard = <String>[];
  final orientationRequests = <List<String>>[];

  final results = <Map<String, Object?>>[];
  var _notes = <String>[];
  var _shots = <String>[];

  ProviderContainer get container => _container!;
  String tr(String key, [Map<String, Object?> values = const {}]) =>
      container.read(i18nProvider).t(key, values);

  Size get window => t.view.physicalSize / t.view.devicePixelRatio;
  bool get wide => window.shortestSide >= 600;
  bool get phone => Platform.isIOS && !wide;
  ui.PointerDeviceKind get kind =>
      Platform.isMacOS ? ui.PointerDeviceKind.mouse : ui.PointerDeviceKind.touch;

  void note(String text) {
    _notes.add(text);
    debugPrint('C_NOTE $text');
  }

  /// Runs one criterion. A failure is written down, and the walk goes on.
  Future<void> check(String id, String what, Future<void> Function() body) async {
    debugPrint('C_CHECK $id $what');
    _notes = [];
    _shots = [];
    final clock = Stopwatch()..start();
    Object? failure;
    try {
      await body();
      failure = t.takeException();
    } catch (error, stack) {
      failure = '$error\n${stack.toString().split('\n').take(12).join('\n')}';
      t.takeException();
      try {
        await shot('$id-FAILURE');
      } catch (_) {}
    }
    results.add({
      'id': id,
      'what': what,
      'result': failure == null ? 'PASS' : 'FAIL',
      'seconds': clock.elapsed.inSeconds,
      'notes': _notes,
      'screenshots': _shots,
      'failure': ?failure?.toString(),
    });
    debugPrint('C_RESULT $id ${failure == null ? 'PASS' : 'FAIL'} $what');
    if (failure != null) debugPrint('C_FAILURE $id $failure');
    await writeResults();
  }

  Future<void> writeResults() => File('${evidence.path}/results.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'device': _device,
      'window': '${window.width.round()}x${window.height.round()}',
      'layout': wide ? 'wide' : 'narrow',
      'results': results,
    }),
  );

  /// Pumps until nothing is moving, for a limited time. A text box with the focus never stops
  /// blinking on Apple platforms, so waiting for it to settle would never end.
  Future<void> settle({Duration max = const Duration(milliseconds: 1500)}) async {
    final end = DateTime.now().add(max);
    var quiet = 0;
    do {
      await t.pump(const Duration(milliseconds: 50));
      quiet = t.binding.hasScheduledFrame ? 0 : quiet + 1;
    } while (quiet < 3 && DateTime.now().isBefore(end));
  }

  /// Pumps until [ready], which may ask the server.
  Future<bool> until(FutureOr<bool> Function() ready, {int seconds = 15}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      if (await ready()) return true;
      await t.pump(const Duration(milliseconds: 100));
    }
    return ready();
  }

  Future<void> see(Finder finder, {int seconds = 15}) async {
    final found = await until(() => finder.evaluate().isNotEmpty, seconds: seconds);
    expect(found, isTrue, reason: 'Not on screen: $finder');
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> gone(Finder finder, {int seconds = 10}) async {
    final left = await until(() => finder.evaluate().isEmpty, seconds: seconds);
    expect(left, isTrue, reason: 'Still on screen: $finder');
  }

  Future<void> reveal(Finder finder) async {
    await see(finder);
    if (finder.hitTestable().evaluate().isEmpty) {
      await t.ensureVisible(finder);
      await settle();
    }
  }

  Future<void> tap(Finder finder) async {
    await reveal(finder);
    await t.tap(finder, kind: kind);
    await settle();
  }

  Future<void> type(Finder field, String text) async {
    await see(field);
    await t.enterText(field, text);
    await t.pump();
  }

  String textIn(Finder field) => t.widget<TextField>(field).controller!.text;

  /// Phones turn sideways for the board, and the app lets go of the direction everywhere else. A
  /// person holding the phone upright then sees it upright. Nobody holds a simulator, which stays
  /// sideways, so once the app has let go this turns it the way the person would have.
  Future<void> upright(bool landscape) async {
    if (!phone) return;
    bool turned() => (t.view.physicalSize.width > t.view.physicalSize.height) == landscape;
    if (landscape) {
      await until(turned, seconds: 6);
    } else {
      final released = await until(
        () => orientationRequests.isEmpty || orientationRequests.last.isEmpty,
        seconds: 5,
      );
      expect(released, isTrue, reason: 'Only the board may hold on to the direction');
      if (!turned()) {
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        await until(turned, seconds: 6);
        await SystemChrome.setPreferredOrientations([]);
      }
    }
    expect(turned(), isTrue, reason: 'The phone should be ${landscape ? 'sideways' : 'upright'}');
    await settle();
  }

  /// Starts the app afresh at [location], so that nothing carries over from an earlier criterion.
  Future<void> open(String location, {_Person? as}) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 100));
    _container?.dispose();
    final container = await bootstrap(sessionStorage: MemorySessionStorage((as ?? me).session));
    _container = container;
    await t.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: UncontrolledProviderScope(container: container, child: const KaneoApp()),
      ),
    );
    await t.pump();
    container.read(routerProvider).go(location);
    await settle();
  }

  Future<void> board(String projectId, {_Person? as}) async {
    await open(AppRoutes.board(projectId), as: as);
    await see(_key('board-horizontal'));
    await upright(true);
  }

  /// Scrolls whichever column holds [id] until it has its card, which lists build as needed.
  Future<void> revealCard(String id) async {
    await see(find.byKey(shellPageKey));
    final card = _card(id);
    if (card.evaluate().isEmpty) {
      final lanes = find.byWidgetPredicate(
        (w) =>
            w is ListView &&
            w.key is PageStorageKey<String> &&
            (w.key! as PageStorageKey<String>).value.startsWith('column-tasks-'),
      );
      for (final element in lanes.evaluate().toList()) {
        final controller = (element.widget as ListView).controller!;
        controller.jumpTo(0);
        await t.pump();
        while (card.evaluate().isEmpty && controller.offset < controller.position.maxScrollExtent) {
          controller.jumpTo(controller.offset + 200);
          await t.pump(const Duration(milliseconds: 50));
        }
        if (card.evaluate().isNotEmpty) break;
      }
    }
    await reveal(card);
  }

  /// Opens [id] from its board, by pressing its card.
  Future<void> openCard(String id) async {
    await revealCard(id);
    await tap(_card(id));
    await see(_taskOpen(id));
    await see(_in(_taskOpen(id), _key('task-title')));
    await upright(false);
    await settle();
  }

  /// Back to whatever the task on top was opened from.
  Future<void> closeTask() async {
    await tap(find.byTooltip(wide ? 'Close' : 'Back').last);
  }

  /// Everything the Markdown renderer put on screen inside [scope].
  Iterable<TextSpan> spans(Finder scope) sync* {
    for (final element in _in(scope, find.byType(SelectableText)).evaluate()) {
      final found = <TextSpan>[];
      (element.widget as SelectableText).textSpan!.visitChildren((span) {
        if (span is TextSpan) found.add(span);
        return true;
      });
      yield* found;
    }
  }

  String plain(Finder scope) => _in(
    scope,
    find.byType(SelectableText),
  ).evaluate().map((e) => (e.widget as SelectableText).textSpan!.toPlainText()).join('\n');

  TextSpan span(Finder scope, String text) =>
      spans(scope).firstWhere((span) => span.text?.contains(text) ?? false);

  Future<void> shot(String name) async {
    await settle();
    final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: phone ? 2 : 1.25);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${evidence.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    _shots.add(file.path.split('/').last);
    debugPrint('C_EVIDENCE ${file.path}');
  }

  Future<void> setRole(_Person person, String role) async {
    final full = await me.api.fullWorkspace(workspace.id);
    final membership = full.members!.firstWhere((m) => m.userId == person.id);
    await me.api.updateMemberRole(workspace.id, membership.id, role);
  }

  Future<Project> project(String name, String slug) => me.api.createProject(
    name: 'C-$name-$_device-${slug.toLowerCase()}',
    workspaceId: workspace.id,
    icon: 'Layout',
    slug: slug,
  );

  Future<Task> task(
    Project project,
    String title, {
    String description = '',
    String? status,
  }) async {
    final columns = await me.api.columns(project.id);
    return me.api.createTask(
      project.id,
      CreateTaskBody(
        title: title,
        description: description,
        priority: priorities.first,
        status: status ?? columns.first.slug,
      ),
    );
  }

  Future<String> storedDescription(String taskId) async =>
      loadDescription(me.api, await me.api.task(taskId));
}

/// A small picture for the renderer to fetch over real HTTP.
Future<Uint8List> _picture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 320, 180), Paint()..color = const Color(0xFF3B82F6));
  canvas.drawCircle(const Offset(160, 90), 60, Paint()..color = const Color(0xFFFACC15));
  final image = await recorder.endRecording().toImage(320, 180);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<Directory> _evidenceDirectory() async {
  if (Platform.isIOS && _evidenceOverride.isNotEmpty) {
    try {
      final directory = Directory(_evidenceOverride)..createSync(recursive: true);
      File('${directory.path}/.writable').writeAsStringSync('');
      return directory;
    } on FileSystemException catch (error) {
      debugPrint('C_NOTE Evidence stays in the app: $error');
    }
  }
  final documents = await getApplicationDocumentsDirectory();
  return Directory('${documents.path}/C-KAN-50/$_device')..createSync(recursive: true);
}

/// Things a Markdown editor or a server tends to rewrite. See description_roundtrip_test.dart.
const _untouched =
    '# 标题  \r\n'
    '\r\n'
    'Two spaces then a break  \n'
    '* star\n'
    '- dash\n'
    '+ plus\n'
    '\n'
    '1) paren\n'
    '\n'
    '- [x] done\n'
    '- [ ] todo\n'
    '\n'
    '<kaneo-mention id="u1" label="Ana"></kaneo-mention> and '
    '<kaneo-attachment url="https://files.test/a.pdf" filename="a.pdf" '
    'mime-type="application/pdf" size="2048" />\n'
    '<kaneo-issue-link url="https://k.test/task/t1" issue-key="KAN-1" task-id="t1" />\n'
    '<kaneo-embed url="https://www.youtube.com/watch?v=abc123" mode="embed" />\n'
    '\n'
    '| a | b |\n'
    '|---|:-:|\n'
    '| 1 | 2 |\n'
    '\n'
    '```dart\n'
    '\tfinal x = "y";  \n'
    '```\n'
    '\n'
    '<h2>Old HTML</h2><p>Text <strong>bold</strong></p>\n'
    '\n'
    '__bold__ *em* \\*escaped\\* &amp; non breaking 🙂 é "quotes" -- dashes\n'
    '\n'
    '\n'
    'The end\n'
    '\n';

Future<void> _markdownCriteria(_Run r, String imageUrl) async {
  final docs = await r.project('Docs', 'CD${_stamp.toUpperCase()}');
  final rendered = await r.task(
    docs,
    'C Markdown',
    description:
        '# 一级标题\n\n'
        '## 二级标题\n\n'
        '### 三级标题\n\n'
        '正文 **粗体文字** *斜体文字* ~~删除文字~~ `行内代码` [链接文字](https://example.com/page)\n\n'
        '- 列表一\n'
        '  - 嵌套列表\n'
        '- 列表二\n\n'
        '1. 有序一\n'
        '2. 有序二\n\n'
        '- [x] 已完成待办\n'
        '- [ ] 未完成待办\n\n'
        '> 引用文字\n\n'
        '```dart\n'
        'final code = "代码块";\n'
        '```\n\n'
        '---\n\n'
        '| 列一 | 列二 |\n'
        '|---|---|\n'
        '| 单元格一 | 单元格二 |\n\n'
        '![网络图片]($imageUrl)\n',
  );
  final tagged = await r.task(
    docs,
    'C Tags',
    description:
        '提及 <kaneo-mention id="u1" label="Ana"></kaneo-mention> 在这里\n\n'
        '<kaneo-attachment url="https://files.test/a.pdf" filename="a.pdf" '
        'mime-type="application/pdf" size="2048" />\n\n'
        '<kaneo-issue-link url="https://k.test/task/t1" issue-key="KAN-1" task-id="t1" />\n\n'
        '<kaneo-embed url="https://www.youtube.com/watch?v=abc123" mode="embed" />\n\n'
        '<img src="$imageUrl" alt="带宽度的图片" width="120" />\n',
  );
  final edited = await r.task(docs, 'C Edit', description: _untouched);
  final legacy = await r.task(
    docs,
    'C Legacy',
    description: '<h2>旧标题</h2><p>旧段落 <strong>旧粗体</strong> <em>旧斜体</em></p><ul><li>旧列表</li></ul>',
  );
  final saving = await r.task(docs, 'C Autosave');
  final rejected = await r.task(docs, 'C Rejected save', description: '原来的文字');

  await r.check('KAN-7.1', '能渲染各种 Markdown', () async {
    await r.board(docs.id);
    await r.openCard(rendered.id);
    await r.see(_in(_description, find.byType(MarkdownView)));
    final text = r.plain(_description);
    for (final piece in [
      '一级标题',
      '二级标题',
      '三级标题',
      '粗体文字',
      '斜体文字',
      '删除文字',
      '行内代码',
      '链接文字',
      '列表一',
      '嵌套列表',
      '有序一',
      '已完成待办',
      '未完成待办',
      '引用文字',
      'final code = "代码块";',
      '单元格一',
    ]) {
      expect(text, contains(piece));
    }
    for (final raw in ['#', '**', '~~', '```', '---', '|', '[x]', '[ ]', '](', '> ']) {
      expect(text, isNot(contains(raw)), reason: 'Source showing: $raw');
    }
    final body = r.span(_description, '正文').style!;
    expect(r.span(_description, '一级标题').style!.fontSize, greaterThan(body.fontSize!));
    expect(r.span(_description, '粗体文字').style!.fontWeight, FontWeight.w600);
    expect(r.span(_description, '斜体文字').style!.fontStyle, FontStyle.italic);
    expect(r.span(_description, '删除文字').style!.decoration, TextDecoration.lineThrough);
    expect(r.span(_description, '行内代码').style!.fontFamily, KaneoFonts.mono);
    expect(r.span(_description, '链接文字').recognizer, isNotNull);
    expect(r.span(_description, 'final code').style!.fontFamily, KaneoFonts.mono);
    expect(_in(_description, find.text('•')), findsWidgets);
    expect(_in(_description, find.text('◦')), findsOneWidget);
    expect(_in(_description, find.text('1.')), findsOneWidget);
    expect(_in(_description, find.byIcon(LucideIcons.squareCheck)), findsOneWidget);
    expect(_in(_description, find.byIcon(LucideIcons.square)), findsOneWidget);
    expect(_in(_description, find.byType(Table)), findsOneWidget);
    await r.shot('KAN-7.1-markdown-top');
    final image = _in(_description, find.byType(RawImage));
    await r.see(image);
    final loaded = await r.until(() => r.t.widget<RawImage>(image).image != null);
    expect(loaded, isTrue, reason: 'The image never loaded');
    await r.t.ensureVisible(image);
    await r.settle();
    expect(r.t.getSize(image).width, greaterThan(100));
    await r.shot('KAN-7.1-markdown-bottom');
  });

  await r.check('KAN-7.2', 'Kaneo 标签显示为提及、链接或图片', () async {
    await r.board(docs.id);
    await r.openCard(tagged.id);
    await r.see(_in(_description, find.byType(MarkdownView)));
    final text = r.plain(_description);
    expect(text, isNot(contains('<')));
    expect(text, isNot(contains('kaneo-')));
    final mention = r.span(_description, '@Ana');
    expect(mention.recognizer, isNull);
    expect(mention.style!.backgroundColor, isNotNull);
    expect(r.span(_description, 'a.pdf').recognizer, isNotNull);
    expect(r.span(_description, 'KAN-1').recognizer, isNotNull);
    expect(r.span(_description, 'youtube.com').recognizer, isNotNull);
    final image = _in(_description, find.byType(RawImage));
    await r.see(image);
    final loaded = await r.until(() => r.t.widget<RawImage>(image).image != null);
    expect(loaded, isTrue, reason: 'The image never loaded');
    await r.settle();
    expect(r.t.getSize(image).width, 120);
    await r.shot('KAN-7.2-tags');
  });

  await r.check('KAN-7.3', '编辑后除改动部分外没有变化', () async {
    await r.board(docs.id);
    await r.openCard(edited.id);
    await r.tap(_in(_description, find.byType(SelectableText)).first);
    await r.see(_descriptionField);
    expect(r.textIn(_descriptionField), _untouched, reason: 'The text box changed the source');
    // Looked at, not changed.
    await r.t.pump(const Duration(milliseconds: 1400));
    expect(await r.storedDescription(edited.id), _untouched);
    await r.shot('KAN-7.3-source-in-text-box');

    final changed = _untouched.replaceFirst('- dash', '- dashes');
    await r.type(_descriptionField, changed);
    expect(await r.until(() async => await r.storedDescription(edited.id) == changed), isTrue);
    expect(await r.storedDescription(edited.id), changed, reason: 'What the web app reads');
    final full = await loadFullBoard(r.me.api, docs.id);
    final card = full.columns
        .expand((c) => c.tasks ?? const <BoardTask>[])
        .firstWhere((task) => task.id == edited.id);
    expect(card.description, changed, reason: 'What the web app reads for its board');
    r.note(
      'Compared byte for byte through the API the web app reads. The web page was not opened.',
    );
    await r.shot('KAN-7.3-saved');
  });

  await r.check('KAN-7.4', '旧 HTML 显示为格式化文本', () async {
    await r.board(docs.id);
    await r.openCard(legacy.id);
    await r.see(_in(_description, find.byType(MarkdownView)));
    final text = r.plain(_description);
    expect(text, isNot(contains('<')));
    for (final piece in ['旧标题', '旧段落', '旧粗体', '旧斜体', '旧列表']) {
      expect(text, contains(piece));
    }
    final body = r.span(_description, '旧段落').style!;
    expect(r.span(_description, '旧标题').style!.fontSize, greaterThan(body.fontSize!));
    expect(r.span(_description, '旧粗体').style!.fontWeight, FontWeight.w600);
    expect(r.span(_description, '旧斜体').style!.fontStyle, FontStyle.italic);
    expect(_in(_description, find.text('•')), findsOneWidget);
    await r.shot('KAN-7.4-legacy-html');
  });

  await r.check('KAN-7.5a', '停止输入约 1 秒后保存', () async {
    await r.board(docs.id);
    await r.openCard(saving.id);
    await r.tap(_in(_description, find.text(r.tr('mobile:taskDetail.screen.addDescription'))));
    await r.see(_descriptionField);

    // Typing that keeps going puts the save off.
    for (final text in ['打', '打字', '打字中', '打字中间', '打字中间不存']) {
      await r.type(_descriptionField, text);
      await r.t.pump(const Duration(milliseconds: 300));
    }
    expect(await r.storedDescription(saving.id), '', reason: 'Saved while still typing');

    const text = '停止输入后保存';
    await r.type(_descriptionField, text);
    final clock = Stopwatch()..start();
    expect(await r.until(() async => await r.storedDescription(saving.id) == text), isTrue);
    clock.stop();
    r.note('On the server ${clock.elapsedMilliseconds} ms after typing stopped');
    expect(clock.elapsedMilliseconds, inInclusiveRange(800, 3000));
    await r.see(find.text(r.tr('app:description.saved')));
    await r.shot('KAN-7.5a-saved-after-a-second');
  });

  await r.check('KAN-7.5b', '离开输入框后保存', () async {
    await r.board(docs.id);
    await r.openCard(saving.id);
    await r.tap(_in(_description, find.byType(SelectableText)).first);
    await r.see(_descriptionField);
    const text = '离开输入框就保存';
    await r.type(_descriptionField, text);
    final clock = Stopwatch()..start();
    await r.t.tap(_in(_taskOpen(saving.id), _key('task-title')), kind: r.kind);
    await r.t.pump();
    expect(await r.until(() async => await r.storedDescription(saving.id) == text), isTrue);
    clock.stop();
    r.note('On the server ${clock.elapsedMilliseconds} ms after leaving the box');
    expect(clock.elapsedMilliseconds, lessThan(800));
    await r.gone(_descriptionField);
    expect(r.plain(_description), contains(text));
    await r.shot('KAN-7.5b-saved-on-leaving');

    // Closing the task right away saves as well.
    await r.tap(_in(_description, find.byType(SelectableText)).first);
    await r.see(_descriptionField);
    const closing = '关闭任务也保存';
    await r.type(_descriptionField, closing);
    await r.closeTask();
    expect(await r.until(() async => await r.storedDescription(saving.id) == closing), isTrue);
  });

  await r.check('KAN-7.5c', '保存失败时保留文字并提示', () async {
    try {
      await r.board(docs.id, as: r.other);
      await r.openCard(rejected.id);
      await r.tap(_in(_description, find.byType(SelectableText)).first);
      await r.see(_descriptionField);
      // The server really refuses: the person lost the right to edit while the box was open.
      await r.setRole(r.other, 'viewer');
      const kept = '保存失败时要保留的文字';
      await r.type(_descriptionField, kept);
      await r.see(find.text(r.tr('app:description.notSaved')));
      expect(r.textIn(_descriptionField), kept);
      expect(await r.storedDescription(rejected.id), '原来的文字');
      final toast = r.tr('app:description.saveFailed', {'reason': ''}).trim();
      await r.see(find.textContaining(toast));
      await r.shot('KAN-7.5c-save-failed');

      await r.setRole(r.other, 'member');
      await r.tap(find.text(r.tr('mobile:common.retry')));
      expect(await r.until(() async => await r.storedDescription(rejected.id) == kept), isTrue);
      // Pressing the button left the box, so once it is saved the box gives way to the formatted text.
      await r.gone(_descriptionField);
      expect(r.plain(_description), contains(kept));
      await r.shot('KAN-7.5c-retry-saved');
    } finally {
      await r.setRole(r.other, 'member');
    }
  });
}

Future<void> _taskCriteria(_Run r) async {
  final scroll = await r.project('Scroll', 'CS${_stamp.toUpperCase()}');
  final main = await r.project('Tasks', 'CT${_stamp.toUpperCase()}');
  final destination = await r.project('Move', 'CM${_stamp.toUpperCase()}');
  final scrollColumns = await r.me.api.columns(scroll.id);
  final columns = await r.me.api.columns(main.id);
  final fillers = [
    for (var i = 0; i < 30; i++) await r.task(scroll, 'C Filler ${i.toString().padLeft(2, '0')}'),
  ];
  final linked = await r.task(main, 'C Link');
  final noticed = await r.task(main, 'C Notice');
  final edited = await r.task(main, 'C Properties');
  final parent = await r.task(main, 'C Subtask parent');
  final family = await r.task(main, 'C Family');
  final child = await r.task(main, 'C Family child');
  final blocked = await r.task(main, 'C Family blocked');
  final related = await r.task(main, 'C Family related');
  await r.me.api.createRelation(family.id, child.id, 'subtask');
  await r.me.api.createRelation(family.id, blocked.id, 'blocks');
  await r.me.api.createRelation(family.id, related.id, 'related');
  final discussed = await r.task(main, 'C Comments');
  final owned = await r.task(main, 'C Comment owners');
  final deleted = await r.task(main, 'C Delete me', description: '要删除的任务');
  final copied = await r.task(main, 'C Duplicate me', description: '要复制的任务');
  final moved = await r.task(main, 'C Move me');
  await r.setRole(r.other, 'member');

  await r.check('KAN-8.1', '宽屏从右侧滑出详情，看板可见，关闭后回到原滚动位置', () async {
    await r.board(scroll.id);
    final lane = find.byKey(PageStorageKey('column-tasks-${scrollColumns.first.slug}'));
    await r.see(lane);
    final vertical = r.t.widget<ListView>(lane).controller!;
    vertical.jumpTo(600);
    await r.settle();
    final horizontal = r.t.widget<SingleChildScrollView>(_key('board-horizontal')).controller!;
    final across = horizontal.position.maxScrollExtent;
    if (across > 0) horizontal.jumpTo(across < 120 ? across : 120);
    await r.settle();
    final down = vertical.offset;
    final along = horizontal.offset;
    expect(down, greaterThan(0));
    r.note('Scrolled the column to $down and the board to $along');
    final shown = fillers.firstWhere((f) => _card(f.id).hitTestable().evaluate().isNotEmpty);
    await r.t.tap(_card(shown.id).first, kind: r.kind);
    if (r.wide) {
      await r.t.pump(const Duration(milliseconds: 90));
      final moving = r.t.getRect(_panel);
      await r.settle();
      final panel = r.t.getRect(_panel);
      r.note('The panel went from x=${moving.left.round()} to x=${panel.left.round()}');
      expect(moving.left, greaterThan(panel.left), reason: 'It should slide in from the right');
      // The page is inset in the window, as the web app's is, and the panel keeps to the page.
      expect(panel.right, closeTo(r.t.getRect(find.byKey(shellPageKey)).right, 1));
      expect(panel.left, greaterThan(90));
      // The board is still there beside the panel.
      expect(r.t.getRect(lane).left, lessThan(panel.left));
      await r.see(_in(_panel, _key('task-title')));
      await r.shot('KAN-8.1-panel-over-board');
      await r.closeTask();
      await r.gone(_panel);
      expect(vertical.offset, down);
      expect(horizontal.offset, along);
      await r.shot('KAN-8.1-board-after-closing');
      // Pressing the part of the page that shows closes it too.
      await r.t.tap(_card(shown.id).first, kind: r.kind);
      await r.settle();
      await r.see(_panel);
      final page = r.t.getRect(find.byKey(shellPageKey));
      await r.t.tapAt(Offset((page.left + panel.left) / 2, page.center.dy), kind: r.kind);
      await r.settle();
      await r.gone(_panel);
      expect(vertical.offset, down);
      expect(horizontal.offset, along);
    } else {
      await r.settle();
      await r.see(_taskOpen(shown.id));
      expect(_panel, findsNothing);
      await r.upright(false);
      await r.see(_key('task-title'));
      expect(r.t.getSize(_taskOpen(shown.id)).width, closeTo(r.window.width, 1));
      await r.shot('KAN-8.1-narrow-full-page');
      await r.closeTask();
      await r.upright(true);
      await r.see(lane);
      final after = r.t.widget<ListView>(lane).controller!;
      expect(after.offset, down);
      r.note('A phone has no panel: it opens a full page, and comes back to the same place');
    }
  });

  await r.check('KAN-8.2', '通过链接或通知打开时显示完整页面', () async {
    await r.open(AppRoutes.task(linked.id));
    await r.see(_taskOpen(linked.id));
    await r.see(_key('task-title'));
    await r.upright(false);
    expect(_panel, findsNothing, reason: 'A link opens a page, not a panel');
    await r.shot('KAN-8.2-link-full-page');

    await r.other.api.createComment(noticed.id, '请看 ${mentionTag(r.me.id, r.me.name)}');
    final notifications = await r.me.api.notifications(workspaceId: r.workspace.id);
    final notice = notifications.firstWhere(
      (n) => n.type == 'task_mention' && n.resourceId == noticed.id,
    );
    await r.open(AppRoutes.inbox);
    await r.upright(false);
    await r.tap(find.byKey(ValueKey(notice.id)));
    await r.see(_taskOpen(noticed.id));
    await r.see(_key('task-title'));
    expect(_panel, findsNothing, reason: 'A notification opens a page, not a panel');
    await r.shot('KAN-8.2-notification-full-page');
    final read = await r.until(() async {
      final again = await r.me.api.notifications(workspaceId: r.workspace.id);
      return isUnread(again.firstWhere((n) => n.id == notice.id)) == false;
    });
    expect(read, isTrue, reason: 'Opening it should mark it read');
    await r.tap(find.byTooltip('Back').last);
    await r.see(find.byKey(ValueKey(notice.id)));
    r.note('The system notification banner itself is left for the administrator');
  });

  await r.check('KAN-8.3', '属性在就近浮层或底部弹层修改，看板和列表同步', () async {
    await r.board(main.id);
    await r.openCard(edited.id);

    Future<void> picker(Finder anchor, String name) async {
      await r.tap(anchor);
      if (r.wide) {
        final surface = find.byType(PopoverSurface).last;
        await r.see(surface);
        expect(find.byType(BottomSheet), findsNothing);
        final near = r.t.getRect(anchor);
        final rect = r.t.getRect(surface);
        final below = rect.top >= near.bottom ? rect.top - near.bottom : 0.0;
        final above = near.top >= rect.bottom ? near.top - rect.bottom : 0.0;
        final beside = rect.left >= near.right ? rect.left - near.right : 0.0;
        final before = near.left >= rect.right ? near.left - rect.right : 0.0;
        r.note(
          '$name: picker ${rect.width.round()}x${rect.height.round()}, gap to its row '
          '${(below + above + beside + before).toStringAsFixed(1)}',
        );
        expect(below + above + beside + before, lessThanOrEqualTo(12), reason: '$name not nearby');
      } else {
        await r.see(find.byType(BottomSheet));
        expect(find.byType(PopoverSurface), findsNothing);
      }
      await r.shot('KAN-8.3-picker-$name');
    }

    final status = _key('task-status');
    await picker(status, 'status');
    await r.tap(find.text(columns[1].name).last);
    expect(
      await r.until(() async => (await r.me.api.task(edited.id)).status == columns[1].slug),
      isTrue,
    );
    await r.see(_in(status, find.text(columns[1].name)));

    final priority = _key('task-priority');
    await picker(priority, 'priority');
    await r.tap(find.text('High').last);
    expect(await r.until(() async => (await r.me.api.task(edited.id)).priority == 'high'), isTrue);
    await r.see(_in(priority, find.text('High')));

    final assignee = _key('task-assignee');
    await picker(assignee, 'assignee');
    await r.tap(find.text(r.other.name).last);
    expect(
      await r.until(() async => (await r.me.api.task(edited.id)).userId == r.other.id),
      isTrue,
    );
    await r.see(_in(assignee, find.text(r.other.name)));

    final labels = _key('task-labels');
    final label = 'C-label-$_stamp';
    await picker(labels, 'labels');
    await r.type(_in(find.byType(PopoverBody).last, find.byType(TextField)), label);
    await r.settle();
    await r.tap(find.text(r.tr('mobile:taskFields.createLabel', {'name': label})).last);
    await r.tap(find.text(r.tr('mobile:common.save')).last);
    expect(
      await r.until(() async => (await r.me.api.taskLabels(edited.id)).any((l) => l.name == label)),
      isTrue,
    );
    await r.see(_in(labels, find.text(label)));

    final start = _key('task-start-date');
    await picker(start, 'start-date');
    await r.tap(_in(find.byType(KaneoCalendar).last, find.text('15')));
    expect(
      await r.until(() async => parseDay((await r.me.api.task(edited.id)).startDate)?.day == 15),
      isTrue,
    );
    final due = _key('task-due-date');
    await picker(due, 'due-date');
    await r.tap(_in(find.byType(KaneoCalendar).last, find.text('20')));
    expect(
      await r.until(() async => parseDay((await r.me.api.task(edited.id)).dueDate)?.day == 20),
      isTrue,
    );
    await r.settle();
    await r.shot('KAN-8.3-all-properties-changed');

    await r.closeTask();
    await r.upright(true);
    final inProgress = _inColumn(columns[1].slug, _card(edited.id));
    await r.see(inProgress);
    await r.reveal(inProgress);
    expect(_in(inProgress, find.text(label)), findsOneWidget, reason: 'The card shows the label');
    await r.shot('KAN-8.3-board-in-sync');

    await r.tap(find.byTooltip(r.tr('mobile:board.listView')));
    await r.upright(false);
    final list = _in(
      find.byKey(PageStorageKey('board-list-${main.id}')),
      find.byType(Scrollable),
    ).first;
    await r.see(list);
    final position = r.t.state<ScrollableState>(list).position;
    final row = _row(edited.id);
    while (row.evaluate().isEmpty && position.pixels < position.maxScrollExtent) {
      position.jumpTo(position.pixels + 200);
      await r.t.pump(const Duration(milliseconds: 50));
    }
    await r.see(row);
    await r.reveal(row);
    // Its new status is the group it is under.
    final group = _key('list-group-${columns[1].slug}');
    await r.see(group);
    expect(r.t.getTopLeft(row).dy, greaterThan(r.t.getTopLeft(group).dy));
    expect(_in(row, find.text(initials(r.other.name))), findsOneWidget);
    if (r.wide) {
      expect(_in(row, find.text(label)), findsOneWidget, reason: 'The list row shows the label');
    } else {
      r.note('A narrow list row has only the id, title and assignee, by design (KAN-6)');
    }
    await r.shot('KAN-8.3-list-in-sync');
    await r.tap(find.byTooltip(r.tr('mobile:board.boardView')));
  });

  await r.check('KAN-8.4', '查看子任务进度，新增并勾选完成', () async {
    await r.board(main.id);
    await r.openCard(parent.id);
    await r.tap(_key('task-add-subtask'));
    await r.type(_key('subtask-title'), 'C 新增的子任务');
    await r.tap(_key('subtask-create'));
    final relations = await r.until(() async {
      final found = await r.me.api.relations(parent.id);
      return found.any((relation) => relation.sourceTaskId == parent.id);
    });
    expect(relations, isTrue, reason: 'The subtask should be linked on the server');
    final link = (await r.me.api.relations(parent.id))
        .firstWhere((relation) => relation.sourceTaskId == parent.id);
    final subtaskId = link.targetTaskId;
    await r.see(_key('task-subtask-$subtaskId'));
    await r.see(_in(_key('task-subtask-progress'), find.text('0/1')));
    await r.shot('KAN-8.4-subtask-added');

    await r.tap(_key('task-subtask-check-$subtaskId'));
    await r.see(_in(_key('task-subtask-progress'), find.text('1/1')));
    final done = await r.until(() async {
      final subtask = await r.me.api.task(subtaskId);
      return subtask.status == columns.firstWhere((c) => c.isFinal == true).slug;
    });
    expect(done, isTrue, reason: 'The subtask should be in the final column');
    await r.shot('KAN-8.4-subtask-completed');
    await r.closeTask();
    await r.upright(true);
    final card = _card(parent.id);
    await r.revealCard(parent.id);
    expect(_in(card, find.text('1/1')), findsOneWidget, reason: 'The card shows the progress');
  });

  await r.check('KAN-8.5', '能跳到父任务、子任务和关联任务并返回', () async {
    await r.board(main.id);
    await r.openCard(family.id);

    Future<void> jump(Finder row, String to) async {
      await r.tap(row);
      await r.see(_taskOpen(to));
      await r.see(_in(_taskOpen(to), _key('task-title')));
    }

    Future<void> back(String to) async {
      await r.closeTask();
      final onTop = await r.until(
        () => r.t.widget<TaskView>(find.byType(TaskView).last).taskId == to,
      );
      expect(onTop, isTrue, reason: 'Closing should come back to $to');
    }

    await jump(_key('task-subtask-${child.id}'), child.id);
    await r.shot('KAN-8.5-subtask');
    await jump(_in(_taskOpen(child.id), _key('task-parent')), family.id);
    await r.shot('KAN-8.5-parent');
    await back(child.id);
    await back(family.id);
    await jump(_key('task-link-blocks-${blocked.id}'), blocked.id);
    await r.shot('KAN-8.5-blocked');
    await back(family.id);
    await jump(_key('task-link-related-${related.id}'), related.id);
    await r.shot('KAN-8.5-related');
    await back(family.id);
    expect(_taskOpen(related.id), findsNothing);
    await r.see(_in(_taskOpen(family.id), _key('task-title')));
    await r.shot('KAN-8.5-back-at-start');
  });

  await r.check('KAN-8.6', '评论支持 Markdown 和 @提及，被提及的人收到通知', () async {
    await r.board(main.id);
    await r.openCard(discussed.id);
    final box = _field('comment-box');
    await r.reveal(box);
    await r.type(box, '@Bo');
    await r.settle();
    await r.see(_key('mention-${r.other.id}'));
    await r.shot('KAN-8.6-mention-offered');
    await r.tap(_key('mention-${r.other.id}'));
    final typed = r.textIn(box);
    expect(typed, startsWith('@Bo Li'));
    await r.type(box, '$typed**粗体评论** `行内代码`');
    await r.tap(_key('comment-send'));
    final saved = await r.until(() async {
      final items = await r.me.api.activities(discussed.id);
      return items.any((a) => a.type == 'comment');
    });
    expect(saved, isTrue);
    final comment = (await r.me.api.activities(discussed.id))
        .firstWhere((a) => a.type == 'comment');
    expect(comment.content, contains('<kaneo-mention'));
    expect(comment.content, contains(r.other.id));
    final shown = _key('task-comment-${comment.id}');
    await r.see(shown);
    await r.see(_in(shown, find.byType(MarkdownView)));
    final text = r.plain(shown);
    expect(text, contains('@Bo Li'));
    expect(text, isNot(contains('<kaneo')));
    expect(text, isNot(contains('**')));
    expect(r.span(shown, '@Bo Li').style!.backgroundColor, isNotNull);
    expect(r.span(shown, '粗体评论').style!.fontWeight, FontWeight.w600);
    expect(r.span(shown, '行内代码').style!.fontFamily, KaneoFonts.mono);
    expect(r.textIn(box), isEmpty);
    await r.reveal(shown);
    await r.shot('KAN-8.6-comment-rendered');

    final told = await r.until(() async {
      final items = await r.other.api.notifications(workspaceId: r.workspace.id);
      return items.any((n) => n.type == 'task_mention' && n.resourceId == discussed.id);
    });
    expect(told, isTrue, reason: 'The person mentioned should be notified');
    final mine = await r.me.api.notifications(workspaceId: r.workspace.id);
    expect(mine.where((n) => n.type == 'task_mention' && n.resourceId == discussed.id), isEmpty);
    // The person mentioned sees it in their inbox.
    await r.open(AppRoutes.inbox, as: r.other);
    await r.upright(false);
    await r.see(find.textContaining(discussed.title, findRichText: true));
    await r.shot('KAN-8.6-notification-in-inbox-of-person-mentioned');
    r.note('The system notification banner itself is left for the administrator');
  });

  await r.check('KAN-8.7', '只能编辑和删除自己的评论，没有权限的操作不显示', () async {
    await r.me.api.createComment(owned.id, '我要改的评论');
    await r.me.api.createComment(owned.id, '我要删的评论');
    await r.other.api.createComment(owned.id, '别人的评论');
    final items = await r.me.api.activities(owned.id);
    String idOf(String text) => items.firstWhere((a) => a.content == text).id;
    final toEdit = idOf('我要改的评论');
    final toDelete = idOf('我要删的评论');
    final theirs = idOf('别人的评论');

    await r.board(main.id);
    await r.openCard(owned.id);
    await r.see(_key('task-comment-$theirs'));
    await r.reveal(_key('task-comment-$theirs'));
    expect(_key('comment-edit-$toEdit'), findsOneWidget);
    expect(_key('comment-delete-$toEdit'), findsOneWidget);
    expect(_key('comment-edit-$theirs'), findsNothing);
    expect(_key('comment-delete-$theirs'), findsNothing);
    await r.shot('KAN-8.7-own-and-someone-elses');

    await r.tap(_key('comment-edit-$toEdit'));
    await r.type(_field('comment-field-$toEdit'), '我改过的评论');
    await r.tap(_key('comment-save-$toEdit'));
    final changed = await r.until(() async {
      final again = await r.me.api.activities(owned.id);
      return again.firstWhere((a) => a.id == toEdit).content == '我改过的评论';
    });
    expect(changed, isTrue);
    await r.see(_in(_key('task-comment-$toEdit'), find.byType(MarkdownView)));

    await r.tap(_key('comment-delete-$toDelete'));
    await r.see(find.text(r.tr('mobile:taskDetail.activity.deleteTitle')));
    await r.shot('KAN-8.7-confirm-delete-comment');
    await r.tap(find.text(r.tr('mobile:common.delete')).last);
    await r.gone(_key('task-comment-$toDelete'));
    final remaining = await r.me.api.activities(owned.id);
    expect(remaining.where((a) => a.id == toDelete), isEmpty);

    // The other way round, for the other person.
    await r.board(main.id, as: r.other);
    await r.openCard(owned.id);
    await r.see(_key('task-comment-$theirs'));
    expect(_key('comment-edit-$theirs'), findsOneWidget);
    expect(_key('comment-delete-$theirs'), findsOneWidget);
    expect(_key('comment-edit-$toEdit'), findsNothing);
    expect(_key('comment-delete-$toEdit'), findsNothing);
    await r.shot('KAN-8.7-as-the-other-person');

    // Someone who can only read gets no way to change anything.
    try {
      await r.setRole(r.other, 'viewer');
      await r.board(main.id, as: r.other);
      await r.openCard(owned.id);
      await r.gone(_key('comment-box'));
      await r.gone(_key('task-add-subtask'));
      expect(_key('comment-edit-$theirs'), findsNothing);
      expect(_key('comment-delete-$theirs'), findsNothing);
      expect(r.t.widget<TextField>(_key('task-title')).readOnly, isTrue);
      await r.tap(_key('task-status'));
      expect(find.byType(PopoverSurface), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      await r.shot('KAN-8.7-read-only');
      await r.tap(_key('task-more'));
      await r.see(find.text(r.tr('mobile:taskDetail.menu.share')));
      expect(find.text(r.tr('mobile:taskDetail.menu.delete')), findsNothing);
      expect(find.text(r.tr('mobile:taskDetail.menu.move')), findsNothing);
      expect(find.text(r.tr('mobile:taskDetail.menu.duplicate')), findsNothing);
      await r.shot('KAN-8.7-read-only-menu');
    } finally {
      await r.setRole(r.other, 'member');
    }
  });

  await r.check('KAN-8.8', '删除任务前二次确认', () async {
    await r.board(main.id);
    await r.openCard(deleted.id);
    final delete = find.text(r.tr('mobile:taskDetail.menu.delete'));
    final title = find.text(r.tr('mobile:taskDetail.menu.deleteTitle'));
    await r.tap(_key('task-more'));
    await r.shot('KAN-8.8-menu');
    await r.tap(delete.last);
    await r.see(title);
    await r.shot('KAN-8.8-confirm');
    await r.tap(find.text(r.tr('mobile:common.cancel')).last);
    await r.gone(title);
    expect((await r.me.api.task(deleted.id)).id, deleted.id, reason: 'Cancel keeps the task');
    await r.see(_taskOpen(deleted.id));

    await r.tap(_key('task-more'));
    await r.tap(delete.last);
    await r.see(title);
    await r.tap(find.text(r.tr('mobile:common.delete')).last);
    await r.gone(_taskOpen(deleted.id));
    await r.upright(true);
    await r.see(_key('board-horizontal'));
    await r.gone(_card(deleted.id));
    await expectLater(r.me.api.task(deleted.id), throwsA(isA<ApiError>()));
    await r.shot('KAN-8.8-back-on-board');
  });

  await r.check('KAN-8.extra', '范围内的其他操作：复制链接、复制任务、移动到其他项目', () async {
    await r.board(main.id);
    await r.openCard(copied.id);
    await r.tap(_key('task-copy-link'));
    expect(
      r.clipboard.last,
      '${_server.replaceAll(RegExp(r'/+$'), '')}/dashboard/workspace/${r.workspace.id}'
      '/project/${main.id}/task/${copied.id}',
    );
    await r.see(find.text(r.tr('mobile:taskDetail.screen.linkCopied')));
    r.note(
      'The link goes to the clipboard channel. The system clipboard and the share sheet are '
      'left for the administrator.',
    );

    await r.tap(_key('task-more'));
    await r.tap(find.text(r.tr('mobile:taskDetail.menu.duplicate')).last);
    Task? copy;
    final made = await r.until(() async {
      final full = await loadFullBoard(r.me.api, main.id);
      final tasks = full.columns.expand((c) => c.tasks ?? const <BoardTask>[]);
      final found = tasks.where((task) => task.id != copied.id && task.description == '要复制的任务');
      if (found.isEmpty) return false;
      copy = await r.me.api.task(found.first.id);
      return true;
    });
    expect(made, isTrue, reason: 'The copy should be on the server');
    await r.see(_taskOpen(copy!.id));
    await r.shot('KAN-8.extra-duplicated');

    await r.board(main.id);
    await r.openCard(moved.id);
    await r.tap(_key('task-more'));
    await r.tap(find.text(r.tr('mobile:taskDetail.menu.move')).last);
    await r.tap(find.text(destination.name).last);
    expect(
      await r.until(() async => (await r.me.api.task(moved.id)).projectId == destination.id),
      isTrue,
    );
    await r.see(find.text(r.tr('mobile:taskDetail.menu.moved')));
    await r.see(find.text(destination.name));
    await r.shot('KAN-8.extra-moved');
  });
}

Future<void> _newTaskCriteria(_Run r) async {
  final create = await r.project('Create', 'CN${_stamp.toUpperCase()}');
  final custom = await r.project('Custom', 'CF${_stamp.toUpperCase()}');
  final doomed = await r.project('Doomed', 'CX${_stamp.toUpperCase()}');
  final columns = await r.me.api.columns(create.id);
  final customColumns = await r.me.api.columns(custom.id);
  final doomedColumns = await r.me.api.columns(doomed.id);
  await r.me.api.createCustomField(
    projectId: custom.id,
    name: 'Team',
    type: 'dropdown',
    required_: true,
    defaultValue: 'Core',
    options: ['Core', 'Web'],
  );
  final title = _key('new-task-title');
  final descriptionBox = _field('new-task-description');
  final createButton = _key('new-task-create');
  final form = find.byType(NewTaskForm);

  Future<void> openForm(String slug) async {
    await r.tap(_key('add-task-column-$slug'));
    await r.see(form);
    await r.upright(false);
    await r.see(title);
  }

  await r.check('KAN-9.1', '宽屏弹窗，看板在背后可见；窄屏全屏', () async {
    await r.board(create.id);
    await openForm(columns.first.slug);
    if (r.wide) {
      final dialog = find.byType(Dialog);
      await r.see(dialog);
      final rect = r.t.getRect(_in(dialog, find.byType(NewTaskForm)));
      r.note('The dialog is ${rect.width.round()} wide in a ${r.window.width.round()} window');
      expect(rect.width, lessThanOrEqualTo(newTaskFormWidth));
      expect(rect.left, greaterThan(0));
      expect(rect.right, lessThan(r.window.width));
      expect(rect.center.dx, closeTo(r.window.width / 2, 1));
      expect(_key('board-horizontal'), findsOneWidget, reason: 'The board stays behind it');
      await r.shot('KAN-9.1-dialog-over-board');
    } else {
      expect(find.byType(Dialog), findsNothing);
      expect(r.t.getSize(form).width, closeTo(r.window.width, 1));
      await r.shot('KAN-9.1-narrow-full-page');
    }
    await r.tap(_key('new-task-cancel'));
    await r.gone(form);
  });

  await r.check('KAN-9.2', '从某列的添加任务进入时，状态默认为该列', () async {
    await r.board(create.id);
    final column = columns[2];
    await openForm(column.slug);
    await r.see(_in(_key('new-task-status'), find.text(column.name)));
    await r.shot('KAN-9.2-status-from-column');
    await r.type(title, 'C 从列头新建');
    await r.settle();
    await r.tap(createButton);
    await r.gone(form);
    final full = await loadFullBoard(r.me.api, create.id);
    final made = full.columns
        .expand((c) => c.tasks ?? const <BoardTask>[])
        .firstWhere((task) => task.title == 'C 从列头新建');
    expect(made.status, column.slug);

    // The button in an empty column does the same.
    await r.upright(true);
    final empty = columns[1];
    await r.tap(_key('add-task-empty-${empty.slug}'));
    await r.see(form);
    await r.upright(false);
    await r.see(_in(_key('new-task-status'), find.text(empty.name)));
    await r.tap(_key('new-task-cancel'));
    await r.gone(form);
  });

  await r.check('KAN-9.3', '没有标题不能提交，失败时已填内容不丢失', () async {
    await r.board(doomed.id);
    await openForm(doomedColumns.first.slug);
    FilledButton button() => r.t.widget<FilledButton>(createButton);
    expect(button().onPressed, isNull, reason: 'No title, no creating');
    await r.type(title, '   ');
    await r.settle();
    expect(button().onPressed, isNull, reason: 'Spaces are not a title');
    await r.shot('KAN-9.3-no-title');

    const typedTitle = 'C 提交失败要保留的标题';
    const typedDescription = '提交失败要保留的描述\n\n- 第二行';
    await r.type(title, typedTitle);
    await r.type(descriptionBox, typedDescription);
    await r.settle();
    expect(button().onPressed, isNotNull);
    // The server really refuses: the project has gone while the form was open.
    await r.me.api.deleteProject(doomed.id);
    await r.tap(createButton);
    await r.see(_key('new-task-error'));
    expect(r.textIn(title), typedTitle);
    expect(r.textIn(descriptionBox), typedDescription);
    expect(form, findsOneWidget, reason: 'The form stays open');
    r.note(
      'Refused with: ${r.t.widget<Text>(_in(_key('new-task-error'), find.byType(Text)).first).data}',
    );
    await r.shot('KAN-9.3-kept-after-failure');
  });

  await r.check('KAN-9.4', '创建成功后卡片立刻出现在对应列', () async {
    await r.board(create.id);
    final column = columns[3];
    await openForm(column.slug);
    await r.type(title, 'C 立刻出现');
    await r.settle();
    await r.reveal(createButton);
    final clock = Stopwatch()..start();
    await r.t.tap(createButton, kind: r.kind);
    final shown = _inColumn(column.slug, find.text('C 立刻出现'));
    await r.see(shown);
    clock.stop();
    r.note('On the board ${clock.elapsedMilliseconds} ms after pressing create, without a refresh');
    await r.gone(form);
    await r.upright(true);
    await r.settle();
    await r.reveal(shown);
    await r.shot('KAN-9.4-card-in-column');
    expect(clock.elapsedMilliseconds, lessThan(3000));
  });

  await r.check('KAN-9.5', '有必填自定义字段时也能创建', () async {
    await r.board(custom.id);
    await openForm(customColumns.first.slug);
    await r.type(title, 'C 必填字段');
    await r.settle();
    await r.tap(createButton);
    await r.gone(form);
    final full = await loadFullBoard(r.me.api, custom.id);
    final made = full.columns
        .expand((c) => c.tasks ?? const <BoardTask>[])
        .firstWhere((task) => task.title == 'C 必填字段');
    final values = await r.me.api.taskCustomFieldValues(made.id);
    expect(values.single.fieldName, 'Team');
    expect(values.single.value, 'Core');
    await r.upright(true);
    await r.see(_card(made.id));
    await r.shot('KAN-9.5-created-with-required-field');
  });

  await r.check('KAN-9.extra', '表单各字段都写到服务端', () async {
    await r.board(create.id);
    await openForm(columns.first.slug);
    await r.type(title, 'C 全部字段');
    await r.type(descriptionBox, '# 描述\n\n正文 **原样** 保存  \n');
    await r.tap(_key('new-task-priority'));
    await r.tap(find.text('Urgent').last);
    await r.tap(_key('new-task-assignee'));
    await r.tap(find.text(r.other.name).last);
    await r.tap(_key('new-task-start-date'));
    await r.tap(_in(find.byType(KaneoCalendar).last, find.text('15')));
    await r.tap(_key('new-task-due-date'));
    await r.tap(_in(find.byType(KaneoCalendar).last, find.text('20')));
    final label = 'C-new-label-$_stamp';
    await r.tap(_key('new-task-labels'));
    await r.type(_in(find.byType(PopoverBody).last, find.byType(TextField)), label);
    await r.settle();
    await r.tap(find.text(r.tr('mobile:taskFields.createLabel', {'name': label})).last);
    await r.tap(find.text(r.tr('mobile:common.save')).last);
    await r.see(_in(_key('new-task-labels'), find.text(label)));
    await r.shot('KAN-9.extra-all-fields');
    await r.tap(createButton);
    await r.gone(form);
    final full = await loadFullBoard(r.me.api, create.id);
    final made = full.columns
        .expand((c) => c.tasks ?? const <BoardTask>[])
        .firstWhere((task) => task.title == 'C 全部字段');
    final stored = await r.me.api.task(made.id);
    expect(stored.description, '# 描述\n\n正文 **原样** 保存  \n');
    expect(stored.priority, 'urgent');
    expect(stored.userId, r.other.id);
    expect(parseDay(stored.startDate)?.day, 15);
    expect(parseDay(stored.dueDate)?.day, 20);
    final labels = await r.me.api.taskLabels(made.id);
    expect(labels.map((l) => l.name), contains(label));
  });
}

final _stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('C task local acceptance on $_device', (tester) async {
    // Keep injected text from racing the native input method. Those are for a person to accept.
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    expect(['localhost', '127.0.0.1'], contains(Uri.parse(_server).host), reason: 'Local only.');
    if (Platform.isMacOS) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1366, 1024));
    }

    final run = _Run(tester);
    // The person's real clipboard stays out of this. What the app asks for is written down instead.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(SystemChannels.platform.name, (message) {
      final call = SystemChannels.platform.codec.decodeMethodCall(message);
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        run.orientationRequests.add(List<String>.from(call.arguments as List));
      }
      if (call.method == 'Clipboard.setData') {
        run.clipboard.add((call.arguments as Map)['text'] as String);
        return Future.value(SystemChannels.platform.codec.encodeSuccessEnvelope(null));
      }
      return messenger.delegate.send(SystemChannels.platform.name, message);
    });
    addTearDown(() => messenger.setMockMessageHandler(SystemChannels.platform.name, null));

    final images = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => images.close(force: true));
    final picture = await _picture();
    images.listen((request) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(picture);
      unawaited(request.response.close());
    });
    final imageUrl = 'http://127.0.0.1:${images.port}/picture.png';

    run.evidence = await _evidenceDirectory();
    debugPrint('C_EVIDENCE_DIR ${run.evidence.path}');
    final first = await bootstrap(sessionStorage: MemorySessionStorage());
    await first.read(languageChoiceProvider.notifier).select(defaultLocale);
    first.dispose();
    final i18n = await I18n.load();
    run.me = await _signUp(i18n, 'Mei Chen $_stamp', 'c-me-$_device-$_stamp@kaneo.local');
    run.other = await _signUp(i18n, 'Bo Li $_stamp', 'c-other-$_device-$_stamp@kaneo.local');
    run.workspace = await run.me.api.createWorkspace(
      name: 'C-accept-$_device-$_stamp',
      slug: 'c-accept-$_device-$_stamp',
    );
    final invitation = await run.me.api.client.request(
      'api/auth/organization/invite-member',
      method: 'POST',
      body: {'organizationId': run.workspace.id, 'email': run.other.email, 'role': 'member'},
    ) as Map<String, dynamic>;
    await run.other.api.acceptInvitation(invitation['id'] as String);
    debugPrint('C_CHECK setup workspace ${run.workspace.name} ${run.workspace.id}');

    await _markdownCriteria(run, imageUrl);
    await _taskCriteria(run);
    await _newTaskCriteria(run);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    run._container?.dispose();
    await run.writeResults();
    debugPrint('C_EVIDENCE ${run.evidence.path}/results.json');
    final failed = [
      for (final result in run.results)
        if (result['result'] != 'PASS') result['id'],
    ];
    expect(failed, isEmpty, reason: 'See ${run.evidence.path}/results.json');
  }, timeout: const Timeout(Duration(minutes: 18)));
}
