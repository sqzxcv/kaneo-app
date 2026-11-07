/// What Kaneo's editors write beyond plain Markdown, as syntaxes for `package:markdown`.
///
/// Parsing them here, rather than rewriting the text first, leaves code blocks and code spans
/// alone: a `<kaneo-mention>` in a code sample stays a code sample.
library;

import 'package:markdown/markdown.dart' as md;

import 'legacy_html.dart';
import 'markdown_urls.dart';

/// Elements `MarkdownView` builds itself.
abstract final class KaneoTags {
  static const mention = 'kaneo-mention';
  static const underline = 'kaneo-underline';

  /// An image the web resized. Plain images stay `img`.
  static const sizedImage = 'kaneo-sized-image';

  /// Holds the blocks converted from a block of HTML.
  static const htmlBlock = 'kaneo-html-block';
}

const List<md.BlockSyntax> kaneoBlockSyntaxes = [
  _TagParagraphSyntax(),
  _HtmlBlockSyntax(),
  _UnorderedTaskListSyntax(),
  _OrderedTaskListSyntax(),
];

List<md.InlineSyntax> kaneoInlineSyntaxes({required String attachmentLabel}) => [
  _KaneoTagSyntax(attachmentLabel),
  _NewlineBreakSyntax(),
  md.DelimiterSyntax(
    r'\++',
    requiresDelimiterRun: true,
    allowIntraWord: true,
    startCharacter: 0x2b,
    tags: [md.DelimiterTag(KaneoTags.underline, 2)],
  ),
];

/// The web parses Markdown with `breaks: true`, so a single newline is a line break there.
class _NewlineBreakSyntax extends md.InlineSyntax {
  _NewlineBreakSyntax() : super(r'\n', startCharacter: 0x0a);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

/// A line that starts with one of our tags is an ordinary paragraph. `HtmlBlockSyntax` would take
/// it as raw HTML otherwise, which the renderer drops.
class _TagParagraphSyntax extends md.ParagraphSyntax {
  const _TagParagraphSyntax();

  static final _start = RegExp(r'^ {0,3}</?(?:kaneo-[a-z-]+|img)(?=[\s/>])', caseSensitive: false);

  @override
  bool canParse(md.BlockParser parser) => _start.hasMatch(parser.current.content);
}

/// Shows any other block of HTML the way the web does, formatted, instead of dropping it.
class _HtmlBlockSyntax extends md.BlockSyntax {
  const _HtmlBlockSyntax();

  static const _html = md.HtmlBlockSyntax();

  @override
  RegExp get pattern => _html.pattern;

  @override
  bool canEndBlock(md.BlockParser parser) => _html.canEndBlock(parser);

  @override
  md.Node? parse(md.BlockParser parser) {
    final html = _html.parseChildLines(parser).map((line) => line.content).join('\n');
    final markdown = legacyHtmlToMarkdown(html);
    if (markdown.isEmpty) return null;
    final lines = markdown.split('\n').map(md.Line.new).toList();
    return md.Element(KaneoTags.htmlBlock, md.BlockParser(lines, parser.document).parseLines());
  }
}

class _UnorderedTaskListSyntax extends md.UnorderedListWithCheckboxSyntax {
  const _UnorderedTaskListSyntax();

  @override
  md.Node parse(md.BlockParser parser) => _withCheckboxesFirst(super.parse(parser));
}

class _OrderedTaskListSyntax extends md.OrderedListWithCheckboxSyntax {
  const _OrderedTaskListSyntax();

  @override
  md.Node parse(md.BlockParser parser) => _withCheckboxesFirst(super.parse(parser));
}

/// In a list with blank lines between its items the parser puts each checkbox inside the item's
/// paragraph, but the renderer only looks for it directly in the item, and draws a bullet if it
/// isn't there. That would lose the state of the to-do.
md.Node _withCheckboxesFirst(md.Node list) {
  if (list is! md.Element) return list;
  for (final item in list.children ?? const <md.Node>[]) {
    if (item is! md.Element) continue;
    final paragraph = item.children?.firstOrNull;
    if (paragraph is! md.Element || paragraph.tag != 'p') continue;
    final checkbox = paragraph.children?.firstOrNull;
    if (checkbox is md.Element && checkbox.attributes['type'] == 'checkbox') {
      paragraph.children!.removeAt(0);
      item.children!.insert(0, checkbox);
    }
  }
  return list;
}

const _attributes = r'''((?:[^>"']|"[^"]*"|'[^']*')*?)''';

class _KaneoTagSyntax extends md.InlineSyntax {
  _KaneoTagSyntax(this.attachmentLabel)
    : super(
        // Group 1 and 2: a mention and what is inside it.
        '<kaneo-mention(?=[\\s/>])$_attributes(?<!/)>([\\s\\S]*?)</kaneo-mention\\s*>'
        // Group 3: a URL the web's embed block refused.
        '|<span\\s+class="kaneo-embed-invalid-link"\\s*>([\\s\\S]*?)</span\\s*>'
        // Group 4: a line break.
        '|(<br\\s*/?>)'
        // Group 5, 6 and 7: any other tag of ours, opening, closing or self-closing.
        '|<(/?)(kaneo-[a-z-]+|img)(?=[\\s/>])$_attributes/?>',
        startCharacter: 0x3c,
        caseSensitive: false,
      );

