// KAN-52 父子折叠：F1 到 F9。F9 在列表视图把 F1 到 F5 再走一遍。
import 'bb.dart';

const _grand = 'E-三层 祖父';
const _parent = 'E-三层 父';
const _child = 'E-三层 子';
const _crossParent = 'E-跨列 父';
const _crossChild = 'E-跨列 子';

/// The rects of the elements [finder] finds.
List<Rect> _rects(Bb bb, Finder finder) => [
  for (final e in finder.evaluate()) bb.tester.getRect(find.byElementPredicate((x) => x == e)),
];

/// The title of [title]'s own card or row: the one in [column], top-most.
Rect? _titleRect(Bb bb, String title, String column, {required bool list}) {
  final hits = <Rect>[];
  for (final e in bb.card(title).evaluate()) {
    final f = find.byElementPredicate((x) => x == e);
    final where = list ? _groupOf(bb, f) : bb.columnOf(f);
    if (where == column) hits.add(bb.tester.getRect(f));
  }
  if (hits.isEmpty) return null;
  hits.sort((a, b) => a.top.compareTo(b.top));
  return hits.first;
}

/// The list group [row] is in: the nearest group title above it.
String? _groupOf(Bb bb, Finder row) {
  final box = bb.rectOf(row);
  String? best;
  var bestTop = double.negativeInfinity;
  for (final name in boardColumnNames) {
    for (final r in _rects(bb, bb.text(name))) {
      if (r.top < box.top - 2 && r.top > bestTop && r.left < box.left + 40) {
        bestTop = r.top;
        best = name;
      }
    }
  }
  return best;
}

/// The expand or collapse button on [title]'s card or row.
Finder _toggle(Bb bb, Rect title, String tooltip) {
  final near = find.byTooltip(tooltip).evaluate().where((e) {
    final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
    return r.center.dy >= title.top - 60 &&
        r.center.dy <= title.bottom + 12 &&
        r.center.dx >= title.left - 170 &&
        r.center.dx <= title.left + 420;
  }).toList();
  near.sort((a, b) {
    double d(Element e) {
      final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
      return (r.center - title.center).distance;
    }

    return d(a).compareTo(d(b));
  });
  return find.byElementPredicate((e) => near.isNotEmpty && e == near.first);
}

/// A progress like 0/1 on [title]'s card or row.
String? _progress(Bb bb, Rect title) {
  for (final e in find.byType(RichText).evaluate()) {
    final text = (e.widget as RichText).text.toPlainText();
    if (!RegExp(r'^\d+ ?/ ?\d+$').hasMatch(text.trim())) continue;
    final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
    if (r.center.dy >= title.top - 60 &&
        r.center.dy <= title.bottom + 60 &&
        r.center.dx >= title.left - 90 &&
        r.center.dx <= title.left + 1100) {
      return text;
    }
  }
  return null;
}

/// The count beside [column]'s title.
int? _count(Bb bb, String column) {
  for (final h in _rects(bb, bb.text(column))) {
    for (final e in bb.containing(RegExp(r'^\d+ tasks?$')).evaluate()) {
      final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
      // Beside the title on a board, at the row's far end in a list.
      if ((r.center.dy - h.center.dy).abs() < 16 && r.left > h.left) {
        return int.parse(
          RegExp(r'\d+').firstMatch((e.widget as RichText).text.toPlainText())!.group(0)!,
        );
      }
    }
  }
  return null;
}

/// Brings [title] into view: in a list by scrolling down, on a board by swiping to [column].
Future<void> _reveal(Bb bb, String column, {required bool list, String? title}) async {
  if (list) {
    final target = bb.text(title ?? column);
    if (bb.visible(target)) return;
    final scroll = find
        .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .evaluate()
        .where((e) => bb.tester.getRect(find.byElementPredicate((x) => x == e)).width > 300)
        .toList();
    await bb.tester.scrollUntilVisible(
      target,
      400,
      scrollable: find.byElementPredicate((e) => e == scroll.last),
      maxScrolls: 80,
    );
    await bb.pumpFor(const Duration(milliseconds: 300));
    return;
  }
  await bb.scrollBoardTo(column);
}

Future<void> _openBoard(Bb bb, {required bool list}) async {
  await bb.openProject('E-Board');
  await bb.see(bb.text('需求池'));
  if (list && bb.showing(bb.tip('List view'))) await bb.tap(bb.tip('List view'));
  await bb.pumpFor(const Duration(seconds: 1));
}

