/// Older task descriptions were saved as editor HTML. The web editor still reads them, but
/// Markdown would show the tags as text, so they are converted before display.
library;

final _legacyStart = RegExp(
  r'^\s*<(p|h[1-6]|ul|ol|blockquote|pre|div|table)\b',
  caseSensitive: false,
);
final _comment = RegExp(r'<!--[\s\S]*?-->');
final _tag = RegExp(r'''<(/?)([a-zA-Z][\w-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>''');
final _attr = RegExp(r'''([a-zA-Z][\w-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''');
final _entity = RegExp(r'&(#x[\da-f]+|#\d+|[a-z]+);', caseSensitive: false);
final _bareUrl = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);

const _namedEntities = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '};

const _marks = {
  'strong': '**',
  'b': '**',
  'em': '*',
  'i': '*',
  's': '~~',
  'del': '~~',
  'strike': '~~',
  'u': '++',
};

final _framed = {
  'ul',
  'ol',
  'li',
  'blockquote',
  'a',
  'code',
  'pre',
  'table',
  'tr',
  'td',
  'th',
  ..._marks.keys,
};

/// What the editor's nodes look like in saved HTML, and the tag each one is written as now.
const _editorNodes = {
  'attachment-card': 'kaneo-attachment',
  'kaneo-issue-link': 'kaneo-issue-link',
  'kaneo-embed': 'kaneo-embed',
  'kaneo-mention': 'kaneo-mention',
};

/// Whether [text] is saved editor HTML. Only text that starts with a block tag counts.
bool isLegacyHtml(String text) => _legacyStart.hasMatch(text);

