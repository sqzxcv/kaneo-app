// KAN-52 Markdown：M1 到 M6，用 E-Formats 的描述。
import 'bb.dart';

/// What each format's description must show once rendered, and what of its source must not show.
class _Format {
  const _Format(this.title, this.shows, {this.raw = const [], this.check});

  final String title;
  final List<String> shows;
  final List<String> raw;
  final Future<void> Function(Bb bb)? check;
}

final _formats = <_Format>[
  _Format(
    'E-格式 01 标题',
    ['一级标题', '二级标题', '三级标题', '标题下面的正文。'],
    raw: ['# '],
    check: (bb) async {
      final h = [
        for (final t in ['一级标题', '二级标题', '三级标题', '标题下面的正文。']) _height(bb, t),
      ];
      bb.note('heights $h');
      expect(
        h[0] > h[1] && h[1] > h[2] && h[2] >= h[3],
        isTrue,
        reason: 'Headings not by size: $h',
      );
    },
  ),
  const _Format(
    'E-格式 02 行内样式',
    ['粗体', '斜体', '删除线', '行内代码', '链接到 Kaneo'],
    raw: ['**', '~~', '`', '](', '[链接'],
  ),
  _Format(
    'E-格式 03 硬换行',
    ['第一行，行尾两个空格', '第二行，行尾反斜杠', '第三行'],
    raw: ['\\'],
    check: (bb) async {
      // One paragraph broken into three lines, or three lines of their own.
      final joined = _allTexts(bb).any((t) => t.contains('第一行，行尾两个空格\n第二行，行尾反斜杠\n第三行'));
      if (joined) return;
      final tops = {
        for (final t in ['第一行，行尾两个空格', '第二行，行尾反斜杠', '第三行']) _rect(bb, t).top.round(),
      };
      expect(tops, hasLength(3), reason: 'The lines are not on lines of their own');
    },
  ),
  _Format(
    'E-格式 04 嵌套无序列表',
    ['第一层 A', '第二层 A1', '第三层 A1a', '第二层 A2', '第一层 B'],
    raw: ['- '],
    check: (bb) async {
      final x = [
        for (final t in ['第一层 A', '第二层 A1', '第三层 A1a']) _rect(bb, t).left,
      ];
      expect(x[0] < x[1] && x[1] < x[2], isTrue, reason: 'Not indented by level: $x');
    },
  ),
  const _Format('E-格式 05 有序列表', ['第一步', '第二步', '第三步']),
  _Format(
    'E-格式 06 待办',
    ['没做完的事', '做完的事', '另一件没做完的事'],
    raw: ['[ ]', '[x]'],
    check: (bb) => _boxes(bb, checked: 1, unchecked: 2),
  ),
  _Format(
    'E-格式 07 嵌套待办',
    ['父待办', '做完的子待办', '没做完的子待办', '做完的父待办'],
    raw: ['[ ]', '[x]'],
    check: (bb) async {
      await _boxes(bb, checked: 2, unchecked: 2);
      expect(_rect(bb, '做完的子待办').left, greaterThan(_rect(bb, '父待办').left + 6));
    },
  ),
  _Format(
    'E-格式 08 引用',
    ['第一层引用', '嵌套的引用'],
    raw: ['> '],
    check: (bb) async {
      expect(_rect(bb, '嵌套的引用').left, greaterThan(_rect(bb, '第一层引用').left + 4));
    },
  ),
  const _Format('E-格式 09 代码块', ['void main() {', "  print('你好，Kaneo');"], raw: ['```']),
  const _Format('E-格式 10 分割线', ['分割线上面', '分割线下面'], raw: ['---']),
  const _Format(
    'E-格式 11 表格',
    ['名称', '状态', '数量', '甲', '进行中', '1', '乙', '已完成', '22'],
    raw: ['|', ':---'],
  ),
  _Format(
    'E-格式 12 Markdown 图片',
    const [],
    raw: ['![', 'raw.githubusercontent'],
    check: (bb) async => _image(bb),
  ),
  _Format(
    'E-格式 13 带宽度的 img',
    const [],
    raw: ['<img', 'width='],
    check: (bb) async {
      final r = await _image(bb);
      bb.note('picture ${r.width.round()} x ${r.height.round()}');
      expect((r.width - 120).abs(), lessThan(4), reason: 'Not 120 wide: ${r.width}');
    },
  ),
  _Format('E-格式 14 kaneo-mention', [Env.member.name], raw: ['<kaneo', 'kaneo-mention']),
  const _Format('E-格式 15 kaneo-attachment', ['OFL.txt'], raw: ['<kaneo', 'kaneo-attachment']),
  _Format(
    'E-格式 16 kaneo-issue-link',
    const [],
    raw: ['<kaneo', 'kaneo-issue-link'],
    check: (bb) async {
      final shown = _allTexts(bb).any((t) => RegExp(r'EBB-\d+|E-三层 祖父').hasMatch(t));
      expect(shown, isTrue, reason: 'The linked task is not named');
    },
  ),
  _Format(
    'E-格式 17 kaneo-embed',
    const [],
    raw: ['<kaneo', 'kaneo-embed'],
    check: (bb) async {
      final shown = _allTexts(bb).any((t) => t.contains('youtube') || t.contains('YouTube'));
      expect(shown, isTrue, reason: 'Nothing of the embed shows');
    },
  ),
];