/// F1 to F5, on the board or in the list.
void _cases(String prefix, {required bool list}) {
  String id(String f) => list ? 'F9-$f' : f;
  final where = list ? '列表' : '看板';

  bbCase(id('F1'), '$where：父子同列默认只显示父卡片，有进度和展开按钮', (bb) async {
    await bb.start(Env.owner);
    await _openBoard(bb, list: list);
    await _reveal(bb, 'To Do', list: list, title: _grand);
    final grand = _titleRect(bb, _grand, 'To Do', list: list);
    await bb.shot('collapsed');
    expect(grand, isNotNull, reason: '$_grand is not in To Do');
    expect(_titleRect(bb, _parent, 'To Do', list: list), isNull, reason: '$_parent shows');
    expect(_titleRect(bb, _child, 'To Do', list: list), isNull, reason: '$_child shows');
    final progress = _progress(bb, grand!);
    bb.note('progress "$progress"');
    expect(progress, isNotNull, reason: 'No progress on $_grand');
    expect(bb.showing(_toggle(bb, grand, 'Expand subtasks')), isTrue, reason: 'No expand button');
  });

  bbCase(id('F2'), '$where：展开后重启 App，子任务缩进显示，展开状态保留', (bb) async {
    await bb.start(Env.owner);
    await _openBoard(bb, list: list);
    await _reveal(bb, 'To Do', list: list, title: _grand);
    final grand = _titleRect(bb, _grand, 'To Do', list: list)!;
    await bb.tap(_toggle(bb, grand, 'Expand subtasks'));
    final parent = _titleRect(bb, _parent, 'To Do', list: list);
    await bb.shot('expanded');
    expect(parent, isNotNull, reason: 'Expanding showed no $_parent');
    await bb.restart();
    await _openBoard(bb, list: list);
    await _reveal(bb, 'To Do', list: list, title: _grand);
    final g = _titleRect(bb, _grand, 'To Do', list: list)!;
    final p = _titleRect(bb, _parent, 'To Do', list: list);
    await bb.shot('after-restart');
    expect(p, isNotNull, reason: 'The expansion was lost');
    bb.note('$_grand at x=${g.left.round()}, $_parent at x=${p!.left.round()}');
    expect(p.left, greaterThan(g.left + 6), reason: 'The subtask is not indented');
  });

  bbCase(id('F3'), '$where：逐层展开三层任务，每层能单独折叠', (bb) async {
    await bb.start(Env.owner);
    await _openBoard(bb, list: list);
    await _reveal(bb, 'To Do', list: list, title: _grand);
    Rect? at(String t) => _titleRect(bb, t, 'To Do', list: list);
    await bb.tap(_toggle(bb, at(_grand)!, 'Expand subtasks'));
    expect(at(_parent), isNotNull, reason: 'No $_parent');
    expect(at(_child), isNull, reason: '$_child shows before its parent is expanded');
    final parentToggle = _toggle(bb, at(_parent)!, 'Expand subtasks');
    expect(bb.showing(parentToggle), isTrue, reason: '$_parent has no expand button');
    await bb.tap(parentToggle);
    final child = at(_child);
    await bb.shot('three-levels');
    expect(child, isNotNull, reason: 'No $_child');
    expect(child!.left, greaterThan(at(_parent)!.left + 6), reason: '$_child not indented');
    // Only the middle level folds.
    await bb.tap(_toggle(bb, at(_parent)!, 'Collapse subtasks'));
    expect(at(_child), isNull, reason: 'Folding $_parent left $_child');
    expect(at(_parent), isNotNull);
    await bb.shot('middle-folded');
    // The top level folds everything under it.
    await bb.tap(_toggle(bb, at(_grand)!, 'Collapse subtasks'));
    expect(at(_parent), isNull);
    expect(at(_child), isNull);
    await bb.shot('top-folded');
  });

  bbCase(id('F4'), '$where：子任务和父任务不同列，子任务单独显示并标注父任务标题', (bb) async {
    await bb.start(Env.owner);
    await _openBoard(bb, list: list);
    await _reveal(bb, 'In Progress', list: list, title: _crossChild);
    final child = _titleRect(bb, _crossChild, 'In Progress', list: list);
    await bb.shot('cross-column');
    expect(child, isNotNull, reason: '$_crossChild is not in In Progress');
    // The parent's title, on the child's card or row.
    final mention = _rects(bb, bb.containing(_crossParent)).where(
      (r) =>
          (r.center.dy - child!.center.dy).abs() < 60 &&
          r.center.dx > child.left - 90 &&
          r.center.dx < child.left + 1100,
    );
    expect(mention, isNotEmpty, reason: 'The child does not name $_crossParent');
  });

  bbCase(id('F5'), '$where：列头数量等于全部任务，不随折叠变化', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final columns = await owner.columns(Env.boardProject);
    final tasks = await owner.boardTasks(Env.boardProject);
    int count(String name) {
      final slug = columns.firstWhere((c) => c['name'] == name)['slug'];
      return tasks.where((t) => t['status'] == slug).length;
    }

    await bb.start(Env.owner);
    await _openBoard(bb, list: list);
    final seen = <String>[];
    for (final column in ['To Do', 'In Progress', 'In Review']) {
      await _reveal(bb, column, list: list);
      final shown = _count(bb, column);
      seen.add('$column ${count(column)}/$shown');
      expect(shown, count(column), reason: '$column says $shown, the server has ${count(column)}');
    }
    await _reveal(bb, 'To Do', list: list, title: _grand);
    await bb.tap(_toggle(bb, _titleRect(bb, _grand, 'To Do', list: list)!, 'Expand subtasks'));
    await bb.shot('expanded');
    expect(_count(bb, 'To Do'), count('To Do'), reason: 'Expanding changed the count');
    bb.note(seen.join(', '));
  });
}