String decodeHtmlEntities(String text) => text.replaceAllMapped(_entity, (match) {
  final entity = match[1]!;
  if (!entity.startsWith('#')) return _namedEntities[entity.toLowerCase()] ?? match[0]!;
  final hex = entity[1] == 'x' || entity[1] == 'X';
  final code = int.tryParse(entity.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
  return code != null && code > 0 && code <= 0x10ffff ? String.fromCharCode(code) : match[0]!;
});

/// Reads the attributes in the text of an opening tag. Names come back in lower case.
Map<String, String> parseHtmlAttributes(String raw) => {
  for (final match in _attr.allMatches(raw))
    match[1]!.toLowerCase(): decodeHtmlEntities(match[2] ?? match[3] ?? match[4]!),
};

/// Keeps text literal, as the web shows it, instead of letting it read as Markdown.
String _escapeText(String text) => text.splitMapJoin(
  // An autolink runs to the next space, so a backslash in one would end up in the address.
  _bareUrl,
  onMatch: (match) => match[0]!,
  onNonMatch: (plain) => plain
      .replaceAllMapped(RegExp(r'[\\`*_\[\]<>#~|+-]'), (m) => '\\${m[0]}')
      .replaceAllMapped(RegExp(r'(\d)([.)])'), (m) => '${m[1]}\\${m[2]}')
      .replaceAllMapped(RegExp(r'&(?=#?\w+;)'), (_) => r'\&'),
);

int _longestBackticks(String text) =>
    RegExp(r'`+')
        .allMatches(text)
        .fold(0, (longest, run) => run[0]!.length > longest ? run[0]!.length : longest);

class _Frame {
  _Frame(this.tag, this.attrs);

  final String tag;
  final String attrs;
  String out = '';
  int items = 0;
}

String _finish(_Frame frame, _Frame parent) {
  final body = frame.out.trim();
  switch (frame.tag) {
    case 'li':
      parent.items += 1;
      final attrs = parseHtmlAttributes(frame.attrs);
      final start = int.tryParse(parseHtmlAttributes(parent.attrs)['start'] ?? '') ?? 1;
      final marker = parent.tag == 'ol' ? '${start + parent.items - 1}. ' : '- ';
      final checkbox = attrs['data-type'] != 'taskItem'
          ? ''
          : attrs['data-checked'] == 'true'
          ? '[x] '
          : '[ ] ';
      final indent = ' ' * marker.length;
      final content = body.replaceAll(RegExp(r'\n{2,}'), '\n').replaceAll('\n', '\n$indent');
      return '$marker$checkbox$content\n';
    case 'ul':
    case 'ol':
      return parent.tag == 'li' ? '\n${frame.out}' : '${frame.out}\n';
    case 'blockquote':
      final quoted = body.split('\n').map((line) => line.isEmpty ? '>' : '> $line').join('\n');
      return '$quoted\n\n';
    case 'pre':
      final fence = '`' * _max(3, _longestBackticks(frame.out) + 1);
      return '$fence\n${frame.out.replaceFirst(RegExp(r'\n$'), '')}\n$fence\n\n';
    case 'code':
      if (frame.out.isEmpty) return '';
      final fence = '`' * (_longestBackticks(frame.out) + 1);
      final pad = frame.out.startsWith('`') || frame.out.endsWith('`') ? ' ' : '';
      return '$fence$pad${frame.out}$pad$fence';
    case 'td':
    case 'th':
      parent.items += 1;
      return ' ${body.replaceAll(RegExp(r'\s*\n\s*'), ' ')} |';
    case 'tr':
      parent.items += 1;
      final row = '|${frame.out}\n';
      // A Markdown table always has a header, so the first row becomes it.
      return parent.items == 1 ? '$row|${' --- |' * frame.items}\n' : row;
    case 'table':
      return '\n\n${frame.out}\n';
    default:
      final mark = _marks[frame.tag];
      if (mark != null) {
        // Markdown ignores delimiters next to inner spaces, so keep the spaces outside.
        final core = frame.out.trim();
        if (core.isEmpty) return frame.out;
        final lead = frame.out.substring(0, frame.out.indexOf(core));
        final trail = frame.out.substring(lead.length + core.length);
        return '$lead$mark$core$mark$trail';
      }
      final href = parseHtmlAttributes(frame.attrs)['href'];
      return href != null ? '[${frame.out}]($href)' : frame.out;
  }
}

int _max(int a, int b) => a > b ? a : b;

/// Converts editor HTML to Markdown. `img` and `kaneo-*` tags stay as they are, for
/// `kaneoInlineSyntaxes` to read.
String legacyHtmlToMarkdown(String html) {
  final stack = [_Frame('', '')];
  _Frame top() => stack.last;
  void emit(String text) => top().out += text;

  var pre = 0;
  String? skipping;
  var skipDepth = 0;

  void text(String token) {
    if (token.isEmpty) return;
    if (pre > 0) {
      emit(decodeHtmlEntities(token));
    } else if (token.trim().isNotEmpty) {
      final decoded = decodeHtmlEntities(token.replaceAll(RegExp(r'\s+'), ' '));
      emit(stack.any((frame) => frame.tag == 'code') ? decoded : _escapeText(decoded));
    } else if (!RegExp(r'\s$').hasMatch(top().out)) {
      emit(' ');
    }
  }

  void tag(String token, bool closing, String name, String attrs) {
    if (name == 'img' || name.startsWith('kaneo-')) {
      emit(token);
    } else if (name == 'script' || name == 'style') {
      if (closing) return;
      skipping = name;
      skipDepth = 1;
    } else if ((name == 'span' || name == 'div') && !closing && _nodeTag(attrs) != null) {
      emit('<${_nodeTag(attrs)}$attrs />${name == 'div' ? '\n\n' : ''}');
      skipping = name;
      skipDepth = 1;
    } else if (name == 'code' && pre > 0) {
      return;
    } else if (_framed.contains(name)) {
      if (name == 'pre') pre = _max(0, pre + (closing ? -1 : 1));
      if (!closing) {
        stack.add(_Frame(name, attrs));
      } else if (stack.skip(1).any((frame) => frame.tag == name)) {
        _Frame frame;
        do {
          frame = stack.removeLast();
          top().out += _finish(frame, top());
        } while (frame.tag != name);
      }
    } else if (RegExp(r'^h[1-6]$').hasMatch(name)) {
      emit(closing ? '\n\n' : '${'#' * int.parse(name[1])} ');
    } else if (name == 'br') {
      emit('  \n');
    } else if (name == 'hr') {
      emit('\n\n---\n\n');
    } else if (closing && (name == 'p' || name == 'div')) {
      emit('\n\n');
    }
  }

  final source = html.replaceAll(_comment, '');
  var position = 0;
  for (final match in _tag.allMatches(source)) {
    final closing = match[1]!.isNotEmpty;
    final name = match[2]!.toLowerCase();
    if (skipping != null) {
      if (name == skipping) skipDepth += closing ? -1 : 1;
      if (skipDepth == 0) skipping = null;
    } else {
      text(source.substring(position, match.start));
      tag(match[0]!, closing, name, match[3]!);
    }
    position = match.end;
  }
  if (skipping == null) text(source.substring(position));

  while (stack.length > 1) {
    final frame = stack.removeLast();
    top().out += _finish(frame, top());
  }
  return top().out
      .replaceAll(RegExp(r'[ \t]+\n\n'), '\n\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String? _nodeTag(String attrs) => _editorNodes[parseHtmlAttributes(attrs)['data-type']];
