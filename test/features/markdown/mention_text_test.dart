import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/features/markdown/mention_text.dart';

const _ana = '<kaneo-mention id="u1" label="Ana"></kaneo-mention>';

TextEditingValue _caretAtEnd(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  group('mentionTag', () {
    test('is what the web editor writes', () {
      expect(mentionTag('u1', 'Ana'), _ana);
    });

    test('keeps a name from breaking out of its attribute', () {
      expect(
        mentionTag('u1', 'A "B" <C> & D'),
        '<kaneo-mention id="u1" label="A &quot;B&quot; &lt;C&gt; &amp; D"></kaneo-mention>',
      );
    });
  });

  group('picking and saving', () {
    test('a picked name is saved as its tag', () {
      final mentions = CommentMentions();
      final shown = 'Hi ${mentions.pick(id: 'u1', name: 'Ana')}, look';
      expect(shown, 'Hi @Ana, look');
      expect(mentions.save(shown), 'Hi $_ana, look');
    });

    test('every use of a picked name counts', () {
      final mentions = CommentMentions()..pick(id: 'u1', name: 'Ana');
      expect(mentions.save('@Ana and @Ana'), '$_ana and $_ana');
    });

    test('a name nobody picked stays plain text', () {
      expect(CommentMentions().save('Hi @Ana'), 'Hi @Ana');
      final mentions = CommentMentions()..pick(id: 'u1', name: 'Ana');
      expect(mentions.save('@Bob'), '@Bob');
    });

    test('a longer name is not read as a shorter one', () {
      final mentions = CommentMentions()
        ..pick(id: 'u1', name: 'Ana')
        ..pick(id: 'u2', name: 'Ana Maria');
      expect(mentions.save('@Ana Maria @Ana'), '${mentionTag('u2', 'Ana Maria')} $_ana');
    });

    test('a name carrying on past the mention is a different word', () {
      final mentions = CommentMentions()..pick(id: 'u1', name: 'Ana');
      expect(mentions.save('@Anabel'), '@Anabel');
      expect(mentions.save('me@Ana'), 'me@Ana');
    });

    test('Chinese needs no space around a mention', () {
      final mentions = CommentMentions()..pick(id: 'u1', name: '张三');
      final tag = mentionTag('u1', '张三');
      expect(mentions.save('你好@张三看一下'), '你好$tag看一下');
    });

    test('a name with characters a pattern would read is taken literally', () {
      final mentions = CommentMentions()..pick(id: 'u1', name: 'A.B (C)');
      expect(mentions.save('@A.B (C)'), mentionTag('u1', 'A.B (C)'));
      expect(mentions.save('@AxB (C)'), '@AxB (C)');
    });

    test('code samples are left alone', () {
      final mentions = CommentMentions()..pick(id: 'u1', name: 'Ana');
      expect(mentions.save('`@Ana` @Ana'), '`@Ana` $_ana');
      expect(mentions.save('```\n@Ana\n```\n@Ana'), '```\n@Ana\n```\n$_ana');
    });

    test('a lone backtick does not hide the rest of the comment', () {
      final mentions = CommentMentions()..pick(id: 'u1', name: 'Ana');
      expect(mentions.save('it`s\n\n@Ana'), 'it`s\n\n$_ana');
    });

    test('two people with one name can both be mentioned', () {
      final mentions = CommentMentions();
      final first = mentions.pick(id: 'u1', name: 'Ana');
      final second = mentions.pick(id: 'u2', name: 'Ana');
      expect(first, '@Ana');
      expect(second, mentionTag('u2', 'Ana'));
      expect(mentions.save('$first $second'), '$_ana ${mentionTag('u2', 'Ana')}');
    });

    test('picking the same person twice is one mention', () {
      final mentions = CommentMentions();
      expect(mentions.pick(id: 'u1', name: 'Ana'), '@Ana');
      expect(mentions.pick(id: 'u1', name: 'Ana'), '@Ana');
    });

    test('clearing forgets the names', () {
      final mentions = CommentMentions()..pick(id: 'u1', name: 'Ana');
      expect(mentions.knows('Ana'), isTrue);
      mentions.clear();
      expect(mentions.knows('Ana'), isFalse);
      expect(mentions.save('@Ana'), '@Ana');
    });
  });

  group('editing what was saved', () {
    void roundTrips(String saved, String shown) {
      final mentions = CommentMentions();
      expect(mentions.show(saved), shown);
      expect(mentions.save(shown), saved);
    }

    test('a mention reads as the name, and goes back unchanged', () {
      roundTrips('Hi $_ana, look', 'Hi @Ana, look');
    });

    test('an escaped name comes back the way it was written', () {
      const saved = '<kaneo-mention id="u1" label="R&amp;D"></kaneo-mention>';
      roundTrips(saved, '@R&D');
    });

    test('any way of writing the tag comes back byte for byte', () {
      const self = "<KANEO-MENTION data-id='u1' data-label='Ana' />";
      roundTrips('$self hi', '@Ana hi');
      const inner = '<kaneo-mention id="u2" label="Bo">@Bo</kaneo-mention>';
      roundTrips('$inner hi', '@Bo hi');
    });

    test('a tag in a code sample stays a tag', () {
      roundTrips('`$_ana`', '`$_ana`');
      roundTrips('```\n$_ana\n```', '```\n$_ana\n```');
    });

    test('a tag with no name stays a tag', () {
      const saved = '<kaneo-mention id="u1" label=""></kaneo-mention>';
      roundTrips(saved, saved);
    });

    test('with two people of one name, the second stays a tag', () {
      final other = mentionTag('u2', 'Ana');
      roundTrips('$_ana $other', '@Ana $other');
    });

    test('text around the mention is not touched', () {
      roundTrips('  # Title  \r\n\r\n* $_ana  \n', '  # Title  \r\n\r\n* @Ana  \n');
    });
  });

  group('mentionQueryAt', () {
    test('finds what follows an @ at the caret', () {
      expect(mentionQueryAt(_caretAtEnd('@')), (start: 0, query: ''));
      expect(mentionQueryAt(_caretAtEnd('Hi @An')), (start: 3, query: 'An'));
      expect(mentionQueryAt(_caretAtEnd('Hi @Test U')), (start: 3, query: 'Test U'));
    });

    test('follows the caret, not the end of the text', () {
      const value = TextEditingValue(
        text: '@Ana and more',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(mentionQueryAt(value), (start: 0, query: 'An'));
    });

    test('starts right after Chinese, with no space', () {
      expect(mentionQueryAt(_caretAtEnd('你好@张')), (start: 2, query: '张'));
    });

    test('is nothing without an @ on the line', () {
      expect(mentionQueryAt(_caretAtEnd('Hello')), isNull);
      expect(mentionQueryAt(_caretAtEnd('@Ana\nHello')), isNull);
    });

    test('is nothing in an address', () {
      expect(mentionQueryAt(_caretAtEnd('me@example')), isNull);
    });

    test('is nothing while selecting, or before the box has a caret', () {
      const selecting = TextEditingValue(
        text: '@Ana',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      expect(mentionQueryAt(selecting), isNull);
      expect(mentionQueryAt(const TextEditingValue(text: '@Ana')), isNull);
    });
  });

  group('changing the text', () {
    test('a mention replaces what was typed, and leaves the caret after a space', () {
      final value = _caretAtEnd('Hi @An');
      final result = withMention(value, mentionQueryAt(value)!, '@Ana');
      expect(result.text, 'Hi @Ana ');
      expect(result.selection.baseOffset, result.text.length);
      expect(result.composing, TextRange.empty);
    });

    test('a mention keeps what comes after the caret', () {
      const value = TextEditingValue(
        text: 'Hi @An, look',
        selection: TextSelection.collapsed(offset: 6),
      );
      final result = withMention(value, mentionQueryAt(value)!, '@Ana');
      expect(result.text, 'Hi @Ana , look');
      expect(result.selection.baseOffset, 8);
    });

    test('an @ is set apart from a word before it', () {
      expect(withAtSign(_caretAtEnd('Hi')).text, 'Hi @');
      expect(withAtSign(_caretAtEnd('Hi ')).text, 'Hi @');
      expect(withAtSign(_caretAtEnd('Hi\n')).text, 'Hi\n@');
      expect(withAtSign(_caretAtEnd('')).text, '@');
    });

    test('an @ goes at the caret, and the caret after it', () {
      const value = TextEditingValue(
        text: 'Hi there',
        selection: TextSelection(baseOffset: 3, extentOffset: 8),
      );
      final result = withAtSign(value);
      expect(result.text, 'Hi @');
      expect(result.selection.baseOffset, 4);
    });

    test('an @ goes at the end of a box that has no caret yet', () {
      final result = withAtSign(const TextEditingValue(text: 'Hi'));
      expect(result.text, 'Hi @');
      expect(result.selection.baseOffset, 4);
    });
  });
}
