// KAN-52 筛选和列表：S1 到 S6。
import 'bb.dart';

/// A project with five tasks that differ in every way the filters look at.
class _Data {
  late Scratch scratch;
  late Api owner;
  late List<Map<String, dynamic>> tasks;
  final red = 'E-QL red $runStamp';
  final blue = 'E-QL blue $runStamp';

  List<String> get titles => [for (final t in tasks) t['title'] as String];

  Future<void> make(String what) async {
    owner = await Api.signIn(Env.owner);
    scratch = await Scratch.make(owner, what);
    final past = DateTime.now().toUtc().subtract(const Duration(days: 3)).toIso8601String();
    final future = DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String();
    final a = await scratch.task(
      'E-Q S apple one $runStamp',
      priority: 'low',
      userId: Env.owner.id,
      dueDate: past,
    );
    final b = await scratch.task(
      'E-Q S apple two $runStamp',
      column: 1,
      priority: 'high',
      userId: Env.member.id,
    );
    final c = await scratch.task(
      'E-Q S banana three $runStamp',
      column: 2,
      priority: 'high',
      userId: Env.owner.id,
      dueDate: future,
    );
    final d = await scratch.task('E-Q S banana four $runStamp', dueDate: past);
    final e = await scratch.task(
      'E-Q S cherry five $runStamp',
      column: 3,
      priority: 'urgent',
      userId: Env.member.id,
    );
    await owner.addLabel(a['id'] as String, red, '#ef4444');
    await owner.addLabel(e['id'] as String, red, '#ef4444');
    await owner.addLabel(b['id'] as String, blue, '#3b82f6');
    await owner.addLabel(c['id'] as String, blue, '#3b82f6');
    tasks = [a, b, c, d, e];
    addTearDown(scratch.remove);
  }

