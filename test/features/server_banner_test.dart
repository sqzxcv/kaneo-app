import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/shell/server_banner.dart';

import '../support/test_app.dart';

final _banner = find.byKey(serverBannerKey);

/// Runs the app once with the server there, so that what [location] shows is cached, then starts it
/// again with the server out of reach, as after quitting the app and losing the network.
Future<TestApp> startOffline(
  WidgetTester tester,
  FakeKaneo server,
  Size size, {
  String location = AppRoutes.home,
}) async {
  final stores = CacheStores(null);
  await pumpKaneoApp(
    tester,
    server: server,
    size: size,
    location: location,
    overrides: [cacheStoresProvider.overrideWithValue(stores)],
  );
  await tester.pumpWidget(const SizedBox());
  server.unreachable = true;
  return pumpKaneoApp(
    tester,
    server: server,
    size: size,
    location: location,
    overrides: [cacheStoresProvider.overrideWithValue(stores)],
  );
}

void main() {
  testBothLayouts('starting offline shows what was saved and says the server is out of reach', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final app = await startOffline(tester, server, size);
    expect(inPage(find.text('Demo')), findsOneWidget);
    expect(_banner, findsOneWidget);
    expect(
      find.descendant(of: _banner, matching: find.text(app.i18n.t('mobile:errors.unreachable'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _banner, matching: find.text(app.i18n.t('mobile:common.retry'))),
      findsOneWidget,
    );
  });

  testBothLayouts('the inbox says so too', (tester, size) async {
    final server = FakeKaneo();
    await startOffline(tester, server, size, location: AppRoutes.inbox);
    expect(_banner, findsOneWidget);
  });

  testBothLayouts('trying again once the server is back clears it and loads anew', (
    tester,
    size,
  ) async {
    final server = FakeKaneo();
    final app = await startOffline(tester, server, size);
    server.unreachable = false;
    server.projects.first['name'] = 'Demo renamed';
    await tester.tap(
      find.descendant(of: _banner, matching: find.text(app.i18n.t('mobile:common.retry'))),
    );
    await tester.pumpAndSettle();
    expect(_banner, findsNothing);
    expect(inPage(find.text('Demo renamed')), findsOneWidget);
  });

  testBothLayouts('trying again while still offline keeps it', (tester, size) async {
    final server = FakeKaneo();
    final app = await startOffline(tester, server, size);
    await tester.tap(
      find.descendant(of: _banner, matching: find.text(app.i18n.t('mobile:common.retry'))),
    );
    await tester.pumpAndSettle();
    expect(_banner, findsOneWidget);
    expect(inPage(find.text('Demo')), findsOneWidget);
  });

  testWidgets('on a phone it sits below the status bar, and the page below it', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.resetPadding);
    final server = FakeKaneo();
    final app = await startOffline(tester, server, narrowSize);
    final banner = tester.getRect(_banner);
    expect(banner.top, 47);
    final search = tester.getRect(inPage(find.byTooltip(app.i18n.t('mobile:home.search'))));
    expect(search.top, greaterThanOrEqualTo(banner.bottom));
    // The page's bar doesn't leave the status bar's room again below the banner.
    expect(search.top - banner.bottom, lessThan(47));
  });

  testBothLayouts('online, there is none', (tester, size) async {
    await pumpKaneoApp(tester, size: size);
    expect(_banner, findsNothing);
  });

  testBothLayouts('a server that answers with an error is not out of reach', (tester, size) async {
    final server = FakeKaneo()..fail('api/task/tasks/', status: 500);
    await pumpKaneoApp(
      tester,
      server: server,
      size: size,
      location: AppRoutes.board(FakeKaneo.projectId),
    );
    expect(_banner, findsNothing);
  });
}
