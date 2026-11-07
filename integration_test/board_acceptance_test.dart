// Local B-line acceptance. Run only through tool/with_device.sh with dev.env.
// Creates new B-prefixed projects; never edits the seeded/shared projects.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/board/board_card.dart';
import 'package:kaneo_app/features/board/board_expansion.dart';
import 'package:kaneo_app/features/shell/app_shell.dart' show shellPageKey;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

const device = String.fromEnvironment('BOARD_TEST_DEVICE', defaultValue: 'device');
final captureKey = GlobalKey();
Finder card(String id) => find.byKey(ValueKey('board-card-$id'));
Finder row(String id) => find.byKey(ValueKey('list-task-$id'));
Finder page(Finder finder) => find.descendant(of: find.byKey(shellPageKey), matching: finder);

Future<bool> until(WidgetTester tester, bool Function() ready, {int seconds = 20}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return ready();
}

Future<void> see(WidgetTester tester, Finder finder) async {
  expect(await until(tester, () => finder.evaluate().isNotEmpty), isTrue, reason: '$finder');
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await see(tester, finder);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final directory = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/B-KAN-49/$device',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}/$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  debugPrint('B_EVIDENCE ${file.path}');
}

Future<void> search(WidgetTester tester, String value) async {
  if (find.byKey(const ValueKey('board-search')).evaluate().isEmpty) {
    await tap(tester, find.byKey(const ValueKey('board-search-toggle')));
  }
  await tester.enterText(find.byKey(const ValueKey('board-search')), value);
  await tester.pumpAndSettle();
}

Future<void> closeSearch(WidgetTester tester) async {
  if (find.byKey(const ValueKey('board-search-toggle')).evaluate().isNotEmpty &&
      find.byKey(const ValueKey('board-search')).evaluate().isNotEmpty) {
    await tap(tester, find.byKey(const ValueKey('board-search-toggle')));
  }
}

Future<void> filter(WidgetTester tester, String label) async {
  await tap(tester, find.byIcon(LucideIcons.listFilter));
  await tap(tester, find.text(label).last);
}

Future<void> selectMany(WidgetTester tester, String label) async {
  await tap(tester, find.widgetWithText(CheckboxListTile, label));
  await tap(tester, find.text('Save').last);
}

Future<void> menu(WidgetTester tester, String title) async {
  final target = page(find.text(title));
  await tester.ensureVisible(target);
  await tester.longPress(target);
  await tester.pumpAndSettle();
}

Future<TestGesture> dragStart(WidgetTester tester, String id, {bool mouse = false}) async {
  final handle = find.byKey(ValueKey('drag-handle-$id'));
  await tester.ensureVisible(handle);
  final gesture = await tester.startGesture(
    tester.getCenter(handle),
    kind: mouse ? ui.PointerDeviceKind.mouse : ui.PointerDeviceKind.touch,
  );
  await gesture.moveBy(const Offset(8, 8));
  await tester.pump();
  return gesture;
}

