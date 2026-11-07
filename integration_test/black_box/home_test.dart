// KAN-52 首页和消息：H1 到 H5，I1 到 I10。
import 'bb.dart';

/// The unread count the navigation shows for the inbox, or 0 when it shows none.
int? _badge(Bb bb) {
  final inbox = bb.label(RegExp(r'Inbox, (\d+) unread')).evaluate();
  if (inbox.isEmpty) {
    return bb.showing(bb.label(RegExp(r'(^|\n)Inbox(\n|$)'))) ? 0 : null;
  }
  final node = bb.tester.getSemantics(find.byElementPredicate((e) => e == inbox.first));
  return int.parse(RegExp(r'Inbox, (\d+) unread').firstMatch(node.label)!.group(1)!);
}

Future<int> _unread(Api api) async =>
    (await api.notifications(Env.workspaceId)).where((n) => n['isRead'] != true).length;

/// A second workspace of the owner's, with a project, a task assigned to the owner and a notice.
class _Second {
  late String id;
  late String name;
  late Map<String, dynamic> project;
  late Map<String, dynamic> task;

  Future<void> make(Api owner) async {
    name = 'E-Q second $runStamp';
    final made = await owner.call('POST', 'api/auth/organization/create', {
      'name': name,
      'slug': 'e-q-second-$runStamp',
    });
    id = (made as Map)['id'] as String;
    addTearDown(() async {
      try {
        await owner.call('POST', 'api/auth/organization/delete', {'organizationId': id});
      } catch (_) {}
    });
    project = await owner.createProject('E-Q second project $runStamp', workspaceId: id);
    final columns = await owner.columns(project['id'] as String);
    task = await owner.createTask(
      project['id'] as String,
      'E-Q second task $runStamp',
      status: columns.first['slug'] as String,
      userId: Env.owner.id,
    );
    await owner.call('POST', 'api/notification', {
      'title': 'E-Q second notice $runStamp',
      'message': 'From the black-box tests',
      'type': 'info',
      'relatedEntityId': task['id'],
      'relatedEntityType': 'task',
    });
  }
}

/// Switches workspace the way a person does, from the workspace switcher.
Future<void> _switchTo(Bb bb, String name) async {
  await bb.nav('Home');
  await bb.tap(bb.label(RegExp('^Switch workspace')).hitTestable());
  await bb.tap(bb.containing(name).hitTestable().last);
  await bb.pumpFor(const Duration(seconds: 1));
}

