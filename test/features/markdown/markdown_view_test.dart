import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/markdown/markdown_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/test_app.dart';

const _attachment =
    '<kaneo-attachment url="https://files.test/report.pdf" filename="report.pdf" '
    'mime-type="application/pdf" size="2048" />';
const _issueLink =
    '<kaneo-issue-link url="https://k.test/task/t1" issue-key="KAN-1" task-id="t1" />';
const _embed = '<kaneo-embed url="https://www.youtube.com/watch?v=abc123" mode="embed" />';
const _mention = '<kaneo-mention id="u1" label="Ana"></kaneo-mention>';
const _sizedImage = '<img src="https://files.test/d.png" alt="Diagram" width="320" />';

/// A 1x1 PNG.
const _pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

Future<TestApp> _pump(
  WidgetTester tester,
  String data,
  Size size, {
  Session? session = testSession,
  bool settle = true,
}) => pumpInApp(
  tester,
  SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: MarkdownView(data: data),
  ),
  size: size,
  session: session,
  settle: settle,
);

Iterable<TextSpan> _spans(WidgetTester tester) sync* {
  for (final widget in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
    final found = <TextSpan>[];
    widget.textSpan!.visitChildren((span) {
      if (span is TextSpan) found.add(span);
      return true;
    });
    yield* found;
  }
}

