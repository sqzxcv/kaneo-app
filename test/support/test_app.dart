import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_kaneo.dart';

export 'fake_kaneo.dart';

/// The two layouts every page is tested in.
const Size wideSize = Size(1366, 1024);
const Size narrowSize = Size(390, 844);

/// A session on [FakeKaneo], signed in with its API key.
const Session testSession = Session(
  serverUrl: FakeKaneo.serverUrl,
  credentialType: CredentialType.apiKey,
  token: FakeKaneo.apiKey,
  userId: FakeKaneo.userId,
  userName: 'Test User',
  userEmail: FakeKaneo.email,
);

/// Registers [description] twice, once per layout. [body] gets the layout's window size.
void testBothLayouts(
  String description,
  Future<void> Function(WidgetTester tester, Size size) body,
) {
  testWidgets('$description (wide)', (tester) => body(tester, wideSize));
  testWidgets('$description (narrow)', (tester) => body(tester, narrowSize));
}

final Map<String, Map<String, dynamic>?> _catalogs = {};

/// Reads the same files the app bundles. Parsing them once keeps the suite fast.
Future<Map<String, dynamic>?> readCatalogFile(String asset) async {
  if (_catalogs.containsKey(asset)) return _catalogs[asset];
  final file = File(asset);
  return _catalogs[asset] = await file.exists()
      ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
      : null;
}

/// Loads a language outside the test's fake clock.
Future<I18n> loadTestI18n(WidgetTester tester, {String locale = defaultLocale}) async =>
    (await tester.runAsync(() => I18n.load(locale: locale, read: readCatalogFile)))!;

void setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Provider overrides that run the app against [server], with nothing kept on disk.
Future<List<Override>> _overrides(
  I18n i18n,
  FakeKaneo server, {
  Session? session,
  SessionStorage? sessionStorage,
  String location = AppRoutes.home,
  DevConfig devConfig = const DevConfig(),
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  return [
    prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
    i18nProvider.overrideWithValue(i18n),
    httpAdapterProvider.overrideWithValue(server),
    sessionStorageProvider.overrideWithValue(sessionStorage ?? MemorySessionStorage(session)),
    initialSessionProvider.overrideWithValue(session),
    initialLocationProvider.overrideWithValue(location),
    devConfigProvider.overrideWithValue(devConfig),
  ];
}

/// What a test holds on to after [pumpKaneoApp].
class TestApp {
  const TestApp(this.container, this.server, this.i18n);

  final ProviderContainer container;
  final FakeKaneo server;
  final I18n i18n;
}

/// Runs the whole app, with its router and theme, against [server] at the given window size.
///
/// Starts signed in on [location]. Pass `session: null` to start signed out. Waits for the first
/// page to finish loading; pass `settle: false` to look at it while a request is held with
/// `server.hold(...)`.
Future<TestApp> pumpKaneoApp(
  WidgetTester tester, {
  FakeKaneo? server,
  Size size = wideSize,
  Session? session = testSession,
  SessionStorage? sessionStorage,
  String location = AppRoutes.home,
  String locale = defaultLocale,
  DevConfig devConfig = const DevConfig(),
  Map<String, Object> preferences = const {},
  bool settle = true,
}) async {
  setWindowSize(tester, size);
  final fake = server ?? FakeKaneo();
  final i18n = await loadTestI18n(tester, locale: locale);
  final overrides = await _overrides(
    i18n,
    fake,
    session: session,
    sessionStorage: sessionStorage,
    location: location,
    devConfig: devConfig,
    preferences: preferences,
  );
  final container = ProviderContainer(retry: (count, error) => null, overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const KaneoApp()));
  if (settle) await tester.pumpAndSettle();
  return TestApp(container, fake, i18n);
}

/// Runs a single widget with the app's theme, translations and providers, without the router. The
/// widget gets a `Scaffold` around it, and `child` can be a `Builder` for tests that need a context.
Future<TestApp> pumpInApp(
  WidgetTester tester,
  Widget child, {
  FakeKaneo? server,
  Size size = wideSize,
  Session? session = testSession,
  String locale = defaultLocale,
  bool settle = true,
}) async {
  setWindowSize(tester, size);
  final fake = server ?? FakeKaneo();
  final i18n = await loadTestI18n(tester, locale: locale);
  final overrides = await _overrides(i18n, fake, session: session);
  final container = ProviderContainer(retry: (count, error) => null, overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: I18nScope(
        i18n: i18n,
        child: MaterialApp(
          scaffoldMessengerKey: rootMessengerKey,
          theme: kaneoLightTheme,
          darkTheme: kaneoDarkTheme,
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return TestApp(container, fake, i18n);
}
