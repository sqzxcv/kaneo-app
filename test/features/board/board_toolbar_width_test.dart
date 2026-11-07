import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/test_app.dart';
import 'board_filter_page_test.dart' show filterMenu, search;

void main() {
  for (final size in [const Size(600, 600), const Size(700, 700), wideSize, narrowSize]) {
    testWidgets('toolbar fits $size with active filters and a long project name', (tester) async {
      final server = FakeKaneo();
      server.projects.first['name'] = 'B A very long project name to exercise narrow page widths';
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.board(FakeKaneo.projectId),
      );
      expect(tester.takeException(), isNull);
      await filterMenu(tester, 'Me');
      expect(find.byKey(const ValueKey('filter-count')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await search(tester, 'Set up');
      final field = find.byKey(const ValueKey('board-search'));
      expect(tester.getSize(field).width, greaterThanOrEqualTo(100));
      expect(find.text('Set up the project'), findsOneWidget);
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('list-task-task-1')), findsOneWidget);
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('filter-count')), findsNothing);
      if (find.byKey(const ValueKey('board-search-toggle')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('board-search-toggle')));
        await tester.pumpAndSettle();
      }
      expect(find.byTooltip('Refresh').hitTestable(), findsOneWidget);
      expect(find.byTooltip('New task').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('actual toolbar width changes with the window and preserves the query', (
    tester,
  ) async {
    await pumpKaneoApp(tester, location: AppRoutes.board(FakeKaneo.projectId));
    await search(tester, 'Set up');
    setWindowSize(tester, const Size(600, 600));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-search-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-search')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('board-search-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('board-search'))).controller!.text,
      'Set up',
    );
    expect(find.byIcon(LucideIcons.listFilter).hitTestable(), findsOneWidget);
    setWindowSize(tester, wideSize);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-search-toggle')), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('board-search'))).controller!.text,
      'Set up',
    );
    expect(tester.takeException(), isNull);
  });
}
