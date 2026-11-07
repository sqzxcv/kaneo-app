// KAN-52 布局：U1 到 U8。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import 'bb.dart';

/// The wide layout's sidebar: its Home entry at the window's left edge, and the Projects heading.
bool _sidebar(Bb bb) {
  // Drawn, even when a dialog over it takes the taps.
  final home = bb.label('Home').evaluate().where((e) {
    return bb.tester.getRect(find.byElementPredicate((x) => x == e)).left < 40;
  });
  return home.isNotEmpty && bb.showing(bb.text('Projects'));
}

/// The narrow layout's tabs at the bottom.
bool _tabs(Bb bb) => bb.showing(bb.label(RegExp(r'Tab \d of \d')));

/// Every page a person can reach, each opened the way a person opens it; [visit] runs on each.
Future<void> _everyPage(Bb bb, Future<void> Function(String page) visit) async {
  for (final page in ['Home', 'Inbox', 'My tasks', 'Activity', 'Account']) {
    await bb.nav(page);
    await bb.pumpFor(const Duration(seconds: 1));
    await visit(page);
  }
  await bb.nav('Home');
  await bb.tap(bb.tip('Search').hitTestable());
  await bb.pumpFor(const Duration(milliseconds: 600));
  await visit('Search');
  await bb.back();
  await bb.openProject('E-Board');
  await bb.pumpFor(const Duration(seconds: 1));
  await visit('Board');
  await bb.tap(bb.tip('List view'));
  await bb.pumpFor(const Duration(seconds: 1));
  await visit('List');
  await bb.tap(bb.tip('Board view'));
  await bb.scrollBoardTo('To Do');
  await bb.openCard('E-三层 祖父');
  await visit('Task');
  await bb.closeTask();
  await bb.tap(bb.tip('New task'));
  await bb.pumpFor(const Duration(milliseconds: 600));
  await visit('New task');
  await bb.escape();
  if (bb.showing(bb.field('Task title'))) await bb.back();
  await bb.nav('Home');
}

