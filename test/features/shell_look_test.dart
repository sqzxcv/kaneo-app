import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/test_app.dart';

/// Stronger than this and a translucent fill is a wash over what's behind it, not a tint.
const double _strongestTint = 0.15;

bool _isWash(Color? color) => color != null && color.a > _strongestTint && color.a < 0.95;

/// Everything on screen that paints a translucent color of its own, or would when hovered.
List<String> _washes(WidgetTester tester) {
  final found = <String>[];
  void look(BoxDecoration? decoration, String what) {
    if (_isWash(decoration?.color)) found.add('$what fill ${decoration!.color}');
    final border = decoration?.border;
    if (border is Border && _isWash(border.bottom.color)) {
      found.add('$what border ${border.bottom}');
    }
  }

  for (final container in tester.widgetList<Container>(find.byType(Container))) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration) look(decoration, 'Container');
  }
  for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) look(decoration, 'DecoratedBox');
  }
  for (final well in tester.widgetList<InkWell>(find.byType(InkWell))) {
    if (_isWash(well.hoverColor)) found.add('InkWell hover ${well.hoverColor}');
  }
  return found;
}

/// Found by looking at the real thing for KAN-48. Nothing here failed, and comments in the activity
/// were close to unreadable.
void main() {
  test('faded keeps a translucent color translucent', () {
    const token = Color(0x0AFFFFFF);
    expect(token.faded(0.5).a, closeTo(token.a / 2, 0.001));
    expect(const Color(0xFF000000).faded(0.5).a, closeTo(0.5, 0.001));
  });

  for (final mode in const ['light', 'dark']) {
    group('with the $mode theme', () {
      for (final (name, location) in const [
        ('home', AppRoutes.home),
        ('inbox', AppRoutes.inbox),
        ('my tasks', AppRoutes.myTasks),
        ('activity', AppRoutes.activity),
      ]) {
        testBothLayouts('$name has no wash of black or white', (tester, size) async {
          final server = FakeKaneo();
          server.addComment('task-1', 'A comment in the activity');
          await pumpKaneoApp(
            tester,
            server: server,
            size: size,
            location: location,
            preferences: {'kaneo.themeMode': mode},
          );
          expect(_washes(tester), isEmpty);
        });
      }

      testBothLayouts('search results have no wash of black or white', (tester, size) async {
        await pumpKaneoApp(
          tester,
          size: size,
          location: AppRoutes.search,
          preferences: {'kaneo.themeMode': mode},
        );
        await tester.enterText(find.byKey(const ValueKey('search-field')), 'board');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.text('Review the board layout'), findsOneWidget);
        expect(_washes(tester), isEmpty);
      });
    });
  }
}
