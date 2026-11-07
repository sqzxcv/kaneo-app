import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/auth/login_page.dart';
import 'package:kaneo_app/features/markdown/markdown_view.dart';
import 'package:kaneo_app/features/task/description_autosave.dart';
import 'package:kaneo_app/features/task/task_description.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/test_app.dart';

/// Things a Markdown editor tends to rewrite: line endings, trailing spaces and blank lines, list
/// markers, escapes, entities, Kaneo's tags, tabs in code, and characters that have two spellings.
const _source =
    '# 标题  \r\n'
    '\r\n'
    'Two spaces then a break  \n'
    '* star\n'
    '- dash\n'
    '+ plus\n'
    '\n'
    '1) paren\n'
    '\n'
    '- [x] done\n'
    '- [ ] todo\n'
    '\n'
    '<kaneo-mention id="u1" label="Ana"></kaneo-mention> and '
    '<kaneo-attachment url="https://files.test/a.pdf" filename="a.pdf" '
    'mime-type="application/pdf" size="2048" />\n'
    '\n'
    '<img src="https://files.test/d.png" alt="D" width="320" />\n'
    '\n'
    '| a | b |\n'
    '|---|:-:|\n'
    '| 1 | 2 |\n'
    '\n'
    '```dart\n'
    '\tfinal x = "y";  \n'
    '```\n'
    '\n'
    '__bold__ *em* \\*escaped\\* &amp; non breaking 🙂 é "quotes" -- dashes\n'
    '\n'
    '\n'
    'The end\n'
    '\n';

const _savePath = 'api/task/description/doc';

final _box = find.byType(TextField);

List<String> _saves(FakeKaneo server, [String path = _savePath]) => [
  for (final request in server.requestsTo(path, method: 'PUT'))
    (request.body! as Map)['description'] as String,
];

Future<TestApp> _pump(
  WidgetTester tester,
  Size size, {
  String description = 'Original text',
  FakeKaneo? server,
  void Function(FakeKaneo server)? setUp,
  bool settle = true,
}) {
  final fake = server ?? FakeKaneo();
  fake.addTask(id: 'doc', title: 'Doc', description: description);
  setUp?.call(fake);
  return pumpKaneoApp(
    tester,
    server: fake,
    size: size,
    location: AppRoutes.task('doc'),
    settle: settle,
  );
}

/// A tap on the first words of the description. The middle of it can be empty space.
Future<void> _tapText(WidgetTester tester) =>
    tester.tapAt(tester.getTopLeft(find.byType(SelectableText).first) + const Offset(8, 8));

Future<void> _openBox(WidgetTester tester) async {
  await _tapText(tester);
  await tester.pumpAndSettle();
  expect(_box, findsOneWidget);
}

TextEditingController _controller(WidgetTester tester) =>
    tester.widget<TextField>(_box).controller!;

/// What an input method sends. Unlike `enterText`, it can leave text unconfirmed.
Future<void> _input(
  WidgetTester tester,
  String text, {
  TextRange composing = TextRange.empty,
}) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: composing,
    ),
  );
  await tester.pump();
}

/// Runs the delay out, and whatever the save it starts needs.
Future<void> _waitForSave(WidgetTester tester) async {
  await tester.pump(descriptionSaveDelay);
  await tester.pump();
  await tester.pump();
}

/// A tap in the app bar, away from the text box and from anything that reacts.
Future<void> _tapOutside(WidgetTester tester, Size size) async {
  await tester.tapAt(Offset(size.width / 2, 12));
  await tester.pumpAndSettle();
}

/// Ends a test that has unsaved text. Closing the page sends it, and that request has to finish.
Future<void> _closePage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

