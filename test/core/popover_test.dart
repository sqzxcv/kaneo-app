import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/core/ui/calendar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/test_app.dart';

/// Runs [open] from a button, and keeps what it resolved to.
class _Runner<T> {
  T? result;
  bool finished = false;

  Widget button(Future<T> Function(BuildContext context) open, {Alignment? alignment}) => Align(
    alignment: alignment ?? const Alignment(-0.2, -0.5),
    child: Builder(
      builder: (context) => ElevatedButton(
        key: const ValueKey('open'),
        onPressed: () async {
          result = await open(context);
          finished = true;
        },
        child: const Text('open'),
      ),
    ),
  );
}

const _columns = [
  ProjectColumn(id: 'c1', projectId: 'p', name: 'To Do', slug: 'to-do'),
  ProjectColumn(id: 'c2', projectId: 'p', name: 'Done', slug: 'done', isFinal: true),
];
const _members = [
  WorkspaceMember(id: 'u1', name: 'Ada', email: 'ada@example.com', role: 'owner'),
  WorkspaceMember(id: 'u2', name: 'Bo', email: 'bo@example.com', role: 'member'),
];
const _labels = [
  Label(id: 'l1', name: 'bug', color: 'red'),
  Label(id: 'l2', name: 'ui', color: 'blue'),
];
const _options = [
  PickerOption(value: 'a', label: 'First'),
  PickerOption(value: 'b', label: 'Second', subtitle: 'More'),
];
const _items = [
  MenuAction(value: 'copy', label: 'Copy', icon: Icons.copy),
  MenuAction(value: 'delete', label: 'Delete', destructive: true),
  MenuAction(value: 'off', label: 'Unavailable', enabled: false),
];

/// Every entry point that shows a popover on wide windows and a bottom sheet on narrow ones. Each
/// names a text that proves it is open.
final Map<String, (String, Future<Object?> Function(BuildContext))> _surfaces = {
  'showActionMenu': ('Copy', (context) => showActionMenu<String>(context, items: _items)),
  'pickOption': (
    'First',
    (context) => pickOption<String>(context, title: 'Pick', options: _options),
  ),
  'pickMany': (
    'First',
    (context) => pickMany<String>(context, title: 'Pick', options: _options, selected: const {}),
  ),
  'pickStatus': ('Done', (context) => pickStatus(context, columns: _columns)),
  'pickPriority': ('Urgent', (context) => pickPriority(context)),
  'pickAssignee': ('Ada', (context) => pickAssignee(context, members: _members)),
  'pickLabels': ('bug', (context) => pickLabels(context, labels: _labels, selectedIds: const {})),
  'pickDate': ('Next week', (context) => pickDate(context, title: 'Due')),
};