Rect _rect(Bb bb, String text) =>
    bb.rectOf(bb.showing(bb.text(text)) ? bb.text(text) : bb.containing(text));

double _height(Bb bb, String text) {
  final f = bb.text(text);
  final e = f.evaluate().first;
  final w = e.widget;
  // The size of the letters, which a heading's line shows.
  if (w is RichText) return w.text.style?.fontSize ?? bb.rectOf(f).height;
  if (w is EditableText) return w.style.fontSize ?? bb.rectOf(f).height;
  return bb.rectOf(f).height;
}

/// Every text on screen, drawn or in a field, without the open task's title and the filter.
List<String> _allTexts(Bb bb) => [
  ...bb.screenTexts(),
  for (final e in find.byType(EditableText).evaluate()) (e.widget as EditableText).controller.text,
];

Future<void> _boxes(Bb bb, {required int checked, required int unchecked}) async {
  final lines = semanticsLines(bb.tester);
  final yes = lines.where((l) => RegExp(r'(^|\s)checked(\s|$)').hasMatch(l.trim())).length;
  final no = lines.where((l) => RegExp(r'(^|\s)unchecked(\s|$)').hasMatch(l.trim())).length;
  bb.note('checked $yes, unchecked $no');
  expect(yes, greaterThanOrEqualTo(checked), reason: 'Ticked boxes: $yes');
  expect(no, greaterThanOrEqualTo(unchecked), reason: 'Empty boxes: $no');
}

/// The description's picture, once it has loaded.
Future<Rect> _image(Bb bb) async {
  final loaded = find.byWidgetPredicate((w) => w is RawImage && w.image != null);
  final ok = await bb.until(
    () => loaded.evaluate().any((e) {
      final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
      return r.width > 40 && r.height > 40;
    }),
    seconds: 30,
  );
  if (!ok) {
    final failed = bb.showing(bb.containing('Image failed to load'));
    throw TestFailure(failed ? 'The picture failed to load' : 'No picture');
  }
  final e = loaded.evaluate().firstWhere((e) {
    final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
    return r.width > 40 && r.height > 40;
  });
  return bb.tester.getRect(find.byElementPredicate((x) => x == e));
}

