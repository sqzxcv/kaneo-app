import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('wide board filters use the shared anchored menu', (tester) async {
    await pumpKaneoApp(tester, location: AppRoutes.board(FakeKaneo.projectId));
    await tester.tap(find.byIcon(LucideIcons.listFilter));
    await tester.pumpAndSettle();
    expect(find.text('Overdue only'), findsOneWidget);
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'KAN-30 requires the wide anchored menu supplied by KAN-26',
    );
  });
  testWidgets('wide project switcher uses the shared anchored picker', (tester) async {
    await pumpKaneoApp(tester, location: AppRoutes.board(FakeKaneo.projectId));
    await tester.tap(inPage(find.text('Demo')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(PopoverSurface), matching: find.text('Second project')),
      findsOneWidget,
    );
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'KAN-30 requires the wide anchored picker supplied by KAN-26',
    );
  });
}
