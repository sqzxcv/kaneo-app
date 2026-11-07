import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/search/search_results.dart';

void main() {
  group('plainPreview', () {
    test('leaves plain words alone', () {
      expect(plainPreview('Plain words'), 'Plain words');
    });

    test('takes the marks off', () {
      expect(plainPreview('**bold** and `code` and ~~gone~~'), 'bold and code and gone');
      expect(plainPreview('# A heading\n> A quote'), 'A heading A quote');
    });

    test('shows a link as its words, and leaves images out', () {
      expect(
        plainPreview('See [the doc](https://x.test) ![a](/api/asset/1) now'),
        'See the doc now',
      );
    });

    test('takes the words out of the editor tags', () {
      expect(
        plainPreview('Ask <kaneo-mention user-id="u" label="Ann">@Ann</kaneo-mention> today'),
        'Ask @Ann today',
      );
      expect(plainPreview('<p>Legacy <strong>text</strong></p><img src="/a.png"/>'), 'Legacy text');
    });

    test('keeps a line together', () {
      expect(plainPreview('  one\n\n  two\tthree '), 'one two three');
    });

    test('keeps words that only look like marks', () {
      expect(
        plainPreview('snake_case and issue #12 and a > b'),
        'snake_case and issue #12 and a > b',
      );
    });
  });

  group('rememberedSearch', () {
    test('finds nothing until a search is kept, and nothing after it is forgotten', () async {
      final store = MemoryCacheStore();
      expect(rememberedSearch(store, 'w'), isNull);

      await store.write('search/w', {'text': 'board', 'response': <String, Object?>{}});
      expect(rememberedSearch(store, 'w'), 'board');
      expect(rememberedSearch(store, 'other'), isNull);

      await forgetSearch(store, 'w');
      expect(rememberedSearch(store, 'w'), isNull);
    });

    test('ignores what an older version kept', () async {
      final store = MemoryCacheStore();
      await store.write('search/w', <Object?>['old']);
      expect(rememberedSearch(store, 'w'), isNull);
      await store.write('search/w', {'text': 1});
      expect(rememberedSearch(store, 'w'), isNull);
    });
  });
}