Future<void> dragTo(WidgetTester tester, String id, Offset target, {bool mouse = false}) async {
  final gesture = await dragStart(tester, id, mouse: mouse);
  await gesture.moveTo(target);
  await tester.pump(const Duration(milliseconds: 80));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('B board local acceptance on $device', (tester) async {
    final config = DevConfig.fromEnvironment();
    final host = Uri.parse(config.serverUrl).host;
    expect(['localhost', '127.0.0.1', '::1'], contains(host), reason: 'Local Kaneo only.');
    var container = await bootstrap(sessionStorage: MemorySessionStorage());
    addTearDown(() => container.dispose());
    await container.read(languageChoiceProvider.notifier).select(defaultLocale);
    final session = await container
        .read(authenticationProvider)
        .withPassword(
          config.serverUrl,
          const String.fromEnvironment('KANEO_DEV_EMAIL'),
          const String.fromEnvironment('KANEO_DEV_PASSWORD'),
        );
    await container.read(sessionProvider.notifier).signIn(session);
    var api = container.read(kaneoApiProvider);
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final project = await api.createProject(
      name: 'B-$device-$stamp',
      workspaceId: config.workspaceId,
      icon: 'Layout',
      slug: 'B${stamp.toUpperCase()}',
    );
    final other = await api.createProject(
      name: 'B-Second-$device-$stamp',
      workspaceId: config.workspaceId,
      icon: 'Layout',
      slug: 'BS${stamp.toUpperCase()}',
    );
    final initial = await api.columns(project.id);
    await api.updateColumn(initial[0].id, name: '需求池');
    await api.updateColumn(initial[1].id, name: '已计划');
    await api.createColumn(project.id, name: 'B Review');
    await api.createColumn(project.id, name: 'B Later');
    final columns = await api.columns(project.id);
    expect(columns.length, 6);
    final todo = columns.first.slug;
    final doing = columns[1].slug;
    final done = columns.firstWhere((c) => c.isFinal == true).slug;
    Future<Task> create(
      String title, {
      String? status,
      String priority = 'no-priority',
      bool metadata = false,
    }) => api.createTask(
      project.id,
      CreateTaskBody(
        title: title,
        description: 'B local board acceptance',
        priority: priority,
        status: status ?? todo,
        userId: metadata ? session.userId : null,
        dueDate: metadata ? '2020-01-01T00:00:00.000Z' : null,
      ),
    );
    final parent = await create('B Parent', priority: 'high', metadata: true);
    final child = await create('B Child');
    final grandchild = await create('B Grandchild');
    final target = await create('B Drag target');
    final moving = await create('B Drag move');
    final cross = await create('B Cross-column child', status: doing);
    final completed = await create('B Completed child', status: done);
    final cycleA = await create('B Cycle A');
    final cycleB = await create('B Cycle B');
    final cycleC = await create('B Cycle C');
    await api.createRelation(parent.id, child.id, 'subtask');
    await api.createRelation(child.id, grandchild.id, 'subtask');
    await api.createRelation(parent.id, cross.id, 'subtask');
    await api.createRelation(parent.id, completed.id, 'subtask');
    await api.createRelation(target.id, child.id, 'subtask');
    await api.createRelation(cycleA.id, cycleB.id, 'subtask');
    await api.createRelation(cycleB.id, cycleC.id, 'subtask');
    await api.createRelation(cycleC.id, cycleA.id, 'subtask');
    final label = await api.createLabel(
      name: 'B-acceptance-$stamp',
      color: 'red',
      workspaceId: config.workspaceId,
    );
    await api.attachLabel(label.id, parent.id);
    await create('B Planned item', status: statusPlanned);
    await create('B Archived item', status: statusArchived);
    for (var i = 0; i < 100; i++) {
      await create('B Load ${i.toString().padLeft(3, '0')}');
    }
    debugPrint('B_CHECK setup ${project.name} ${project.id}');
    Future<void> mount() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: UncontrolledProviderScope(container: container, child: const KaneoApp()),
        ),
      );
      container.read(routerProvider).go(AppRoutes.board(project.id));
      await see(tester, card(parent.id));
    }

    await mount();
    final phone =
        Platform.isIOS &&
        tester.view.display.size.shortestSide / tester.view.display.devicePixelRatio < 600;
    if (phone) {
      expect(
        await until(tester, () => tester.view.physicalSize.width > tester.view.physicalSize.height),
        isTrue,
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.getSize(find.byType(AppBar)).height, 48);
    }
    expect(card(child.id), findsNothing);
    expect(find.descendant(of: card(parent.id), matching: find.text('1/3')), findsOneWidget);
    expect(find.descendant(of: card(parent.id), matching: find.text(label.name)), findsOneWidget);
    expect(
      find.descendant(of: card(cross.id), matching: find.text('Parent task: B Parent')),
      findsOneWidget,
    );
    final header = find.byKey(ValueKey('column-header-${columns.first.slug}'));
    expect(find.descendant(of: header, matching: find.text('108 tasks')), findsOneWidget);
    await shot(tester, '01-board-collapsed');
    final firstPosition = tester.getTopLeft(card(parent.id));
    await tap(tester, find.byKey(ValueKey('expand-task-${parent.id}')));
    await tap(tester, find.byKey(ValueKey('expand-task-${child.id}')));
    expect(card(grandchild.id), findsOneWidget);
    expect(tester.getTopLeft(card(child.id)).dx, greaterThan(firstPosition.dx));
    await shot(tester, '02-board-expanded');
    await tap(tester, find.byKey(ValueKey('expand-task-${parent.id}')));

    debugPrint('B_CHECK drag');
    final lane = find.byKey(PageStorageKey('column-tasks-${columns.first.slug}'));
    final headerBefore = tester.getTopLeft(header);
    final targetRect = tester.getRect(find.byKey(ValueKey('drop-card-${target.id}')));
    await dragTo(
      tester,
      moving.id,
      targetRect.topLeft + const Offset(70, 10),
      mouse: Platform.isMacOS,
    );
    expect(tester.getTopLeft(card(moving.id)).dy, lessThan(tester.getTopLeft(card(target.id)).dy));
    final storedMoved = await api.task(moving.id);
    final storedTarget = await api.task(target.id);
    expect(storedMoved.position!, lessThan(storedTarget.position!));
    final nextHeader = find.byKey(ValueKey('column-header-${columns[1].slug}'));
    await dragTo(tester, parent.id, tester.getTopLeft(nextHeader) + const Offset(20, 20));
    expect(
      find.descendant(of: find.byKey(ValueKey('drop-column-$doing')), matching: card(parent.id)),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getTopLeft(header), headerBefore);
    expect((await api.task(parent.id)).status, doing);
    expect((await api.task(child.id)).status, todo);
    expect(card(child.id), findsOneWidget);
    await shot(tester, '03-parent-moved');
    // Put the parent back using the shared long-press menu.
    await search(tester, 'B Parent');
    await menu(tester, 'B Parent');
    await tap(tester, find.text('Move to').last);
    await tap(tester, find.text('需求池').last);
    await see(
      tester,
      find.descendant(of: find.byKey(ValueKey('drop-column-$todo')), matching: card(parent.id)),
    );
    await menu(tester, 'B Parent');
    await tap(
      tester,
      find.text(container.read(i18nProvider).t('mobile:board.sendToTopOfColumn')).last,
    );
    await tester.pumpAndSettle();

    await tap(tester, find.byTooltip('Reset'));
    await closeSearch(tester);
    // A held drag scrolls horizontally, then stops when cancelled.
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byKey(const ValueKey('board-horizontal')))
        .controller!;
    final gesture = await dragStart(tester, parent.id);
    final pageBox = tester.getRect(find.byKey(shellPageKey));
    await gesture.moveTo(Offset(pageBox.right - 2, pageBox.top + 140));
    await tester.pump(const Duration(milliseconds: 600));
    expect(horizontal.offset, greaterThan(0));
    await gesture.cancel();
    horizontal.jumpTo(0);
    await tester.pumpAndSettle();
    final vertical = tester.widget<ListView>(lane).controller!;
    final top = tester.getTopLeft(header);
    final timer = Stopwatch()..start();
    await tester.dragUntilVisible(
      find.text('B Load 099'),
      lane,
      const Offset(0, -500),
      maxIteration: 40,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header), top);
    expect(find.byType(BoardCard).evaluate().length, lessThan(60));
    debugPrint('B_METRIC 100-card-scroll ${timer.elapsedMilliseconds}ms');
    await shot(tester, '04-hundred-cards');
    vertical.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.drag(lane, const Offset(0, 350));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(RefreshProgressIndicator).evaluate().length, lessThanOrEqualTo(1));
    await tester.pumpAndSettle();

    debugPrint('B_CHECK filters');
    await search(tester, 'B missing');
    expect(
      find.text(container.read(i18nProvider).t('mobile:board.noTasksMatchTheFilters')),
      findsNWidgets(6),
    );
    await shot(tester, '05-filter-empty');
    await tap(tester, find.byTooltip('Reset'));
    await closeSearch(tester);
    await filter(tester, 'Priority');
    await selectMany(tester, 'High');
    expect(card(parent.id), findsOneWidget);
    expect(card(moving.id), findsNothing);
    await filter(tester, 'Labels');
    await selectMany(tester, label.name);
    await filter(tester, 'Overdue only');
    await filter(tester, 'Me');
    expect(find.byKey(const ValueKey('filter-count')), findsOneWidget);
    await shot(tester, '06-filter-active');
    await tap(tester, find.byTooltip('List view'));
    await see(tester, row(parent.id));
    expect(find.byKey(const ValueKey('filter-count')), findsOneWidget);
    await shot(tester, '07-list-filtered');
    await tap(tester, find.byTooltip('Reset'));
    await tap(tester, find.byKey(ValueKey('expand-task-${parent.id}')));
    await see(tester, row(child.id));
    expect(row(grandchild.id), findsOneWidget); // child expansion was remembered independently.
    await shot(tester, '08-list-expanded');
    await search(tester, 'B Child');
    expect(row(parent.id), findsNothing);
    expect(row(child.id), findsOneWidget);
    expect(
      find.descendant(of: row(child.id), matching: find.textContaining('B Parent')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row(child.id), matching: find.textContaining('B Drag target')),
      findsOneWidget,
    );
    await tap(tester, find.byTooltip('Reset'));
    await closeSearch(tester);
    await filter(tester, 'Show planned');
    await filter(tester, 'Show archived');
    await see(tester, find.text('B Planned item'));
    await tester.scrollUntilVisible(
      find.text('B Archived item'),
      500,
      scrollable: page(find.byType(Scrollable)).last,
      maxScrolls: 50,
    );
    expect(find.text('B Archived item'), findsOneWidget);
    await shot(tester, '09-list-collections');
    await filter(tester, 'Hide planned');
    await filter(tester, 'Hide archived');
    await search(tester, 'B Parent');
    await closeSearch(tester);
    await tap(tester, page(find.text(project.name)));
    final chooser = find.byType(PopoverSurface).evaluate().isNotEmpty
        ? find.byType(PopoverSurface)
        : find.byType(BottomSheet);
    await tap(tester, find.descendant(of: chooser, matching: find.text(other.name)));
    await see(tester, page(find.text(other.name)));
    expect(find.byKey(const ValueKey('filter-count')), findsNothing);
    await tap(tester, page(find.text(other.name)));
    final chooserBack = find.byType(PopoverSurface).evaluate().isNotEmpty
        ? find.byType(PopoverSurface)
        : find.byType(BottomSheet);
    await tap(tester, find.descendant(of: chooserBack, matching: find.text(project.name)));
    await see(tester, row(parent.id));

    debugPrint('B_CHECK reopen');
    final expanded = container.read(prefsProvider).getStringList(boardExpansionKey(project.id));
    expect(expanded, containsAll([parent.id, child.id]));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    container = await bootstrap(sessionStorage: MemorySessionStorage(session));
    api = container.read(kaneoApiProvider);
    await mount();
    await see(tester, card(child.id));
    await shot(tester, '10-board-restored');
    // Keep the parent at the top and collapse before testing a real server rejection.
    await tap(tester, find.byKey(ValueKey('expand-task-${parent.id}')));
    final rollbackBefore = tester.getTopLeft(card(moving.id));
    await api.deleteTask(moving.id); // only our test task, concurrent deletion leaves a stale card.
    await dragTo(tester, moving.id, tester.getTopLeft(nextHeader) + const Offset(20, 20));
    await see(tester, find.textContaining('Tasks must belong'));
    expect(tester.getTopLeft(card(moving.id)), rollbackBefore);
    await shot(tester, '11-rejected-move');
    await tap(tester, find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    // External-client change: record its real outcome without hiding a pending A-line dependency.
    final clock = Stopwatch()..start();
    await api.updateTitle(parent.id, 'B Parent external update');
    final live = await until(
      tester,
      () => find.text('B Parent external update').evaluate().isNotEmpty,
      seconds: 5,
    );
    debugPrint(
      'B_RESULT realtime_5_seconds ${live ? 'PASS' : 'FAIL'} ${clock.elapsedMilliseconds}ms',
    );
    await shot(tester, '12-external-update');
    final evidenceRoot = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/B-KAN-49/$device',
    );
    final report = File('${evidenceRoot.path}/results.json');
    await report.writeAsString(
      jsonEncode({
        'device': device,
        'project': project.name,
        'projectId': project.id,
        'realtimeWithinFiveSeconds': live,
        'realtimeElapsedMs': clock.elapsedMilliseconds,
        'phoneLandscape': phone,
        'completed': true,
      }),
    );
    debugPrint('B_EVIDENCE ${report.path}');
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
