// KAN-52 任务详情：T1 到 T10。
import 'bb.dart';

/// Picks [option] in the picker a property's value opened, saving if the picker asks to.
Future<void> _choose(Bb bb, String property, String option) async {
  await bb.tap(bb.valueOf(property));
  await bb.pumpFor(const Duration(milliseconds: 400));
  await bb.tap(bb.containing(option).hitTestable().last);
  if (bb.visible(bb.text('Save'))) await bb.tap(bb.text('Save').hitTestable());
  await bb.pumpFor(const Duration(milliseconds: 600));
  for (var i = 0; i < 2 && bb.visible(bb.label('Dismiss')); i++) {
    await bb.escape();
  }
}

/// Whether the task on screen shows its whole page: title, properties, and every section.
Future<void> _wholePage(Bb bb, String title) async {
  await bb.see(bb.titleField(title), seconds: 20);
  for (final part in ['Status', 'Priority', 'Assignee', 'Subtasks', 'Relations', 'Activity']) {
    await bb.see(bb.text(part), seconds: 10, reason: 'The task page has no $part');
  }
}

void main() {
  blackBoxModule();

  if (!isPhone) {
    bbCase('T1', '宽屏点击卡片从右侧滑出，看板可见，关闭后回到原滚动位置', (bb) async {
      final owner = await Api.signIn(Env.owner);
      final scratch = await Scratch.make(owner, 'T1', extraColumns: ['Q5', 'Q6', 'Q7', 'Q8']);
      addTearDown(scratch.remove);
      final title = 'E-Q T1 card $runStamp';
      await scratch.task(title, column: 2);
      await bb.start(Env.owner);
      await bb.openProject(scratch.name);
      await bb.scrollBoardTo(scratch.nameOf(2));
      await bb.tester.drag(bb.boardScroll, const Offset(-120, 0));
      await bb.pumpFor(const Duration(milliseconds: 500));
      final header = bb.rectOf(bb.text(scratch.nameOf(2)));
      await bb.openCard(title);
      final field = bb.rectOf(bb.titleField(title));
      await bb.shot('panel');
      bb.note(
        'board column at x=${header.left.round()}, task title field from x=${field.left.round()}',
      );
      expect(field.left, greaterThan(bb.window.width * 0.3), reason: 'Not on the right');
      // Some of the board shows to the left of the panel.
      final boardShowing = boardColumnNames.any(
        (c) => bb.showing(bb.text(c)) && bb.rectOf(bb.text(c)).right < field.left - 20,
      );
      expect(boardShowing, isTrue, reason: 'The board is covered');
      await bb.closeTask();
      await bb.gone(bb.titleField(title), seconds: 5);
      final after = bb.rectOf(bb.text(scratch.nameOf(2)));
      await bb.shot('closed');
      expect((after.left - header.left).abs(), lessThan(2), reason: 'The board scrolled away');
    });
  }

  if (isPhone) {
    bbCase('T2', '窄屏点击卡片全屏打开', (bb) async {
      final owner = await Api.signIn(Env.owner);
      final scratch = await Scratch.make(owner, 'T2');
      addTearDown(scratch.remove);
      final title = 'E-Q T2 card $runStamp';
      await scratch.task(title);
      await bb.start(Env.owner);
      await bb.openProject(scratch.name);
      await bb.openCard(title);
      await bb.pumpFor(const Duration(seconds: 1));
      await bb.shot('page');
      // A page of its own: a way back at the top left, and no board around it.
      final back = bb.rectOf(bb.tip('Back').hitTestable());
      final field = bb.rectOf(bb.titleField(title));
      bb.note(
        'back button at ${back.topLeft}, title from x=${field.left.round()} of ${bb.window.width.round()}',
      );
      expect(back.left, lessThan(bb.window.width * 0.15), reason: 'No back button at the top left');
      expect(
        field.left,
        lessThan(bb.window.width * 0.2),
        reason: 'The task does not start at the left',
      );
      expect(bb.visible(bb.filtersButton), isFalse, reason: 'The board is still there');
      expect(bb.visible(bb.text(scratch.nameOf(1))), isFalse, reason: 'Board columns still show');
    });
  }

  bbCase('T3', '通过链接和通知打开任务，显示完整页面', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'T3');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q T3 notified $runStamp');
    await owner.notify('E-Q T3 notice $runStamp', taskId: task['id'] as String);
    await bb.start(Env.owner);

    final failures = <String>[];

    // A link in a description: E-格式 16 points at E-三层 祖父, a task of this workspace.
    await bb.openProject('E-Formats');
    await bb.typeFilter('E-格式 16 kaneo-issue-link');
    await bb.pumpFor(const Duration(milliseconds: 800));
    await bb.openCard('E-格式 16 kaneo-issue-link');
    final link = bb.containing(RegExp(r'EBB-\d+|E-三层 祖父')).hitTestable();
    await bb.tap(link);
    await bb.pumpFor(const Duration(seconds: 1));
    if (await bb.until(() => bb.showing(bb.titleField('E-三层 祖父')), seconds: 10)) {
      await _wholePage(bb, 'E-三层 祖父');
      await bb.shot('from-link');
      await bb.closeTask();
    } else {
      await bb.shot('from-link');
      failures.add(
        'The task link in a description did not open the task in the app; '
        'it went to the system as ${openedLinks.join(', ')}',
      );
    }
    await bb.closeTask();

    // A notification.
    await bb.nav('Inbox');
    await bb.tap(bb.containing('E-Q T3 notice $runStamp'));
    try {
      await _wholePage(bb, task['title'] as String);
    } catch (e) {
      failures.add('The notification: $e');
    }
    await bb.shot('from-notification');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbCase('T4', '逐项修改标题、状态、优先级、负责人、标签、日期，看板、列表和 API 都同步', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'T4');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q T4 before $runStamp');
    final id = task['id'] as String;
    // A label the workspace already has, on another task.
    final other = await scratch.task('E-Q T4 label holder $runStamp', column: 3);
    final labelName = 'E-QL T4 $runStamp';
    await owner.addLabel(other['id'] as String, labelName, '#22c55e');
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.openCard(task['title'] as String);
    final failures = <String>[];
    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
        bb.note('$name ok');
      } catch (e) {
        failures.add('$name: $e');
        await bb.shot('fail-$name');
      }
    }

    final renamed = 'E-Q T4 after $runStamp';
    await step('title', () async {
      final field = bb.titleField(task['title'] as String);
      await bb.tap(field);
      await bb.tester.enterText(field.first, renamed);
      await bb.submitKeyboard();
      await bb.server('the title', () async => (await owner.task(id))['title'] == renamed);
    });
    await step('status', () async {
      await _choose(bb, 'Status', scratch.nameOf(1));
      await bb.server(
        'the status',
        () async => (await owner.task(id))['status'] == scratch.slugOf(1),
      );
    });
    await step('priority', () async {
      await _choose(bb, 'Priority', 'High');
      await bb.server('the priority', () async => (await owner.task(id))['priority'] == 'high');
    });
    await step('assignee', () async {
      await _choose(bb, 'Assignee', Env.member.name);
      await bb.server(
        'the assignee',
        () async => (await owner.task(id))['userId'] == Env.member.id,
      );
    });
    await step('labels', () async {
      await bb.tap(bb.valueOf('Labels'));
      await bb.pumpFor(const Duration(milliseconds: 500));
      final search = find.ancestor(
        of: find.textContaining('Search'),
        matching: find.byType(TextField),
      );
      await bb.see(search, reason: 'The label picker did not open');
      final box = bb.rectOf(search);
      // Options of the picker: drawn text under its search field, not the board behind it.
      Finder option() => find.byElementPredicate((e) {
        final w = e.widget;
        if (w is! RichText || !w.text.toPlainText().contains(labelName)) return false;
        final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
        return r.top > box.bottom - 2 && (r.center.dx - box.center.dx).abs() < box.width;
      });
      final offered = bb.showing(option());
      bb.note('the label picker offers the workspace label $labelName: $offered');
      if (!offered) {
        await bb.shot('labels-offered');
        failures.add('The label picker does not offer $labelName, which another task has');
      }
      // Typing its name picks it, or offers to make it.
      await bb.type(search, labelName);
      await bb.pumpFor(const Duration(milliseconds: 500));
      await bb.see(option(), reason: 'Nothing to pick or make $labelName');
      await bb.tap(find.byElementPredicate((e) => e == option().evaluate().last));
      if (bb.visible(bb.text('Save'))) await bb.tap(bb.text('Save').hitTestable());
      await bb.pumpFor(const Duration(milliseconds: 600));
      for (var i = 0; i < 2 && bb.visible(bb.label('Dismiss')); i++) {
        await bb.escape();
      }
      await bb.server('the label', () async {
        return (await owner.taskLabels(id)).any((l) => l['name'] == labelName);
      });
    });
    await step('due date', () async {
      await bb.tap(bb.valueOf('Due date'));
      await bb.tap(bb.text('Tomorrow').hitTestable());
      await bb.pumpFor(const Duration(milliseconds: 600));
      for (var i = 0; i < 2 && bb.visible(bb.label('Dismiss')); i++) {
        await bb.escape();
      }
      await bb.server('the due date', () async => (await owner.task(id))['dueDate'] != null);
    });
    await step('start date', () async {
      await bb.tap(bb.valueOf('Start date'));
      await bb.tap(bb.text('Today').hitTestable());
      await bb.pumpFor(const Duration(milliseconds: 600));
      for (var i = 0; i < 2 && bb.visible(bb.label('Dismiss')); i++) {
        await bb.escape();
      }
      await bb.server('the start date', () async => (await owner.task(id))['startDate'] != null);
    });
    await bb.shot('task-edited');
    await bb.closeTask();
    await bb.pumpFor(const Duration(seconds: 1));

    // The board.
    await step('board', () async {
      await bb.see(bb.card(renamed));
      expect(bb.columnOf(bb.card(renamed)), scratch.nameOf(1));
      final card = bb.tester.getSemantics(bb.card(renamed));
      final says = '${card.label} ${card.tooltip}';
      bb.note('card says: ${says.replaceAll('\n', ' | ')}');
      expect(says, contains('High'));
      expect(says, contains(labelName));
      expect(says.contains('EM') || says.contains(Env.member.name), isTrue, reason: 'No assignee');
    });
    await bb.shot('board');
    // The list.
    await step('list', () async {
      await bb.tap(bb.tip('List view'));
      await bb.see(bb.card(renamed));
      final row = bb.tester.getSemantics(bb.card(renamed));
      final says = '${row.label} ${row.tooltip}';
      bb.note('row says: ${says.replaceAll('\n', ' | ')}');
      expect(says.contains('EM') || says.contains(Env.member.name), isTrue, reason: 'No assignee');
    });
    await bb.shot('list');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbCase('T5', '新增并勾选子任务，进度更新', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'T5');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q T5 parent $runStamp');
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.openCard(task['title'] as String);
    await bb.tap(bb.tip('Add subtask'));
    final sub = 'E-Q T5 sub $runStamp';
    final field = find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus);
    await bb.see(field, reason: 'No field for the subtask');
    await bb.tester.enterText(field.first, sub);
    await bb.submitKeyboard();
    await bb.see(bb.containing(sub), seconds: 10);
    await bb.see(bb.label(RegExp(r'^0 ?/ ?1$')), seconds: 10, reason: 'No 0/1');
    await bb.shot('added');
    await bb.tap(bb.label('Mark subtask complete').hitTestable());
    await bb.see(bb.label(RegExp(r'^1 ?/ ?1$')), seconds: 10, reason: 'Progress did not change');
    await bb.shot('checked');
    final children = await owner.relations(task['id'] as String);
    bb.note('relations ${children.length}');
    await bb.closeTask();
    await bb.see(bb.card(task['title'] as String));
    await bb.pumpFor(const Duration(seconds: 1));
    final card = bb.tester.getSemantics(bb.card(task['title'] as String));
    bb.note('card says ${card.label.replaceAll('\n', ' | ')}');
    expect(card.label, contains('1/1'), reason: 'The card does not show 1/1');
  });

  bbCase('T6', '跳到父任务、子任务、关联任务再返回，跳转正确', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'T6');
    addTearDown(scratch.remove);
    final parent = await scratch.task('E-Q T6 parent $runStamp');
    final child = await scratch.task('E-Q T6 child $runStamp', column: 1);
    final related = await scratch.task('E-Q T6 related $runStamp', column: 2);
    await owner.relate(parent['id'] as String, child['id'] as String, 'subtask');
    await owner.relate(parent['id'] as String, related['id'] as String, 'related');
    final p = parent['title'] as String;
    final c = child['title'] as String;
    final r = related['title'] as String;
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.openCard(p);
    final failures = <String>[];
    Future<void> jump(String from, String to) async {
      try {
        await bb.tap(bb.containing(to).hitTestable().last);
        await bb.see(bb.titleField(to), seconds: 10, reason: '$to did not open from $from');
        await bb.shot('${from.split(' ')[2]}-to-${to.split(' ')[2]}');
        await bb.back();
        await bb.see(bb.titleField(from), seconds: 10, reason: 'Back did not return to $from');
      } catch (e) {
        failures.add('$e');
        await bb.shot('fail-${to.split(' ')[2]}');
      }
    }

    await jump(p, c);
    await jump(p, r);
    await bb.closeTask();
    await bb.scrollBoardTo(scratch.nameOf(1));
    await bb.openCard(c);
    await jump(c, p);
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbCase('T7', '新增、编辑、删除评论，@提及另一账号，对方收到通知', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final member = await Api.signIn(Env.member);
    final scratch = await Scratch.make(owner, 'T7');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q T7 task $runStamp');
    final id = task['id'] as String;
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.openCard(task['title'] as String);
    final box = bb.field('Leave a comment...');
    final first = 'E-Q T7 comment $runStamp';
    await bb.type(box, first);
    await bb.tap(bb.label('Send comment'));
    await bb.see(bb.text(first), seconds: 10);
    await bb.server('the comment', () async {
      return (await owner.comments(id)).any((c) => '${c['content']}'.contains(first));
    });
    await bb.shot('added');

    // Edit: the Edit button on the row of the comment.
    final row = bb.rectOf(bb.text(first));
    Finder near(String tooltip) => find.byElementPredicate((e) {
      if (e.widget is! Tooltip || (e.widget as Tooltip).message != tooltip) return false;
      final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
      return r.center.dy < row.center.dy && r.center.dy > row.top - 70;
    });
    await bb.tap(near('Edit'));
    final edited = 'E-Q T7 edited $runStamp';
    final editor = bb.titleField(first);
    await bb.see(editor, reason: 'Edit did not open the comment');
    await bb.tester.enterText(editor.first, edited);
    if (bb.visible(bb.text('Save'))) {
      await bb.tap(bb.text('Save').hitTestable());
    } else {
      await bb.submitKeyboard();
    }
    await bb.server('the edit', () async {
      return (await owner.comments(id)).any((c) => '${c['content']}'.contains(edited));
    });
    await bb.see(bb.text(edited), seconds: 10);
    await bb.shot('edited');

    final row2 = bb.rectOf(bb.text(edited));
    final delete = find.byElementPredicate((e) {
      if (e.widget is! Tooltip || (e.widget as Tooltip).message != 'Delete') return false;
      final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
      return r.center.dy < row2.center.dy && r.center.dy > row2.top - 70;
    });
    await bb.tap(delete);
    final confirm = find.widgetWithText(FilledButton, 'Delete');
    if (await bb.until(() => bb.visible(confirm), seconds: 3)) await bb.tap(confirm.hitTestable());
    await bb.gone(bb.text(edited), seconds: 10);
    await bb.server('the deletion', () async {
      return (await owner.comments(id)).every((c) => !'${c['content']}'.contains(edited));
    });

    // A mention.
    await bb.tap(bb.tip('Mention someone'));
    await bb.tap(bb.containing(Env.member.name).hitTestable().last);
    final field = find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text.contains(Env.member.name),
    );
    await bb.see(field, reason: 'The mention did not go into the comment');
    final text = bb.tester.widget<EditableText>(field.first).controller.text;
    await bb.tester.enterText(field.first, '$text please look $runStamp');
    await bb.tap(bb.label('Send comment'));
    await bb.shot('mentioned');
    await bb.server('the member notified', () async {
      final all = await member.notifications(Env.workspaceId);
      return all.any((n) => '$n'.contains(id) || '$n'.contains('E-Q T7 task')) ? true : null;
    });
  });

  bbCase('T8', '查看别人的评论，没有编辑和删除', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final member = await Api.signIn(Env.member);
    final scratch = await Scratch.make(owner, 'T8');
    addTearDown(scratch.remove);
    final task = await scratch.task('E-Q T8 task $runStamp');
    final theirs = 'E-Q T8 from the member $runStamp';
    await member.comment(task['id'] as String, theirs);
    final mine = 'E-Q T8 from the owner $runStamp';
    await owner.comment(task['id'] as String, mine);
    for (final (who, account, other) in [
      ('owner', Env.owner, theirs),
      ('member', Env.member, mine),
    ]) {
      bb.storage = null;
      await bb.start(account);
      await bb.openProject(scratch.name);
      await bb.openCard(task['title'] as String);
      await bb.see(bb.text(other), seconds: 10);
      final row = bb.rectOf(bb.text(other));
      final actions = find
          .byWidgetPredicate((w) {
            return w is Tooltip && (w.message == 'Edit' || w.message == 'Delete');
          })
          .evaluate()
          .where((e) {
            final r = bb.tester.getRect(find.byElementPredicate((x) => x == e));
            return r.center.dy < row.center.dy && r.center.dy > row.top - 70;
          });
      await bb.shot(who);
      bb.note('$who sees ${actions.length} actions on the other comment');
      expect(actions, isEmpty, reason: 'The $who can edit or delete the other\'s comment');
      await bb.stop();
    }
  });

  bbCase('T9', '复制链接、分享、复制任务、移动项目、删除都生效，删除前二次确认', (bb) async {
    final owner = await Api.signIn(Env.owner);
    final scratch = await Scratch.make(owner, 'T9');
    addTearDown(scratch.remove);
    final target = await Scratch.make(owner, 'T9 target');
    addTearDown(target.remove);
    final task = await scratch.task('E-Q T9 task $runStamp');
    final id = task['id'] as String;
    final title = task['title'] as String;
    await bb.start(Env.owner);
    await bb.openProject(scratch.name);
    await bb.openCard(title);
    final failures = <String>[];

    // Copy link, into a clipboard of the test's own: the system's belongs to whoever uses the Mac.
    var copied = '';
    final messenger = bb.tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = ((call.arguments as Map)['text'] as String?) ?? '';
      }
      if (call.method == 'Clipboard.getData') return {'text': copied};
      if (call.method == 'Clipboard.hasStrings') return {'value': copied.isNotEmpty};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await bb.tap(bb.tip('Copy link'));
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    bb.note('copied "$copied"');
    if (!copied.contains(id) && !copied.contains('${task['number']}')) {
      failures.add('Copy link copied "$copied"');
    }

    // Share: what the app hands to the system's share sheet, recorded instead of shown.
    await bb.tap(bb.tip('More'));
    await bb.tap(bb.text('Share').hitTestable());
    await bb.pumpFor(const Duration(seconds: 1));
    bb.note('shared $sharedItems');
    if (!sharedItems.any((s) => s.contains(id) || s.contains(title))) {
      failures.add('Share handed over $sharedItems');
    }
    for (var i = 0; i < 2 && !bb.visible(bb.tip('More')); i++) {
      await bb.escape();
    }

    // Duplicate.
    await bb.tap(bb.tip('More'));
    await bb.tap(bb.text('Duplicate').hitTestable());
    var copyId = '';
    try {
      copyId = await bb.server('a copy', () async {
        final others = (await owner.boardTasks(scratch.id)).where((t) => t['id'] != id);
        return others.isEmpty ? null : others.first['id'] as String;
      });
    } catch (e) {
      failures.add('Duplicate: $e');
    }
    await bb.pumpFor(const Duration(seconds: 1));
    await bb.shot('duplicated');
    for (var i = 0; i < 2 && !bb.visible(bb.tip('More')); i++) {
      await bb.escape();
    }
    if (!bb.showing(bb.titleField(title))) await bb.openCard(title);

    // Move to another project: whichever of the two is open goes.
    await bb.tap(bb.tip('More'));
    await bb.tap(bb.text('Move to project…').hitTestable());
    await bb.tap(bb.containing(target.name).hitTestable().last);
    final move = find.widgetWithText(FilledButton, 'Move');
    if (await bb.until(() => bb.visible(move), seconds: 3)) await bb.tap(move.hitTestable());
    var moved = '';
    try {
      moved = await bb.server('the move', () async {
        for (final t in [id, if (copyId.isNotEmpty) copyId]) {
          if ((await owner.task(t))['projectId'] == target.id) return t;
        }
        return null;
      });
      bb.note(moved == id ? 'moved the original' : 'moved the copy, which the app had opened');
    } catch (e) {
      failures.add('Move: $e');
    }
    await bb.shot('moved');

    // Delete, which asks first.
    if (!bb.showing(bb.titleField(title))) {
      await bb.openProject(target.name);
      await bb.openCard(title);
    }
    final doomed = moved.isNotEmpty ? moved : id;
    await bb.tap(bb.tip('More'));
    await bb.tap(bb.text('Delete task').hitTestable());
    await bb.pumpFor(const Duration(milliseconds: 500));
    await bb.shot('confirm');
    final asked = await bb.until(
      () =>
          bb.visible(find.widgetWithText(FilledButton, 'Delete')) ||
          bb.visible(find.widgetWithText(FilledButton, 'Delete task')),
      seconds: 5,
    );
    if (!asked) {
      failures.add('Delete did not ask first');
    } else {
      // Asking first means nothing has gone yet.
      expect((await owner.task(doomed))['id'], doomed);
      final yes = find.widgetWithText(FilledButton, 'Delete').evaluate().isNotEmpty
          ? find.widgetWithText(FilledButton, 'Delete')
          : find.widgetWithText(FilledButton, 'Delete task');
      await bb.tap(yes.hitTestable());
      try {
        await bb.server('the deletion', () async {
          try {
            await owner.task(doomed);
            return null;
          } on ApiException catch (e) {
            return e.status == 404 ? true : null;
          }
        });
      } catch (e) {
        failures.add('Delete: $e');
      }
    }
    await bb.shot('deleted');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  bbCase('T10', '用权限受限账号操作，没有权限的操作不显示', (bb) async {
    await bb.start(Env.viewer);
    await bb.openProject('E-Board');
    await bb.pumpFor(const Duration(seconds: 1));
    final offered = <String>[
      for (final t in ['New task', 'Add task'])
        if (bb.visible(bb.tip(t))) 'board: $t',
    ];
    await bb.shot('board');
    await bb.scrollBoardTo('To Do');
    await bb.openCard('E-三层 祖父');
    await bb.shot('task');
    for (final t in ['Add subtask', 'Mention someone', 'Edit', 'Delete']) {
      if (bb.visible(bb.tip(t))) offered.add('task: $t');
    }
    final title = bb.tester.widget<EditableText>(bb.titleField('E-三层 祖父').first);
    if (!title.readOnly) offered.add('task: the title can be edited');
    if (bb.visible(bb.field('Leave a comment...'))) offered.add('task: comment box');
    if (bb.visible(bb.tip('More'))) {
      await bb.tap(bb.tip('More'));
      for (final t in ['Duplicate', 'Move to project…', 'Delete task']) {
        if (bb.visible(bb.text(t))) offered.add('more: $t');
      }
      await bb.shot('more');
      await bb.escape();
    }
    // The status picker: tapping it opens nothing that could change it.
    await bb.tap(bb.valueOf('Status'));
    if (bb.visible(bb.text('In Progress').hitTestable()) &&
        find.text('In Progress').hitTestable().evaluate().length > 1) {
      offered.add('task: status picker');
    }
    await bb.shot('status');
    bb.note('offered: $offered');
    expect(offered, isEmpty, reason: 'A viewer is offered: $offered');
  });
}