String _shown(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((widget) => widget.textSpan!.toPlainText())
    .join('\n');

Finder _toast(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.textContaining(text));

void main() {
  group('tapping the description', () {
    testBothLayouts('opens its source in a plain text box with no toolbar', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: _source);
      expect(_box, findsNothing);
      expect(_shown(tester), isNot(contains('<kaneo')));

      await _openBox(tester);

      expect(_controller(tester).text, _source);
      expect(find.byType(MarkdownView), findsNothing);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(tester.testTextInput.isVisible, isTrue);
      final tools = find.descendant(
        of: find.byType(TaskDescription),
        matching: find.byWidgetPredicate((w) => w is IconButton || w is Icon || w is ToggleButtons),
      );
      expect(tools, findsNothing);
      expect(_saves(server), isEmpty);
    });

    testBothLayouts('opens from empty space beside the text', (tester, size) async {
      await _pump(tester, size, description: 'Short');
      final area = tester.getRect(find.byType(TaskDescription));
      await tester.tapAt(area.centerRight - const Offset(4, 0));
      await tester.pumpAndSettle();
      expect(_box, findsOneWidget);
    });

    testBothLayouts('opens an empty description, and offers to add one', (tester, size) async {
      final app = await _pump(tester, size, description: '');
      final hint = app.i18n.t('mobile:taskDetail.screen.addDescription');
      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      expect(_controller(tester).text, '');
      await tester.enterText(_box, 'First words');
      await _waitForSave(tester);
      expect(_saves(app.server), ['First words']);
    });

    testBothLayouts('keeps blank-only text as it is', (tester, size) async {
      final app = await _pump(tester, size, description: ' \n\n ');
      await tester.tap(find.text(app.i18n.t('mobile:taskDetail.screen.addDescription')));
      await tester.pumpAndSettle();
      expect(_controller(tester).text, ' \n\n ');
    });

    testBothLayouts('shows an old HTML description as the HTML it is', (tester, size) async {
      const html = '<h2>Old</h2><p>Text <strong>bold</strong></p>';
      final app = await _pump(tester, size, description: html);
      expect(_shown(tester), isNot(contains('<h2>')));
      await _openBox(tester);
      expect(_controller(tester).text, html);
      await _tapOutside(tester, size);
      expect(_saves(app.server), isEmpty);
    });

    testBothLayouts('on a link opens the link and not the text box', (tester, size) async {
      final opened = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        opened.add((call.arguments as Map)['url'] as String);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await _pump(tester, size, description: '[Open](https://files.test/a)');
      await tester.tapAt(tester.getTopLeft(find.byType(SelectableText)) + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(opened, ['https://files.test/a']);
      expect(_box, findsNothing);
    });

    testBothLayouts('shows progress, then starts from the server\'s text', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server, description: 'On screen');
      server.tasks.firstWhere((t) => t['id'] == 'doc')['description'] = 'Changed on the web';

      final gate = server.hold(RegExp(r'api/task/doc$'), method: 'GET');
      await _tapText(tester);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(_box, findsNothing);

      gate.release();
      await tester.pumpAndSettle();
      expect(_controller(tester).text, 'Changed on the web');

      await tester.enterText(_box, 'Changed on the web, and here');
      await _waitForSave(tester);
      expect(_saves(app.server), ['Changed on the web, and here']);
    });

    testBothLayouts('says why when the text cannot be fetched, and can try again', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server);
      server.failNext(
        RegExp(r'api/task/doc$'),
        method: 'GET',
        status: 500,
        body: {'message': 'Fetch broke'},
      );
      await _tapText(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(_toast('Fetch broke'), findsOneWidget);
      expect(_box, findsNothing);
      expect(find.byType(MarkdownView), findsOneWidget);
      await tester.pumpAndSettle();

      await _openBox(tester);
    });

    testBothLayouts('does nothing without permission to update tasks', (tester, size) async {
      final server = FakeKaneo()..capabilities['updateTasks'] = false;
      await _pump(tester, size, server: server);
      final reads = server.requestsTo(RegExp(r'api/task/doc$')).length;
      await _tapText(tester);
      await tester.pumpAndSettle();
      expect(_box, findsNothing);
      final area = tester.getRect(find.byType(TaskDescription));
      await tester.tapAt(area.centerRight - const Offset(4, 0));
      await tester.pumpAndSettle();
      expect(_box, findsNothing);
      expect(server.requestsTo(RegExp(r'api/task/doc$')), hasLength(reads));
    });

    testBothLayouts('without permission, says an empty description is empty', (tester, size) async {
      final server = FakeKaneo()..capabilities['updateTasks'] = false;
      final app = await _pump(tester, size, server: server, description: '');
      expect(find.text(app.i18n.t('app:description.empty')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:taskDetail.screen.addDescription')), findsNothing);
    });

    testBothLayouts('still works when permissions cannot be read', (tester, size) async {
      final server = FakeKaneo()..fail('capabilities', status: 500);
      await _pump(tester, size, server: server);
      await _openBox(tester);
    });
  });

  group('a description the server sends separately', () {
    void deferred(FakeKaneo server) {
      server
        ..on(
          RegExp(r'api/task/big$'),
          (_) => FakeResponse(200, {
            ...server.tasks.firstWhere((t) => t['id'] == 'big'),
            'description': null,
            'descriptionDeferred': true,
          }),
        )
        ..on('api/task/big/description', (request) {
          final first = request.query['offset'] == '0';
          return FakeResponse(200, {
            'content': first ? 'first page, ' : 'second page',
            'version': 'v1',
            'nextOffset': first ? 12 : null,
          });
        });
    }

    Future<void> pumpBig(WidgetTester tester, Size size, FakeKaneo server) async {
      server.addTask(id: 'big', title: 'Big', description: 'unused');
      deferred(server);
      await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('big'));
    }

    testBothLayouts('is shown whole, and opens whole', (tester, size) async {
      final server = FakeKaneo();
      await pumpBig(tester, size, server);
      expect(_shown(tester), 'first page, second page');

      await _openBox(tester);
      expect(_controller(tester).text, 'first page, second page');
      await _tapOutside(tester, size);
      expect(_saves(server, 'api/task/description/big'), isEmpty);
    });

    testBothLayouts('saving an edit sends the whole text', (tester, size) async {
      final server = FakeKaneo();
      await pumpBig(tester, size, server);
      await _openBox(tester);
      await tester.enterText(_box, 'first page, second page!');
      await _waitForSave(tester);
      expect(_saves(server, 'api/task/description/big'), ['first page, second page!']);
    });

    testBothLayouts('shows that it is loading', (tester, size) async {
      final server = FakeKaneo();
      server.addTask(id: 'big', title: 'Big', description: 'unused');
      deferred(server);
      final gate = server.hold('api/task/big/description');
      await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('big'),
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
      expect(_shown(tester), 'first page, second page');
    });

    testBothLayouts('offers to try again when it cannot be read', (tester, size) async {
      final server = FakeKaneo();
      server.addTask(id: 'big', title: 'Big', description: 'unused');
      deferred(server);
      server.clearOverrides();
      server.failNext('api/task/big/description', status: 500);
      deferred(server);
      final app = await pumpKaneoApp(
        tester,
        server: server,
        size: size,
        location: AppRoutes.task('big'),
      );
      expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(_shown(tester), 'first page, second page');
    });
  });

  group('nothing but the edit changes', () {
    testBothLayouts('opening and leaving saves nothing', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: _source);
      await _openBox(tester);
      await tester.pump(const Duration(seconds: 5));
      await _tapOutside(tester, size);
      expect(_box, findsNothing);
      expect(_saves(server), isEmpty);
    });

    testBothLayouts('moving the cursor saves nothing', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: _source);
      await _openBox(tester);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: _source, selection: TextSelection.collapsed(offset: 3)),
      );
      await tester.pump(const Duration(seconds: 5));
      await _tapOutside(tester, size);
      expect(_saves(server), isEmpty);
    });

    testBothLayouts('typing and undoing it saves nothing', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: _source);
      await _openBox(tester);
      await _input(tester, '${_source}x');
      await _input(tester, _source);
      await tester.pump(const Duration(seconds: 5));
      await _tapOutside(tester, size);
      expect(_saves(server), isEmpty);
    });

    testBothLayouts('one change in the middle leaves every other character alone', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: _source);
      await _openBox(tester);
      final edited = _source.replaceFirst('- dash', '- dashes');
      await _input(tester, edited);
      await _waitForSave(tester);

      expect(_saves(server), [edited]);
      expect(server.tasks.firstWhere((t) => t['id'] == 'doc')['description'], edited);
    });

    testBothLayouts('the text box does nothing that rewrites text or stops Chinese input', (
      tester,
      size,
    ) async {
      await _pump(tester, size);
      await _openBox(tester);
      final field = tester.widget<TextField>(_box);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.inputFormatters, isNull);
      expect(field.maxLength, isNull);
      expect(field.maxLines, isNull);
      expect(field.enableSuggestions, isTrue);
      expect(field.keyboardType, TextInputType.multiline);
      expect(field.textInputAction, TextInputAction.newline);
      expect(field.obscureText, isFalse);
    });
  });

  group('saving', () {
    testBothLayouts('happens about a second after typing stops', (tester, size) async {
      final app = await _pump(tester, size);
      await _openBox(tester);

      await tester.enterText(_box, 'One');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.enterText(_box, 'One two');
      await tester.pump(const Duration(milliseconds: 900));
      expect(_saves(app.server), isEmpty);
      expect(find.text(app.i18n.t('app:description.saved')), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump();
      expect(_saves(app.server), ['One two']);
      expect(find.text(app.i18n.t('app:description.saved')), findsOneWidget);
      expect(_box, findsOneWidget, reason: 'Still typing, so the text box stays.');
    });

    testBothLayouts('says when it is under way', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      final gate = server.hold(_savePath, method: 'PUT');
      await tester.enterText(_box, 'One');
      await _waitForSave(tester);
      expect(find.text(app.i18n.t('app:description.saving')), findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
      expect(find.text(app.i18n.t('app:description.saved')), findsOneWidget);
    });

    testBothLayouts('happens at once on leaving the text box, which then closes', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server);
      await _openBox(tester);
      await tester.enterText(_box, 'Left quickly **bold**');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_saves(server), isEmpty);

      await _tapOutside(tester, size);
      expect(_saves(server), ['Left quickly **bold**']);
      expect(_box, findsNothing);
      expect(_shown(tester), contains('Left quickly bold'));
    });

    testBothLayouts('the text box stays until the save is done', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server);
      await _openBox(tester);
      final gate = server.hold(_savePath, method: 'PUT');
      await tester.enterText(_box, 'Slow');
      await tester.tapAt(Offset(size.width / 2, 12));
      await tester.pump();
      await tester.pump();
      expect(_box, findsOneWidget);
      gate.release();
      await tester.pumpAndSettle();
      expect(_box, findsNothing);
      expect(_shown(tester), contains('Slow'));
    });

    testBothLayouts('happens at once on leaving the page', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      await tester.enterText(_box, 'Left the page');
      await tester.pump(const Duration(milliseconds: 100));

      app.container.read(routerProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(_saves(server), ['Left the page']);
      expect(server.tasks.firstWhere((t) => t['id'] == 'doc')['description'], 'Left the page');
    });

    testBothLayouts('happens at once when the app goes to the background', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server);
      await _openBox(tester);
      await tester.enterText(_box, 'Went away');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_saves(server), isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(milliseconds: 10));
      expect(_saves(server), ['Went away']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    testBothLayouts('goes to the task it was typed in, even when moving to another', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      server.addTask(id: 'other', title: 'Other', description: 'Other text');
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      await tester.enterText(_box, 'For doc');

      app.container.read(routerProvider).go(AppRoutes.task('other'));
      await tester.pumpAndSettle();
      expect(_saves(server), ['For doc']);
      expect(_saves(server, 'api/task/description/other'), isEmpty);
      expect(_shown(tester), 'Other text');
      expect(_box, findsNothing);
    });

    testBothLayouts('the page shows the new text when opened again', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      await tester.enterText(_box, 'New text');
      final router = app.container.read(routerProvider);
      router.go(AppRoutes.home);
      await tester.pumpAndSettle();

      final gate = server.hold(RegExp(r'api/task/doc$'), method: 'GET');
      router.go(AppRoutes.task('doc'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(_shown(tester), 'New text', reason: 'The cached copy must not be the old text.');
      gate.release();
      await tester.pumpAndSettle();
      expect(_shown(tester), 'New text');
    });

    testBothLayouts('a slow response does not overwrite newer typing', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server);
      await _openBox(tester);
      final gate = server.hold(_savePath, method: 'PUT');
      await tester.enterText(_box, 'One');
      await _waitForSave(tester);
      await tester.enterText(_box, 'One two');
      await tester.pump();

      gate.release();
      await tester.pump();
      await tester.pump();
      expect(_controller(tester).text, 'One two');

      await _waitForSave(tester);
      expect(_saves(server), ['One', 'One two']);
      expect(_controller(tester).text, 'One two');
    });

    testBothLayouts('a refresh does not touch the open text box', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server, description: 'Mine');
      await _openBox(tester);
      await tester.enterText(_box, 'Mine, edited');
      server.tasks.firstWhere((t) => t['id'] == 'doc')['description'] = 'From the web';

      unawaited(app.container.read(taskQuery('doc').notifier).refresh());
      await tester.pump(const Duration(milliseconds: 10));
      expect(_controller(tester).text, 'Mine, edited');
      await _closePage(tester);
    });

    testBothLayouts('leaving unchanged shows what a refresh brought', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server, description: 'Mine');
      await _openBox(tester);
      server.tasks.firstWhere((t) => t['id'] == 'doc')['description'] = 'From the web';
      unawaited(app.container.read(taskQuery('doc').notifier).refresh());
      await tester.pump(const Duration(milliseconds: 10));
      expect(_controller(tester).text, 'Mine');

      await _tapOutside(tester, size);
      expect(_saves(server), isEmpty);
      expect(_shown(tester), 'From the web');
    });
  });

  group('a failed save', () {
    Future<void> showToast(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
    }

    testBothLayouts('keeps the text and says why', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      server.fail(_savePath, status: 500, body: {'message': 'Database down'}, method: 'PUT');

      await tester.enterText(_box, 'Precious words');
      await _waitForSave(tester);
      await showToast(tester);

      expect(_toast('Database down'), findsOneWidget);
      expect(_controller(tester).text, 'Precious words');
      expect(find.text(app.i18n.t('app:description.notSaved')), findsOneWidget);
      await _closePage(tester);
    });

    testBothLayouts('keeps the text when the server cannot be reached', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      server.unreachable = true;

      await tester.enterText(_box, 'Precious words');
      await _waitForSave(tester);
      await showToast(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(_controller(tester).text, 'Precious words');
      expect(find.text(app.i18n.t('app:description.notSaved')), findsOneWidget);
      await _closePage(tester);
    });

    testBothLayouts('keeps the text without permission to save', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server);
      await _openBox(tester);
      server.fail(_savePath, status: 403, body: {'message': 'Not allowed'}, method: 'PUT');

      await tester.enterText(_box, 'Precious words');
      await _waitForSave(tester);
      await showToast(tester);

      expect(_toast('Not allowed'), findsOneWidget);
      expect(_controller(tester).text, 'Precious words');
      await _closePage(tester);
    });

    testBothLayouts('can be tried again, and the box closes once it works', (tester, size) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      server.failNext(_savePath, status: 500, method: 'PUT');
      await tester.enterText(_box, 'Precious words');
      await tester.tapAt(Offset(size.width / 2, 12));
      await tester.pumpAndSettle();
      expect(_box, findsOneWidget, reason: 'Left the box, but the text is not safe yet.');
      expect(_controller(tester).text, 'Precious words');

      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(_saves(server), ['Precious words', 'Precious words']);
      expect(_box, findsNothing);
      expect(_shown(tester), 'Precious words');
    });

    testBothLayouts('goes through on the next edit', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server);
      await _openBox(tester);
      server.failNext(_savePath, status: 500, method: 'PUT');
      await tester.enterText(_box, 'One');
      await _waitForSave(tester);
      await tester.enterText(_box, 'One two');
      await _waitForSave(tester);
      expect(_saves(server), ['One', 'One two']);
      expect(server.tasks.firstWhere((t) => t['id'] == 'doc')['description'], 'One two');
    });

    testBothLayouts('on leaving the page keeps the text for when the task is opened again', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      server.failNext(_savePath, status: 500, body: {'message': 'Database down'}, method: 'PUT');
      await tester.enterText(_box, 'Precious words');

      final router = app.container.read(routerProvider);
      router.go(AppRoutes.home);
      await tester.pump();
      await tester.pump();
      await showToast(tester);
      expect(_toast('Database down'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_box, findsNothing);

      router.go(AppRoutes.task('doc'));
      await tester.pumpAndSettle();
      expect(_controller(tester).text, 'Precious words');
      expect(find.text(app.i18n.t('app:description.notSaved')), findsOneWidget);

      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      await tester.pumpAndSettle();
      expect(_box, findsNothing);
      expect(_shown(tester), 'Precious words');
      expect(server.tasks.firstWhere((t) => t['id'] == 'doc')['description'], 'Precious words');
    });

    testBothLayouts('after the session ended goes to the login page and says why', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server);
      await _openBox(tester);
      server.credentialsRevoked = true;
      await tester.enterText(_box, 'Words');
      await _waitForSave(tester);
      await showToast(tester);
      expect(_toast(app.i18n.t('mobile:errors.sessionExpired')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(app.container.read(sessionProvider), isNull);
    });
  });

  group('input methods', () {
    testBothLayouts('text still being composed is not saved', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: 'Hello ');
      await _openBox(tester);

      await _input(tester, 'Hello ni', composing: const TextRange(start: 6, end: 8));
      await tester.pump(const Duration(seconds: 3));
      await _input(tester, "Hello ni'hao", composing: const TextRange(start: 6, end: 12));
      await tester.pump(const Duration(seconds: 3));
      expect(_saves(server), isEmpty);

      await _closePage(tester);
      expect(_saves(server), ["Hello ni'hao"], reason: 'Leaving must not lose what is on screen.');
    });

    testBothLayouts('a chosen candidate appears and saves once', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: 'Hello ');
      await _openBox(tester);

      await _input(tester, "Hello ni'hao", composing: const TextRange(start: 6, end: 12));
      await tester.pump(const Duration(seconds: 3));
      await _input(tester, 'Hello 你好');
      expect(_controller(tester).text, 'Hello 你好');
      await _waitForSave(tester);
      await tester.pump(const Duration(seconds: 3));

      expect(_saves(server), ['Hello 你好']);
      expect(_controller(tester).text, 'Hello 你好');
    });

    testBothLayouts('confirming the letters as typed still saves', (tester, size) async {
      final server = FakeKaneo();
      await _pump(tester, size, server: server, description: 'Hello ');
      await _openBox(tester);

      await _input(tester, 'Hello ni', composing: const TextRange(start: 6, end: 8));
      await tester.pump(const Duration(seconds: 3));
      await _input(tester, 'Hello ni');
      await _waitForSave(tester);
      expect(_saves(server), ['Hello ni']);
    });

    testBothLayouts('a save or refresh finishing during composing leaves the input method alone', (
      tester,
      size,
    ) async {
      final server = FakeKaneo();
      final app = await _pump(tester, size, server: server, description: 'Hello');
      await _openBox(tester);

      final gate = server.hold(_savePath, method: 'PUT');
      await _input(tester, 'Hello 世界');
      await _waitForSave(tester);
      expect(find.text(app.i18n.t('app:description.saving')), findsOneWidget);

      const composing = TextEditingValue(
        text: 'Hello 世界ni',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 8, end: 10),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      tester.testTextInput.log.clear();
      final field = tester.element(_box);

      gate.release();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text(app.i18n.t('app:description.saving')), findsNothing);
      expect(
        find.text(app.i18n.t('app:description.saved')),
        findsNothing,
        reason: 'The text being composed is not saved yet.',
      );
      unawaited(app.container.read(taskQuery('doc').notifier).refresh());
      await tester.pump(const Duration(seconds: 3));

      expect(_controller(tester).value, composing);
      expect(tester.element(_box), same(field), reason: 'The text box was rebuilt from scratch.');
      final disturbing = tester.testTextInput.log.where(
        (call) => const {
          'TextInput.setEditingState',
          'TextInput.setClient',
          'TextInput.clearClient',
          'TextInput.hide',
        }.contains(call.method),
      );
      expect(disturbing, isEmpty);
      expect(_saves(server), ['Hello 世界'], reason: 'The composing text stays unsaved.');
      await _closePage(tester);
    });
  });

  test('every language has the new text', () async {
    for (final locale in ['en-US', 'zh-CN', 'zh-TW']) {
      final file = await readCatalogFile('assets/i18n/overrides/$locale.json');
      final texts = (file!['app'] as Map)['description'] as Map;
      for (final key in ['saving', 'saved', 'notSaved', 'saveFailed', 'empty']) {
        expect(texts[key], isNotEmpty, reason: '$locale $key');
      }
      expect(texts['saveFailed'], contains('{{reason}}'), reason: locale);
    }
  });

  testWidgets('has no icons that could pass for a formatting toolbar', (tester) async {
    await _pump(tester, wideSize);
    await _openBox(tester);
    for (final icon in const [LucideIcons.bold, LucideIcons.italic, LucideIcons.list]) {
      expect(find.byIcon(icon), findsNothing);
    }
  });
}