void main() {
  group('placePopover', () {
    const bounds = Rect.fromLTRB(8, 8, 992, 792);
    const size = Size(200, 100);

    test('opens below the anchor, at its left edge', () {
      const anchor = Rect.fromLTWH(100, 100, 80, 32);
      expect(placePopover(anchor, size, bounds), const Offset(100, 136));
    });

    test('flips above when it does not fit below', () {
      const anchor = Rect.fromLTWH(100, 740, 80, 32);
      expect(placePopover(anchor, size, bounds), const Offset(100, 636));
    });

    test('lines up with the right edge when it does not fit to the right', () {
      const anchor = Rect.fromLTWH(900, 100, 80, 32);
      expect(placePopover(anchor, size, bounds), const Offset(780, 136));
    });

    test('at a pointer near the corner, it opens up and to the left of it', () {
      const anchor = Rect.fromLTWH(980, 780, 0, 0);
      expect(placePopover(anchor, size, bounds), const Offset(780, 676));
    });

    test('stays inside the window when it fits on neither side', () {
      const anchor = Rect.fromLTWH(0, 300, 1000, 200);
      expect(placePopover(anchor, const Size(1200, 400), bounds), const Offset(8, 392));
    });

    test('may use the roomier side of the anchor', () {
      expect(popoverHeightLimit(const Rect.fromLTWH(0, 100, 10, 20), bounds), 668);
      expect(popoverHeightLimit(const Rect.fromLTWH(0, 700, 10, 20), bounds), 688);
    });

    test('covers an anchor that leaves no room on either side', () {
      expect(popoverHeightLimit(const Rect.fromLTWH(0, 0, 1000, 800), bounds), bounds.height);
    });
  });

  group('calendar logic', () {
    test('monthGrid starts weeks on Monday and fills only the month', () {
      // March 2026 starts on a Sunday and ends on a Tuesday.
      final weeks = monthGrid(2026, 3);
      expect(weeks.first.take(6), everyElement(isNull));
      expect(weeks.first.last, DateTime(2026, 3, 1));
      expect(weeks[1].first, DateTime(2026, 3, 2));
      expect(weeks.last[1], DateTime(2026, 3, 31));
      expect(weeks.last.skip(2), everyElement(isNull));
      expect(weeks, everyElement(hasLength(7)));
    });

    test('monthGrid handles February in a leap year', () {
      final days = monthGrid(2028, 2).expand((week) => week).whereType<DateTime>();
      expect(days.length, 29);
    });

    test('nextMonday is always in the following week', () {
      expect(nextMonday(DateTime(2026, 3, 2)), DateTime(2026, 3, 9)); // Monday
      expect(nextMonday(DateTime(2026, 3, 8)), DateTime(2026, 3, 9)); // Sunday
      expect(nextMonday(DateTime(2026, 12, 30)), DateTime(2027, 1, 4)); // Across the year
    });
  });

  Future<_Runner<T>> open<T>(
    WidgetTester tester,
    Size size,
    Future<T> Function(BuildContext context) action, {
    Alignment? alignment,
  }) async {
    final runner = _Runner<T>();
    await pumpInApp(tester, runner.button(action, alignment: alignment), size: size);
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return runner;
  }

  Future<void> esc(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<TestGesture> mouseOver(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    return mouse;
  }

  Color? highlightBehind(WidgetTester tester, Finder target) {
    final highlight = find.ancestor(of: target, matching: find.byType(HoverHighlight)).first;
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: highlight, matching: find.byType(DecoratedBox)).first,
    );
    return (box.decoration as BoxDecoration).color;
  }

  Finder rowOf(String text) => find.ancestor(of: find.text(text), matching: find.byType(ListTile));

  for (final MapEntry(key: name, value: (text, show)) in _surfaces.entries) {
    group(name, () {
      testWidgets('is a popover next to its anchor on wide windows', (tester) async {
        await open<Object?>(tester, wideSize, show);
        expect(find.text(text), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        final anchor = tester.getRect(find.byKey(const ValueKey('open')));
        final surface = tester.getRect(find.byType(PopoverSurface));
        expect(surface.left, anchor.left);
        expect(surface.top, anchor.bottom + 4);
      });

      testWidgets('is a bottom sheet on narrow windows', (tester) async {
        await open<Object?>(tester, narrowSize, show);
        expect(find.text(text), findsOneWidget);
        expect(find.byType(PopoverSurface), findsNothing);
        final sheet = tester.getRect(find.byType(BottomSheet));
        expect(sheet.width, narrowSize.width);
        expect(sheet.bottom, narrowSize.height);
      });

      testWidgets('Esc closes it without an answer', (tester) async {
        final runner = await open<Object?>(tester, wideSize, show);
        await esc(tester);
        expect(find.text(text), findsNothing);
        expect(runner.finished, isTrue);
        expect(runner.result, isNull);
      });

      testWidgets('clicking outside closes it without an answer', (tester) async {
        final runner = await open<Object?>(tester, wideSize, show);
        await tester.tapAt(const Offset(1300, 1000));
        await tester.pumpAndSettle();
        expect(find.text(text), findsNothing);
        expect(runner.result, isNull);
      });
    });
  }

  group('position', () {
    testWidgets('showActionMenu opens at the pointer', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) =>
            showActionMenu<String>(context, items: _items, position: const Offset(700, 400)),
      );
      expect(tester.getRect(find.byType(PopoverSurface)).topLeft, const Offset(700, 404));
    });

    testWidgets('pickers pass the pointer on', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) => pickStatus(context, columns: _columns, position: const Offset(700, 400)),
      );
      expect(tester.getRect(find.byType(PopoverSurface)).topLeft, const Offset(700, 404));
    });

    testWidgets('near the bottom right corner, it flips to stay in the window', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) => showActionMenu<String>(context, items: _items),
        alignment: const Alignment(0.95, 0.95),
      );
      final anchor = tester.getRect(find.byKey(const ValueKey('open')));
      final surface = tester.getRect(find.byType(PopoverSurface));
      expect(surface.bottom, anchor.top - 4);
      expect(surface.right, anchor.right);
    });

    testWidgets('a long list scrolls inside the window', (tester) async {
      final runner = await open<Picked<int>?>(
        tester,
        wideSize,
        (context) => pickOption<int>(
          context,
          title: 'Pick',
          options: [for (var i = 0; i < 100; i++) PickerOption(value: i, label: 'Option $i')],
        ),
        alignment: Alignment.topLeft,
      );
      final surface = tester.getRect(find.byType(PopoverSurface));
      expect(surface.height, 420);
      await tester.scrollUntilVisible(
        find.text('Option 99'),
        200,
        scrollable: find.descendant(
          of: find.byType(PopoverSurface),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Option 99'));
      await tester.pumpAndSettle();
      expect(runner.result?.value, 99);
    });

    testWidgets('a long list fits on a phone turned on its side', (tester) async {
      final runner = await open<Picked<int>?>(
        tester,
        const Size(844, 390),
        (context) => pickOption<int>(
          context,
          title: 'Pick',
          options: [for (var i = 0; i < 100; i++) PickerOption(value: i, label: 'Option $i')],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.text('Option 1'));
      await tester.pumpAndSettle();
      expect(runner.result?.value, 1);
    });
  });

  group('hover', () {
    testWidgets('a menu row lights up under the mouse and goes dark again', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) => showActionMenu<String>(context, items: _items),
      );
      final accent = tester.element(find.text('Copy')).colors.accent;
      expect(highlightBehind(tester, find.text('Copy')), isNull);
      final mouse = await mouseOver(tester, find.text('Copy'));
      expect(highlightBehind(tester, find.text('Copy')), accent);
      await mouse.moveTo(tester.getCenter(find.text('Delete')));
      await tester.pump();
      expect(highlightBehind(tester, find.text('Copy')), isNull);
      expect(highlightBehind(tester, find.text('Delete')), accent);
    });

    testWidgets('a disabled menu row does not', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) => showActionMenu<String>(context, items: _items),
      );
      await mouseOver(tester, find.text('Unavailable'));
      expect(highlightBehind(tester, find.text('Unavailable')), isNull);
    });

    testWidgets('picker rows do', (tester) async {
      await open<Picked<String>?>(
        tester,
        wideSize,
        (context) => pickOption<String>(context, title: 'Pick', options: _options),
      );
      await mouseOver(tester, find.text('First'));
      expect(
        highlightBehind(tester, find.text('First')),
        tester.element(find.text('First')).colors.accent,
      );
    });

    testWidgets('checkbox rows do', (tester) async {
      await open<Set<String>?>(
        tester,
        wideSize,
        (context) =>
            pickMany<String>(context, title: 'Pick', options: _options, selected: const {}),
      );
      await mouseOver(tester, find.text('Second'));
      expect(
        highlightBehind(tester, find.text('Second')),
        tester.element(find.text('Second')).colors.accent,
      );
    });

    testWidgets('calendar days do, except the selected one', (tester) async {
      await open<Picked<DateTime?>?>(
        tester,
        wideSize,
        (context) => pickDate(context, title: 'Due', current: DateTime(2026, 3, 9)),
      );
      final mouse = await mouseOver(tester, find.text('15'));
      expect(
        highlightBehind(tester, find.text('15')),
        tester.element(find.text('15')).colors.accent,
      );
      await mouse.moveTo(tester.getCenter(find.text('9')));
      await tester.pump();
      expect(highlightBehind(tester, find.text('9')), isNull);
    });
  });

  group('ContextMenuRegion', () {
    Future<List<String>> pumpRegion(WidgetTester tester, Size size) async {
      final chosen = <String>[];
      await pumpInApp(
        tester,
        Center(
          child: ContextMenuRegion<String>(
            items: () => _items,
            onSelected: chosen.add,
            child: const SizedBox(width: 200, height: 100, child: Text('card')),
          ),
        ),
        size: size,
      );
      return chosen;
    }

    testWidgets('a right-click opens the menu at the pointer on wide windows', (tester) async {
      final chosen = await pumpRegion(tester, wideSize);
      final point = tester.getCenter(find.text('card'));
      await tester.tapAt(point, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getRect(find.byType(PopoverSurface)).topLeft, point + const Offset(0, 4));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(chosen, ['delete']);
    });

    testWidgets('a long press opens it as a sheet on narrow windows', (tester) async {
      final chosen = await pumpRegion(tester, narrowSize);
      await tester.longPress(find.text('card'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(chosen, ['copy']);
    });

    testWidgets('dismissing it chooses nothing', (tester) async {
      final chosen = await pumpRegion(tester, wideSize);
      await tester.tapAt(tester.getCenter(find.text('card')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await esc(tester);
      expect(find.text('Copy'), findsNothing);
      expect(chosen, isEmpty);
    });

    testWidgets('a right-click outside the menu closes it, one inside does not', (tester) async {
      await pumpRegion(tester, wideSize);
      await tester.tapAt(tester.getCenter(find.text('card')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.text('Copy')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);
    });
  });

  group('looks like the web app', () {
    testWidgets('the popover uses the theme\'s popover tokens', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) => showActionMenu<String>(context, items: _items),
      );
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(PopoverSurface), matching: find.byType(Material)).first,
      );
      final shape = material.shape! as RoundedRectangleBorder;
      expect(material.color, KaneoColors.light.popover);
      expect(shape.borderRadius, BorderRadius.circular(KaneoRadius.lg));
      expect(shape.side.color, KaneoColors.light.border);
    });

    testWidgets('it follows the dark theme', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await open<String?>(
        tester,
        wideSize,
        (context) => showActionMenu<String>(context, items: _items),
      );
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(PopoverSurface), matching: find.byType(Material)).first,
      );
      expect(material.color, KaneoColors.dark.popover);
    });

    testWidgets('menu items have the web app\'s size and colors', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) => showActionMenu<String>(context, items: _items),
      );
      expect(tester.getSize(rowOf('Copy')).height, 32);
      expect(tester.getSize(find.byIcon(Icons.copy)), const Size.square(16));
      final style = tester.renderObject<RenderParagraph>(find.text('Delete')).text.style!;
      expect(style.fontSize, 14);
      expect(style.color, KaneoColors.light.destructiveForeground);
      final disabled = tester.widget<Opacity>(
        find.ancestor(of: find.text('Unavailable'), matching: find.byType(Opacity)).first,
      );
      expect(disabled.opacity, 0.64);
    });

    testWidgets('sheet rows keep the current app\'s size', (tester) async {
      await open<String?>(
        tester,
        narrowSize,
        (context) => showActionMenu<String>(context, items: _items),
      );
      expect(tester.getSize(rowOf('Copy')).height, 48);
    });

    testWidgets('the current choice has a check mark, on the left', (tester) async {
      await open<String?>(
        tester,
        wideSize,
        (context) => pickStatus(context, columns: _columns, current: 'done'),
      );
      final done = tester.getRect(find.text('Done'));
      final checks = find.byIcon(LucideIcons.check);
      expect(checks, findsOneWidget);
      expect(tester.getCenter(checks).dy, closeTo(done.center.dy, 1));
      expect(tester.getCenter(checks).dx, lessThan(done.left));
    });

    testWidgets('the wide toast sits in the corner, 360 wide', (tester) async {
      await pumpInApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showToast(context, 'Saved', kind: ToastKind.success),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final toast = tester.getRect(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
      );
      expect(toast.width, 360);
      expect(toast.right, wideSize.width - 32);
      expect(toast.bottom, wideSize.height - 32);
    });

    testWidgets('the narrow toast spans the window, as in the current app', (tester) async {
      await pumpInApp(
        tester,
        Builder(
          builder: (context) =>
              TextButton(onPressed: () => showToast(context, 'Saved'), child: const Text('go')),
        ),
        size: narrowSize,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final toast = tester.getRect(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
      );
      expect(toast.width, greaterThan(narrowSize.width - 40));
    });

    testWidgets('each kind of toast has its icon', (tester) async {
      await pumpInApp(tester, const SizedBox());
      for (final (kind, color) in [
        (ToastKind.info, KaneoColors.light.info),
        (ToastKind.success, KaneoColors.light.success),
        (ToastKind.error, KaneoColors.light.destructive),
      ]) {
        showGlobalToast('Message', kind: kind);
        await tester.pumpAndSettle();
        final icon = tester.widget<Icon>(
          find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)),
        );
        expect(icon.color, color);
      }
    });

    testWidgets('the confirm dialog is the web app\'s alert dialog', (tester) async {
      await open<bool>(
        tester,
        wideSize,
        (context) =>
            showConfirm(context, title: 'Delete it?', destructive: true, confirmLabel: 'Yes'),
      );
      final dialog = find.byType(Dialog);
      final rect = tester.getRect(
        find.descendant(of: dialog, matching: find.byType(ConstrainedBox)).first,
      );
      expect(rect.width, 512);
      expect(rect.center.dx, wideSize.width / 2);
      final shape = tester.widget<Dialog>(dialog).shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
      final barrier = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last;
      expect(barrier.color, kaneoScrim);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style!.backgroundColor!.resolve(const {}), KaneoColors.light.destructive);
    });
  });

  group('showConfirm', () {
    for (final (name, size) in [('wide', wideSize), ('narrow', narrowSize)]) {
      testWidgets('Esc and clicking outside answer no ($name)', (tester) async {
        final runner = await open<bool>(
          tester,
          size,
          (context) => showConfirm(context, title: 'Sure?'),
        );
        await esc(tester);
        expect(runner.result, isFalse);
        await tester.tap(find.byKey(const ValueKey('open')));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.text('Sure?'), findsNothing);
        expect(runner.result, isFalse);
      });

      testWidgets('a long message scrolls ($name)', (tester) async {
        await open<bool>(
          tester,
          size,
          (context) => showConfirm(context, title: 'Sure?', message: 'Long words. ' * 800),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Save'), findsOneWidget);
      });
    }
  });

  group('showPanel', () {
    Future<String?> Function(BuildContext) panel() =>
        (context) => showPanel<String>(
          context,
          title: 'New task',
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).pop('made'),
            child: const Text('Create'),
          ),
        );

    testBothLayouts('resolves to what its content pops with', (tester, size) async {
      final runner = await open<String?>(tester, size, panel());
      expect(find.text('New task'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(runner.result, 'made');
    });

    testWidgets('is a centered dialog that Esc closes on wide windows', (tester) async {
      final runner = await open<String?>(tester, wideSize, panel());
      final rect = tester.getRect(find.byType(Dialog));
      expect(rect.center, wideSize.center(Offset.zero));
      await esc(tester);
      expect(find.text('New task'), findsNothing);
      expect(runner.result, isNull);
    });

    testWidgets('has a close button on wide windows', (tester) async {
      final runner = await open<String?>(tester, wideSize, panel());
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('New task'), findsNothing);
      expect(runner.result, isNull);
    });

    testWidgets('is a full page with a close button on narrow windows', (tester) async {
      final runner = await open<String?>(tester, narrowSize, panel());
      expect(find.byType(Dialog), findsNothing);
      expect(tester.getSize(find.byType(AppBar)).width, narrowSize.width);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('New task'), findsNothing);
      expect(runner.result, isNull);
    });
  });

  group('pickOption', () {
    testBothLayouts('a search hint adds a field that filters by label and subtitle', (
      tester,
      size,
    ) async {
      final runner = await open<Picked<String>?>(
        tester,
        size,
        (context) =>
            pickOption<String>(context, title: 'Pick', options: _options, searchHint: 'Search'),
      );
      await tester.enterText(find.byType(TextField), 'mor');
      await tester.pump();
      expect(find.text('First'), findsNothing);
      await tester.enterText(find.byType(TextField), 'nothing');
      await tester.pump();
      expect(find.textContaining('nothing'), findsWidgets);
      expect(find.text('Second'), findsNothing);
      await tester.enterText(find.byType(TextField), ' SEC ');
      await tester.pump();
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(runner.result?.value, 'b');
    });

    testWidgets('Esc works while the search field has focus', (tester) async {
      final runner = await open<Picked<String?>?>(
        tester,
        wideSize,
        (context) => pickAssignee(context, members: _members),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await esc(tester);
      expect(find.text('Ada'), findsNothing);
      expect(runner.finished, isTrue);
      expect(runner.result, isNull);
    });
  });

  group('crossing the breakpoint while open', () {
    testWidgets('a popover stays usable and in the window when the window narrows', (tester) async {
      final runner = await open<Picked<String>?>(
        tester,
        wideSize,
        (context) => pickOption<String>(context, title: 'Pick', options: _options),
        alignment: Alignment.bottomRight,
      );
      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final surface = tester.getRect(find.byType(PopoverSurface));
      expect(
        Offset.zero & narrowSize,
        predicate<Rect>((window) => window.contains(surface.topLeft)),
      );
      expect(surface.right, lessThanOrEqualTo(narrowSize.width));
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(runner.result?.value, 'b');
    });

    for (final (name, from, to) in [
      ('wide to narrow', wideSize, narrowSize),
      ('narrow to wide', narrowSize, wideSize),
    ]) {
      testWidgets('checked options survive $name', (tester) async {
        final runner = await open<Set<String>?>(
          tester,
          from,
          (context) =>
              pickMany<String>(context, title: 'Pick', options: _options, selected: const {}),
        );
        await tester.tap(find.text('Second'));
        await tester.pump();
        setWindowSize(tester, to);
        await tester.pumpAndSettle();
        await tester.tap(find.text('First'));
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(runner.result, {'a', 'b'});
      });

      testWidgets('text typed in the label picker survives $name', (tester) async {
        await open<Set<String>?>(
          tester,
          from,
          (context) => pickLabels(context, labels: _labels, selectedIds: const {}),
        );
        await tester.enterText(find.byType(TextField), 'bu');
        await tester.pump();
        setWindowSize(tester, to);
        await tester.pumpAndSettle();
        expect(find.text('bu'), findsOneWidget);
        expect(find.text('ui'), findsNothing);
      });
    }
  });

  testBothLayouts('an empty list of options shows no empty search result', (tester, size) async {
    await open<Picked<String>?>(
      tester,
      size,
      (context) => pickOption<String>(context, title: 'Pick', options: const []),
    );
    expect(find.text('Pick'), findsOneWidget);
    expect(find.textContaining('Nothing matches'), findsNothing);
  });

  group('pickAssignee', () {
    testBothLayouts('shows people with avatars, and finds them by email', (tester, size) async {
      await open<Picked<String?>?>(
        tester,
        size,
        (context) => pickAssignee(context, members: _members, current: 'u1'),
      );
      expect(find.text('AD'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bo@');
      await tester.pump();
      expect(find.text('Ada'), findsNothing);
      expect(find.text('Bo'), findsOneWidget);
    });
  });

  group('pickLabels', () {
    Future<_Runner<Set<String>?>> openLabels(
      WidgetTester tester,
      Size size, {
      Future<Label> Function(String name, String color)? onCreate,
      List<Label> labels = _labels,
    }) => open<Set<String>?>(
      tester,
      size,
      (context) =>
          pickLabels(context, labels: labels, selectedIds: const {'l1'}, onCreate: onCreate),
    );

    testBothLayouts('the field filters the labels', (tester, size) async {
      await openLabels(tester, size);
      await tester.enterText(find.byType(TextField), 'BU');
      await tester.pump();
      expect(find.text('bug'), findsOneWidget);
      expect(find.text('ui'), findsNothing);
    });

    testBothLayouts('without onCreate there is nothing to create', (tester, size) async {
      await openLabels(tester, size);
      await tester.enterText(find.byType(TextField), 'brand new');
      await tester.pump();
      expect(find.textContaining('Create label'), findsNothing);
      expect(find.textContaining('brand new'), findsWidgets);
    });

    testBothLayouts('a new name creates a label in the chosen color, selected', (
      tester,
      size,
    ) async {
      final created = <(String, String)>[];
      final runner = await openLabels(
        tester,
        size,
        onCreate: (name, color) async {
          created.add((name, color));
          return Label(id: 'l3', name: name, color: color);
        },
      );
      await tester.enterText(find.byType(TextField), ' Docs ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('label-color-teal')));
      await tester.pump();
      await tester.tap(find.textContaining('Create label'));
      await tester.pumpAndSettle();
      expect(created, [('Docs', 'teal')]);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.textContaining('Create label'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(runner.result, {'l1', 'l3'});
    });

    testBothLayouts('an existing name offers no create, whatever its case', (tester, size) async {
      await openLabels(tester, size, onCreate: (name, color) async => throw StateError('no'));
      await tester.enterText(find.byType(TextField), 'BUG');
      await tester.pump();
      expect(find.textContaining('Create label'), findsNothing);
    });

    testBothLayouts('a failed create says why and keeps the text', (tester, size) async {
      await openLabels(
        tester,
        size,
        onCreate: (name, color) async => throw const ApiError('Name is taken', status: 400),
      );
      await tester.enterText(find.byType(TextField), 'Docs');
      await tester.pump();
      await tester.tap(find.textContaining('Create label'));
      await tester.pumpAndSettle();
      expect(find.text('Name is taken'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
    });

    testBothLayouts('with no labels yet, it says so', (tester, size) async {
      final i18n = await loadTestI18n(tester);
      await openLabels(tester, size, labels: const [], onCreate: (name, color) async => _labels[0]);
      expect(find.text(i18n.t('mobile:taskFields.noLabels')), findsOneWidget);
    });
  });

  group('pickDate', () {
    Future<_Runner<Picked<DateTime?>?>> openDate(
      WidgetTester tester,
      Size size, {
      DateTime? current,
    }) => open<Picked<DateTime?>?>(
      tester,
      size,
      (context) => pickDate(context, title: 'Due', current: current),
    );

    testBothLayouts('opens on the current month and pages through months', (tester, size) async {
      await openDate(tester, size, current: DateTime(2026, 3, 9));
      expect(find.text('March 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      expect(find.text('April 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pump();
      expect(find.text('February 2026'), findsOneWidget);
    });

    testBothLayouts('pages across the year', (tester, size) async {
      await openDate(tester, size, current: DateTime(2026, 12, 9));
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      expect(find.text('January 2027'), findsOneWidget);
    });

    testBothLayouts('the shortcuts resolve to local midnight', (tester, size) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final (label, expected) in [
        ('Today', today),
        ('Tomorrow', DateTime(now.year, now.month, now.day + 1)),
        ('Next week', nextMonday(today)),
      ]) {
        final runner = _Runner<Picked<DateTime?>?>();
        await pumpInApp(
          tester,
          runner.button((context) => pickDate(context, title: 'Due')),
          size: size,
        );
        await tester.tap(find.byKey(const ValueKey('open')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(runner.result?.value, expected);
      }
    });

    testBothLayouts('without a date there is nothing to clear', (tester, size) async {
      await openDate(tester, size);
      expect(find.text('Clear'), findsNothing);
    });

    testBothLayouts('dismissing keeps the date, unlike clearing', (tester, size) async {
      final runner = await openDate(tester, size, current: DateTime(2026, 3, 9));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(runner.finished, isTrue);
      expect(runner.result, isNull);
    });
  });
}