/// WCAG contrast of two colours.
double _contrast(Color a, Color b) {
  double l(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final x = l(a);
  final y = l(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// Text on screen that can hardly be read: its colour against what is drawn just beside it.
Future<List<String>> _hardToRead(Bb bb) async {
  final boundary =
      find.byType(RepaintBoundary).evaluate().first.renderObject! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final w = image.width;
  final h = image.height;
  image.dispose();
  Color at(double x, double y) {
    final px = x.clamp(0, w - 1).toInt();
    final py = y.clamp(0, h - 1).toInt();
    final i = (py * w + px) * 4;
    return Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  final bad = <String>[];
  for (final e in find.byType(RichText).hitTestable().evaluate()) {
    final rt = e.widget as RichText;
    final text = rt.text.toPlainText().trim();
    if (text.length < 2 || text.codeUnits.every((c) => c > 0xE000)) continue;
    final color = rt.text.style?.color;
    if (color == null) continue;
    final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
    if (r.width < 4 || r.height < 4) continue;
    // A control that is switched off may be faint; a screen reader is told it is disabled.
    try {
      final node = bb.tester.getSemantics(find.byElementPredicate((x) => x == e));
      if (node.getSemanticsData().flagsCollection.isEnabled == ui.Tristate.isFalse) continue;
    } catch (_) {}
    // The background: the corner pixels just around the text, taking the most common.
    final samples = [
      at(r.left - 2, r.top - 2),
      at(r.right + 2, r.top - 2),
      at(r.left - 2, r.bottom + 2),
      at(r.right + 2, r.bottom + 2),
    ];
    samples.sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
    final back = samples[1];
    final fore = Color.alphaBlend(color, back);
    final ratio = _contrast(fore, back);
    if (ratio < 3) bad.add('"$text" ${ratio.toStringAsFixed(1)}:1');
  }
  return bad;
}

/// Picks [option] from an account setting's choices, such as Theme or Language.
Future<void> _setting(Bb bb, String setting, Pattern option) async {
  if (setting == '语言') {
    // The navigation speaks Chinese by now.
    if (bb.visible(bb.label('账户'))) {
      await bb.tap(bb.label('账户').hitTestable().first);
    } else {
      await bb.tap(bb.label('首页').hitTestable().first);
      await bb.tap(bb.tip('账户').hitTestable());
    }
  } else {
    await bb.nav('Account');
  }
  // The setting's current value, beside its name, opens its choices.
  await bb.tap(bb.valueOf(setting));
  await bb.pumpFor(const Duration(milliseconds: 800));
  final choice = bb.containing(option).hitTestable();
  // A long list scrolls: down it until the choice shows.
  for (var i = 0; i < 12 && !bb.showing(choice); i++) {
    final lists = find
        .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .evaluate()
        .toList();
    if (lists.isEmpty) break;
    await bb.tester.drag(find.byElementPredicate((e) => e == lists.last), const Offset(0, -250));
    await bb.pumpFor(const Duration(milliseconds: 300));
  }
  await bb.see(choice, reason: 'No "$option" among the $setting choices');
  await bb.tap(find.byElementPredicate((e) => e == choice.evaluate().last));
  await bb.pumpFor(const Duration(seconds: 1));
  for (var i = 0; i < 2 && bb.visible(bb.label('Dismiss')); i++) {
    await bb.escape();
  }
}

void main() {
  blackBoxModule();

  if (isTablet) {
    bbCase(
      'U1',
      'iPad 横竖屏打开各页面，都有左侧栏，没有底部标签',
      (bb) async {
        await bb.start(Env.owner);
        final real = bb.window;
        final failures = <String>[];
        for (final (name, size) in [
          ('portrait', Size(real.shortestSide, real.longestSide)),
          ('landscape', Size(real.longestSide, real.shortestSide)),
        ]) {
          if (bb.window != size) await bb.setViewSize(size);
          await _everyPage(bb, (page) async {
            await bb.shot('$name-${page.replaceAll(' ', '-')}');
            if (!_sidebar(bb)) failures.add('$name $page: no sidebar');
            if (_tabs(bb)) failures.add('$name $page: bottom tabs');
          });
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
      simulated: '竖屏是模拟器真实方向；横屏把 App 视图改成横向尺寸模拟（iPad 多任务时不跟随方向请求）',
      timeout: const Timeout(Duration(minutes: 10)),
    );

    bbCase('U3', 'iPad 分屏到较短边小于 600 再恢复，布局切换，当前页面和筛选不丢', (bb) async {
      await bb.start(Env.owner);
      await bb.openProject('E-Board');
      await bb.type(bb.field('Filter tasks…'), 'E-三层');
      await bb.pumpFor(const Duration(seconds: 1));
      final full = bb.window;
      expect(_sidebar(bb), isTrue);
      await bb.shot('full');
      await bb.setViewSize(Size(507, full.height));
      await bb.pumpFor(const Duration(seconds: 1));
      await bb.shot('split');
      final narrowSidebar = _sidebar(bb);
      final kept = bb.showing(bb.titleField('E-三层')) && bb.showing(bb.text('需求池'));
      bb.note('split: sidebar $narrowSidebar, board and filter kept $kept');
      expect(narrowSidebar, isFalse, reason: 'Still the wide layout at 507 wide');
      expect(kept, isTrue, reason: 'The board or its filter was lost');
      await bb.setViewSize(full);
      await bb.pumpFor(const Duration(seconds: 1));
      await bb.shot('restored');
      expect(_sidebar(bb), isTrue, reason: 'Not back to the wide layout');
      expect(bb.showing(bb.titleField('E-三层')), isTrue, reason: 'The filter was lost');
      expect(bb.showing(bb.text('需求池')), isTrue, reason: 'The board was lost');
    }, simulated: '分屏用把 App 视图改成 507 宽模拟');
  }

  if (isPhone) {
    bbCase('U2', '手机横竖屏打开首页，都有底部导航', (bb) async {
      await bb.start(Env.owner);
      expect(bb.landscape, isFalse);
      await bb.shot('portrait');
      expect(_tabs(bb), isTrue, reason: 'No bottom tabs upright');
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
      final turned = await bb.until(() => bb.landscape, seconds: 10);
      bb.note('the phone turned: $turned');
      if (!turned) await bb.setViewSize(Size(bb.window.height, bb.window.width));
      await bb.pumpFor(const Duration(seconds: 1));
      await bb.shot('landscape');
      final tabs = _tabs(bb);
      await SystemChrome.setPreferredOrientations(const []);
      expect(tabs, isTrue, reason: 'No bottom tabs sideways');
    });
  }

  if (isMacOS) {
    bbCase(
      'U4',
      'macOS 窗口缩到最小，仍是宽屏，没有溢出',
      (bb) async {
        await bb.start(Env.owner);
        addTearDown(() => windowManager.setSize(const Size(1366, 1024)));
        // What a program can do: it is not held to the window's minimum, as a person dragging is.
        await windowManager.setSize(const Size(200, 200));
        await bb.pumpFor(const Duration(seconds: 1));
        bb.note('set to 200x200 by the test, the app got ${bb.window}');
        await bb.shot('set-200');
        // The smallest wide window there can be: 600 high.
        await windowManager.setSize(const Size(900, 628));
        await bb.pumpFor(const Duration(seconds: 1));
        // The title bar takes its share: make the app's own part exactly 600 high.
        final short = 600 - bb.window.height;
        if (short != 0) {
          await windowManager.setSize(Size(900, 628 + short));
          await bb.pumpFor(const Duration(seconds: 1));
        }
        final size = bb.window;
        bb.note('a window 600 high: the app got $size');
        final failures = <String>[];
        await _everyPage(bb, (page) async {
          await bb.shot('short-${page.replaceAll(' ', '-')}');
          if (!_sidebar(bb)) failures.add('$page: no sidebar');
          final error = bb.tester.takeException();
          if (error != null) failures.add('$page: $error');
        });
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
      unverified:
          '测试拖不了窗口边缘；用 window_manager 程序化缩小不受窗口最小尺寸约束（设 200×200 就变成了 200×168），'
          '所以“拖到最小仍是宽屏”要人工拖一次确认。下面记的是短边约 600 时各页面有侧栏、没有溢出的检查结果',
    );

    bbCase('U7', 'macOS 上悬停有反馈，右键菜单在指针旁，Esc 能关闭', (bb) async {
      final owner = await Api.signIn(Env.owner);
      final scratch = await Scratch.make(owner, 'U7');
      addTearDown(scratch.remove);
      final title = 'E-Q U7 card $runStamp';
      await scratch.task(title);
      await bb.start(Env.owner);
      await bb.openProject(scratch.name);
      await bb.see(bb.card(title));
      // Hover: what is drawn under the pointer changes.
      final card = bb.rectOf(bb.card(title));
      Future<List<int>> pixels() async {
        final boundary =
            find.byType(RepaintBoundary).evaluate().first.renderObject! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final w = image.width;
        image.dispose();
        final i = ((card.top + 4).toInt() * w + (card.right - 30).toInt()) * 4;
        return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
      }

      final away = await pixels();
      final mouse = await bb.tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 900));
      await mouse.moveTo(card.center);
      await bb.pumpFor(const Duration(milliseconds: 600));
      final over = await pixels();
      await bb.shot('hover');
      await mouse.moveTo(const Offset(700, 900));
      await mouse.removePointer();
      bb.note('card background away $away, under the pointer $over');
      expect(away, isNot(over), reason: 'No hover feedback');

      // A right click at a point, and the menu beside it.
      final point = Offset(card.left + 60, card.center.dy);
      final right = await bb.tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.addPointer(location: point);
      await right.down(point);
      await bb.tester.pump(const Duration(milliseconds: 60));
      await right.up();
      await right.removePointer();
      await bb.pumpFor(const Duration(milliseconds: 600));
      await bb.see(bb.text('Move to'));
      final menu = bb.rectOf(bb.text('Move to'));
      await bb.shot('menu');
      bb.note('pointer at $point, menu item at ${menu.topLeft}');
      expect((menu.left - point.dx).abs(), lessThan(80), reason: 'The menu is not by the pointer');
      expect((menu.top - point.dy).abs(), lessThan(80), reason: 'The menu is not by the pointer');
      await bb.escape();
      expect(bb.showing(bb.text('Move to')), isFalse, reason: 'Esc left the menu open');

      // Esc closes the task panel and the new task dialog too.
      await bb.openCard(title);
      await bb.escape();
      final panel = !bb.showing(bb.titleField(title));
      await bb.tap(bb.tip('New task'));
      await bb.see(bb.field('Task title'));
      await bb.escape();
      final dialog = !bb.showing(bb.field('Task title'));
      bb.note('Esc closed the task panel: $panel, the new task dialog: $dialog');
      expect(panel, isTrue, reason: 'Esc left the task open');
      expect(dialog, isTrue, reason: 'Esc left the new task dialog open');
    });
  }

  bbCase('U5', '切换深色和浅色遍历各页面，没有不可读的文字', (bb) async {
    await bb.start(Env.owner);
    final failures = <String>[];
    for (final theme in ['Dark', 'Light']) {
      await _setting(bb, 'Theme', theme);
      await _everyPage(bb, (page) async {
        await bb.shot('${theme.toLowerCase()}-${page.replaceAll(' ', '-')}');
        final bad = await _hardToRead(bb);
        if (bad.isNotEmpty) failures.add('$theme $page: ${bad.join(', ')}');
      });
    }
    await _setting(bb, 'Theme', 'Match system');
    for (final f in failures) {
      bb.note(f);
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 12)));

  bbCase('U6', '简体中文遍历各页面，没有英文残留和文案 key', (bb) async {
    await bb.start(Env.owner);
    await _setting(bb, 'Language', RegExp(r'简体|Simplified|中文 ?[（(]中国[)）]'));
    addTearDown(() async {
      try {
        await _setting(bb, '语言', RegExp('跟随系统|Match system'));
      } catch (_) {}
    });
    // What the data says, which stays as it was typed.
    final data = RegExp(
      r'^(E-|E |EBB-|EFM-|EEM-|ERQ-|Q[A-Z0-9]+-|Kaneo$|To Do$|In Progress$|In Review$|Done$|E[MOVL]$|@)',
    );
    final key = RegExp(r'^[a-zA-Z]+:[\w.]+$|^\w+(\.\w+){2,}$');
    final english = RegExp(r'[A-Za-z]{3,}');
    final found = <String>{};
    final names = ['首页', '收件箱', '我的任务', '活动', '账户'];
    for (final page in names) {
      // On a phone the account is behind the home page's button.
      if (page == '账户' && !bb.visible(bb.label(page))) {
        await bb.tap(bb.label(names.first).hitTestable().first);
        await bb.tap(bb.tip(page).hitTestable());
      } else {
        await bb.tap(bb.label(page).hitTestable().first);
      }
      await bb.pumpFor(const Duration(seconds: 1));
      await bb.shot(page);
      for (final t in bb.screenTexts()) {
        final line = t.trim();
        if (line.isEmpty || data.hasMatch(line)) continue;
        if (key.hasMatch(line)) found.add('$page key: $line');
        if (english.hasMatch(line.replaceAll(RegExp(r'E-\S+|e-[\w.@-]+|https?://\S+'), ''))) {
          found.add('$page: $line');
        }
      }
    }
    await bb.tap(bb.label(names.first).hitTestable().first);
    final board = bb.label(RegExp(r'^E-Board\n'));
    await bb.tap(board.hitTestable());
    await bb.pumpFor(const Duration(seconds: 2));
    await bb.shot('board');
    for (final t in bb.screenTexts()) {
      final line = t.trim();
      if (line.isEmpty || data.hasMatch(line)) continue;
      if (key.hasMatch(line) || english.hasMatch(line)) found.add('board: $line');
    }
    for (final f in found) {
      bb.note(f);
    }
    expect(found, isEmpty, reason: found.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 8)));

  if (!isPhone) {
    bbCase('U8', '账户、收件箱、动态在宽屏下不拉满全宽', (bb) async {
      await bb.start(Env.owner);
      final failures = <String>[];
      for (final page in ['Account', 'Inbox', 'Activity']) {
        await bb.nav(page);
        await bb.pumpFor(const Duration(seconds: 1));
        await bb.shot(page);
        // The page is right of the sidebar; its widest piece of content.
        final sidebar = bb.rectOf(bb.label('Home').hitTestable()).right;
        final area = bb.window.width - sidebar;
        var widest = 0.0;
        for (final e in find.byType(RichText).hitTestable().evaluate()) {
          final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
          // Below the page's own title bar.
          if (r.left > sidebar + 4 && r.top > 70) widest = math.max(widest, r.right - sidebar);
        }
        final lines = semanticsLines(bb.tester);
        bb.note('$page: content reaches ${widest.round()} of ${area.round()}');
        if (widest > area * 0.92) {
          failures.add('$page reaches ${widest.round()} of ${area.round()}');
        }
        expect(lines, isNotEmpty);
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