/// Opens [title] from the E-Formats board, finding it with the board's filter.
Future<void> _open(Bb bb, String title) async {
  await bb.typeFilter(title);
  await bb.pumpFor(const Duration(milliseconds: 800));
  await bb.tap(bb.card(title).hitTestable());
  await bb.see(_titleField(title), seconds: 20);
  await bb.pumpFor(const Duration(seconds: 1));
}

Finder _titleField(String title) =>
    find.byWidgetPredicate((w) => w is EditableText && w.controller.text == title);

Future<void> _close(Bb bb) async {
  if (bb.visible(bb.tip('Close'))) {
    await bb.tap(bb.tip('Close').hitTestable());
  } else {
    await bb.back();
  }
  await bb.pumpFor(const Duration(milliseconds: 600));
}

/// The description as a text field, opened for editing by tapping what it shows.
Future<Finder> _edit(Bb bb, String source, Finder target, {bool beside = false}) async {
  final editor = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == source);
  if (beside) {
    // Beside what it shows, on the same line, where a link isn't.
    await bb.see(target);
    final r = bb.rectOf(target);
    await bb.tester.tapAt(Offset(r.right + 30, r.center.dy));
    await bb.pumpFor(const Duration(milliseconds: 400));
  } else {
    await bb.tap(target);
  }
  if (!await bb.until(() => bb.showing(editor), seconds: 5)) {
    throw TestFailure('Tapping the description did not open it for editing as it was stored');
  }
  return editor;
}

