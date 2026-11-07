// KAN-52 平台和异常：P4、X1 到 X4。P1、P3 不在设备上跑，见报告。
import 'bb.dart';

void main() {
  blackBoxModule();

  bbCase('P4', '操作中旋转、切到后台再回来，不丢失状态', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'P4');
    addTearDown(scratch.remove);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.tap(bb.tip('New task'));
    final title = 'E-Q P4 half typed $runStamp';
    await bb.type(bb.field('Task title'), title);
    await bb.type(bb.field('Add a description for your task...'), 'Some words $runStamp');
    await bb.shot('typed');
    final failures = <String>[];
    if (!isMacOS) {
      final size = bb.window;
      await bb.setViewSize(Size(size.height, size.width));
      await bb.pumpFor(const Duration(seconds: 1));
      await bb.shot('turned');
      if (!bb.showing(bb.titleField(title))) failures.add('turning lost the title');
      await bb.setViewSize(size);
      await bb.pumpFor(const Duration(seconds: 1));
    }
    // Away and back. While away the app draws nothing, so the test only waits.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      bb.tester.binding.handleAppLifecycleStateChanged(state);
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      bb.tester.binding.handleAppLifecycleStateChanged(state);
    }
    await bb.pumpFor(const Duration(seconds: 2));
    await bb.shot('back');
    if (!bb.showing(bb.titleField(title))) failures.add('the background lost the title');
    if (!bb.showing(bb.titleField('Some words $runStamp'))) {
      failures.add('the background lost the description');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, simulated: '旋转用把 App 视图改成横竖互换的尺寸模拟；后台用发送系统生命周期事件模拟');

  bbCase('X1', '断网启动有提示，能重试', (bb) async {
    final proxy = Proxy();
    await proxy.start();
    addTearDown(proxy.close);
    await bb.launch();
    await bb.signIn(Env.owner, server: proxy.url);
    await bb.see(bb.containing('E-Board'));
    await bb.stop();
    await proxy.down();
    await bb.launch(keepPrefs: true);
    await bb.pumpFor(const Duration(seconds: 3));
    final told = await bb.until(
      () => bb.screenTexts().any(
        (t) => RegExp(r"reach|connect|offline|network|load", caseSensitive: false).hasMatch(t),
      ),
      seconds: 30,
    );
    await bb.shot('offline-start');
    bb.note(
      'offline start: ${told ? 'told' : 'nothing said'}; '
      '${bb.screenTexts().where((t) => t.length > 6).take(12).join(' / ')}',
    );
    // What the person meets next: the inbox and a board, still offline.
    final offline = RegExp(r"reach|connect|offline|network|load", caseSensitive: false);
    final pages = <String>[];
    for (final page in ['Inbox', 'Home']) {
      await bb.nav(page);
      await bb.pumpFor(const Duration(seconds: 3));
      final said = bb.screenTexts().where(offline.hasMatch).toList();
      pages.add('$page: ${said.isEmpty ? 'nothing said' : said.join(' / ')}');
      await bb.shot('offline-${page.toLowerCase()}');
    }
    await bb.openProjectOrFail('E-Board');
    await bb.pumpFor(const Duration(seconds: 3));
    final onBoard = bb.screenTexts().where(offline.hasMatch).toList();
    pages.add('board: ${onBoard.isEmpty ? 'nothing said' : onBoard.join(' / ')}');
    await bb.shot('offline-board');
    bb.note(pages.join('; '));
    final retry = find.byWidgetPredicate((w) {
      return (w is Tooltip &&
              RegExp('retry|try again|refresh', caseSensitive: false).hasMatch(w.message ?? '')) ||
          (w is RichText && RegExp(r'^(Retry|Try again)$').hasMatch(w.text.toPlainText().trim()));
    });
    final canRetry = bb.showing(retry);
    await proxy.up();
    if (canRetry) {
      await bb.tap(retry.hitTestable());
      final loaded = await bb.until(() => bb.showing(bb.text('需求池')), seconds: 30);
      bb.note('after retrying the board loaded: $loaded');
    }
    await bb.shot('retried');
    expect(told, isTrue, reason: 'Starting offline, nothing says the server cannot be reached');
    expect(canRetry, isTrue, reason: 'No way to retry');
  }, simulated: '断网用测试里的本地代理断开模拟');

  bbCase('X2', '服务端返回 500，显示可读提示', (bb) async {
    final proxy = Proxy();
    await proxy.start();
    addTearDown(proxy.close);
    await bb.launch();
    await bb.signIn(Env.owner, server: proxy.url);
    await bb.see(bb.containing('E-Board'));
    proxy
      ..mode = ProxyMode.fail500
      ..failPattern = '/api/task/tasks/';
    final before = bb.screenTexts().toSet();
    await bb.tap(bb.label(RegExp(r'^E-Board\n')).hitTestable());
    final said = await bb.until(
      () => bb.screenTexts().toSet().difference(before).any((t) => t.length > 10),
      seconds: 20,
    );
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('500');
    final message = bb.screenTexts().toSet().difference(before).where((t) => t.length > 6);
    bb.note('shown: ${message.join(' / ')}');
    proxy.mode = ProxyMode.pass;
    expect(said, isTrue, reason: 'Nothing was said');
    expect(
      message.join(' '),
      isNot(matches(RegExp(r'Exception|Dio|stack|null|Instance of', caseSensitive: false))),
    );
  }, simulated: '500 用测试里的本地代理对看板请求返回 500 模拟');

  bbCase('X3', '延迟 3 秒的网络下提交，有加载状态，不重复提交', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'X3');
    addTearDown(scratch.remove);
    final proxy = Proxy();
    await proxy.start();
    addTearDown(proxy.close);
    await bb.launch();
    await bb.signIn(Env.owner, server: proxy.url);
    await bb.openProject(scratch.name);
    await bb.tap(bb.tip('New task'));
    final title = 'E-Q X3 once $runStamp';
    await bb.type(bb.field('Task title'), title);
    proxy.delay = const Duration(seconds: 3);
    final create = find.widgetWithText(FilledButton, 'Create');
    final at = bb.tester.getCenter(create.first);
    await bb.tester.tapAt(at);
    await bb.tester.pump(const Duration(milliseconds: 150));
    await bb.tester.tapAt(at);
    await bb.tester.pump(const Duration(milliseconds: 150));
    await bb.tester.tapAt(at);
    var busy = false;
    final end = DateTime.now().add(const Duration(milliseconds: 2500));
    while (DateTime.now().isBefore(end)) {
      await bb.tester.pump(const Duration(milliseconds: 50));
      final spinner = find.byWidgetPredicate(
        (w) => w is CircularProgressIndicator || w is LinearProgressIndicator,
      );
      final disabled =
          create.evaluate().isNotEmpty &&
          bb.tester.widget<ButtonStyleButton>(create.first).onPressed == null;
      if (spinner.evaluate().isNotEmpty || disabled) {
        if (!busy) await bb.shot('busy');
        busy = true;
      }
    }
    proxy.delay = Duration.zero;
    await bb.pumpFor(const Duration(seconds: 5));
    final made = (await owner.boardTasks(scratch.id)).where((t) => t['title'] == title).length;
    bb.note('busy shown: $busy; tasks made: $made');
    await bb.shot('done');
    expect(busy, isTrue, reason: 'No loading state');
    expect(made, 1, reason: 'Made $made tasks');
  }, simulated: '延迟用测试里的本地代理给每个请求加 3 秒模拟');

  bbCase('X4', '两个设备同时改同一任务，两端最终一致', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'X4');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q X4 task $runStamp');
    final id = task['id'] as String;
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.openCard(task['title'] as String);
    // This device changes the title while the other changes the status and the priority.
    final mine = 'E-Q X4 from this device $runStamp';
    final field = bb.titleField(task['title'] as String);
    await bb.tap(field);
    await bb.tester.enterText(field.first, mine);
    await Future.wait([
      owner.setStatus(id, scratch.slugOf(2)),
      owner.setPriority(id, 'urgent'),
      () async {
        await bb.submitKeyboard();
      }(),
    ]);
    await bb.pumpFor(const Duration(seconds: 6));
    final server = await owner.task(id);
    final shownStatus = bb.valueText('Status');
    final shownPriority = bb.valueText('Priority');
    await bb.shot('settled');
    bb.note(
      'server: ${server['title']} / ${server['status']} / ${server['priority']}; '
      'screen: status "$shownStatus", priority "$shownPriority"',
    );
    expect(server['title'], mine);
    expect(server['status'], scratch.slugOf(2));
    expect(shownStatus, scratch.nameOf(2));
    expect(shownPriority, 'Urgent');
    expect(bb.showing(bb.titleField(mine)), isTrue);
  }, simulated: '第二台设备用另一个 API 会话同时修改模拟');
}
