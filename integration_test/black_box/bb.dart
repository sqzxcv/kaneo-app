// The black-box harness for KAN-52: starts the app the way main() does, signs in through the login
// page, and finds things only by what is on screen: text, tooltips and semantics labels. Results go
// to results.jsonl beside the screenshots, one line per case and device.
//
// Run through tool/with_device.sh, with the black-box accounts, never dev.env:
//
//     tool/with_device.sh --boot "iPad Pro 13-inch (M5)" flutter test integration_test/black_box/login_test.dart \
//       -d "iPad Pro 13-inch (M5)" --dart-define-from-file=$HOME/.config/kaneo-app/black-box.env \
//       --dart-define=BB_DEVICE=ipad-pro-13 --dart-define=BB_EVIDENCE=<folder outside the repository>
//     FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=app.kaneo.kaneoApp.QTest tool/with_device.sh \
//       flutter test integration_test/black_box/login_test.dart -d macos \
//       --dart-define-from-file=$HOME/.config/kaneo-app/black-box.env --dart-define=BB_DEVICE=macos
//
// macOS keeps the evidence in the app's container, because of its sandbox, and prints where.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaneo_app/app.dart';
import 'package:kaneo_app/bootstrap.dart';
import 'package:kaneo_app/core/core.dart'
    show MemorySessionStorage, SessionStorage, notificationChecksEnabledKey;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:window_manager/window_manager.dart';

import 'screen.dart';
import 'server.dart';

export 'package:flutter/gestures.dart';
export 'package:flutter/material.dart';
export 'package:flutter/services.dart';
export 'package:flutter_test/flutter_test.dart';

export 'screen.dart';
export 'server.dart';

const device = String.fromEnvironment('BB_DEVICE', defaultValue: 'device');
const _evidence = String.fromEnvironment('BB_EVIDENCE');

bool get isMacOS => Platform.isMacOS;
bool get isPhone => device.startsWith('iphone');
bool get isTablet => device.startsWith('ipad');

final _capture = GlobalKey();
Directory? _evidenceRoot;

Future<Directory> evidenceDirectory() async {
  if (_evidenceRoot != null) return _evidenceRoot!;
  final Directory directory;
  if (Platform.isMacOS || _evidence.isEmpty) {
    directory = Directory('${(await getApplicationDocumentsDirectory()).path}/KAN-52/$device');
  } else {
    directory = Directory('$_evidence/$device');
  }
  await directory.create(recursive: true);
  debugPrint('BB_EVIDENCE_DIR ${directory.path}');
  return _evidenceRoot = directory;
}

/// Links the app handed to the system during the current case, recorded instead of opened: the
/// tests never open the owner's browser, mail or files. Whether a link really opens is for a person.
final openedLinks = <String>[];

/// What the app handed to the system share sheet, recorded instead of shown.
final sharedItems = <String>[];

class _RecordingLauncher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    openedLinks.add(url);
    debugPrint('BB_LINK $url');
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    openedLinks.add(url);
    debugPrint('BB_LINK $url');
    return true;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;

  @override
  Future<void> closeWebView() async {}
}

class _RecordingShare extends SharePlatform {
  @override
  Future<ShareResult> share(ShareParams params) async {
    sharedItems.add([params.subject, params.text, params.uri].whereType<Object>().join(' | '));
    debugPrint('BB_SHARE ${sharedItems.last}');
    return const ShareResult('recorded by the black-box tests', ShareResultStatus.success);
  }
}

/// Keeps everything the app would hand to the system inside the test.
void _stayInside() {
  UrlLauncherPlatform.instance = _RecordingLauncher();
  SharePlatform.instance = _RecordingShare();
}

/// The columns of E-Board, and of every new project, which has the last four.
const boardColumnNames = ['需求池', '已计划', 'To Do', 'In Progress', 'In Review', 'Done'];

/// Signs out from the account page, confirming.
Future<void> signOut(Bb bb) async {
  await bb.nav('Account');
  await bb.tap(bb.text('Sign out'));
  final confirm = find.widgetWithText(FilledButton, 'Sign out');
  if (await bb.until(() => bb.visible(confirm), seconds: 5)) await bb.tap(confirm.hitTestable());
  await bb.see(bb.field('Password'), seconds: 20, reason: 'Not back on the login page');
}

