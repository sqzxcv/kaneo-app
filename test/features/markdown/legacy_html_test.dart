import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/features/markdown/legacy_html.dart';

void main() {
  group('isLegacyHtml', () {
    test('only treats text that starts with a block tag as HTML', () {
      expect(isLegacyHtml('<p>Hello</p>'), isTrue);
      expect(isLegacyHtml('  <ul class="x"><li>a</li></ul>'), isTrue);
      expect(isLegacyHtml('<TABLE><tr><td>a</td></tr></TABLE>'), isTrue);
      expect(isLegacyHtml('Hello <p> world'), isFalse);
      expect(isLegacyHtml('```html\n<p>x</p>\n```'), isFalse);
      expect(isLegacyHtml('<kaneo-mention id="1"></kaneo-mention>'), isFalse);
    });
  });

  group('legacyHtmlToMarkdown', () {
    test('converts paragraphs and inline marks', () {
      expect(
        legacyHtmlToMarkdown(
          '<p>Hello <strong>bold</strong> and <em>soft</em> &amp; <code>x &lt; y</code></p>'
          '<p>Next<br>line</p>',
        ),
        'Hello **bold** and *soft* & `x < y`\n\nNext  \nline',
      );
    });

    test('keeps Markdown characters in text literal', () {
      expect(
        legacyHtmlToMarkdown(
          '<p>Use *literal* markers, [draft](notes) and <code>a*b</code></p><p>1. not a list</p>',
        ),
        'Use \\*literal\\* markers, \\[draft\\](notes) and `a*b`\n\n1\\. not a list',
      );
    });

    test('leaves bare addresses unescaped, so they link to the right place', () {
      expect(
        legacyHtmlToMarkdown('<p>See https://kaneo.app/a-b_c.1 and www.kaneo.app/x-y, v1.5</p>'),
        r'See https://kaneo.app/a-b_c.1 and www.kaneo.app/x-y, v1\.5',
      );
    });

    test('does not let escaped entities turn back into characters', () {
      expect(legacyHtmlToMarkdown('<p>Write &amp;lt; for &lt;</p>'), r'Write \&lt; for \<');
    });

    test('keeps spaces outside marks and backticks inside code', () {
      expect(
        legacyHtmlToMarkdown(
          '<p><strong>Hello </strong>world, <em>in</em>line and <code>echo `hostname`</code></p>',
        ),
        '**Hello** world, *in*line and `` echo `hostname` ``',
      );
    });

    test('converts strikethrough and underline', () {
      expect(
        legacyHtmlToMarkdown(
          '<p><s>gone</s> <del>too</del> <strike>also</strike> <u>under</u></p>',
        ),
        '~~gone~~ ~~too~~ ~~also~~ ++under++',
      );
    });

    test('fences code blocks that contain backtick fences', () {
      expect(
        legacyHtmlToMarkdown('<pre><code>a\n```\nb\n</code></pre><p>after</p>'),
        '````\na\n```\nb\n````\n\nafter',
      );
    });

    test('does not escape or drop what is inside a code block', () {
      expect(
        legacyHtmlToMarkdown(
          '<pre><code class="language-html">&lt;p&gt;*x*&lt;/p&gt;</code></pre>',
        ),
        '```\n<p>*x*</p>\n```',
      );
    });

    test('converts editor task lists with their checked state', () {
      const html =
          '<ul class="not-prose pl-2" data-type="taskList"><li class="flex gap-2 items-start" '
          'data-checked="false" data-type="taskItem"><label><input type="checkbox"><span></span>'
          '</label><div><p>Move the instances.json</p></div></li><li data-checked="true" '
          'data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span>'
          r'</label><div><p>Use a $schema</p></div></li></ul>';
      expect(legacyHtmlToMarkdown(html), '- [ ] Move the instances.json\n- [x] Use a \$schema');
    });

    test('keeps nested and ordered lists', () {
      expect(
        legacyHtmlToMarkdown(
          '<ol start="3"><li><p>One</p><ul><li><p>Inner</p></li></ul></li><li><p>Two</p></li></ol>'
          '<p>After</p>',
        ),
        '3. One\n   - Inner\n4. Two\n\nAfter',
      );
    });

    test('converts headings, links, quotes, and code blocks', () {
      expect(
        legacyHtmlToMarkdown(
          '<h2>Title</h2><p>See <a href="https://kaneo.app" target="_blank">site</a></p>'
          '<blockquote><p>Quote</p><p>More</p></blockquote>'
          '<pre><code class="language-ts">const a = 1 &lt; 2;\n</code></pre>',
        ),
        '## Title\n\nSee [site](https://kaneo.app)\n\n> Quote\n>\n> More\n\n'
        '```\nconst a = 1 < 2;\n```',
      );
    });

    test('converts a divider', () {
      expect(legacyHtmlToMarkdown('<p>a</p><hr><p>b</p>'), 'a\n\n---\n\nb');
    });

    test('converts a table, with the first row as its header', () {
      expect(
        legacyHtmlToMarkdown(
          '<table><colgroup><col></colgroup><tbody><tr><th colspan="1"><p>Name</p></th>'
          '<th><p>Status</p></th></tr><tr><td><p>Board | list</p></td><td><p>Done</p></td></tr>'
          '</tbody></table><p>After</p>',
        ),
        '| Name | Status |\n| --- | --- |\n| Board \\| list | Done |\n\nAfter',
      );
    });

    test('keeps images and Kaneo tags for the Markdown syntaxes', () {
      expect(
        legacyHtmlToMarkdown(
          '<p>Hi <kaneo-mention id="u1" label="Ana">@Ana</kaneo-mention></p>'
          '<img src="/api/asset/1" alt="shot">',
        ),
        'Hi <kaneo-mention id="u1" label="Ana">@Ana</kaneo-mention>\n\n'
        '<img src="/api/asset/1" alt="shot">',
      );
    });

    test('turns the editor nodes in saved HTML into Kaneo tags', () {
      expect(
        legacyHtmlToMarkdown(
          '<p><span data-type="attachment-card" data-url="https://a/r.pdf"></span> and '
          '<span data-type="kaneo-mention" data-label="Ana">@Ana</span></p>',
        ),
        '<kaneo-attachment data-type="attachment-card" data-url="https://a/r.pdf" /> and '
        '<kaneo-mention data-type="kaneo-mention" data-label="Ana" />',
      );
    });

    test('replaces everything inside a saved embed', () {
      expect(
        legacyHtmlToMarkdown(
          '<div data-type="kaneo-embed" data-url="https://youtu.be/x"><div class="x">Only YouTube'
          '</div><iframe src="https://youtube.com/embed/x"></iframe></div><p>After</p>',
        ),
        '<kaneo-embed data-type="kaneo-embed" data-url="https://youtu.be/x" />\n\nAfter',
      );
    });

    test('drops comments, scripts, styles and tags it does not know, but keeps their text', () {
      expect(
        legacyHtmlToMarkdown(
          '<p>a<!-- <b>note</b> --></p><script>alert("<p>x</p>")</script><style>p{}</style>'
          '<p><span class="c" style="color: red">b</span><mark>c</mark></p>',
        ),
        'a\n\nbc',
      );
    });

    test('closes tags that were left open and ignores stray closing tags', () {
      expect(legacyHtmlToMarkdown('<p><strong>open</p></em>'), '**open**');
      expect(legacyHtmlToMarkdown('<ul><li>a'), '- a');
    });

    test('reads a tag with > in an attribute', () {
      expect(
        legacyHtmlToMarkdown('<p><a href="https://a/b" title="x > y">z</a></p>'),
        '[z](https://a/b)',
      );
    });
  });

  test('decodeHtmlEntities decodes named and numeric entities', () {
    expect(
      decodeHtmlEntities('&lt;a&gt; &amp; &quot;b&quot; &#39;c&#39; &#x4e2d;&#25991;'),
      '<a> & "b" \'c\' 中文',
    );
    expect(decodeHtmlEntities('&nope; &#99999999;'), '&nope; &#99999999;');
  });

  test('parseHtmlAttributes reads every quoting style and lowercases names', () {
    expect(parseHtmlAttributes(' URL="a&amp;b" data-x=\'c\' width=320 '), {
      'url': 'a&b',
      'data-x': 'c',
      'width': '320',
    });
  });
}