/// All the text on screen.
String _text(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((widget) => widget.textSpan!.toPlainText())
    .join('\n');

/// The span holding [text].
TextSpan _span(WidgetTester tester, String text) =>
    _spans(tester).firstWhere((span) => span.text?.contains(text) ?? false);

/// Answers link taps, and lists what was opened.
List<String> _mockLinks(WidgetTester tester, {bool opens = true}) {
  final opened = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    opened.add((call.arguments as Map)['url'] as String);
    return opens;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return opened;
}

/// Waits for a real decode of [_pixel], which the test clock can't do by itself.
Future<void> _decodePixel(WidgetTester tester) async {
  final element = tester.element(find.byType(MarkdownView));
  await tester.runAsync(() => precacheImage(MemoryImage(base64Decode(_pixel)), element));
  await tester.pumpAndSettle();
}

NetworkImage _networkImage(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).image as NetworkImage;

void main() {
  group('Markdown', () {
    testBothLayouts('renders headings', (tester, size) async {
      await _pump(tester, '# One\n\n## Two\n\n### Three\n\nBody', size);
      expect(_text(tester), isNot(contains('#')));
      final one = _span(tester, 'One').style!;
      final two = _span(tester, 'Two').style!;
      final three = _span(tester, 'Three').style!;
      final body = _span(tester, 'Body').style!;
      expect(one.fontSize, greaterThan(two.fontSize!));
      expect(two.fontSize, greaterThan(three.fontSize!));
      expect(three.fontSize, greaterThan(body.fontSize!));
      expect(one.fontWeight, FontWeight.w600);
    });

    testBothLayouts('renders bold, italic, strikethrough, underline and inline code', (
      tester,
      size,
    ) async {
      await _pump(tester, '**bold** *soft* ~~gone~~ ++under++ `mono`', size);
      expect(_text(tester), 'bold soft gone under mono');
      expect(_span(tester, 'bold').style!.fontWeight, FontWeight.w600);
      expect(_span(tester, 'soft').style!.fontStyle, FontStyle.italic);
      expect(_span(tester, 'gone').style!.decoration, TextDecoration.lineThrough);
      expect(_span(tester, 'under').style!.decoration, TextDecoration.underline);
      expect(_span(tester, 'mono').style!.fontFamily, KaneoFonts.mono);
    });

    testBothLayouts('renders links in the link color', (tester, size) async {
      await _pump(tester, 'See [the site](https://kaneo.app) now', size);
      expect(_text(tester), 'See the site now');
      final span = _span(tester, 'the site');
      expect(span.style!.decoration, TextDecoration.underline);
      expect(span.recognizer, isNotNull);
      expect(_span(tester, 'See').recognizer, isNull);
    });

    testBothLayouts('renders bullet and nested lists', (tester, size) async {
      await _pump(tester, '- one\n- two\n  - inner\n    - deep', size);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('◦'), findsOneWidget);
      expect(find.text('▪'), findsOneWidget);
      expect(
        _text(tester),
        allOf(contains('one'), contains('two'), contains('inner'), contains('deep')),
      );
      final outer = tester.getTopLeft(find.text('one'));
      final inner = tester.getTopLeft(find.text('inner'));
      expect(inner.dx, greaterThan(outer.dx));
    });

    testBothLayouts('renders ordered lists from their first number', (tester, size) async {
      await _pump(tester, '3. three\n4. four\n\n1. one', size);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsOneWidget);
      expect(find.text('5.'), findsOneWidget);
      expect(_text(tester), allOf(contains('three'), contains('four'), contains('one')));
    });

    testBothLayouts('renders to-dos with their state', (tester, size) async {
      await _pump(tester, '- [ ] open\n- [x] done\n- [X] also\n  - [ ] nested', size);
      expect(_text(tester), isNot(contains('[')));
      expect(find.byIcon(LucideIcons.square), findsNWidgets(2));
      expect(find.byIcon(LucideIcons.squareCheck), findsNWidgets(2));
      expect(find.text('•'), findsNothing);
      for (final item in ['open', 'done', 'also', 'nested']) {
        expect(_text(tester), contains(item));
      }
    });

    testBothLayouts('renders to-dos that are far apart', (tester, size) async {
      await _pump(tester, '- [ ] open\n\n- [x] done', size);
      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.byIcon(LucideIcons.squareCheck), findsOneWidget);
      expect(find.text('•'), findsNothing);
      expect(_text(tester), allOf(contains('open'), contains('done')));
    });

    testBothLayouts('does not let a to-do be ticked from the page', (tester, size) async {
      final app = await _pump(tester, '- [ ] open', size);
      await tester.tap(find.byIcon(LucideIcons.square));
      await tester.pump();
      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(app.server.requestsTo('api/task', method: 'PUT'), isEmpty);
    });

    testBothLayouts('renders quotes with a bar on the left', (tester, size) async {
      await _pump(tester, '> quoted **text**', size);
      expect(_text(tester), 'quoted text');
      final bars = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => (decoration.border as Border?)?.left.width == 2);
      expect(bars, hasLength(1));
    });

    testBothLayouts('renders code blocks exactly, and long lines scroll', (tester, size) async {
      final long = 'x' * 400;
      await _pump(tester, '```ts\nconst a = "**1**";\n  indented\n$long\n```\n\nAfter', size);
      expect(_text(tester), contains('const a = "**1**";\n  indented\n$long'));
      expect(_span(tester, 'const').style!.fontFamily, KaneoFonts.mono);
      expect(_span(tester, 'const').style!.backgroundColor, isNull);
      expect(_text(tester), isNot(contains('```')));
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .where((view) => view.scrollDirection == Axis.horizontal),
        hasLength(1),
      );
    });

    testBothLayouts('renders dividers', (tester, size) async {
      await _pump(tester, 'above\n\n---\n\nbelow', size);
      expect(_text(tester), isNot(contains('---')));
      final divider = tester
          .widgetList<Container>(find.byType(Container))
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => (decoration.border as Border?)?.top.width == 1);
      expect(divider, hasLength(1));
    });

    testBothLayouts('renders tables', (tester, size) async {
      await _pump(
        tester,
        '| Name | Status |\n| --- | --- |\n| Board | **Done** |\n| List |  |',
        size,
      );
      expect(find.byType(Table), findsOneWidget);
      expect(_text(tester), isNot(contains('|')));
      expect(_span(tester, 'Name').style!.fontWeight, FontWeight.w600);
      expect(_span(tester, 'Board').style!.fontWeight, isNot(FontWeight.w600));
      expect(_span(tester, 'Done').style!.fontWeight, FontWeight.w600);
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children, hasLength(3));
    });

    testBothLayouts('table headers keep the theme\'s faint tint', (tester, size) async {
      // The token is already translucent. Setting its alpha turned the header nearly black.
      await _pump(tester, '| Name |\n| --- |\n| Board |', size);
      final header = tester.widget<Table>(find.byType(Table)).children.first.decoration;
      expect((header! as BoxDecoration).color!.a, lessThan(0.1));
    });

    testBothLayouts('a wide table scrolls instead of overflowing', (tester, size) async {
      final cell = 'word ' * 60;
      await _pump(tester, '| a | b | c |\n| - | - | - |\n| $cell | $cell | $cell |', size);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Table)).width, greaterThan(size.width));
      expect(
        find.ancestor(of: find.byType(Table), matching: find.byType(SingleChildScrollView)),
        findsWidgets,
      );
    });

    testBothLayouts('a single newline is a line break, as on the web', (tester, size) async {
      await _pump(tester, 'first\nsecond', size);
      expect(_text(tester), 'first\nsecond');
    });

    testBothLayouts('shows backslash escapes and entities as the characters they mean', (
      tester,
      size,
    ) async {
      await _pump(tester, r'\*not italic\* &amp; 1\. &lt;b&gt;', size);
      expect(_text(tester), '*not italic* & 1. <b>');
    });

    testBothLayouts('turns bare addresses into links', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, 'https://a.co/b?c=1&d=2', size);
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['https://a.co/b?c=1&d=2']);
    });

    testBothLayouts('shows nothing for an empty description, without failing', (
      tester,
      size,
    ) async {
      await _pump(tester, '', size);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('long text wraps within the window', (tester, size) async {
      await _pump(tester, '中文内容' * 300, size);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SelectableText)).width, lessThanOrEqualTo(size.width));
    });
  });

  group('links', () {
    testBothLayouts('open when tapped', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, '[site](https://kaneo.app/a?b=1&c=2)', size);
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['https://kaneo.app/a?b=1&c=2']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testBothLayouts('on the server open on the signed-in server', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, '[file](/api/asset/1)', size);
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['${FakeKaneo.serverUrl}/api/asset/1']);
    });

    testBothLayouts('with a scheme that could run something do not open', (tester, size) async {
      final opened = _mockLinks(tester);
      final app = await _pump(tester, '[bad](file:///etc/passwd)', size);
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, isEmpty);
      expect(find.text(app.i18n.t('app:markdown.linkFailed')), findsOneWidget);
    });

    testBothLayouts('say so when nothing could open them', (tester, size) async {
      _mockLinks(tester, opens: false);
      final app = await _pump(tester, '[site](https://kaneo.app)', size);
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(find.text(app.i18n.t('app:markdown.linkFailed')), findsOneWidget);
    });
  });

  group('images', () {
    testBothLayouts('load from their address', (tester, size) async {
      await _pump(tester, '![Diagram](https://files.test/d.png)', size);
      expect(_networkImage(tester).url, 'https://files.test/d.png');
    });

    testBothLayouts('on the server load from it, with the credentials', (tester, size) async {
      await _pump(tester, '![Shot](/api/asset/1)', size);
      final image = _networkImage(tester);
      expect(image.url, '${FakeKaneo.serverUrl}/api/asset/1');
      expect(image.headers, {'x-api-key': FakeKaneo.apiKey});
    });

    testBothLayouts('on the server use a bearer token after a password sign-in', (
      tester,
      size,
    ) async {
      const session = Session(
        serverUrl: FakeKaneo.serverUrl,
        credentialType: CredentialType.bearer,
        token: 'token',
        userId: FakeKaneo.userId,
        userName: 'Test User',
        userEmail: FakeKaneo.email,
      );
      await _pump(tester, '![Shot](/api/asset/1)', size, session: session);
      expect(_networkImage(tester).headers, {'Authorization': 'Bearer token'});
    });

    testBothLayouts('anywhere else never get the credentials', (tester, size) async {
      await _pump(tester, '![Shot](https://evil.test/${FakeKaneo.serverUrl}/x.png)', size);
      expect(_networkImage(tester).headers, isNull);
    });

    testBothLayouts('show a placeholder while loading', (tester, size) async {
      await _pump(tester, '![Diagram](https://files.test/d.png)', size, settle: false);
      expect(find.byKey(markdownImageLoadingKey), findsOneWidget);
      expect(tester.getSize(find.byKey(markdownImageLoadingKey)).height, greaterThan(0));
    });

    testBothLayouts('that fail show their description instead', (tester, size) async {
      await _pump(tester, '![Diagram](https://files.test/d.png)', size);
      expect(find.textContaining('Diagram'), findsOneWidget);
      expect(find.byIcon(LucideIcons.imageOff), findsOneWidget);
      expect(find.byKey(markdownImageLoadingKey), findsNothing);
    });

    testBothLayouts('that fail with no description say they failed', (tester, size) async {
      final app = await _pump(tester, '![](https://files.test/d.png)', size);
      expect(find.textContaining(app.i18n.t('app:markdown.imageFailed')), findsOneWidget);
    });

    testBothLayouts('that point at a local file do not load', (tester, size) async {
      await _pump(tester, '![Secret](file:///etc/passwd)', size);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('Secret'), findsOneWidget);
    });

    testBothLayouts('can be embedded in the text', (tester, size) async {
      await _pump(tester, '![Dot](data:image/png;base64,$_pixel)', size);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as MemoryImage).bytes, base64Decode(_pixel));
    });

    testBothLayouts('that are embedded and broken show their description', (tester, size) async {
      await _pump(tester, '<img src="data:image/png;base64,@@@" alt="Dot" width="10" />', size);
      expect(find.textContaining('Dot'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('inside a link open the link', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, '[![Dot](data:image/png;base64,$_pixel)](https://kaneo.app)', size);
      await _decodePixel(tester);
      await tester.tap(find.byType(Image));
      await tester.pump();
      expect(opened, ['https://kaneo.app']);
    });
  });

  group('Kaneo tags', () {
    /// None of the markup may reach the screen.
    void expectNoMarkup(WidgetTester tester) {
      for (final widget in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
        final text = widget.textSpan!.toPlainText();
        expect(text, isNot(contains('<')), reason: text);
        expect(text, isNot(contains('kaneo-')), reason: text);
        expect(text, isNot(contains('="')), reason: text);
      }
    }

    testBothLayouts('kaneo-mention shows as a mention', (tester, size) async {
      await _pump(tester, 'Hi $_mention, welcome', size);
      expectNoMarkup(tester);
      expect(_text(tester), 'Hi @Ana, welcome');
      final style = _span(tester, '@Ana').style!;
      expect(style.fontWeight, FontWeight.w500);
      expect(style.backgroundColor, isNotNull);
      expect(_span(tester, '@Ana').recognizer, isNull);
    });

    testBothLayouts('kaneo-attachment shows as a link to the file', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, _attachment, size);
      expectNoMarkup(tester);
      expect(_text(tester), 'report.pdf');
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['https://files.test/report.pdf']);
    });

    testBothLayouts('kaneo-attachment on the server links to the server', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, '<kaneo-attachment url="/api/asset/9" filename="r.pdf" />', size);
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['${FakeKaneo.serverUrl}/api/asset/9']);
    });

    testBothLayouts('kaneo-attachment without a name uses a translated one', (tester, size) async {
      final app = await _pump(tester, '<kaneo-attachment url="https://a.test/x" />', size);
      expect(_text(tester), app.i18n.t('mobile:editor.attachment'));
    });

    // Tapping one opens the task in the app: see task_view_test.dart.
    testBothLayouts('kaneo-issue-link shows as a link with the issue key', (tester, size) async {
      await _pump(tester, _issueLink, size);
      expectNoMarkup(tester);
      expect(_text(tester), 'KAN-1');
      expect(_span(tester, 'KAN-1').recognizer, isA<TapGestureRecognizer>());
    });

    testBothLayouts('kaneo-issue-link to no task of ours opens its address', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, '<kaneo-issue-link url="https://k.test/x" issue-key="KAN-1" />', size);
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['https://k.test/x']);
    });

    testBothLayouts('kaneo-embed shows as a link', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, _embed, size);
      expectNoMarkup(tester);
      expect(_text(tester), 'https://www.youtube.com/watch?v=abc123');
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['https://www.youtube.com/watch?v=abc123']);
    });

    testBothLayouts('an embed the web refused shows its address as text', (tester, size) async {
      await _pump(tester, '<span class="kaneo-embed-invalid-link">not a url</span>', size);
      expectNoMarkup(tester);
      expect(_text(tester), 'not a url');
    });

    testBothLayouts('img with a width shows as an image of that width', (tester, size) async {
      await _pump(tester, _sizedImage, size);
      expect(find.byType(SelectableText), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://files.test/d.png');
      expect(image.width, 320);
      expect(image.semanticLabel, 'Diagram');
    });

    testBothLayouts('img with a width shows that wide once loaded', (tester, size) async {
      await _pump(tester, '<img src="data:image/png;base64,$_pixel" width="320" />', size);
      await _decodePixel(tester);
      expect(tester.getSize(find.byType(Image)).width, 320);
    });

    testBothLayouts('img wider than the window fits in it', (tester, size) async {
      await _pump(tester, '<img src="data:image/png;base64,$_pixel" width="5000" />', size);
      await _decodePixel(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Image)).width, lessThanOrEqualTo(size.width));
    });

    testBothLayouts('img on the server gets the credentials', (tester, size) async {
      await _pump(tester, '<img src="/api/asset/1" alt="x" width="100" />', size);
      final image = _networkImage(tester);
      expect(image.url, '${FakeKaneo.serverUrl}/api/asset/1');
      expect(image.headers, {'x-api-key': FakeKaneo.apiKey});
    });

    testBothLayouts('all together, the way the web writes them, show no markup', (
      tester,
      size,
    ) async {
      await _pump(
        tester,
        [
          '# Release notes',
          '',
          'Ping $_mention about this.',
          '',
          '',
          _attachment,
          '',
          '',
          _issueLink,
          '',
          '',
          _embed,
          '',
          '',
          _sizedImage,
          '',
          '- [ ] Draft $_mention',
          '- [x] Review $_issueLink',
          '',
          '> Quote $_mention',
          '',
          '| Name | Who |',
          '| ---- | --- |',
          '| Board | $_mention |',
          '',
        ].join('\n'),
        size,
      );
      expectNoMarkup(tester);
      final text = _text(tester);
      expect(text, allOf(contains('Release notes'), contains('@Ana'), contains('report.pdf')));
      expect(text, allOf(contains('KAN-1'), contains('youtube.com'), contains('Draft')));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('stay literal in code samples', (tester, size) async {
      await _pump(tester, '`$_mention`\n\n```html\n$_sizedImage\n```', size);
      expect(_text(tester), allOf(contains(_mention), contains(_sizedImage)));
      expect(find.byType(Image), findsNothing);
    });
  });

  group('old HTML descriptions', () {
    testBothLayouts('show as formatted text, without tags', (tester, size) async {
      await _pump(
        tester,
        '<h2>Plan</h2><p>Some <strong>bold</strong> and <a href="https://kaneo.app">site</a></p>'
        '<ul data-type="taskList"><li data-checked="true" data-type="taskItem"><label>'
        '<input type="checkbox" checked="checked"><span></span></label><div><p>Done</p></div></li>'
        '<li data-checked="false" data-type="taskItem"><label><input type="checkbox"><span></span>'
        '</label><div><p>Open</p></div></li></ul>'
        '<ol><li><p>First</p></li></ol><blockquote><p>Quote</p></blockquote>'
        '<pre><code>x &lt; y</code></pre><hr>'
        '<table><tbody><tr><th><p>Name</p></th></tr><tr><td><p>Board</p></td></tr></tbody></table>',
        size,
      );
      final text = _text(tester);
      expect(text, isNot(contains('<h2')));
      expect(text, isNot(contains('<p')));
      expect(text, isNot(contains('<li')));
      expect(text, isNot(contains('data-')));
      expect(_span(tester, 'Plan').style!.fontWeight, FontWeight.w600);
      expect(_span(tester, 'bold').style!.fontWeight, FontWeight.w600);
      expect(_span(tester, 'site').recognizer, isNotNull);
      expect(find.byIcon(LucideIcons.squareCheck), findsOneWidget);
      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(text, contains('x < y'));
      expect(find.byType(Table), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothLayouts('keep Markdown characters in their text literal', (tester, size) async {
      await _pump(tester, '<p>2 * 3 * 4, a_b_c, # not a title, 1. not a list, ~x~ | y</p>', size);
      expect(_text(tester), '2 * 3 * 4, a_b_c, # not a title, 1. not a list, ~x~ | y');
    });

    testBothLayouts('with bare addresses link to them correctly', (tester, size) async {
      final opened = _mockLinks(tester);
      await _pump(tester, '<p>https://a.co/b-c_d.1</p>', size);
      expect(_text(tester), 'https://a.co/b-c_d.1');
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      expect(opened, ['https://a.co/b-c_d.1']);
    });

    testBothLayouts('with Kaneo tags in them show those too', (tester, size) async {
      await _pump(
        tester,
        '<p>Hi <kaneo-mention id="u1" label="Ana">@Ana</kaneo-mention></p>'
        '<p><kaneo-attachment url="https://a.test/r.pdf" filename="r.pdf"></kaneo-attachment></p>'
        '<img src="https://a.test/d.png" alt="Diagram" width="100">',
        size,
      );
      expect(_text(tester), allOf(contains('Hi @Ana'), contains('r.pdf')));
      expect(_text(tester), isNot(contains('<')));
      expect(tester.widget<Image>(find.byType(Image)).width, 100);
    });

    testBothLayouts('with an editor attachment in them show it', (tester, size) async {
      await _pump(
        tester,
        '<p><span data-type="attachment-card" data-url="https://a.test/r.pdf" '
        'data-filename="r.pdf"></span></p>',
        size,
      );
      expect(_text(tester), 'r.pdf');
      expect(_span(tester, 'r.pdf').recognizer, isNotNull);
    });
  });

  testBothLayouts('blocks of HTML in Markdown show as formatted text', (tester, size) async {
    await _pump(tester, 'Intro\n\n<div>Hello <b>there</b></div>\n\nOutro', size);
    expect(_text(tester), allOf(contains('Intro'), contains('Hello there'), contains('Outro')));
    expect(_span(tester, 'there').style!.fontWeight, FontWeight.w600);
  });

  testBothLayouts('text inline with a mention and a link stays on one line', (tester, size) async {
    await _pump(tester, 'Hi $_mention see [x](https://a.test) ok', size);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(_text(tester), 'Hi @Ana see x ok');
  });

  testBothLayouts('the task page shows the description formatted', (tester, size) async {
    final server = FakeKaneo();
    server.addTask(
      id: 'md',
      title: 'With tags',
      description: '## Goal\n\nAsk $_mention\n\n- [x] Done',
    );
    await pumpKaneoApp(tester, server: server, size: size, location: AppRoutes.task('md'));
    expect(_text(tester), allOf(contains('Goal'), contains('Ask @Ana'), contains('Done')));
    expect(_text(tester), isNot(contains('<kaneo')));
    expect(find.byIcon(LucideIcons.squareCheck), findsOneWidget);
  });

  test('every language has the new text', () async {
    for (final locale in ['en-US', 'zh-CN', 'zh-TW']) {
      final file = await readCatalogFile('assets/i18n/overrides/$locale.json');
      final markdown = (file!['app'] as Map)['markdown'] as Map;
      expect(markdown['imageFailed'], isNotEmpty, reason: locale);
      expect(markdown['linkFailed'], isNotEmpty, reason: locale);
    }
  });
}