void main() {
  blackBoxModule();

  bbCase('M1', '17 种格式的描述都正确渲染', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Formats');
    final failures = <String>[];
    for (final (i, f) in _formats.indexed) {
      try {
        await _open(bb, f.title);
        for (final t in f.shows) {
          await bb.see(bb.containing(t), seconds: 10, reason: '"$t" is not shown');
        }
        final texts = _allTexts(bb).where((t) => t != f.title && !t.startsWith('E-格式')).toList();
        for (final r in f.raw) {
          final hit = texts.where((t) => t.contains(r)).toList();
          if (hit.isNotEmpty) throw TestFailure('Source "$r" shows: ${hit.first}');
        }
        await f.check?.call(bb);
        await bb.shot((i + 1).toString().padLeft(2, '0'));
        bb.note('${f.title}: ok');
      } catch (e) {
        await bb.shot('${(i + 1).toString().padLeft(2, '0')}-fail');
        await bb.dumpScreen((i + 1).toString().padLeft(2, '0'));
        failures.add('${f.title}: $e');
        bb.note('${f.title}: $e');
      }
      await _close(bb);
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbCase('M2', '在这些描述末尾追加一行并保存，用 API 读取原文，除了追加的一行逐字节相同', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final formats = (await owner.boardTasks(Env.formatsProject))
        .where((t) => (t['title'] as String).startsWith('E-格式'))
        .toList();
    await bb.start(Env.owner);
    await bb.openProject('E-Formats');
    final failures = <String>[];
    for (final f in _formats) {
      final id = formats.firstWhere((t) => t['title'] == f.title)['id'] as String;
      final original = await owner.description(id);
      // The seeded text; never write an empty one back over it.
      expect(original, isNotEmpty, reason: '${f.title} has no description to start from');
      addTearDown(() async {
        if (await owner.description(id) != original) await owner.setDescription(id, original);
      });
      final line = 'E-Q M2 appended $runStamp';
      try {
        await _open(bb, f.title);
        // Taps what the description shows: its first text, else its picture or its box.
        Finder target;
        if (f.shows.isNotEmpty) {
          target = bb.containing(f.shows.first).hitTestable();
        } else if (bb.visible(find.byType(RawImage))) {
          target = find.byType(RawImage).hitTestable();
        } else {
          target = find
              .byWidgetPredicate(
                (w) => w is EditableText && w.readOnly && w.controller.text.trim().isNotEmpty,
              )
              .hitTestable();
        }
        // A description that is only a link opens the link when tapped, so it's tapped beside.
        final onlyLink = RegExp('kaneo-(attachment|issue-link|embed)').hasMatch(f.title);
        if (onlyLink) {
          target = find
              .byWidgetPredicate(
                (w) =>
                    w is EditableText &&
                    w.readOnly &&
                    w.controller.text.trim().isNotEmpty &&
                    !w.controller.text.startsWith('E-格式'),
              )
              .hitTestable();
        }
        final linksBefore = openedLinks.length;
        final Finder editor;
        try {
          editor = await _edit(bb, original, target, beside: onlyLink);
        } finally {
          if (openedLinks.length > linksBefore) {
            bb.note(
              '${f.title}: tapping beside the link opened ${openedLinks.sublist(linksBefore)}',
            );
          }
        }
        final shown = bb.tester.widget<EditableText>(editor.first).controller.text;
        await bb.tester.enterText(editor.first, '$shown$line');
        await bb.pumpFor(const Duration(milliseconds: 300));
        final saved = await bb.server('the appended line', () async {
          final now = await owner.description(id);
          return now.contains(line) ? now : null;
        });
        final expected = '$original$line';
        if (saved != expected && saved != '$expected\n') {
          throw TestFailure(
            'Changed more than the line: ${jsonEncodeSafe(original)} -> ${jsonEncodeSafe(saved)}',
          );
        }
        bb.note('${f.title}: ok');
      } catch (e) {
        await bb.shot(f.title.substring(5, 7));
        failures.add('${f.title}: $e');
        bb.note('${f.title}: $e');
      }
      await _close(bb);
      if (await owner.description(id) != original) await owner.setDescription(id, original);
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbCase('M3', '打开旧 HTML 描述，显示格式化文本，没有标签原文', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Formats');
    await _open(bb, 'E-旧 HTML 描述');
    for (final t in ['旧编辑器保存的描述', '一个链接', '第一项', '第二项', '一段引用']) {
      await bb.see(bb.containing(t), seconds: 10, reason: '"$t" is not shown');
    }
    await bb.shot('legacy-html');
    final tags = _allTexts(bb)
        .where((t) => RegExp(r'</?(h2|p|strong|em|a|ul|li|blockquote)\b').hasMatch(t));
    expect(tags, isEmpty, reason: 'Tags show: ${tags.join(' / ')}');
  });

  bbCase('M4', '打开带 Kaneo 标签的描述，不显示标签原文', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Formats');
    final shown = <String>[];
    for (final f in _formats.where((f) => f.title.contains('kaneo-'))) {
      await _open(bb, f.title);
      await bb.pumpFor(const Duration(seconds: 2));
      await bb.shot(f.title.substring(5, 7));
      shown.addAll(_allTexts(bb).where((t) => t.contains('<kaneo') || t.contains('</kaneo')));
      await _close(bb);
    }
    expect(shown, isEmpty, reason: 'Tags show: ${shown.join(' / ')}');
  });

  bbCase('M5', '停止输入约 1 秒后保存；切换页面会保存；断网保存失败时文字保留并提示，恢复后能保存', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'M5');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q M5 task $runStamp', description: 'Start.\n');
    final id = task['id'] as String;
    final proxy = Proxy();
    await proxy.start();
    addTearDown(proxy.close);
    await bb.launch();
    await bb.signIn(Env.owner, server: proxy.url);
    await bb.openProject(scratch.name);
    await bb.tap(bb.card(task['title'] as String));
    await bb.see(_titleField(task['title'] as String));

    // 1. Stops typing, and about a second later it's saved.
    var editor = await _edit(bb, 'Start.\n', bb.text('Start.').hitTestable());
    final first = 'Start.\nTyped once $runStamp';
    await bb.tester.enterText(editor.first, first);
    final watch = Stopwatch()..start();
    await bb.server(
      'the first text',
      () async => await owner.description(id) == first ? true : null,
    );
    bb.note('saved ${watch.elapsedMilliseconds} ms after typing stopped');
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));

    // 2. Types and leaves at once.
    final second = '$first\nThen left $runStamp';
    editor = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == first);
    if (!bb.showing(editor)) {
      editor = await _edit(bb, first, bb.containing('Typed once').hitTestable());
    }
    await bb.tester.enterText(editor.first, second);
    await bb.tester.pump(const Duration(milliseconds: 100));
    await _close(bb);
    await bb.server('the text typed before leaving', () async {
      return await owner.description(id) == second ? true : null;
    });
    await bb.shot('left');

    // 3. The network goes, the text stays and says so; it comes back, and it saves.
    await bb.tap(bb.card(task['title'] as String));
    await bb.see(_titleField(task['title'] as String));
    editor = await _edit(bb, second, bb.containing('Then left').hitTestable());
    await proxy.down();
    final third = '$second\nTyped offline $runStamp';
    await bb.tester.enterText(editor.first, third);
    final before = bb.screenTexts().toSet();
    final told = await bb.until(
      () => bb.screenTexts().toSet().difference(before).any((t) => t.length > 6),
      seconds: 20,
    );
    await bb.shot('offline');
    final said = bb.screenTexts().toSet().difference(before).join(' / ');
    bb.note('offline the app said: $said');
    expect(told, isTrue, reason: 'Nothing said the save failed');
    expect(
      find.byWidgetPredicate((w) => w is EditableText && w.controller.text == third),
      findsWidgets,
      reason: 'The text was lost',
    );
    await proxy.up();
    var back = true;
    try {
      await bb.server(
        'the offline text',
        () async => await owner.description(id) == third ? true : null,
        seconds: 25,
      );
    } catch (_) {
      back = false;
    }
    if (!back) {
      // Not by itself: one more keystroke, as a person would.
      final f = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == third);
      if (bb.showing(f)) {
        await bb.tester.enterText(f.first, '$third.');
        await bb.server('the text after the network came back', () async {
          final now = await owner.description(id);
          return now.startsWith(third) ? true : null;
        }, seconds: 20);
        bb.note('saved after one more keystroke once the network was back');
      } else {
        throw TestFailure('The text was not saved after the network came back');
      }
    } else {
      bb.note('saved by itself once the network was back');
    }
    await bb.shot('saved');
  }, simulated: '断网用测试里的本地代理断开模拟');

  bbCase('M6', '打开超长描述，内容完整', (bb) async {
    await bb.start(Env.owner);
    await bb.openProject('E-Formats');
    await _open(bb, 'E-超长描述');
    await bb.see(bb.containing('第 0001 段'), seconds: 20);
    final end = bb.containing('超长描述到这里结束。');
    final seen = <int>{};
    void look() {
      for (final t in _allTexts(bb)) {
        for (final m in RegExp(r'第 (\d{4}) 段').allMatches(t)) {
          seen.add(int.parse(m.group(1)!));
        }
      }
    }

    // Scrolls the task down a little under a screen at a time, noting every paragraph that shows.
    final at = bb.rectOf(bb.containing('第 0001 段'));
    final step = bb.window.height * 0.6;
    for (var i = 0; i < 400 && !bb.visible(end); i++) {
      look();
      await bb.tester.dragFrom(Offset(at.center.dx, bb.window.height * 0.8), Offset(0, -step));
      await bb.pumpFor(const Duration(milliseconds: 120));
    }
    look();
    await bb.shot('end');
    final missing = [
      for (var n = 1; n <= 1200; n++)
        if (!seen.contains(n)) n,
    ];
    bb.note('paragraphs seen ${seen.length}/1200; end shown ${bb.visible(end)}');
    expect(bb.visible(end), isTrue, reason: 'Never reached the end');
    expect(missing, isEmpty, reason: 'Missing paragraphs: ${missing.take(20)}');
  });
}

String jsonEncodeSafe(String text) => text.replaceAll('\n', r'\n');
