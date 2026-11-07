// KAN-52 登录：L1 到 L9。
import 'bb.dart';

void main() {
  blackBoxModule();

  bbCase('L1', '不带协议、带 http://、带 /api 的服务器地址都能连接', (bb) async {
    final uri = Uri.parse(Env.server);
    final hostPort = '${uri.host}:${uri.port}';
    final failed = <String>[];
    for (final (name, address) in [
      ('bare', hostPort),
      ('http', 'http://$hostPort'),
      ('api', 'http://$hostPort/api'),
    ]) {
      bb.storage = null;
      await bb.launch();
      final before = bb.screenTexts().toSet();
      await bb.signIn(Env.owner, server: address, expectHome: false);
      final home = await bb.until(
        () => bb.showing(bb.text('Your projects')) && bb.showing(bb.containing('E-Board')),
        seconds: 25,
      );
      await bb.shot(name);
      if (home) {
        bb.note('$name: connected');
      } else {
        await bb.dumpScreen(name);
        final said = bb.screenTexts().toSet().difference(before).join(' / ');
        bb.note('$name: did not connect, the app said "$said"');
        failed.add(name);
      }
    }
    expect(failed, isEmpty, reason: 'These addresses did not connect: $failed');
  });

  bbCase('L2', '密码错误留在登录页，显示服务器返回的原因', (bb) async {
    final answer = await Api.tryPassword(Env.owner.email, '${Env.owner.password}-wrong');
    final reason = (answer.body as Map)['message'] as String;
    bb.note('server said ${answer.status} "$reason"');
    await bb.launch();
    final wrong = Account(Env.owner.email, '${Env.owner.password}-wrong', '', '');
    await bb.signIn(wrong, expectHome: false);
    await bb.see(
      bb.containing(reason),
      seconds: 15,
      reason: 'The server reason "$reason" is not shown',
    );
    await bb.shot('wrong-password');
    expect(bb.showing(bb.text('Your projects')), isFalse);
    expect(bb.showing(bb.field('Password')), isTrue, reason: 'Left the login page');
  });

  bbCase('L3', '服务器不可达时显示可读提示，不崩溃', (bb) async {
    await bb.launch();
    final before = bb.screenTexts().toSet();
    await bb.signIn(Env.owner, server: 'http://127.0.0.1:9', expectHome: false);
    final appeared = await bb.until(
      () => bb.screenTexts().toSet().difference(before).any((t) => t.length > 8),
      seconds: 40,
    );
    await bb.shot('unreachable');
    expect(appeared, isTrue, reason: 'No message appeared');
    final message = bb.screenTexts().toSet().difference(before).join(' / ');
    bb.note('shown: $message');
    expect(bb.showing(bb.field('Password')), isTrue, reason: 'Left the login page');
    expect(
      message,
      isNot(
        matches(RegExp(r'Exception|Errno|errno|SocketException|Dio|stack', caseSensitive: false)),
      ),
      reason: 'The message is not readable: $message',
    );
  });

  if (isMacOS) {
    bbUnverified(
      'L4',
      '登录后杀掉 App 重开，保持登录',
      '测试构建读写钥匙串时 macOS 弹出钥匙串授权框，无人值守时没人能点允许，测试卡住；'
          '需要管理员在正式签名的安装包上验证',
    );
  } else {
    bbCase('L4', '登录后杀掉 App 重开，保持登录', (bb) async {
      await bb.launch(keychain: true);
      if (await bb.until(() => bb.showing(bb.text('Your projects')), seconds: 8)) {
        await signOut(bb);
      }
      await bb.signIn(Env.owner);
      await bb.shot('signed-in');
      await bb.restart(keychain: true);
      await bb.see(bb.text('Your projects'), seconds: 30, reason: 'Back on the login page');
      expect(bb.showing(bb.field('Password')), isFalse);
      await bb.shot('reopened');
      await signOut(bb);
    }, simulated: '在同一进程里销毁 App 再按 main() 重新启动，会话读系统钥匙串');
  }

  bbCase('L5', '正确的 API Key 登录成功，错误的有提示', (bb) async {
    await bb.launch();
    await bb.tap(bb.text('API key'));
    await bb.pumpFor(const Duration(milliseconds: 500));
    final before = bb.screenTexts();
    await bb.signInWithKey(
      '${Env.apiKey.substring(0, Env.apiKey.length - 4)}zzzz',
      expectHome: false,
    );
    final shown = await bb.until(
      () => bb.screenTexts().any((t) => !before.contains(t) && t.length > 8),
      seconds: 20,
    );
    await bb.shot('wrong-key');
    expect(bb.showing(bb.text('Your projects')), isFalse, reason: 'A wrong key signed in');
    expect(shown, isTrue, reason: 'No message for a wrong key');
    bb.note('wrong key: ${bb.screenTexts().where((t) => !before.contains(t)).join(' / ')}');

    bb.storage = null;
    await bb.launch();
    await bb.signInWithKey(Env.apiKey);
    await bb.see(bb.containing('E-Board'));
    await bb.shot('right-key');
  });

  bbCase('L6', '退出后登录另一账号，看不到上一账号的数据和通知', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'L6');
    addTearDown(scratch.remove);
    final marker = 'E-Q owner only $runStamp';
    final task = await scratch.task('$marker task', userId: Env.owner.id);
    await owner.notify('$marker notice', taskId: task['id'] as String);

    await bb.start(Env.owner);
    await bb.nav('Inbox');
    await bb.see(bb.containing(marker), seconds: 20);
    await bb.shot('owner-inbox');
    await bb.nav('My tasks');
    await bb.see(bb.containing(marker), seconds: 20);
    await signOut(bb);
    await bb.signIn(Env.member);
    await bb.shot('member-home');
    for (final page in ['Inbox', 'My tasks', 'Home']) {
      await bb.nav(page);
      await bb.pumpFor(const Duration(seconds: 3));
      await bb.shot('member-${page.replaceAll(' ', '-')}');
      expect(
        bb.showing(bb.containing(marker)),
        isFalse,
        reason: '$page shows the owner\'s $marker',
      );
    }
  });

  bbCase('L7', '在服务端让会话失效后再操作，回到登录页', (bb) async {
    await bb.start(Env.owner);
    final other = await Api.signIn(Env.owner);
    await other.revokeAllSessions();
    // Whatever the person does next.
    for (final page in ['Inbox', 'My tasks', 'Home']) {
      if (bb.showing(bb.field('Password'))) break;
      try {
        await bb.nav(page);
        await bb.pumpFor(const Duration(seconds: 2));
      } catch (_) {}
    }
    await bb.see(
      bb.field('Password'),
      seconds: 30,
      reason: 'Still signed in after the session ended',
    );
    await bb.shot('back-to-login');
  });

  bbCase('L8', '登录页只有服务器地址、账号密码和 API Key', (bb) async {
    await bb.launch();
    await bb.see(bb.field('Server address'));
    final forbidden = RegExp(
      r'cloud|verification|one-time|otp|magic|browser|github|google|sso|sign up|create account|\bcode\b',
      caseSensitive: false,
    );
    final password = bb.screenTexts();
    await bb.shot('password');
    await bb.tap(bb.text('API key'));
    final key = bb.screenTexts();
    await bb.shot('api-key');
    bb.note('password tab: ${password.join(' / ')}');
    bb.note('key tab: ${key.join(' / ')}');
    expect(bb.showing(bb.field('API key')), isTrue);
    expect([...password, ...key].where(forbidden.hasMatch), isEmpty);
    final semantics = semanticsLines(bb.tester).join('\n');
    expect(forbidden.hasMatch(semantics), isFalse, reason: semantics);
  });

  bbCase('L9', '用 API Key 登录，API 修改任务后看板 5 秒内更新，通知能收到', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final member = await Api.signIn(Env.member);
    final scratch = await Scratch.make(owner, 'L9');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q L9 card $runStamp', userId: Env.owner.id);
    final id = task['id'] as String;

    await bb.launch();
    await bb.signInWithKey(Env.apiKey);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(task['title'] as String));
    await bb.pumpFor(const Duration(seconds: 2));
    final renamed = 'E-Q L9 renamed $runStamp';
    await owner.setTitle(id, renamed);
    await owner.setStatus(id, scratch.slugOf(1));
    final watch = Stopwatch()..start();
    final moved = await bb.until(
      () => bb.showing(bb.card(renamed)) && bb.columnOf(bb.card(renamed)) == scratch.nameOf(1),
      seconds: 15,
    );
    watch.stop();
    await bb.shot('board-updated');
    bb.note('board caught up in ${watch.elapsedMilliseconds} ms');
    expect(moved, isTrue, reason: 'The board never caught up');
    expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 5)));

    // Someone else comments on a task assigned to this account, which the server notifies about.
    await bb.nav('Inbox');
    await bb.pumpFor(const Duration(seconds: 2));
    await member.comment(id, 'E-Q L9 comment $runStamp');
    await bb.see(bb.containing(renamed), seconds: 20, reason: 'The notification never came');
    await bb.shot('notification');
  });
}