  final String attachmentLabel;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final node = _node(match);
    if (node != null) parser.addNode(node);
    return true;
  }

  md.Node? _node(Match match) {
    if (match[2] != null) return _mention(parseHtmlAttributes(match[1]!), match[2]);
    if (match[3] != null) return md.Text(decodeHtmlEntities(match[3]!));
    if (match[4] != null) return md.Element.empty('br');
    if (match[5]!.isNotEmpty) return null;

    final attrs = parseHtmlAttributes(match[7]!);
    return switch (match[6]!.toLowerCase()) {
      'kaneo-mention' => _mention(attrs, null),
      'kaneo-attachment' => _attachment(attrs),
      'kaneo-issue-link' => _issueLink(attrs),
      'kaneo-embed' => _embed(attrs),
      'img' => _image(attrs),
      // A tag from a newer version. Its markup still must not show.
      _ => null,
    };
  }

  md.Node _mention(Map<String, String> attrs, String? inner) {
    final label = _first(attrs, ['label', 'data-label']);
    final text = label ?? _unescaped(inner ?? '').replaceFirst(RegExp(r'^@'), '');
    return md.Element.text(KaneoTags.mention, '@$text');
  }

  md.Node _attachment(Map<String, String> attrs) {
    final label = _first(attrs, ['filename', 'data-filename']) ?? attachmentLabel;
    return _link(label, _first(attrs, ['url', 'data-url']));
  }

  /// A link to a task, which the app opens itself, as the web opens it in place. The web finds the
  /// task by its id, or else by the address of its page.
  md.Node? _issueLink(Map<String, String> attrs) {
    final url = _first(attrs, ['url', 'data-url']);
    final key = _first(attrs, ['issue-key', 'data-issue-key', 'issuekey']);
    final taskId = _first(attrs, ['task-id', 'data-task-id', 'taskid']) ?? taskIdInAddress(url);
    final label = key ?? url;
    return label == null ? null : _link(label, taskId == null ? url : taskLinkTo(taskId));
  }

  md.Node? _embed(Map<String, String> attrs) {
    final url = _first(attrs, ['url', 'data-url']);
    return url == null ? null : _link(url, url);
  }

  md.Node? _image(Map<String, String> attrs) {
    final src = attrs['src'];
    if (src == null || src.isEmpty) return null;
    final width = parsePixelWidth(attrs['width']) ?? _styleWidth(attrs['style']);
    return md.Element.empty(width == null ? 'img' : KaneoTags.sizedImage)
      ..attributes['src'] = src
      ..attributes['alt'] = attrs['alt'] ?? ''
      ..attributes.addAll({'title': ?attrs['title'], if (width != null) 'width': '$width'});
  }
}

md.Node _link(String label, String? url) {
  if (url == null) return md.Text(label);
  return md.Element.text('a', label)..attributes['href'] = url;
}

/// The first of [names] with a value. The same attribute goes by several names in saved content.
String? _first(Map<String, String> attrs, List<String> names) {
  for (final name in names) {
    final value = attrs[name];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// Undoes the Markdown escapes `legacyHtmlToMarkdown` adds to text inside a tag.
String _unescaped(String text) =>
    text.replaceAllMapped(RegExp(r'\\([!-/:-@\[-`{-~])'), (match) => match[1]!);

int? _styleWidth(String? style) {
  if (style == null) return null;
  return parsePixelWidth(RegExp(r'(?:^|;)\s*width\s*:\s*([^;]+)').firstMatch(style)?[1]);
}

/// A width in pixels, as the web reads it. Any other unit means the image keeps its own size.
int? parsePixelWidth(String? value) {
  final match = RegExp(r'^(\d+)(?:px)?$', caseSensitive: false).firstMatch(value?.trim() ?? '');
  final width = match == null ? null : int.tryParse(match[1]!);
  return width != null && width > 0 ? width : null;
}