void main() {
  blackBoxModule();

  _cases('', list: false);

  bbCase('F6', '拖动父任务，只有父任务移动，子任务状态不变', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'F6');
    addTearDown(scratch.remove);
    final parent = await scratch.task('E-Q F6 parent $runStamp');
    final child = await scratch.task('E-Q F6 child $runStamp');
    await owner.relate(parent['id'] as String, child['id'] as String, 'subtask');
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    final title = parent['title'] as String;
    await bb.see(bb.card(title));
    final header = bb.rectOf(bb.text(scratch.nameOf(1)).hitTestable());
    await bb.dragCard(title, Offset(header.center.dx, header.bottom + 120));
    await bb.server(
      'the parent moved',
      () async => (await owner.task(parent['id'] as String))['status'] == scratch.slugOf(1),
    );
    await bb.pumpFor(const Duration(seconds: 2));
    await bb.shot('parent-moved');
    expect((await owner.task(child['id'] as String))['status'], scratch.slugOf(0));
    expect(bb.columnOf(bb.card(title)), scratch.nameOf(1));
    expect(
      bb.columnOf(bb.card(child['title'] as String)),
      scratch.nameOf(0),
      reason: 'The child is not on its own in ${scratch.nameOf(0)}',
    );
  });

  bbCase('F7', '筛选命中子任务但没命中父任务，子任务单独显示', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Board');
    await bb.type(bb.field('Filter tasks…'), _child);
    await bb.pumpFor(const Duration(seconds: 2));
    await bb.scrollBoardTo('To Do');
    await bb.shot('filtered');
    expect(bb.visible(bb.card(_child)), isTrue, reason: '$_child is hidden under its parents');
    expect(bb.showing(bb.card(_grand)), isFalse);
  });

  bbCase('F8', '打开多父和成环的数据，不崩溃，不卡死', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Board');
    for (final column in ['In Progress', 'In Review']) {
      await bb.scrollBoardTo(column);
      await bb.pumpFor(const Duration(seconds: 1));
      await bb.shot(column.replaceAll(' ', '-'));
      // Opens whatever opens, three times over, and the app keeps answering.
      for (var round = 0; round < 3; round++) {
        final toggles = find.byTooltip('Expand subtasks').hitTestable().evaluate().toList();
        for (final e in toggles.take(4)) {
          final watch = Stopwatch()..start();
          await bb.tester.tap(find.byElementPredicate((x) => x == e), warnIfMissed: false);
          await bb.tester.pump(const Duration(milliseconds: 100));
          expect(watch.elapsed, lessThan(const Duration(seconds: 3)), reason: 'The app hung');
        }
        await bb.pumpFor(const Duration(milliseconds: 500));
      }
      await bb.shot('${column.replaceAll(' ', '-')}-expanded');
    }
    final shown = [
      for (final t in ['E-双父 子', 'E-双父 父一', 'E-双父 父二', 'E-成环 甲', 'E-成环 乙', 'E-成环 丙'])
        if (bb.showing(bb.card(t))) t,
    ];
    bb.note('on screen: $shown');
    expect(shown.where((t) => t.startsWith('E-双父')), isNotEmpty);
    expect(shown.where((t) => t.startsWith('E-成环')), isNotEmpty);
  });

  _cases('F9', list: true);
}