/// One line of results.jsonl.
Future<void> record(
  String id,
  String result, {
  String note = '',
  List<String> evidence = const [],
}) async {
  final directory = await evidenceDirectory();
  final line = jsonEncode({
    'id': id,
    'device': device,
    'result': result,
    'note': note,
    'evidence': evidence,
    'at': DateTime.now().toIso8601String(),
  });
  await File('${directory.path}/results.jsonl').writeAsString('$line\n', mode: FileMode.append);
  debugPrint('BB_RESULT $line');
}

/// Registers the module's setup: the window, the saved preferences, which every launch clears and
/// the end of the module puts back.
void blackBoxModule() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Object> saved;
  setUpAll(() async {
    expect(Env.server, isNotEmpty, reason: 'Run with black-box.env');
    expect(Env.isLocal, isTrue, reason: 'Local Kaneo only');
    if (isMacOS) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1366, 1024));
    }
    final prefs = await SharedPreferences.getInstance();
    saved = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    _stayInside();
  });
  tearDownAll(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    for (final MapEntry(:key, :value) in saved.entries) {
      if (value is bool) await prefs.setBool(key, value);
      if (value is String) await prefs.setString(key, value);
      if (value is int) await prefs.setInt(key, value);
      if (value is double) await prefs.setDouble(key, value);
      if (value is List<String>) await prefs.setStringList(key, value);
    }
  });
}

/// A case of the KAN-52 table. [body] passes or throws; either way the result is recorded, with a
/// screenshot and what was on screen when it failed. [simulated] says how a pass was simulated.
void bbCase(
  String id,
  String title,
  Future<void> Function(Bb bb) body, {
  String? simulated,
  String? unverified,
  Timeout timeout = const Timeout(Duration(minutes: 6)),
}) {
  testWidgets('$id $title', (tester) async {
    final bb = Bb(tester, id);
    final semantics = tester.ensureSemantics();
    _stayInside();
    openedLinks.clear();
    sharedItems.clear();
    try {
      await body(bb);
      if (openedLinks.isNotEmpty) bb.note('links handed to the system: $openedLinks');
      if (sharedItems.isNotEmpty) bb.note('shared: $sharedItems');
      final error = tester.takeException();
      if (error != null) throw StateError('The app reported an error: $error');
      final why = unverified ?? bb.unverified;
      await record(
        id,
        why != null ? 'unverified' : (simulated == null ? 'pass' : 'pass-simulated'),
        note: [?why, ?simulated, ...bb.notes].join('; '),
        evidence: bb.shots,
      );
    } catch (error) {
      try {
        await bb.shot('FAIL');
        await bb.dumpScreen('FAIL');
      } catch (_) {}
      await record(id, 'fail', note: '$error | ${bb.notes.join('; ')}', evidence: bb.shots);
      rethrow;
    } finally {
      semantics.dispose();
    }
  }, timeout: timeout);
}

/// A case this machine can't verify on this device, recorded with the reason.
void bbUnverified(String id, String title, String reason) {
  testWidgets('$id $title (unverified)', (tester) async {
    await record(id, 'unverified', note: reason);
  });
}

/// Drives the app for one case.
class Bb {
  Bb(this.tester, this.id);

  final WidgetTester tester;
  final String id;
  final shots = <String>[];
  final notes = <String>[];
  ProviderContainer? _container;
  SessionStorage? storage;

  /// Set when part of the case can't be verified on this machine, with the reason.
  String? unverified;

  void note(String text) {
    notes.add(text);
    debugPrint('BB_NOTE $id $text');
  }

  // --- Starting ---

