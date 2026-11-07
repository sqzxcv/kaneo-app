// KAN-52 新建任务：N1 到 N6。
import 'bb.dart';

Finder get _create => find.widgetWithText(FilledButton, 'Create');

/// The new task form's title field.
Finder _title(Bb bb) => bb.field('Task title');

bool _enabled(Bb bb, Finder button) =>
    bb.tester.widget<ButtonStyleButton>(button.first).onPressed != null;

void main() {
  blackBoxModule();

  bbCase('N1', '宽屏新建是弹窗，窄屏是全屏', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'N1');
    addTearDown(scratch.remove);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.tap(bb.tip('New task'));
    await bb.see(_title(bb));
    await bb.pumpFor(const Duration(milliseconds: 500));
    final field = bb.rectOf(_title(bb));
    await bb.shot(bb.wide ? 'wide' : 'narrow');
    bb.note('window ${bb.window}; title field $field');
    if (bb.wide) {
      expect(field.left, greaterThan(bb.window.width * 0.12), reason: 'Not a dialog');
      expect(field.right, lessThan(bb.window.width * 0.88), reason: 'Not a dialog');
      // The board is still there behind it.
      expect(bb.showing(bb.text(scratch.nameOf(0))), isTrue);
    } else {
      expect(field.width, greaterThan(bb.window.width * 0.8), reason: 'Not full screen');
      expect(bb.visible(bb.filtersButton), isFalse, reason: 'The board shows');
    }
  });

  bbCase('N2', '从某列点添加任务，状态默认为该列', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'N2');
    addTearDown(scratch.remove);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    final column = scratch.nameOf(2);
    await bb.scrollBoardTo(column);
    final header = bb.rectOf(bb.text(column).hitTestable());
    final add =
        // On the column's title row, scrolled into view below if a narrow screen hides it.
        find.byTooltip('Add task').evaluate().where((e) {
          final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
          return (r.center.dy - header.center.dy).abs() < 20 && r.left > header.left;
        }).toList()..sort(
          (a, b) => bb.tester
              .getRect(find.byElementPredicate((x) => x == a))
              .left
              .compareTo(bb.tester.getRect(find.byElementPredicate((x) => x == b)).left),
        );
    expect(add, isNotEmpty, reason: '$column has no add button');
    await bb.tap(find.byElementPredicate((e) => e == add.first));
    await bb.see(_title(bb));
    await bb.shot('form');
    final shown = bb.showing(bb.text(column));
    expect(shown, isTrue);
    final title = 'E-Q N2 task $runStamp';
    await bb.type(_title(bb), title);
    await bb.tap(_create.hitTestable());
    final made = await bb.server('the task', () async {
      return (await owner.boardTasks(scratch.id)).where((t) => t['title'] == title).firstOrNull;
    });
    expect(made['status'], scratch.slugOf(2), reason: 'Made in ${made['status']}');
  });

  bbCase('N3', '不填标题不能提交；提交失败后内容不丢', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'N3');
    addTearDown(scratch.remove);
    final proxy = Proxy();
    await proxy.start();
    addTearDown(proxy.close);
    await bb.launch();
    await bb.signIn(Env.owner, server: proxy.url);
    await bb.openProject(scratch.name);
    await bb.tap(bb.tip('New task'));
    await bb.see(_title(bb));
    await bb.see(_create);
    expect(_enabled(bb, _create), isFalse, reason: 'Create works without a title');
    await bb.tap(_create);
    expect(bb.showing(_title(bb)), isTrue, reason: 'The form went away');
    await bb.shot('no-title');

    final title = 'E-Q N3 kept $runStamp';
    final body = 'A description that must survive $runStamp';
    await bb.type(_title(bb), title);
    await bb.type(bb.field('Add a description for your task...'), body);
    proxy
      ..mode = ProxyMode.fail500
      ..failPattern = '/api/task/${scratch.id}'
      ..failMethod = 'POST';
    final before = bb.screenTexts().toSet();
    await bb.tap(_create.hitTestable());
    final said = await bb.until(
      () => bb.screenTexts().toSet().difference(before).any((t) => t.length > 6),
      seconds: 15,
    );
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('failed');
    bb.note('shown: ${bb.screenTexts().toSet().difference(before).join(' / ')}');
    proxy.mode = ProxyMode.pass;
    expect(said, isTrue, reason: 'Nothing said it failed');
    expect(bb.showing(bb.titleField(title)), isTrue, reason: 'The title was lost');
    expect(bb.showing(bb.titleField(body)), isTrue, reason: 'The description was lost');
    expect((await owner.boardTasks(scratch.id)).where((t) => t['title'] == title), isEmpty);
  }, simulated: '提交失败用测试里的本地代理对创建请求返回 500 模拟');

  bbCase('N4', '提交成功，卡片立刻出现在对应列', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'N4');
    addTearDown(scratch.remove);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.tap(bb.tip('New task'));
    final title = 'E-Q N4 task $runStamp';
    await bb.type(_title(bb), title);
    await bb.tap(_create.hitTestable());
    final watch = Stopwatch()..start();
    final there = await bb.until(() => bb.visible(bb.card(title)), seconds: 10);
    bb.note('on the board ${watch.elapsedMilliseconds} ms after Create');
    await bb.shot('created');
    expect(there, isTrue);
    expect(watch.elapsedMilliseconds, lessThan(2000), reason: 'Not at once');
    expect(
      bb.columnOf(bb.card(title), names: [for (var i = 0; i < 4; i++) scratch.nameOf(i)]),
      scratch.nameOf(0),
    );
  });

  bbCase('N5', '在有必填自定义字段的项目新建，成功', (bb) async {
    final owner = await Api.signIn(Env.owner);
    await bb.start(Env.owner);
    await bb.openProject('E-Required field');
    await bb.tap(bb.tip('New task'));
    final title = 'E-Q N5 task $runStamp';
    await bb.type(_title(bb), title);
    await bb.shot('form');
    final before = bb.screenTexts().toSet();
    await bb.tap(_create.hitTestable());
    final made = await bb.until(() => bb.visible(bb.card(title)), seconds: 10);
    await bb.shot('after');
    bb.note('new on screen: ${bb.screenTexts().toSet().difference(before).take(8).join(' / ')}');
    final stored = (await owner.boardTasks(Env.requiredProject))
        .where((t) => t['title'] == title)
        .toList();
    for (final t in stored) {
      await owner.deleteTask(t['id'] as String);
    }
    expect(made, isTrue, reason: 'The card did not appear');
    expect(stored, hasLength(1), reason: 'The server has ${stored.length}');
  });

  bbCase('N6', '内联新建标签，标签创建并选中', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'N6');
    addTearDown(scratch.remove);
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.tap(bb.tip('New task'));
    final title = 'E-Q N6 task $runStamp';
    await bb.type(_title(bb), title);
    // A chip in the wide dialog; a row whose value opens it on a narrow page.
    final value = bb.valueOf('Labels');
    await bb.tap(
      bb.showing(value) && bb.valueText('Labels').contains('label') ? value : bb.label('Labels'),
    );
    final name = 'E-QL N6 $runStamp';
    await bb.type(bb.field('Search or create'), name);
    await bb.pumpFor(const Duration(milliseconds: 500));
    await bb.shot('typed');
    // The option that makes it.
    final make = bb.containing(RegExp('(Create|Add).*${RegExp.escape(name)}')).hitTestable();
    await bb.tap(make);
    await bb.pumpFor(const Duration(milliseconds: 500));
    if (bb.visible(bb.text('Save'))) await bb.tap(bb.text('Save').hitTestable());
    await bb.pumpFor(const Duration(milliseconds: 500));
    await bb.shot('picked');
    expect(bb.showing(bb.containing(name)), isTrue, reason: 'The label is not shown as picked');
    await bb.tap(_create.hitTestable());
    final made = await bb.server('the task', () async {
      return (await owner.boardTasks(scratch.id)).where((t) => t['title'] == title).firstOrNull;
    });
    final labels = await owner.taskLabels(made['id'] as String);
    bb.note('task labels: ${labels.map((l) => l['name']).toList()}');
    expect(labels.any((l) => l['name'] == name), isTrue, reason: 'The label is not on the task');
  });
}