  /// What the server's data says a filter should leave, by title.
  Set<String> expected({
    String? text,
    String? assignee,
    String? priority,
    String? label,
    bool overdue = false,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return {
      for (final (i, t) in tasks.indexed)
        if ((text == null || (t['title'] as String).toLowerCase().contains(text.toLowerCase())) &&
            (assignee == null || t['userId'] == assignee) &&
            (priority == null || t['priority'] == priority) &&
            (label == null || (label == red ? [0, 4] : [1, 2]).contains(i)) &&
            (!overdue ||
                (t['dueDate'] != null &&
                    DateTime.parse(t['dueDate'] as String).toLocal().isBefore(today))))
          t['title'] as String,
    };
  }
}

/// Every title of [titles] the board shows, swiping through all of its columns.
Future<Set<String>> _shown(Bb bb, List<String> titles, List<String> columns) async {
  final found = <String>{};
  await bb.tester.drag(bb.boardScroll, const Offset(4000, 0));
  await bb.pumpFor(const Duration(milliseconds: 400));
  for (final column in columns) {
    await bb.scrollBoardTo(column);
    for (final t in titles) {
      if (bb.visible(bb.card(t))) found.add(t);
    }
  }
  return found;
}

/// Closes the filter menu, if it is open.
Future<void> _closeMenu(Bb bb) async {
  for (var i = 0; i < 3 && bb.visible(bb.text('Overdue only')); i++) {
    await bb.escape();
  }
}

/// Picks [option] in the filter menu's [entry], a list with a Save button.
Future<void> _pick(Bb bb, String entry, String option) async {
  await bb.tap(bb.filtersButton);
  await bb.tap(bb.label(entry).hitTestable());
  await bb.tap(bb.containing(option).last);
  if (bb.visible(bb.text('Save'))) await bb.tap(bb.text('Save'));
  await _closeMenu(bb);
}

Future<void> _toggle(Bb bb, String entry) async {
  await bb.tap(bb.filtersButton);
  await bb.tap(bb.label(entry).hitTestable());
  await _closeMenu(bb);
}

Future<void> _reset(Bb bb) async {
  if (bb.visible(bb.tip('Reset'))) await bb.tap(bb.tip('Reset'));
  if (bb.filterText().isNotEmpty) await bb.typeFilter('');
  await bb.pumpFor(const Duration(milliseconds: 600));
}

void main() {
  blackBoxModule();

  bbCase('S1', '单独和组合使用文字、负责人、优先级、标签、逾期，结果和 API 一致', (bb) async {
    final data = _Data();
    await data.make('S1');
    final columns = [for (var i = 0; i < 4; i++) data.scratch.nameOf(i)];
    await bb.start(Env.owner);
    await bb.openProject(data.scratch.name);
    await bb.see(bb.card(data.titles.first));
    final all = await _shown(bb, data.titles, columns);
    expect(all, data.titles.toSet(), reason: 'Not every task shows before filtering');
    final results = <String>[];

    Future<void> check(String name, Set<String> want) async {
      await bb.pumpFor(const Duration(seconds: 1));
      final got = await _shown(bb, data.titles, columns);
      await bb.shot(name);
      results.add(
        '$name ${got.length == want.length && got.containsAll(want) ? 'ok' : 'got $got want $want'}',
      );
      expect(got, want, reason: name);
    }

    final failures = <String>[];
    Future<void> run(String name, Future<void> Function() apply, Set<String> want) async {
      try {
        await apply();
        await check(name, want);
      } catch (e) {
        failures.add('$name: $e');
      }
      await _closeMenu(bb);
      await _reset(bb);
    }

    await run('text', () => bb.typeFilter('apple'), data.expected(text: 'apple'));
    await run(
      'assignee',
      () => _pick(bb, 'Assignee', Env.member.name),
      data.expected(assignee: Env.member.id),
    );
    await run('me', () => _toggle(bb, 'Me'), data.expected(assignee: Env.owner.id));
    await run('priority', () => _pick(bb, 'Priority', 'High'), data.expected(priority: 'high'));
    await run('label', () => _pick(bb, 'Labels', data.blue), data.expected(label: data.blue));
    await run('overdue', () => _toggle(bb, 'Overdue only'), data.expected(overdue: true));
    await run('text+overdue', () async {
      await bb.typeFilter('banana');
      await _toggle(bb, 'Overdue only');
    }, data.expected(text: 'banana', overdue: true));
    await run('me+priority+label', () async {
      await _toggle(bb, 'Me');
      await _pick(bb, 'Priority', 'High');
      await _pick(bb, 'Labels', data.blue);
    }, data.expected(assignee: Env.owner.id, priority: 'high', label: data.blue));
    for (final r in results) {
      bb.note(r);
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbCase('S2', '输入不存在的文字，所有列显示同一种提示', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Board');
    await bb.typeFilter('zzzz no such task $runStamp');
    await bb.pumpFor(const Duration(seconds: 2));
    final messages = <String, String>{};
    await bb.tester.drag(bb.boardScroll, const Offset(4000, 0));
    await bb.pumpFor(const Duration(milliseconds: 400));
    for (final column in boardColumnNames) {
      await bb.scrollBoardTo(column);
      final header = bb.rectOf(bb.text(column).hitTestable());
      final under = [
        for (final e in find.byType(RichText).hitTestable().evaluate())
          if (() {
            final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
            return r.top > header.bottom + 4 &&
                r.left >= header.left - 40 &&
                r.left < header.left + 260;
          }())
            (e.widget as RichText).text.toPlainText(),
      ].where((t) => t.trim().length > 3 && t.trim() != 'Add task').toList();
      messages[column] = under.join(' / ');
      await bb.shot('column-${boardColumnNames.indexOf(column)}');
    }
    bb.note('$messages');
    expect(messages.values.toSet(), hasLength(1), reason: 'Columns say different things');
    expect(messages.values.first, isNotEmpty);
  });

  bbCase('S3', '查看筛选数量并清除，数量正确，一键恢复', (bb) async {
    final data = _Data();
    await data.make('S3');
    final columns = [for (var i = 0; i < 4; i++) data.scratch.nameOf(i)];
    await bb.start(Env.owner);
    await bb.openProject(data.scratch.name);
    await bb.see(bb.card(data.titles.first));
    await _pick(bb, 'Priority', 'High');
    await _pick(bb, 'Labels', data.blue);
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('two-filters');
    final badge = bb.rectOf(bb.filtersButton).inflate(14);
    final two = find.byType(RichText).evaluate().any((e) {
      final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
      return badge.overlaps(r) && (e.widget as RichText).text.toPlainText().trim() == '2';
    });
    expect(two, isTrue, reason: 'The filter button does not say 2');
    expect(
      await _shown(bb, data.titles, columns),
      data.expected(priority: 'high', label: data.blue),
    );
    await bb.tap(bb.tip('Reset'));
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('reset');
    expect(await _shown(bb, data.titles, columns), data.titles.toSet());
    expect(bb.showing(bb.tip('Reset')), isFalse, reason: 'Reset is still offered');
  });

  bbCase('S4', '切换视图保留筛选，切项目清除', (bb) async {
    final data = _Data();
    await data.make('S4');
    await bb.start(Env.owner);
    await bb.openProject(data.scratch.name);
    await bb.see(bb.card(data.titles.first));
    await bb.typeFilter('apple');
    await _pick(bb, 'Priority', 'High');
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.tap(bb.tip('List view'));
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('list-filtered');
    final inList = {
      for (final t in data.titles)
        if (bb.showing(bb.card(t))) t,
    };
    expect(
      inList,
      data.expected(text: 'apple', priority: 'high'),
      reason: 'The list lost the filter',
    );
    await bb.openProject('E-Empty');
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('other-project');
    expect(bb.filterText(), isEmpty, reason: 'The text filter came along');
    expect(bb.showing(bb.tip('Reset')), isFalse, reason: 'A filter came along');
  });

  bbCase('S5', '显示和隐藏已计划、已归档', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'S5');
    addTearDown(scratch.remove);
    final planned = await scratch.task('E-Q S5 planned $runStamp');
    final archived = await scratch.task('E-Q S5 archived $runStamp');
    final normal = await scratch.task('E-Q S5 normal $runStamp');
    await owner.setStatus(planned['id'] as String, 'planned');
    await owner.setStatus(archived['id'] as String, 'archived');
    final p = planned['title'] as String;
    final a = archived['title'] as String;
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.see(bb.card(normal['title'] as String));
    await bb.pumpFor(const Duration(seconds: 1));
    final columns = [for (var i = 0; i < 4; i++) scratch.nameOf(i), 'Planned', 'Archived'];
    Future<Set<String>> shown() async {
      final found = <String>{};
      await bb.tester.drag(bb.boardScroll, const Offset(4000, 0));
      await bb.pumpFor(const Duration(milliseconds: 300));
      for (var i = 0; i < 12; i++) {
        for (final t in [p, a]) {
          if (bb.visible(bb.card(t))) found.add(t);
        }
        await bb.tester.drag(bb.boardScroll, const Offset(-300, 0));
        await bb.pumpFor(const Duration(milliseconds: 200));
      }
      return found;
    }

    bb.note('columns looked through: $columns');
    expect(await shown(), isEmpty, reason: 'Planned or archived shows by default');
    await _toggle(bb, 'Show planned');
    await bb.pumpFor(const Duration(seconds: 1));
    final withPlanned = await shown();
    await bb.shot('planned');
    expect(withPlanned, {p});
    await _toggle(bb, 'Show archived');
    await bb.pumpFor(const Duration(seconds: 1));
    final withBoth = await shown();
    await bb.shot('both');
    expect(withBoth, {p, a});
    // The menu now offers to hide them.
    await _toggle(bb, 'Hide planned');
    await _toggle(bb, 'Hide archived');
    await bb.pumpFor(const Duration(seconds: 1));
    expect(await shown(), isEmpty, reason: 'Hiding them again did not');
  });

  bbCase('S6', '列表按状态分组；宽屏字段和网页端一致，窄屏显示编号、标题、负责人', (bb) async {
    final data = _Data();
    await data.make('S6');
    await bb.start(Env.owner);
    await bb.openProject(data.scratch.name);
    await bb.see(bb.card(data.titles.first));
    await bb.tap(bb.tip('List view'));
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('list');
    // Groups, in the board's order, each over its own tasks: what the list says, top to bottom,
    // read while scrolling it, since a short screen shows only part of it.
    final groups = [for (var i = 0; i < 4; i++) data.scratch.nameOf(i)];
    final sequence = <String>[];
    final list = find
        .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .evaluate()
        .where((e) => bb.tester.getRect(find.byElementPredicate((x) => x == e)).width > 300)
        .toList();
    final scroller = find.byElementPredicate((e) => e == list.last);
    final box = bb.rectOf(scroller);
    for (var i = 0; i < 12; i++) {
      final here = <(double, String)>[
        for (final name in [...groups, ...data.titles])
          for (final e in bb.card(name).evaluate())
            if (() {
              final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
              return r.top >= box.top - 1 && r.bottom <= box.bottom + 1;
            }())
              (bb.tester.getRect(find.byElementPredicate((x) => x == e)).top, name),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      for (final (_, name) in here) {
        if (!sequence.contains(name)) sequence.add(name);
      }
      if (data.titles.every(sequence.contains) && groups.every(sequence.contains)) break;
      await bb.tester.timedDragFrom(
        Offset(box.center.dx, box.bottom - 40),
        Offset(0, -(box.height * 0.5)),
        const Duration(milliseconds: 700),
      );
      await bb.pumpFor(const Duration(milliseconds: 400));
    }
    bb.note('the list reads: ${sequence.join(' / ')}');
    final order = [for (final g in groups) sequence.indexOf(g)];
    expect(order.every((i) => i >= 0), isTrue, reason: 'Some groups are missing: $order');
    for (var i = 1; i < 4; i++) {
      expect(order[i], greaterThan(order[i - 1]), reason: 'Groups out of order');
    }
    for (final (i, t) in data.tasks.indexed) {
      final at = sequence.indexOf(t['title'] as String);
      final group = [for (var g = 0; g < 4; g++) g]
          .lastWhere((g) => order[g] < at, orElse: () => -1);
      final want = [0, 1, 2, 0, 3][i];
      expect(group, want, reason: '${t['title']} is under group $group');
    }
    // Back to the top, then to the fullest row.
    await bb.tester.fling(scroller, const Offset(0, 20000), 8000);
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.tester.scrollUntilVisible(
      bb.card(data.tasks[2]['title'] as String),
      150,
      scrollable: scroller,
    );
    await bb.pumpFor(const Duration(milliseconds: 500));
    // The fullest row: high priority, assigned, a label, a due date.
    final c = data.tasks[2];
    final key = '${data.scratch.project['slug']}-${c['number']}';
    final rowNode = bb.tester.getSemantics(bb.card(c['title'] as String));
    final said = '${rowNode.label} | tooltip ${rowNode.tooltip}';
    bb.note('row says: $said');
    final rowRect = bb.rectOf(bb.card(c['title'] as String));
    final onRow = [
      for (final e in find.byType(RichText).evaluate())
        if ((bb.tester.getRect(find.byElementPredicate((x) => x == e)).center.dy -
                    rowRect.center.dy)
                .abs() <
            20)
          (e.widget as RichText).text.toPlainText(),
    ].join(' | ');
    final tips = [
      for (final e in find.byType(Tooltip).evaluate())
        if ((bb.tester.getRect(find.byElementPredicate((x) => x == e)).center.dy -
                    rowRect.center.dy)
                .abs() <
            20)
          (e.widget as Tooltip).message ?? '',
    ].join(' | ');
    bb.note('row texts: $onRow; tooltips: $tips');
    final everything = '$said | $onRow | $tips';
    expect(everything, contains(key), reason: 'No task number');
    expect(everything, contains(c['title']), reason: 'No title');
    expect(
      everything.contains(Env.owner.name) || everything.contains('EO'),
      isTrue,
      reason: 'No assignee',
    );
    if (bb.wide) {
      final due = DateTime.parse(c['dueDate'] as String).toLocal();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final missing = [
        if (!everything.contains('High')) 'priority',
        if (!everything.contains(data.blue)) 'label',
        if (!everything.contains(months[due.month - 1]) &&
            !everything.contains('${due.month}/${due.day}'))
          'due date',
      ];
      expect(missing, isEmpty, reason: 'Wide rows lack what the web shows: $missing');
    }
  });
}
