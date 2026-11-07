// KAN-52 看板：B1 到 B15。

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/scheduler.dart';

import 'bb.dart';

/// Every kind of busy indicator a page can show.
Finder get _spinners => find.byWidgetPredicate(
  (w) =>
      w is CircularProgressIndicator ||
      w is RefreshProgressIndicator ||
      w is LinearProgressIndicator ||
      w is CupertinoActivityIndicator,
);

/// Drags [title]'s card into [column], below its title.
Future<void> _dragTo(Bb bb, String title, String column, {double below = 120}) async {
  await bb.see(bb.card(title));
  final header = bb.rectOf(bb.text(column).hitTestable());
  await bb.dragCard(title, Offset(header.center.dx, header.bottom + below));
}

void main() {
  blackBoxModule();

  if (isPhone) {
    bbCase('B1', '手机进入看板时横屏，切到列表再回首页恢复跟随系统', (bb) async {
      await bb.start(Env.owner);
      expect(bb.landscape, isFalse, reason: 'The phone did not start upright');
      await bb.openProject('E-Board');
      final turned = await bb.until(() => bb.landscape, seconds: 10);
      await bb.shot('board');
      expect(turned, isTrue, reason: 'The board did not turn the phone sideways');
      await bb.tap(bb.tip('List view'));
      await bb.shot('list');
      bb.note('list view landscape: ${bb.landscape}');
      await bb.nav('Home');
      final upright = await bb.until(() => !bb.landscape, seconds: 10);
      await bb.shot('home');
      expect(upright, isTrue, reason: 'Home stayed sideways after the board');
    });
  }

  if (isTablet) {
    bbCase('B2', 'iPad 竖屏进入看板，方向不变，显示多列', (bb) async {
      await bb.start(Env.owner);
      if (bb.landscape) await bb.setViewSize(Size(bb.window.height, bb.window.width));
      expect(bb.landscape, isFalse);
      await bb.openProject('E-Board');
      await bb.pumpFor(const Duration(seconds: 3));
      await bb.shot('portrait-board');
      expect(bb.landscape, isFalse, reason: 'The iPad turned');
      final shown = [
        for (final c in boardColumnNames)
          if (bb.visible(bb.text(c))) c,
      ];
      bb.note('columns on screen: $shown');
      expect(shown.length, greaterThanOrEqualTo(2));
    });
  }

  bbCase('B3', '6 列项目横向滚动，每列显示图标、列名和数量，列名跟着列走', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final tasks = await owner.boardTasks(Env.boardProject);
    final counts = {for (final c in boardColumnNames) c: 0};
    final columns = await owner.columns(Env.boardProject);
    for (final t in tasks) {
      final name = columns.where((c) => c['slug'] == t['status']).firstOrNull?['name'];
      if (name != null) counts[name as String] = counts[name]! + 1;
    }
    bb.note('API counts $counts');
    await bb.start(Env.owner);
    await bb.openProject('E-Board');
    await bb.see(bb.text('需求池'));
    for (final (i, column) in boardColumnNames.indexed) {
      await bb.scrollBoardTo(column);
      final header = bb.rectOf(bb.text(column).hitTestable());
      final n = counts[column]!;
      final count = bb.text('$n ${n == 1 ? 'task' : 'tasks'}');
      final sameRow = count.evaluate().where((e) {
        final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
        return (r.center.dy - header.center.dy).abs() < 16 && r.left > header.left;
      });
      expect(sameRow, isNotEmpty, reason: '$column has no count $n beside its title');
      final icons = find.byType(Icon).evaluate().where((e) {
        final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
        return (r.center.dy - header.center.dy).abs() < 16 &&
            r.right <= header.left + 2 &&
            r.right > header.left - 40;
      });
      expect(icons, isNotEmpty, reason: '$column has no icon before its title');
      // The column's cards start under its title.
      final cards = find.byWidgetPredicate((w) => w is RichText).evaluate().where((e) {
        final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
        return r.top > header.bottom + 8 &&
            r.left >= header.left - 60 &&
            r.left <= header.left + 40 &&
            (e.widget as RichText).text.toPlainText().startsWith('E-');
      });
      if (n > 0) expect(cards, isNotEmpty, reason: '$column title is not over its cards');
      await bb.shot('column-$i');
    }
  });

  bbCase('B4', '拖到其他列，松手立刻到位，重启后和 API 一致', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B4');
    addTearDown(scratch.remove);
    final a = 'E-Q B4 moving $runStamp';
    await scratch.task(a);
    await scratch.task('E-Q B4 staying $runStamp');
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await _dragTo(bb, a, scratch.nameOf(1));
    final watch = Stopwatch()..start();
    final arrived = await bb.until(() => bb.columnOf(bb.card(a)) == scratch.nameOf(1), seconds: 5);
    bb.note('in place after ${watch.elapsedMilliseconds} ms');
    await bb.shot('dropped');
    expect(arrived, isTrue, reason: 'The card is not in ${scratch.nameOf(1)}');
    expect(watch.elapsedMilliseconds, lessThan(1000), reason: 'Not in place at once');
    await bb.server('the move', () async {
      return (await owner.task((await _id(owner, scratch, a))))['status'] == scratch.slugOf(1);
    });
    await bb.restart();
    await bb.openProject(scratch.name);
    await bb.see(bb.card(a));
    await bb.shot('after-restart');
    expect(bb.columnOf(bb.card(a)), scratch.nameOf(1));
  });

  bbCase('B5', '同列内调整顺序，重启后顺序保持', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B5');
    addTearDown(scratch.remove);
    final titles = ['E-Q B5 one $runStamp', 'E-Q B5 two $runStamp', 'E-Q B5 three $runStamp'];
    for (final t in titles) {
      await scratch.task(t);
    }
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(titles.last));
    final column = scratch.nameOf(0);
    final before = bb.orderIn(column, titles);
    bb.note('before $before');
    // The bottom card goes to the top.
    final top = bb.rectOf(bb.card(before.first));
    final moving = before.last;
    await bb.dragCard(moving, Offset(top.center.dx, top.top - 6));
    await bb.pumpFor(const Duration(seconds: 2));
    final after = bb.orderIn(column, titles);
    await bb.shot('reordered');
    bb.note('after $after');
    expect(after.first, moving, reason: 'The card did not move to the top');
    await bb.server('the order', () async => _same(await scratch.titlesIn(0), after));
    await bb.restart();
    await bb.openProject(scratch.name);
    await bb.see(bb.card(moving));
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('after-restart');
    expect(bb.orderIn(column, titles), after);
  });

  bbCase('B6', '把卡片拖到屏幕边缘，看板自动滚动', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B6', extraColumns: ['Q5', 'Q6', 'Q7', 'Q8', 'Q9']);
    addTearDown(scratch.remove);
    final a = 'E-Q B6 card $runStamp';
    await scratch.task(a);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(a));
    final before = bb.rectOf(bb.text(scratch.nameOf(0))).left;
    final from = bb.grip(a);
    final edge = Offset(bb.window.width - 8, from.dy);
    final gesture = await bb.tester.startGesture(
      from,
      kind: isMacOS ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await bb.pumpFor(bb.pickUp);
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(Offset.lerp(from, edge, i / 20)!);
      await bb.tester.pump(const Duration(milliseconds: 16));
    }
    await bb.pumpFor(const Duration(seconds: 2));
    await bb.shot('at-edge');
    final shown = [
      for (final c in ['Q7', 'Q8', 'Q9'])
        if (bb.showing(bb.text(c)) && bb.rectOf(bb.text(c)).left < bb.window.width) c,
    ];
    final first = bb.text(scratch.nameOf(0));
    final after = bb.showing(first) ? bb.rectOf(first).left : double.negativeInfinity;
    await gesture.up();
    if (isMacOS) await gesture.removePointer();
    await bb.pumpFor(const Duration(seconds: 1));
    bb.note('first column title moved from $before to $after; now showing $shown');
    expect(after, lessThan(before - 100), reason: 'The board did not scroll');
  });

  bbCase('B7', '断网后拖动卡片，卡片回到原位，有提示', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B7');
    addTearDown(scratch.remove);
    final a = 'E-Q B7 card $runStamp';
    await scratch.task(a);
    final proxy = Proxy();
    await proxy.start();
    addTearDown(proxy.close);
    await bb.launch();
    await bb.signIn(Env.owner, server: proxy.url);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(a));
    final before = bb.screenTexts().toSet();
    await proxy.down();
    final header = bb.rectOf(bb.text(scratch.nameOf(1)).hitTestable());
    final target = Offset(header.center.dx, header.bottom + 120);
    final from = bb.grip(a);
    final gesture = await bb.tester.startGesture(
      from,
      kind: isMacOS ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await bb.pumpFor(bb.pickUp);
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(Offset.lerp(from, target, i / 20)!);
      await bb.tester.pump(const Duration(milliseconds: 16));
    }
    await bb.pumpFor(const Duration(milliseconds: 200));
    // The card goes along with the finger.
    final carried = _rectsOf(bb, bb.card(a)).any((r) => (r.center - target).distance < 200);
    await bb.shot('carried');
    await gesture.up();
    if (isMacOS) await gesture.removePointer();
    var landed = false;
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(end)) {
      await bb.tester.pump(const Duration(milliseconds: 30));
      if (bb.columnOf(bb.card(a)) == scratch.nameOf(1)) landed = true;
    }
    final back = await bb.until(() => bb.columnOf(bb.card(a)) == scratch.nameOf(0), seconds: 20);
    final message = bb.screenTexts().toSet().difference(before).where((t) => t != a).toList();
    await bb.shot('returned');
    bb.note(
      'carried $carried; seen in ${scratch.nameOf(1)} after the drop: $landed; shown: $message',
    );
    expect(carried, isTrue, reason: 'The drag did not pick the card up');
    expect(back, isTrue, reason: 'The card stayed in ${scratch.nameOf(1)}');
    expect(message.any((t) => t.length > 8), isTrue, reason: 'No message');
    expect((await owner.task(await _id(owner, scratch, a)))['status'], scratch.slugOf(0));
    await proxy.up();
  }, simulated: '测试里的本地代理断开，App 连不上服务器');

  bbCase('B8', '移动卡片时其他列不转圈，不跳动', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B8');
    addTearDown(scratch.remove);
    final a = 'E-Q B8 moving $runStamp';
    await scratch.task(a);
    final others = [
      'E-Q B8 doing one $runStamp',
      'E-Q B8 doing two $runStamp',
      'E-Q B8 review $runStamp',
    ];
    await scratch.task(others[0], column: 1);
    await scratch.task(others[1], column: 1);
    await scratch.task(others[2], column: 3);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(others.first));
    await bb.pumpFor(const Duration(seconds: 1));
    // The cards on screen, wherever they are; one column may be out of sight.
    final rects = {
      for (final t in others)
        if (bb.showing(bb.card(t))) t: bb.rectOf(bb.card(t)),
    };
    bb.note('watching ${rects.length} cards in other columns');
    await _dragTo(bb, a, scratch.nameOf(2));
    var spun = 0;
    final moved = <String>{};
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(end)) {
      await bb.tester.pump(const Duration(milliseconds: 50));
      spun = spun + (_spinners.evaluate().isNotEmpty ? 1 : 0);
      for (final t in rects.keys) {
        if (!bb.showing(bb.card(t))) {
          moved.add('$t (gone)');
          continue;
        }
        final r = bb.rectOf(bb.card(t));
        if ((r.top - rects[t]!.top).abs() > 1 || (r.left - rects[t]!.left).abs() > 1) moved.add(t);
      }
    }
    await bb.shot('after-move');
    bb.note('frames with a spinner: $spun; moved: $moved');
    expect(spun, 0, reason: 'Something spun');
    expect(moved, isEmpty, reason: 'Other cards jumped');
  });

  bbCase('B9', '下拉刷新只有一个刷新提示', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Board');
    await bb.see(bb.text('需求池'));
    await bb.pumpFor(const Duration(seconds: 2));
    final header = bb.rectOf(bb.text('需求池').hitTestable());
    final from = Offset(header.center.dx, header.bottom + 60);
    final gesture = await bb.tester.startGesture(from, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 30; i++) {
      await gesture.moveTo(from + Offset(0, 12.0 * i));
      await bb.tester.pump(const Duration(milliseconds: 16));
    }
    var most = 0;
    var shot = false;
    await gesture.up();
    if (isMacOS) await gesture.removePointer();
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(end)) {
      await bb.tester.pump(const Duration(milliseconds: 50));
      final n = _spinners.evaluate().where((e) {
        final box = e.renderObject as RenderBox?;
        return box != null && box.attached && box.hasSize && box.size.width > 0;
      }).length;
      if (n > most) most = n;
      if (n > 0 && !shot) {
        shot = true;
        await bb.shot('refreshing');
      }
    }
    bb.note('pulling down: most refresh indicators at once: $most');
    if (most == 0 && isMacOS) {
      // A mouse has nothing to pull with; the toolbar's refresh button stands in.
      bb.note('macOS 没有下拉手势，改用工具栏的刷新按钮');
      await bb.tap(bb.tip('Refresh'));
      final until = DateTime.now().add(const Duration(seconds: 4));
      var button = 0;
      while (DateTime.now().isBefore(until)) {
        await bb.tester.pump(const Duration(milliseconds: 30));
        final n = _spinners.evaluate().length;
        if (n > button) button = n;
      }
      bb.note('refresh button: most indicators at once: $button');
      expect(button, lessThanOrEqualTo(1), reason: '$button indicators');
      return;
    }
    expect(most, 1, reason: most == 0 ? 'Pulling down did not refresh' : '$most indicators');
  });

  bbCase('B10', '右键和长按卡片，菜单的移动、负责人、优先级、列首、列尾、打开都生效', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B10');
    addTearDown(scratch.remove);
    final a = 'E-Q B10 card $runStamp';
    final b = 'E-Q B10 second $runStamp';
    final c = 'E-Q B10 third $runStamp';
    final made = await scratch.task(a);
    final id = made['id'] as String;
    await scratch.task(b, column: 1);
    await scratch.task(c, column: 1);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(a));

    // Both ways open the menu.
    if (!isPhone) {
      await bb.rightClick(bb.card(a));
      await bb.see(bb.text('Move to'), reason: 'A right click opened no menu');
      await bb.shot('right-click');
      await bb.escape();
      await bb.gone(bb.text('Move to'), seconds: 5);
    }
    await bb.longPress(bb.card(a));
    await bb.see(bb.text('Move to'), reason: 'A long press opened no menu');
    await bb.shot('long-press');

    await bb.tap(bb.text('Move to'));
    await bb.tap(bb.text(scratch.nameOf(1)).last);
    await bb.server('the move', () async => (await owner.task(id))['status'] == scratch.slugOf(1));
    await bb.pumpFor(const Duration(seconds: 1));
    expect(bb.columnOf(bb.card(a)), scratch.nameOf(1));

    await _menu(bb, a);
    await bb.tap(bb.text('Assignee'));
    await bb.tap(bb.containing(Env.member.name).last);
    await bb.server('the assignee', () async => (await owner.task(id))['userId'] == Env.member.id);

    await _menu(bb, a);
    await bb.tap(bb.text('Priority'));
    await bb.tap(bb.text('High').last);
    await bb.server('the priority', () async => (await owner.task(id))['priority'] == 'high');

    final column = scratch.nameOf(1);
    await _menu(bb, a);
    await bb.tap(bb.text('Send to bottom of column'));
    await bb.server('the card last', () async => (await scratch.titlesIn(1)).last == a);
    await bb.pumpFor(const Duration(seconds: 1));
    expect(bb.orderIn(column, [a, b, c]).last, a);

    await _menu(bb, a);
    await bb.tap(bb.text('Send to top of column'));
    await bb.server('the card first', () async => (await scratch.titlesIn(1)).first == a);
    await bb.pumpFor(const Duration(seconds: 1));
    expect(bb.orderIn(column, [a, b, c]).first, a);
    await bb.shot('after-menu');

    await _menu(bb, a);
    await bb.tap(bb.text('Open task'));
    await bb.see(find.byWidgetPredicate((w) => w is EditableText && w.controller.text == a));
    await bb.shot('opened');
  });

  bbCase('B11', '用 API 修改任务，打开的看板 5 秒内更新', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B11');
    addTearDown(scratch.remove);
    final made = await scratch.task('E-Q B11 card $runStamp');
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(made['title'] as String));
    await bb.pumpFor(const Duration(seconds: 2));
    final renamed = 'E-Q B11 renamed $runStamp';
    await owner.setTitle(made['id'] as String, renamed);
    await owner.setStatus(made['id'] as String, scratch.slugOf(2));
    final watch = Stopwatch()..start();
    final ok = await bb.until(
      () => bb.showing(bb.card(renamed)) && bb.columnOf(bb.card(renamed)) == scratch.nameOf(2),
      seconds: 15,
    );
    bb.note('caught up in ${watch.elapsedMilliseconds} ms');
    await bb.shot('updated');
    expect(ok, isTrue);
    expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 5)));
  });

  bbCase('B12', '断网 30 秒后恢复，自动重连并刷新', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B12');
    addTearDown(scratch.remove);
    final made = await scratch.task('E-Q B12 card $runStamp');
    final proxy = Proxy();
    await proxy.start();
    addTearDown(proxy.close);
    await bb.launch();
    await bb.signIn(Env.owner, server: proxy.url);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(made['title'] as String));
    await proxy.down();
    await bb.pumpFor(const Duration(seconds: 5));
    final renamed = 'E-Q B12 changed while away $runStamp';
    await owner.setTitle(made['id'] as String, renamed);
    await bb.pumpFor(const Duration(seconds: 25));
    await bb.shot('offline');
    await proxy.up();
    final watch = Stopwatch()..start();
    final ok = await bb.until(() => bb.showing(bb.card(renamed)), seconds: 60);
    bb.note('refreshed ${watch.elapsed.inSeconds} s after the network came back');
    await bb.shot('back');
    expect(ok, isTrue, reason: 'The board did not refresh by itself');
  }, simulated: '测试里的本地代理断开 30 秒再恢复');

  bbCase('B13', '在 100 张卡片的列滚动和拖动，没有明显卡顿', (bb) async {
    // A column of 100 cards of this run's own, so that carrying one around changes no seed data.
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B13');
    addTearDown(scratch.remove);
    await Future.wait([
      for (var i = 1; i <= 100; i++)
        scratch.task('E-卡片 Q${i.toString().padLeft(3, '0')} $runStamp'),
    ]);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.containing('E-卡片 Q'));
    final count = bb.containing(RegExp(r'^100 tasks$'));
    bb.note('the column says 100 tasks: ${bb.showing(count)}');
    await bb.pumpFor(const Duration(seconds: 2));
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));
    final column = scratch.nameOf(0);
    final header = bb.rectOf(bb.text(column).hitTestable());
    final inColumn = Offset(header.center.dx, header.bottom + 200);
    for (var i = 0; i < 3; i++) {
      await bb.tester.flingFrom(inColumn, const Offset(0, -600), 2500);
      await bb.pumpFor(const Duration(milliseconds: 1500));
    }
    for (var i = 0; i < 3; i++) {
      await bb.tester.flingFrom(inColumn, const Offset(0, 600), 2500);
      await bb.pumpFor(const Duration(milliseconds: 1500));
    }
    final scrolling = List.of(timings);
    timings.clear();
    // Picks a card up, carries it around the column, and puts it back where it was.
    final card = bb.containing('E-卡片').hitTestable();
    await bb.see(card);
    final picked = (bb.tester.widget(card.first) as RichText).text.toPlainText();
    final from = bb.grip(picked);
    final gesture = await bb.tester.startGesture(
      from,
      kind: isMacOS ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await bb.pumpFor(bb.pickUp);
    for (var i = 1; i <= 60; i++) {
      await gesture.moveTo(from + Offset(0, 300 * (i <= 30 ? i / 30 : (60 - i) / 30)));
      await bb.tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.moveTo(from);
    await bb.pumpFor(const Duration(milliseconds: 300));
    await gesture.up();
    if (isMacOS) await gesture.removePointer();
    await bb.pumpFor(const Duration(seconds: 1));
    final dragging = List.of(timings);
    String summary(String what, List<FrameTiming> t) {
      if (t.isEmpty) return '$what: no frames';
      final total = [for (final f in t) f.totalSpan.inMicroseconds / 1000]..sort();
      final build = [for (final f in t) f.buildDuration.inMicroseconds / 1000]..sort();
      final raster = [for (final f in t) f.rasterDuration.inMicroseconds / 1000]..sort();
      double p(List<double> l, double q) => l[((l.length - 1) * q).round()];
      final slow = total.where((v) => v > 33.4).length;
      return '$what: ${t.length} frames, total p50 ${p(total, .5).toStringAsFixed(1)} '
          'p90 ${p(total, .9).toStringAsFixed(1)} max ${total.last.toStringAsFixed(1)} ms, '
          'build p90 ${p(build, .9).toStringAsFixed(1)}, raster p90 ${p(raster, .9).toStringAsFixed(1)}, '
          'over 33 ms: $slow';
    }

    bb.note(summary('scroll', scrolling));
    bb.note(summary('drag', dragging));
    bb.note('debug build');
    await bb.shot('after');
    for (final t in [scrolling, dragging]) {
      expect(t, isNotEmpty);
      final total = [for (final f in t) f.totalSpan.inMicroseconds / 1000]..sort();
      expect(total[((total.length - 1) * .9).round()], lessThan(50), reason: 'p90 over 50 ms');
    }
  });

  bbCase('B14', '连续快速拖动 5 张卡片，最终顺序和服务端一致', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'B14');
    addTearDown(scratch.remove);
    final titles = [for (var i = 1; i <= 6; i++) 'E-Q B14 card $i $runStamp'];
    for (final t in titles) {
      await scratch.task(t);
    }
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(titles.last));
    await bb.pumpFor(const Duration(seconds: 1));
    for (final t in titles.take(5)) {
      await _dragTo(bb, t, scratch.nameOf(1), below: 40);
      await bb.tester.pump(const Duration(milliseconds: 100));
    }
    await bb.pumpFor(const Duration(seconds: 5));
    await bb.shot('after-drags');
    final shown = bb.orderIn(scratch.nameOf(1), titles);
    final stored = await scratch.titlesIn(1);
    bb.note('screen $shown; server $stored');
    expect(shown, stored);
    expect(shown.length, 5);
    await bb.restart();
    await bb.openProject(scratch.name);
    await bb.see(bb.card(titles.first));
    await bb.pumpFor(const Duration(seconds: 1));
    expect(bb.orderIn(scratch.nameOf(1), titles), stored);
    await bb.shot('after-restart');
  });

  bbCase('B15', '打开空项目有空状态，能添加任务', (bb) async {
    final owner = await Api.signIn(Env.owner);
    await bb.start(Env.owner);
    await bb.openProject('E-Empty');
    await bb.pumpFor(const Duration(seconds: 2));
    await bb.shot('empty');
    final texts = bb.screenTexts();
    bb.note('screen: ${texts.join(' / ')}');
    expect(
      texts.any((t) => RegExp('no task|empty|nothing|add', caseSensitive: false).hasMatch(t)),
      isTrue,
      reason: 'No empty state',
    );
    final title = 'E-Q B15 first $runStamp';
    await bb.tap(bb.tip('New task'));
    await bb.type(bb.field('Task title'), title);
    await bb.tap(find.widgetWithText(FilledButton, 'Create').hitTestable());
    await bb.see(bb.card(title), seconds: 10);
    await bb.shot('added');
    final made = await bb.server('the new task', () async {
      return (await owner.boardTasks(Env.emptyProject))
          .where((t) => t['title'] == title)
          .firstOrNull;
    });
    await owner.deleteTask(made['id'] as String);
  });
}

List<Rect> _rectsOf(Bb bb, Finder finder) => [
  for (final e in finder.evaluate()) bb.tester.getRect(find.byElementPredicate((x) => x == e)),
];

/// Opens [title]'s menu the way this device does: a right click on macOS, a long press on an
/// iPad or a phone. Trying twice, in case the first press was too short.
Future<void> _menu(Bb bb, String title) async {
  for (var i = 0; i < 2; i++) {
    await bb.openMenu(bb.card(title));
    if (await bb.until(() => bb.visible(bb.text('Move to')), seconds: 4)) return;
    bb.note(
      'the menu did not open at attempt ${i + 1} (${isMacOS ? 'right click' : 'long press'})',
    );
    await bb.pumpFor(const Duration(seconds: 1));
  }
  await bb.dumpScreen('menu-missing');
  throw TestFailure('The card menu did not open again');
}

Future<String> _id(Api api, Scratch scratch, String title) async =>
    (await api.boardTasks(scratch.id)).firstWhere((t) => t['title'] == title)['id'] as String;

bool _same(List<String> stored, List<String> shown) =>
    stored.where(shown.contains).toList().join('|') == shown.join('|');