void main() {
  blackBoxModule();

  bbCase('H1', '项目进度和 API 一致', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'H1');
    addTearDown(scratch.remove);
    await scratch.task('E-Q H1 a $runStamp');
    await scratch.task('E-Q H1 b $runStamp', column: 1);
    await scratch.task('E-Q H1 c $runStamp', column: 2);
    await scratch.task('E-Q H1 d $runStamp', column: 3);
    final projects = (await owner.get('api/project?workspaceId=${Env.workspaceId}') as List)
        .cast<Map>();
    await bb.start(Env.owner);
    await bb.pumpFor(const Duration(seconds: 2));
    final failures = <String>[];
    for (final name in ['E-Board', 'E-Formats', 'E-Empty', scratch.name]) {
      final p = projects.firstWhere((p) => p['name'] == name);
      final stats = (p['statistics'] as Map?) ?? const {};
      final percent = stats['completionPercentage'];
      final total = stats['totalTasks'];
      final card = bb.label(RegExp('^${RegExp.escape(name)}\\n'));
      if (!bb.showing(card)) {
        await bb.tester.scrollUntilVisible(card, 200, maxScrolls: 20);
      }
      final says = bb.tester.getSemantics(card.first).label.replaceAll('\n', ' | ');
      final ok =
          says.contains('$percent%') &&
          (says.contains('$total task') ||
              says.contains('of $total') ||
              (total == 0 && says.contains('No tasks')));
      bb.note('$name: server $percent% of $total; card "$says"');
      if (!ok) failures.add('$name: server $percent% of $total, card "$says"');
    }
    await bb.shot('home');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbUnverified('H2', '让 App 跨过零点后回到前台，日期和问候语更新', '模拟器不能把系统时间调过零点，测试进程也不能改设备时钟；需要真机跨零点验证');

  bbCase('H3', '切换工作区，项目、任务、收件箱都切换', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final second = _Second();
    await second.make(owner);
    await bb.start(Env.owner);
    await bb.see(bb.containing('E-Board'));
    await _switchTo(bb, second.name);
    await bb.see(bb.containing(second.project['name'] as String), seconds: 15);
    await bb.shot('home');
    expect(bb.showing(bb.label(RegExp(r'^E-Board\n'))), isFalse, reason: 'E-Board still on Home');
    await bb.nav('My tasks');
    await bb.see(bb.containing(second.task['title'] as String), seconds: 15);
    expect(bb.showing(bb.containing('E-三层')), isFalse);
    await bb.shot('my-tasks');
    await bb.nav('Inbox');
    await bb.see(bb.containing('E-Q second notice $runStamp'), seconds: 15);
    await bb.shot('inbox');
  });

  bbCase('H4', '重启 App 回到上次的工作区', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final second = _Second();
    await second.make(owner);
    await bb.start(Env.owner);
    await _switchTo(bb, second.name);
    await bb.see(bb.containing(second.project['name'] as String), seconds: 15);
    await bb.restart();
    await bb.waitHome();
    await bb.see(bb.containing(second.project['name'] as String), seconds: 15);
    await bb.shot('after-restart');
    expect(bb.showing(bb.label(RegExp(r'^E-Board\n'))), isFalse);
  }, simulated: '在同一进程里销毁 App 再按 main() 启动，会话和偏好保留');

  bbCase('H5', '用没有工作区的账号登录，提示到网页端创建或接受邀请', (bb) async {
    await bb.launch();
    await bb.signIn(Env.loner, expectHome: false);
    final told = await bb.until(
      () => bb.screenTexts().any(
        (t) =>
            RegExp('web', caseSensitive: false).hasMatch(t) &&
            RegExp('workspace|invitation', caseSensitive: false).hasMatch(t),
      ),
      seconds: 20,
    );
    await bb.shot('loner');
    bb.note('screen: ${bb.screenTexts().join(' / ')}');
    expect(told, isTrue, reason: 'No hint to use the web app');
  });

  bbCase('I1', '产生未读通知再标记已读，导航数量正确，立即减少', (bb) async {
    final owner = await Api.signIn(Env.owner);
    await owner.notify('E-Q I1 first $runStamp');
    await owner.notify('E-Q I1 second $runStamp');
    await bb.start(Env.owner);
    await bb.nav('Inbox');
    await bb.see(bb.containing('E-Q I1 second $runStamp'), seconds: 15);
    await bb.pumpFor(const Duration(seconds: 1));
    final server = await _unread(owner);
    final shown = _badge(bb);
    bb.note('server unread $server, navigation says $shown');
    await bb.shot('before');
    expect(shown, server);
    await bb.tap(bb.containing('E-Q I1 first $runStamp'));
    final watch = Stopwatch()..start();
    final fell = await bb.until(() => _badge(bb) == server - 1, seconds: 5);
    bb.note('dropped to ${_badge(bb)} after ${watch.elapsedMilliseconds} ms');
    await bb.shot('after');
    expect(fell, isTrue);
    expect(watch.elapsedMilliseconds, lessThan(1500), reason: 'Not at once');
    await bb.server('read on the server', () async => await _unread(owner) == server - 1);
  });

  bbCase('I2', '点击任务通知打开任务并已读，非任务通知只标记已读', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'I2');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q I2 task $runStamp');
    await owner.notify('E-Q I2 about a task $runStamp', taskId: task['id'] as String);
    await owner.notify('E-Q I2 about nothing $runStamp');
    await bb.start(Env.owner);
    await bb.nav('Inbox');
    await bb.tap(bb.containing('E-Q I2 about nothing $runStamp'));
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('plain');
    expect(
      bb.showing(bb.containing('E-Q I2 about a task $runStamp')),
      isTrue,
      reason: 'Left the inbox',
    );
    await bb.server('the plain one read', () async {
      final n = (await owner.notifications(Env.workspaceId))
          .firstWhere((n) => '${n['title']}'.contains('E-Q I2 about nothing'));
      return n['isRead'] == true;
    });
    await bb.tap(bb.containing('E-Q I2 about a task $runStamp'));
    await bb.see(
      bb.titleField(task['title'] as String),
      seconds: 15,
      reason: 'The task did not open',
    );
    await bb.shot('task');
    await bb.server('the task one read', () async {
      final n = (await owner.notifications(Env.workspaceId))
          .firstWhere((n) => '${n['title']}'.contains('E-Q I2 about a task'));
      return n['isRead'] == true;
    });
  });

  bbCase('I3', '全部已读，然后清空，都生效', (bb) async {
    final owner = await Api.signIn(Env.owner);
    await owner.notify('E-Q I3 one $runStamp');
    await owner.notify('E-Q I3 two $runStamp');
    await bb.start(Env.owner);
    await bb.nav('Inbox');
    await bb.see(bb.containing('E-Q I3 two $runStamp'), seconds: 15);
    await bb.tap(bb.label('Mark all read').hitTestable());
    await bb.server('all read', () async => await _unread(owner) == 0);
    await bb.pumpFor(const Duration(seconds: 1));
    expect(_badge(bb), 0, reason: 'The navigation still counts unread');
    await bb.shot('all-read');
    await bb.tap(bb.tip('Clear all notifications'));
    for (final b in ['Clear all', 'Clear']) {
      final yes = find.widgetWithText(FilledButton, b);
      if (await bb.until(() => bb.visible(yes), seconds: 2)) {
        await bb.tap(yes.hitTestable());
        break;
      }
    }
    await bb.server('cleared', () async => (await owner.notifications(Env.workspaceId)).isEmpty);
    await bb.gone(bb.containing('E-Q I3 two $runStamp'), seconds: 10);
    await bb.shot('cleared');
  });

  bbCase('I4', '切换我的任务的三种分组，分组正确，能打开任务', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'I4');
    addTearDown(scratch.remove);
    final past = DateTime.now().toUtc().subtract(const Duration(days: 3)).toIso8601String();
    final late = await scratch.task('E-Q I4 late $runStamp', userId: Env.owner.id, dueDate: past);
    final doing = await scratch.task('E-Q I4 doing $runStamp', column: 1, userId: Env.owner.id);
    await bb.start(Env.owner);
    await bb.nav('My tasks');
    await bb.see(bb.containing('E-Q I4 late $runStamp'), seconds: 15);

    /// The group title right above [title].
    String groupOf(String title, List<String> groups) {
      final row = bb.rectOf(bb.containing(title));
      String? best;
      var top = double.negativeInfinity;
      for (final g in groups) {
        for (final e in bb.containing(g).evaluate()) {
          final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
          if (r.top < row.top - 2 && r.top > top && r.height < 40) {
            top = r.top;
            best = g;
          }
        }
      }
      return best ?? '';
    }

    final results = <String>[];
    await bb.tap(bb.label('Project').hitTestable().first);
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('project');
    results.add(
      'project: ${groupOf(late['title'] as String, [scratch.name, 'E-Board', 'E-Formats'])}',
    );
    expect(groupOf(late['title'] as String, [scratch.name, 'E-Board', 'E-Formats']), scratch.name);
    await bb.tap(bb.label('Status').hitTestable().first);
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('status');
    final statusGroups = ['To Do', 'In Progress', 'In Review', 'Done', '需求池', '已计划'];
    results.add('status: ${groupOf(doing['title'] as String, statusGroups)}');
    expect(groupOf(doing['title'] as String, statusGroups), 'In Progress');
    expect(groupOf(late['title'] as String, statusGroups), 'To Do');
    await bb.tap(bb.label('Due date').hitTestable().first);
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('due');
    final dueGroups = [
      'Overdue',
      'Today',
      'This week',
      'Later',
      'No due date',
      'Upcoming',
      'Tomorrow',
    ];
    final lateGroup = groupOf(late['title'] as String, dueGroups);
    final doingGroup = groupOf(doing['title'] as String, dueGroups);
    results.add('due: late in "$lateGroup", no date in "$doingGroup"');
    bb.note(results.join('; '));
    expect(lateGroup, 'Overdue');
    expect(doingGroup, 'No due date');
    await bb.tap(bb.containing(doing['title'] as String).hitTestable());
    await bb.see(bb.titleField(doing['title'] as String), seconds: 15);
    await bb.shot('opened');
  });

  bbCase('I5', '打开动态能打开任务；切走再回来先显示内容，不转圈', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'I5');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q I5 task $runStamp');
    await owner.comment(task['id'] as String, 'E-Q I5 comment $runStamp');
    await bb.start(Env.owner);
    await bb.nav('Activity');
    await bb.see(bb.containing('E-Q I5 comment $runStamp'), seconds: 20);
    await bb.tap(bb.containing('E-Q I5 comment $runStamp').hitTestable());
    await bb.see(
      bb.titleField(task['title'] as String),
      seconds: 15,
      reason: 'The task did not open',
    );
    await bb.shot('opened');
    await bb.closeTask();
    await bb.nav('Home');
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.nav('Activity');
    var spun = 0;
    var empty = 0;
    for (var i = 0; i < 6; i++) {
      await bb.tester.pump(const Duration(milliseconds: 16));
      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) spun++;
      if (!bb.showing(bb.containing('E-Q I5 comment $runStamp'))) empty++;
    }
    await bb.shot('back');
    bb.note('first frames: $spun with a spinner, $empty without the content');
    expect(spun, 0, reason: 'It spun');
    expect(empty, 0, reason: 'The content was not there at once');
  });

  bbCase('I6', '搜索任务、项目、评论，结果正确，能打开', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'I6 searchable');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q I6 findme task $runStamp');
    final other = await scratch.task('E-Q I6 commented $runStamp');
    await owner.comment(other['id'] as String, 'E-Q I6 unusualword$runStamp in a comment');
    await bb.start(Env.owner);
    final failures = <String>[];
    Future<void> search(String query, String shows, Future<void> Function() opened) async {
      try {
        if (!bb.visible(bb.field('Search tasks, projects, comments'))) {
          await bb.nav('Home');
          await bb.tap(bb.tip('Search').hitTestable());
        }
        await bb.type(bb.field('Search tasks, projects, comments'), query);
        await bb.submitKeyboard(TextInputAction.search);
        await bb.see(bb.containing(shows), seconds: 15, reason: 'No result for "$query"');
        await bb.shot(query.split(' ').first.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ''));
        await bb.tap(bb.containing(shows).hitTestable().last);
        await opened();
      } catch (e) {
        failures.add('$query: $e');
      }
    }

    await search('findme task $runStamp', task['title'] as String, () async {
      await bb.see(bb.titleField(task['title'] as String), seconds: 15);
      await bb.closeTask();
    });
    await search(scratch.name, scratch.name, () async {
      await bb.see(bb.filtersButton, seconds: 15);
    });
    await search('unusualword$runStamp', 'unusualword$runStamp', () async {
      await bb.see(bb.titleField(other['title'] as String), seconds: 15);
      await bb.closeTask();
    });
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbUnverified(
    'I7',
    '开启通知后退到后台，产生通知并触发后台检查，收到本地通知，点击打开任务',
    '系统通知横幅、iOS BGTask 和点击系统通知都在 App 之外，测试进程触发不了也看不到；需要真机验证',
  );
  bbUnverified('I8', '第一次检查不补发历史；积压很多通知时合并成摘要', '要看系统通知中心里出现了几条，测试进程看不到；需要真机验证');
  bbUnverified('I9', '切换账号后触发检查，不显示上一账号的通知', '同 I7：后台检查和系统通知在 App 之外');
  bbUnverified('I10', '关闭通知开关后触发检查，不再检查', '同 I7：后台检查由系统调度，测试进程触发不了');
}
