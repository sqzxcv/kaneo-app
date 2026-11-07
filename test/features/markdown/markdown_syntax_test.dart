import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/features/markdown/legacy_html.dart';
import 'package:kaneo_app/features/markdown/markdown_syntax.dart';
import 'package:kaneo_app/features/markdown/markdown_urls.dart';
import 'package:markdown/markdown.dart' as md;

/// Parses [source] the way `MarkdownBody` does, and prints the result.
String parse(String source) {
  final document = md.Document(
    blockSyntaxes: kaneoBlockSyntaxes,
    inlineSyntaxes: kaneoInlineSyntaxes(attachmentLabel: 'Attachment'),
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  return md.HtmlRenderer().render(document.parseLines(source.split('\n'))).trim();
}

void main() {
  group('mentions', () {
    test('read the label', () {
      expect(
        parse('Hi <kaneo-mention id="u1" label="Ana Li"></kaneo-mention>!'),
        '<p>Hi <kaneo-mention>@Ana Li</kaneo-mention>!</p>',
      );
    });

    test('fall back to the text inside the tag', () {
      expect(
        parse('<kaneo-mention id="u1">@Mira</kaneo-mention>'),
        '<p><kaneo-mention>@Mira</kaneo-mention></p>',
      );
    });

    test('decode the label, and cope with > in it', () {
      expect(
        parse('<kaneo-mention id="u1" label="A &amp; B > C"></kaneo-mention>'),
        '<p><kaneo-mention>@A & B > C</kaneo-mention></p>',
      );
    });

    test('work without a closing tag', () {
      expect(
        parse(
          '<kaneo-mention id="a" label="A" /> and <kaneo-mention id="b" label="B"></kaneo-mention>',
        ),
        '<p><kaneo-mention>@A</kaneo-mention> and <kaneo-mention>@B</kaneo-mention></p>',
      );
    });

    test('read the saved editor form, without its Markdown escapes', () {
      expect(
        parse(legacyHtmlToMarkdown('<p><kaneo-mention id="u1">@Mary-Jane</kaneo-mention></p>')),
        '<p><kaneo-mention>@Mary-Jane</kaneo-mention></p>',
      );
      expect(
        parse(
          legacyHtmlToMarkdown(
            '<p><span data-type="kaneo-mention" data-label="Ana">@Ana</span></p>',
          ),
        ),
        '<p><kaneo-mention>@Ana</kaneo-mention></p>',
      );
    });
  });

  group('attachments', () {
    test('become a link named after the file', () {
      expect(
        parse(
          '<kaneo-attachment url="https://a/r.pdf" filename="spec &quot;final&quot;_v1.pdf" '
          'mime-type="application/pdf" size="10" />',
        ),
        '<p><a href="https://a/r.pdf">spec "final"_v1.pdf</a></p>',
      );
    });

    test('have a name even without a file name', () {
      expect(
        parse('<kaneo-attachment url="/api/asset/1" />'),
        '<p><a href="/api/asset/1">Attachment</a></p>',
      );
    });

    test('are plain text without a URL', () {
      expect(parse('<kaneo-attachment filename="r.pdf" />'), '<p>r.pdf</p>');
    });

    test('read the saved editor form', () {
      expect(
        parse(
          '<kaneo-attachment data-type="attachment-card" data-url="https://a/r.pdf" '
          'data-filename="r.pdf"></kaneo-attachment>',
        ),
        '<p><a href="https://a/r.pdf">r.pdf</a></p>',
      );
    });
  });

  group('issue links', () {
    test('show the issue key, and go to the task in the app', () {
      expect(
        parse('<kaneo-issue-link url="https://k/task/t1" issue-key="KAN-1" task-id="t1" />'),
        '<p><a href="${taskLinkTo('t1')}">KAN-1</a></p>',
      );
      expect(
        parse(
          '<kaneo-issue-link data-url="https://k/x" data-issue-key="KAN-1" data-task-id="t1" />',
        ),
        '<p><a href="${taskLinkTo('t1')}">KAN-1</a></p>',
      );
    });

    test('show the address without a key', () {
      expect(
        parse('<kaneo-issue-link url="https://k/task/t1" issue-key="" task-id="t1" />'),
        '<p><a href="${taskLinkTo('t1')}">https://k/task/t1</a></p>',
      );
    });

    test('without a task id go to the task their address is the page of', () {
      expect(
        parse(
          '<kaneo-issue-link url="https://k/dashboard/workspace/w1/project/p1/task/t1" '
          'issue-key="KAN-1" />',
        ),
        '<p><a href="${taskLinkTo('t1')}">KAN-1</a></p>',
      );
    });

    test('go to their address when it is no task page', () {
      expect(
        parse('<kaneo-issue-link url="https://k/task/t1" issue-key="KAN-1" />'),
        '<p><a href="https://k/task/t1">KAN-1</a></p>',
      );
    });

    test('show nothing with nothing to show', () {
      expect(parse('a <kaneo-issue-link task-id="t1" /> b'), '<p>a  b</p>');
    });
  });

  group('embeds', () {
    test('become a link', () {
      expect(
        parse('<kaneo-embed url="https://www.youtube.com/watch?v=abc" mode="embed" />'),
        '<p><a href="https://www.youtube.com/watch?v=abc">https://www.youtube.com/watch?v=abc</a></p>',
      );
    });

    test('that the web refused show their address as text', () {
      expect(
        parse('<span class="kaneo-embed-invalid-link">not a &lt;url&gt;</span>'),
        '<p>not a <url></p>',
      );
    });
  });

  group('images', () {
    test('with a width keep it', () {
      expect(
        parse('<img src="https://a/d.png" alt="Diagram" width="320" />'),
        '<p><kaneo-sized-image src="https://a/d.png" alt="Diagram" width="320" /></p>',
      );
    });

    test('read a pixel width from any of the places the web does', () {
      expect(parse('<img src="a" width="320px">'), contains('width="320"'));
      expect(parse('<img src="a" style="width: 320px">'), contains('width="320"'));
      expect(
        parse('<img src="a" width="50%" style="color: red; width: 320px">'),
        contains('width="320"'),
      );
    });

    test('without a usable width stay plain images', () {
      for (final width in ['50%', '20em', '0', '-1', '9' * 40]) {
        expect(parse('<img src="a" alt="b" width="$width">'), '<p><img src="a" alt="b" /></p>');
      }
    });

    test('without a source show nothing', () {
      expect(parse('a <img alt="b"> c'), '<p>a  c</p>');
    });

    test('in Markdown stay Markdown images', () {
      expect(
        parse('![Diagram](https://a/d.png)'),
        '<p><img src="https://a/d.png" alt="Diagram" /></p>',
      );
    });
  });

  group('tags', () {
    test('never show their markup, known or not', () {
      expect(parse('a <kaneo-new x="1">b</kaneo-new> c'), '<p>a b c</p>');
      expect(parse('a </kaneo-mention> b </img> c'), '<p>a  b  c</p>');
      expect(parse('<KANEO-EMBED URL="https://a" />'), '<p><a href="https://a">https://a</a></p>');
    });

    test('on their own line, next to each other or in a sentence, all work', () {
      const tag = '<kaneo-issue-link url="https://k" issue-key="K-1" />';
      expect(parse(tag), '<p><a href="https://k">K-1</a></p>');
      expect(parse('$tag$tag'), '<p><a href="https://k">K-1</a><a href="https://k">K-1</a></p>');
      expect(parse('See $tag now'), '<p>See <a href="https://k">K-1</a> now</p>');
    });

    test('work inside lists, quotes, tables, headings and emphasis', () {
      const tag = '<kaneo-mention id="u" label="A"></kaneo-mention>';
      const shown = '<kaneo-mention>@A</kaneo-mention>';
      expect(parse('- $tag'), contains(shown));
      expect(parse('> $tag'), contains(shown));
      expect(parse('# $tag'), contains(shown));
      expect(parse('**$tag**'), '<p><strong>$shown</strong></p>');
      expect(parse('| a |\n| - |\n| $tag |'), contains(shown));
    });

    test('in a list or quote on a line of their own still work', () {
      const tag = '<kaneo-embed url="https://a" />';
      expect(parse('- x\n\n  $tag'), contains('<a href="https://a">'));
      expect(parse('> $tag'), contains('<a href="https://a">'));
    });

    test('stay literal in code', () {
      const tag = '<kaneo-mention id="u" label="A"></kaneo-mention>';
      expect(parse('`$tag`'), '<p><code>$tag</code></p>');
      expect(parse('```html\n$tag\n```'), contains(tag));
      expect(parse('    $tag'), contains(tag));
      expect(parse('```\n<img src="a" width="1" />\n```'), contains('<img src="a" width="1" />'));
    });

    test('keep Markdown going around them', () {
      expect(
        parse('**a** <kaneo-mention id="u" label="B"></kaneo-mention> *c*'),
        '<p><strong>a</strong> <kaneo-mention>@B</kaneo-mention> <em>c</em></p>',
      );
    });
  });

  group('line breaks', () {
    test('a single newline is a break, as on the web', () {
      expect(parse('a\nb'), '<p>a<br />\nb</p>');
    });

    test('a hard break stays one break', () {
      expect(parse('a  \nb'), '<p>a<br />\nb</p>');
      expect(parse('a\\\nb'), '<p>a<br />\nb</p>');
    });

    test('<br> is a break', () {
      expect(parse('a<br>b<br/>c<BR />d'), '<p>a<br />\nb<br />\nc<br />\nd</p>');
    });
  });

  group('underline', () {
    test('reads the ++ the web writes', () {
      expect(parse('a ++b++ c'), '<p>a <kaneo-underline>b</kaneo-underline> c</p>');
    });

    test('leaves other plus signs alone', () {
      expect(parse('C++ and C++'), '<p>C++ and C++</p>');
      expect(parse('1 + 2'), '<p>1 + 2</p>');
    });
  });

  group('blocks of HTML', () {
    test('between Markdown blocks are formatted, not dropped', () {
      expect(
        parse('Intro\n\n<div>Hello <b>there</b></div>\n\nOutro'),
        '<p>Intro</p><kaneo-html-block>\n<p>Hello <strong>there</strong></p></kaneo-html-block>\n<p>Outro</p>',
      );
    });

    test('with a table become a table', () {
      expect(
        parse('Intro\n\n<table><tr><th>a</th></tr><tr><td>b</td></tr></table>'),
        allOf(contains('<th>a</th>'), contains('<td>b</td>')),
      );
    });

    test('with only a comment show nothing', () {
      expect(parse('a\n\n<!-- note -->\n\nb'), '<p>a</p>\n<p>b</p>');
    });

    test('can follow a tag on the next line', () {
      expect(parse('<!-- note -->\n<img src="a" />'), contains('<img src="a" alt="" />'));
    });
  });

  group('to-dos', () {
    test('keep their checkbox directly in the item when the list is tight', () {
      expect(
        parse('- [x] a'),
        contains('<li class="task-list-item"><input type="checkbox" checked="true"></input>a'),
      );
    });

    test('move their checkbox to the item when items are far apart', () {
      for (final source in ['- [x] a\n\n- [ ] b', '1. [x] a\n\n2. [ ] b']) {
        final html = parse(source);
        expect(
          html,
          contains('<li class="task-list-item"><input type="checkbox" checked="true"></input>'),
        );
        expect(html, contains('<p>a</p>'));
        expect(html, isNot(contains('<p><input')));
      }
    });

    test('work at every depth of a list with blank lines', () {
      expect(parse('- [ ] a\n  - [x] b\n\n    more\n\n  more'), isNot(contains('<p><input')));
    });
  });

  test('other inline HTML stays text, so Option<string> reads as written', () {
    expect(parse('Returns Option<string> here'), '<p>Returns Option<string> here</p>');
  });

  test('the Markdown the web editor writes parses completely', () {
    // From kaneo/packages/editor/src/base-extensions.test.ts.
    final html = parse(
      [
        '# Release notes',
        '',
        'Ping <kaneo-mention id="user-1" label="Ada"></kaneo-mention> about this.',
        '',
        '',
        '<kaneo-attachment url="https://kaneo.app/files/report.pdf" filename="report.pdf" mime-type="application/pdf" size="2048" />',
        '',
        '',
        'Related work:',
        '',
        '',
        '<kaneo-issue-link url="https://kaneo.app/dashboard/workspace/w1/project/p1/task/t1" issue-key="KAN-1" task-id="t1" />',
        '',
        '',
        'Demo:',
        '',
        '',
        '<kaneo-embed url="https://www.youtube.com/watch?v=abc123" mode="embed" />',
        '',
        '',
        '<img src="https://kaneo.app/diagram.png" alt="Diagram" width="320" />',
        '',
        '- [ ] Draft',
        '- [x] Review',
        '',
        '',
        '| Name  | Status |',
        '| ----- | ------ |',
        '| Board | Done   |',
        '',
      ].join('\n'),
    );
    expect(html, contains('<h1>Release notes</h1>'));
    expect(html, contains('<kaneo-mention>@Ada</kaneo-mention>'));
    expect(html, contains('<a href="https://kaneo.app/files/report.pdf">report.pdf</a>'));
    expect(html, contains('>KAN-1</a>'));
    expect(html, contains('<a href="https://www.youtube.com/watch?v=abc123">'));
    expect(html, contains('<kaneo-sized-image src="https://kaneo.app/diagram.png"'));
    expect(html, contains('<input type="checkbox" checked="true">'));
    expect(html, contains('<td>Board</td>'));
    expect(html, isNot(contains('<kaneo-attachment')));
    expect(html, isNot(contains('<kaneo-issue-link')));
    expect(html, isNot(contains('<kaneo-embed')));
    expect(html, isNot(contains('<img')));
  });

  test('parsePixelWidth takes only a positive number of pixels', () {
    expect(parsePixelWidth('320'), 320);
    expect(parsePixelWidth(' 320PX '), 320);
    expect(parsePixelWidth('50%'), isNull);
    expect(parsePixelWidth('0'), isNull);
    expect(parsePixelWidth(''), isNull);
    expect(parsePixelWidth(null), isNull);
  });
}
