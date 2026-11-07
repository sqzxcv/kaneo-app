import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

/// Comfortably past the point where a press becomes a long press.
const _held = Duration(milliseconds: 600);

void main() {
  late List<Offset> asked;

  Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
    asked = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MenuGestures(
            onMenu: enabled ? asked.add : null,
            child: const SizedBox(width: 200, height: 100, child: Text('card')),
          ),
        ),
      ),
    );
  }

  testWidgets('a long press and a right-click both ask for the menu at the pointer', (
    tester,
  ) async {
    await pump(tester);
    final point = tester.getCenter(find.text('card'));
    await tester.longPressAt(point);
    await tester.tapAt(point + const Offset(10, 0), buttons: kSecondaryButton);
    expect(asked, [point, point + const Offset(10, 0)]);
  });

  testWidgets('a tap or a short press does not', (tester) async {
    await pump(tester);
    await tester.tap(find.text('card'));
    final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(_held);
    expect(asked, isEmpty);
  });

  testWidgets('without a menu, neither asks', (tester) async {
    await pump(tester, enabled: false);
    await tester.longPress(find.text('card'));
    await tester.tapAt(tester.getCenter(find.text('card')), buttons: kSecondaryButton);
    expect(asked, isEmpty);
  });

  // A route that opens cancels the pointer, but integration tests drop that cancel, and with it the
  // press's end: the next long press on the same card used to do nothing (KAN-63).
  testWidgets('a long press whose end never arrives does not stop the next one', (tester) async {
    await pump(tester);
    final point = tester.getCenter(find.text('card'));
    final first = await tester.startGesture(point);
    await tester.pump(_held);
    expect(asked, hasLength(1));
    for (var i = 2; i <= 3; i++) {
      final next = await tester.startGesture(point);
      await tester.pump(_held);
      expect(asked, hasLength(i), reason: 'long press $i');
      await next.up();
    }
    await first.up();
    await tester.pump();
    expect(asked, hasLength(3));
  });

  testWidgets('screen readers can still long-press it', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester.getSemantics(find.text('card')),
      matchesSemantics(label: 'card', hasLongPressAction: true),
    );
    semantics.dispose();
  });
}
