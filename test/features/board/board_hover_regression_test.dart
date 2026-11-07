import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../../support/test_app.dart';

void main() {
  testBothLayouts('hovered picker rows remain safe when their content rebuilds', (
    tester,
    size,
  ) async {
    final label = ValueNotifier('First');
    addTearDown(label.dispose);
    await pumpInApp(
      tester,
      ValueListenableBuilder<String>(
        valueListenable: label,
        builder: (context, value, child) => HoverHighlight(
          child: ListTile(title: Text(value), onTap: () {}),
        ),
      ),
      size: size,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ListTile)));
    await tester.pumpAndSettle();
    label.value = 'Second';
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('hovering a board project choice does not hide ListTile ink or throw', (
    tester,
  ) async {
    await pumpKaneoApp(tester, location: AppRoutes.board(FakeKaneo.projectId));
    await tester.tap(inPage(find.text('Demo')));
    await tester.pumpAndSettle();
    final choice = find.descendant(
      of: find.byType(PopoverSurface),
      matching: find.text('Second project'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(choice));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });
}