  /// Starts the app as main() does. Preferences are cleared unless [keepPrefs], as on a fresh
  /// install. [storage] holds the session; it is the system keychain when [keychain] is set.
  Future<void> launch({bool keepPrefs = false, bool keychain = false}) async {
    tester.testTextInput.register();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    if (!keepPrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      // Already decided, so that starting doesn't ask the system for notification permission.
      await prefs.setBool(notificationChecksEnabledKey, false);
    }
    if (!keychain) storage ??= MemorySessionStorage();
    final container = await bootstrap(sessionStorage: keychain ? null : storage);
    _container = container;
    // After the app's own start, in case it registered the real plugins again.
    _stayInside();
    if (UrlLauncherPlatform.instance is! _RecordingLauncher ||
        SharePlatform.instance is! _RecordingShare) {
      throw StateError('Links or sharing would leave the app; stopping before anything opens');
    }
    if (isPhone) await _upright();
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: UncontrolledProviderScope(container: container, child: const KaneoApp()),
      ),
    );
    addTearDown(() async {
      if (_container == container) await stop();
    });
    await pumpFor(const Duration(milliseconds: 500));
  }

  /// A simulator has no hand holding it: once an app has turned it sideways it stays so. Each
  /// launch starts it upright again, as a person holding a phone would.
  Future<void> _upright() async {
    if (!landscape) return;
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    for (var i = 0; i < 40 && landscape; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await SystemChrome.setPreferredOrientations(const []);
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Takes the app away, as when it's killed. The session store and preferences stay.
  Future<void> stop() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    _container?.dispose();
    _container = null;
    await SystemChrome.setPreferredOrientations(const []);
  }

  /// Kills and opens the app again.
  Future<void> restart({bool keychain = false}) async {
    await stop();
    await launch(keepPrefs: true, keychain: keychain);
  }

  /// Signs in through the login page with a password.
  Future<void> signIn(Account account, {String? server, bool expectHome = true}) async {
    await see(find.text('Sign in'));
    await type(field('Server address'), server ?? Env.server);
    await tap(find.text('Email and password'));
    await type(field('Email'), account.email);
    await type(field('Password'), account.password);
    await tap(find.widgetWithText(FilledButton, 'Sign in'));
    if (expectHome) await waitHome();
  }

  Future<void> signInWithKey(String key, {String? server, bool expectHome = true}) async {
    await see(find.text('Sign in'));
    await type(field('Server address'), server ?? Env.server);
    await tap(find.text('API key'));
    await type(field('API key'), key);
    await tap(find.widgetWithText(FilledButton, 'Sign in'));
    if (expectHome) await waitHome();
  }

  /// Launches and signs in as [account], ready on the home page.
  Future<void> start(Account account, {String? server}) async {
    await launch();
    await signIn(account, server: server);
  }

  Future<void> waitHome() async {
    await see(find.text('Your projects'), seconds: 30);
  }

  // --- The window ---

  Size get window => tester.view.physicalSize / tester.view.devicePixelRatio;
  bool get wide => window.shortestSide >= 600;
  bool get landscape => window.width > window.height;

  /// Makes the app's view [size], as a split screen or a turned device would. Undone at the end.
  Future<void> setViewSize(Size logical) async {
    tester.view.physicalSize = logical * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await pumpFor(const Duration(milliseconds: 600));
  }

  // --- Finding ---

  /// A text field, by the label or hint it shows.
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  Finder text(String text) => find.text(text, findRichText: true);

  /// Drawn text only, leaving out text fields, such as the filter field or an open task's title.
  Finder card(String text) =>
      find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text);
  Finder containing(Pattern text) => find.textContaining(text, findRichText: true);
  Finder tip(Pattern message) => find.byTooltip(message);

  /// The board's filter button, which says how many filters are on.
  Finder get filtersButton => find.byTooltip(RegExp(r'^(Filters|Filter tasks… \(\d+ active\))$'));
  Finder label(Pattern label) => find.bySemanticsLabel(
    label is String ? RegExp('(^|\\n)${RegExp.escape(label)}(\$|\\n)') : label,
  );

  bool showing(Finder finder) => finder.evaluate().isNotEmpty;

  /// Whether [finder] has something that can be hit on screen now.
  bool visible(Finder finder) => finder.hitTestable().evaluate().isNotEmpty;

  Rect rectOf(Finder finder) => tester.getRect(finder.first);

  /// Everything the screen says, for checks over all of it.
  List<String> screenTexts() => [
    for (final e in find.byType(RichText).evaluate())
      if ((e.widget as RichText).text.toPlainText().trim().isNotEmpty)
        (e.widget as RichText).text.toPlainText(),
  ];

  // --- Waiting ---

  Future<void> pumpFor(Duration time) async {
    final end = DateTime.now().add(time);
    do {
      await tester.pump(const Duration(milliseconds: 50));
    } while (DateTime.now().isBefore(end));
  }

  Future<bool> until(bool Function() ready, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!ready() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return ready();
  }

  Future<void> see(Finder finder, {int seconds = 20, String? reason}) async {
    if (!await until(() => finder.evaluate().isNotEmpty, seconds: seconds)) {
      throw TestFailure(reason ?? 'Not on screen within ${seconds}s: $finder');
    }
  }

  Future<void> gone(Finder finder, {int seconds = 20, String? reason}) async {
    if (!await until(() => finder.evaluate().isEmpty, seconds: seconds)) {
      throw TestFailure(reason ?? 'Still on screen after ${seconds}s: $finder');
    }
  }

  /// Waits for the server to agree, keeping the app running meanwhile.
  Future<T> server<T>(String what, Future<T?> Function() check, {int seconds = 15}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    Object? last;
    while (true) {
      try {
        final value = await check();
        if (value != null && value != false) return value;
      } catch (e) {
        last = e;
      }
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('The server never had $what${last == null ? '' : ' ($last)'}');
      }
      await pumpFor(const Duration(milliseconds: 300));
    }
  }

  // --- Acting ---

  Future<void> tap(Finder finder, {int seconds = 20}) async {
    await see(finder, seconds: seconds);
    var target = finder.first;
    if (target.hitTestable().evaluate().isEmpty) {
      try {
        await tester.ensureVisible(target);
        await pumpFor(const Duration(milliseconds: 300));
      } catch (_) {}
    }
    final hittable = finder.hitTestable();
    if (hittable.evaluate().isNotEmpty) target = hittable.first;
    await tester.tap(target, warnIfMissed: false);
    await pumpFor(const Duration(milliseconds: 400));
  }

  Future<void> type(Finder finder, String text) async {
    await see(finder);
    await tester.showKeyboard(finder.first);
    await tester.enterText(finder.first, text);
    await pumpFor(const Duration(milliseconds: 200));
  }

  Future<void> submitKeyboard([TextInputAction action = TextInputAction.done]) async {
    await tester.testTextInput.receiveAction(action);
    await pumpFor(const Duration(milliseconds: 300));
  }

  Future<void> escape() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(const Duration(milliseconds: 400));
  }

  Future<void> longPress(Finder finder) async {
    await see(finder);
    await tester.longPress(finder.first, warnIfMissed: false);
    await pumpFor(const Duration(milliseconds: 500));
  }

  /// A right click, as a mouse makes it: it arrives, moves over, presses, lets go and leaves.
  Future<void> rightClick(Finder finder) async {
    await see(finder);
    final at = tester.getCenter(finder.first);
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.addPointer(location: at - const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 30));
    await mouse.moveTo(at);
    await tester.pump(const Duration(milliseconds: 30));
    await mouse.down(at);
    await tester.pump(const Duration(milliseconds: 60));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 30));
    await mouse.removePointer();
    await pumpFor(const Duration(milliseconds: 500));
  }

  /// Opens [finder]'s menu the way this device does: a right click with a mouse, else a long press.
  Future<void> openMenu(Finder finder) async => isMacOS ? rightClick(finder) : longPress(finder);

  /// Where to take hold of [title]'s card: its title. Cards have no grip since KAN-69.
  Offset grip(String title) => rectOf(card(title)).center;

  /// How long to hold before moving: a finger picks a card up with a long press, and a mouse may
  /// rest on it as long as it likes.
  Duration get pickUp => const Duration(milliseconds: 700);

  /// Drags [title]'s card to [to], the way this device does.
  Future<void> dragCard(String title, Offset to, {int steps = 20}) =>
      drag(grip(title), to, hold: pickUp, steps: steps);

  /// Drags with a finger, or the mouse on macOS: press, hold, move in steps, release.
  Future<void> drag(
    Offset from,
    Offset to, {
    Duration hold = const Duration(milliseconds: 700),
    int steps = 20,
    Duration stepTime = const Duration(milliseconds: 16),
    Duration atEnd = const Duration(milliseconds: 200),
  }) async {
    final gesture = await tester.startGesture(
      from,
      kind: isMacOS ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await pumpFor(hold);
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
      await tester.pump(stepTime);
    }
    await pumpFor(atEnd);
    await gesture.up();
    if (isMacOS) await gesture.removePointer();
    await tester.pump(const Duration(milliseconds: 16));
  }

  // --- Navigating, the way a person does ---

  /// Goes to a page of the navigation: Home, Inbox, My tasks, Activity or Account.
  Future<void> nav(String page) async {
    if (wide) {
      // The sidebar's entry: the leftmost of what says [page].
      final entry = label(page).hitTestable();
      await see(entry);
      final hits = entry.evaluate().toList()
        ..sort(
          (a, b) => tester
              .getRect(find.byElementPredicate((e) => e == a))
              .left
              .compareTo(tester.getRect(find.byElementPredicate((e) => e == b)).left),
        );
      await tap(find.byElementPredicate((e) => e == hits.first));
      return;
    }
    final tab = label(
      RegExp('(^|\\n)${RegExp.escape(page)}(\\n|\$).*Tab \\d of \\d', dotAll: true),
    );
    final home = label(RegExp('(^|\\n)Home\\n.*Tab \\d of \\d', dotAll: true));
    for (var i = 0; i < 4 && !visible(home); i++) {
      await back();
    }
    if (page == 'Account') {
      if (!visible(tip('Account'))) await tap(home.hitTestable());
      await tap(tip('Account').hitTestable());
      return;
    }
    await tap(tab.hitTestable());
  }

  /// The value beside a task property's name, such as Status or Due date, which opens its picker.
  Finder valueOf(String property) {
    final names = text(property).hitTestable().evaluate().toList();
    for (final n in names) {
      final r = tester.getRect(find.byElementPredicate((x) => x == n));
      final candidates = find.byType(RichText).hitTestable().evaluate().where((e) {
        final v = tester.getRect(find.byElementPredicate((x) => x == e));
        return (v.center.dy - r.center.dy).abs() < 14 && v.left > r.right + 2;
      }).toList();
      if (candidates.isEmpty) continue;
      candidates.sort(
        (a, b) => tester
            .getRect(find.byElementPredicate((x) => x == a))
            .left
            .compareTo(tester.getRect(find.byElementPredicate((x) => x == b)).left),
      );
      // The text of the value, skipping an icon drawn before it.
      final first = candidates.firstWhere(
        (e) => (e.widget as RichText).text.toPlainText().trim().length > 1,
        orElse: () => candidates.first,
      );
      return find.byElementPredicate((x) => x == first);
    }
    return find.byElementPredicate((_) => false);
  }

  /// The text a property shows, such as 'To Do' beside Status.
  String valueText(String property) {
    final f = valueOf(property);
    if (f.evaluate().isEmpty) return '';
    return (f.evaluate().first.widget as RichText).text.toPlainText();
  }

  /// The open task's title field, by what it says.
  Finder titleField(String title) =>
      find.byWidgetPredicate((w) => w is EditableText && w.controller.text == title);

  /// Opens [title] from the board on screen, by tapping its card.
  Future<void> openCard(String title) async {
    await tap(card(title).hitTestable());
    await see(titleField(title), seconds: 20, reason: 'The task did not open');
    await pumpFor(const Duration(milliseconds: 500));
  }

  /// Closes the open task, wherever it opened.
  Future<void> closeTask() async {
    final close = tip('Close').hitTestable();
    if (visible(close)) {
      final hits = close.evaluate().toList();
      // The panel's own close button, at its top right.
      hits.sort(
        (a, b) => tester
            .getRect(find.byElementPredicate((x) => x == b))
            .right
            .compareTo(tester.getRect(find.byElementPredicate((x) => x == a)).right),
      );
      await tap(find.byElementPredicate((x) => x == hits.first));
    } else {
      await back();
    }
    await pumpFor(const Duration(milliseconds: 600));
  }

  /// The titles among [titles] that are in [column] on the board, top to bottom.
  List<String> orderIn(String column, List<String> titles) {
    final found = <(double, String)>[];
    for (final t in titles) {
      final f = card(t);
      if (!showing(f)) continue;
      if (columnOf(f) != column) continue;
      found.add((rectOf(f).top, t));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, t) in found) t];
  }

  /// Types into the board's filter field, opening it first where a narrow toolbar folds it away.
  Future<void> typeFilter(String text) async {
    final field = this.field('Filter tasks…');
    if (!showing(field) && visible(tip('Filter tasks…'))) {
      await tap(tip('Filter tasks…').hitTestable());
    }
    await type(field, text);
  }

  /// The filter field's text, or empty when the field is folded away.
  String filterText() {
    final field = this.field('Filter tasks…');
    if (!showing(field)) return '';
    return tester.widget<TextField>(field.first).controller?.text ?? '';
  }

  /// The board's horizontal scroll view.
  Finder get boardScroll => find
      .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)
      .first;

  /// Swipes the board sideways until [column]'s title shows.
  Future<void> scrollBoardTo(String column) async {
    final title = text(column);
    if (visible(title)) return;
    await tester.scrollUntilVisible(title, 250, scrollable: boardScroll, maxScrolls: 30);
    await pumpFor(const Duration(milliseconds: 300));
  }

  /// Goes back, with the page's back button, or the panel's close button.
  Future<void> back() async {
    for (final f in [tip('Back'), tip('Close')]) {
      if (visible(f)) {
        await tap(f.hitTestable());
        return;
      }
    }
    await tester.pageBack();
    await pumpFor(const Duration(milliseconds: 400));
  }

  Future<void> openProject(String name) async {
    await nav('Home');
    final card = label(RegExp('^${RegExp.escape(name)}\\n'));
    await see(card, seconds: 30);
    await tap(card);
    await see(filtersButton, seconds: 30);
  }

  /// Opens [name] from the home page if the card is there, without waiting for the board.
  Future<void> openProjectOrFail(String name) async {
    final card = label(RegExp('^${RegExp.escape(name)}\\n'));
    if (await until(() => visible(card), seconds: 10)) await tap(card.hitTestable());
  }

  /// The board column [card] is in: the nearest column title to its left, above it.
  String? columnOf(Finder card, {List<String> names = boardColumnNames}) {
    final hits = card.evaluate();
    if (hits.isEmpty) return null;
    final box = tester.getRect(card.first);
    String? best;
    var bestLeft = double.negativeInfinity;
    for (final name in names) {
      for (final e in find.text(name).evaluate()) {
        final r = tester.getRect(find.byElementPredicate((x) => x == e));
        if (r.top >= box.top) continue;
        if (r.left - 40 <= box.center.dx && r.left > bestLeft) {
          bestLeft = r.left;
          best = name;
        }
      }
    }
    return best;
  }

  // --- Evidence ---

  Future<String> shot(String name) async {
    await pumpFor(const Duration(milliseconds: 300));
    final boundary = _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: isMacOS ? 1 : 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = await evidenceDirectory();
    final file = File('${directory.path}/$id-$name.png');
    // The evidence folder may not tell upper from lower case: replace what is there.
    if (await file.exists()) await file.delete();
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    shots.add('$device/$id-$name.png');
    debugPrint('BB_SHOT ${file.path}');
    return file.path;
  }

  Future<void> dumpScreen(String name) async {
    final directory = await evidenceDirectory();
    await File('${directory.path}/$id-$name.txt').writeAsString(
      '${semanticsLines(tester).join('\n')}\n\n--- text ---\n${textLines(tester).join('\n')}\n',
    );
  }
}
