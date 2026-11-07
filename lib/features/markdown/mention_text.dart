/// Mentions in a plain text box.
///
/// What is saved for a mention is a `<kaneo-mention>` tag, and that tag is what makes the server
/// notify the person. Nobody wants to read or edit one, so the text box says `@Name` and
/// [CommentMentions] remembers which tag each name stands for.
library;

import 'package:flutter/services.dart';

import 'legacy_html.dart';

final _mentionTag = RegExp(
  r'''<kaneo-mention(?=[\s/>])((?:[^>"']|"[^"]*"|'[^']*')*?)(?:/>|(?<!/)>[\s\S]*?</kaneo-mention\s*>)''',
  caseSensitive: false,
);

/// A fenced code block, or a code span within a paragraph. Unclosed fences run to the end of the text.
final _code = RegExp(
  r'^ {0,3}(`{3,}|~{3,})[^\n]*\n[\s\S]*?(?:^ {0,3}\1[`~]*[ \t]*$|(?![\s\S]))'
  r'|(?<!`)(`+)(?!`)(?:(?!\n[ \t]*\n)[\s\S])*?(?<!`)\2(?!`)',
  multiLine: true,
);

/// A letter of the kind that makes an `@` part of an address, or a name go on past a mention. Chinese
/// isn't one, because it is written without spaces: `@张三你好` mentions 张三.
final _wordCharacter = RegExp(r'[A-Za-z0-9_]');

/// A code sample stays what it is, as it does when it is shown: see `markdown_syntax.dart`.
String _outsideCode(String text, String Function(String plain) change) =>
    text.splitMapJoin(_code, onMatch: (match) => match[0]!, onNonMatch: change);

/// The tag the web editor writes for a mention, which the server looks for.
String mentionTag(String userId, String name) {
  String escaped(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return '<kaneo-mention id="${escaped(userId)}" label="${escaped(name)}"></kaneo-mention>';
}

/// Goes between what a comment's text box shows and what is saved. One per text box.
class CommentMentions {
  final _tags = <String, String>{};

  void clear() => _tags.clear();

  /// Whether [name] is already a mention here, rather than the start of a longer name being typed.
  bool knows(String name) => _tags.containsKey(name);

  /// What to show in the text box for [saved]. [save] gives back the very same tags.
  String show(String saved) => _outsideCode(
    saved,
    (plain) => plain.replaceAllMapped(_mentionTag, (match) {
      final attributes = parseHtmlAttributes(match[1]!);
      final name = attributes['label'] ?? attributes['data-label'];
      if (name == null || name.isEmpty) return match[0]!;
      final tag = match[0]!;
      if (_tags.putIfAbsent(name, () => tag) != tag) return tag;
      return '@$name';
    }),
  );

  /// What to put in the text box for a mention picked from a list.
  ///
  /// Two people can share a name, but one text can't stand for both, so the second one stays a tag.
  String pick({required String id, required String name}) {
    final tag = mentionTag(id, name);
    final known = _tags[name];
    if (known != null && _idIn(known) != id) return tag;
    _tags[name] ??= tag;
    return '@$name';
  }

  /// What to save for [shown], the text in the text box. A name typed by hand with nothing picked for
  /// it stays plain text, as on the web.
  String save(String shown) {
    if (_tags.isEmpty) return shown;
    // Longest first, so that `@Ana Maria` isn't read as `@Ana` and some words.
    final names = _tags.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    final mention = RegExp(
      '(?<![A-Za-z0-9_])@(${names.map(RegExp.escape).join('|')})(?![A-Za-z0-9_])',
    );
    return _outsideCode(
      shown,
      (plain) => plain.replaceAllMapped(mention, (match) => _tags[match[1]]!),
    );
  }

  String? _idIn(String tag) {
    final attributes = parseHtmlAttributes(_mentionTag.firstMatch(tag)?[1] ?? '');
    return attributes['id'] ?? attributes['data-id'];
  }
}

/// The `@` being typed at the caret: where it is, and what comes after it so far.
typedef MentionQuery = ({int start, String query});

/// Null unless the caret is on a line with an `@` before it that isn't part of an address. Names have
/// spaces in them, so it is up to the list of people to say when this has stopped being a name.
MentionQuery? mentionQueryAt(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final before = value.text.substring(0, selection.start);
  final lineStart = before.lastIndexOf('\n') + 1;
  final at = before.lastIndexOf('@');
  if (at < lineStart) return null;
  if (at > lineStart && _wordCharacter.hasMatch(before[at - 1])) return null;
  return (start: at, query: before.substring(at + 1));
}

/// [value] with [query] replaced by [mention] and a space to carry on from.
TextEditingValue withMention(TextEditingValue value, MentionQuery query, String mention) {
  final inserted = '$mention ';
  return TextEditingValue(
    text: value.text.replaceRange(query.start, value.selection.start, inserted),
    selection: TextSelection.collapsed(offset: query.start + inserted.length),
  );
}

/// [value] with an `@` at the caret, set apart from the word before it.
TextEditingValue withAtSign(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);
  final before = text.substring(0, selection.start);
  final start = before.isEmpty || before.endsWith(' ') || before.endsWith('\n')
      ? '$before@'
      : '$before @';
  return TextEditingValue(
    text: '$start${text.substring(selection.end)}',
    selection: TextSelection.collapsed(offset: start.length),
  );
}
