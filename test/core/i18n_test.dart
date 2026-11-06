import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/test_app.dart';

Map<String, dynamic> _flatten(Map<String, dynamic> tree, [String prefix = '']) => {
  for (final entry in tree.entries)
    if (entry.value is Map<String, dynamic>)
      ..._flatten(entry.value as Map<String, dynamic>, '$prefix${entry.key}.')
    else
      '$prefix${entry.key}': entry.value,
};

Map<String, dynamic> _readFlat(String path) {
  final file = File(path);
  return file.existsSync()
      ? _flatten(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
      : const {};
}

void main() {
  group('translating', () {
    Future<I18n> load(Map<String, Map<String, dynamic>> files, {String locale = defaultLocale}) =>
        I18n.load(locale: locale, read: (asset) async => files[asset]);

    test('finds a namespaced key, and assumes mobile without a namespace', () async {
      final i18n = await load({
        'assets/i18n/en-US.json': {
          'mobile': {
            'a': {'b': 'From mobile'},
          },
          'common': {'c': 'From common'},
        },
      });
      expect(i18n.t('common:c'), 'From common');
      expect(i18n.t('mobile:a.b'), 'From mobile');
      expect(i18n.t('a.b'), 'From mobile');
    });

    test('an unknown key shows the key rather than nothing', () async {
      final i18n = await load({});
      expect(i18n.t('mobile:nope'), 'mobile:nope');
    });

    test('looks in the override, the catalog, then English', () async {
      final i18n = await load({
        'assets/i18n/en-US.json': {
          'app': {'one': 'en catalog', 'two': 'en catalog', 'three': 'en catalog'},
        },
        'assets/i18n/overrides/en-US.json': {
          'app': {'four': 'en override'},
        },
        'assets/i18n/de-DE.json': {
          'app': {'one': 'de catalog', 'two': 'de catalog'},
        },
        'assets/i18n/overrides/de-DE.json': {
          'app': {'one': 'de override'},
        },
      }, locale: 'de-DE');
      expect(i18n.t('app:one'), 'de override');
      expect(i18n.t('app:two'), 'de catalog');
      expect(i18n.t('app:three'), 'en catalog');
      expect(i18n.t('app:four'), 'en override');
    });

    test('fills placeholders', () async {
      final i18n = await load({
        'assets/i18n/en-US.json': {
          'app': {
            'hello': 'Hello {{name}} and {{ other }}',
            'missing': 'Hello {{name}}!',
            'number': '{{count, number}} tasks',
            'list': 'For {{names, list}}',
          },
        },
      });
      expect(i18n.t('app:hello', {'name': 'Ada', 'other': 'Bo'}), 'Hello Ada and Bo');
      expect(i18n.t('app:missing'), 'Hello !');
      expect(i18n.t('app:number', {'count': 1234}), '1,234 tasks');
      expect(
        i18n.t('app:list', {
          'names': ['a', 'b'],
        }),
        'For a, b',
      );
    });

    test('picks plural forms by count', () async {
      final i18n = await load({
        'assets/i18n/en-US.json': {
          'app': {'task_one': '{{count}} task', 'task_other': '{{count}} tasks', 'plain': 'Plain'},
        },
      });
      expect(i18n.t('app:task', {'count': 1}), '1 task');
      expect(i18n.t('app:task', {'count': 2}), '2 tasks');
      expect(i18n.t('app:task', {'count': 0}), '0 tasks');
      expect(i18n.t('app:plain', {'count': 2}), 'Plain');
    });

    test('a _zero form wins at zero', () async {
      final i18n = await load({
        'assets/i18n/en-US.json': {
          'app': {'task_zero': 'None', 'task_other': '{{count}} tasks'},
        },
      });
      expect(i18n.t('app:task', {'count': 0}), 'None');
    });
  });

  group('the shipped catalogs', () {
    test('plurals follow each language\'s rules', () async {
      final english = await I18n.load(read: readCatalogFile);
      expect(english.t('app:board.taskCount', {'count': 1}), '1 task');
      expect(english.t('app:board.taskCount', {'count': 5}), '5 tasks');

      final chinese = await I18n.load(locale: 'zh-CN', read: readCatalogFile);
      expect(chinese.t('app:board.taskCount', {'count': 1}), '1 个任务');
      expect(chinese.t('app:board.taskCount', {'count': 5}), '5 个任务');

      Future<String> russian(int count) async {
        final i18n = await I18n.load(
          locale: 'ru-RU',
          read: (asset) async => asset == 'assets/i18n/ru-RU.json'
              ? {
                  'app': {'n_one': 'one', 'n_few': 'few', 'n_many': 'many', 'n_other': 'other'},
                }
              : null,
        );
        return i18n.t('app:n', {'count': count});
      }

      expect(await russian(1), 'one');
      expect(await russian(3), 'few');
      expect(await russian(5), 'many');
      expect(await russian(21), 'one');
    });

    test('every language has the same plural-free keys as English, or falls back', () {
      final english = _readFlat('assets/i18n/en-US.json');
      final pluralSuffix = RegExp(r'_(zero|one|two|few|many|other)$');
      String base(String key) => key.replaceFirst(pluralSuffix, '');
      final englishBases = english.keys.map(base).toSet();

      for (final locale in supportedLocales.keys) {
        final catalog = _readFlat('assets/i18n/$locale.json');
        expect(catalog, isNotEmpty, reason: '$locale has no catalog');
        final bases = catalog.keys.map(base).toSet();
        final missing = englishBases.difference(bases);
        expect(missing, isEmpty, reason: '$locale is missing $missing');
      }
    });

    test('every supported language has a catalog, and every catalog is listed', () {
      final files = Directory('assets/i18n')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last.replaceFirst('.json', ''))
          .toSet();
      expect(files, supportedLocales.keys.toSet());
    });

    test('app strings exist in English and in both Chinese catalogs', () {
      final english = _readFlat('assets/i18n/overrides/en-US.json');
      expect(english, isNotEmpty);
      for (final locale in ['zh-CN', 'zh-TW']) {
        final override = _readFlat('assets/i18n/overrides/$locale.json');
        for (final key in english.keys) {
          final singularOnly = key.replaceFirst(RegExp(r'_(one|other)$'), '_other');
          expect(override.containsKey(singularOnly), isTrue, reason: '$locale lacks $singularOnly');
        }
      }
    });

    test('Simplified Chinese has no English left in the delete-account strings', () async {
      final i18n = await I18n.load(locale: 'zh-CN', read: readCatalogFile);
      expect(i18n.t('mobile:account.deleteAccount.sectionTitle'), '危险区域');
      expect(i18n.t('mobile:account.deleteAccount.title'), '删除账户');
      expect(i18n.t('mobile:account.deleteAccount.confirm'), '删除账户');
    });

    test('Danger zone and Delete account appear nowhere in Simplified Chinese', () {
      final merged = {
        ..._readFlat('assets/i18n/zh-CN.json'),
        ..._readFlat('assets/i18n/overrides/zh-CN.json'),
      };
      final offending = merged.entries.where(
        (e) => RegExp('danger zone|delete account', caseSensitive: false).hasMatch('${e.value}'),
      );
      expect(offending.map((e) => e.key), isEmpty);
    });

    test('every key the app asks for exists', () {
      final english = {
        ..._readFlat('assets/i18n/en-US.json'),
        ..._readFlat('assets/i18n/overrides/en-US.json'),
      };
      final used = RegExp(r"'((?:mobile|app|settings|common|auth|tasks|navigation):[\w.]+)'");
      final missing = <String>{};
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final match in used.allMatches(file.readAsStringSync())) {
          final key = match[1]!.replaceFirst(':', '.');
          if (!english.containsKey(key) && !english.containsKey('${key}_other')) {
            missing.add(match[1]!);
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('apart from sign-in routes that are out of scope, mobile strings are translated', () {
      final english = _readFlat('assets/i18n/en-US.json');
      final chinese = {
        ..._readFlat('assets/i18n/zh-CN.json'),
        ..._readFlat('assets/i18n/overrides/zh-CN.json'),
      };
      const sameInBoth = {
        'mobile.taskDetail.links.url',
        'mobile.taskDetail.activity.entry',
        'mobile.notificationSettings.delivery.webhook',
      };
      final untranslated = [
        for (final entry in english.entries)
          if (entry.key.startsWith('mobile.') &&
              !entry.key.startsWith('mobile.signIn.') &&
              !sameInBoth.contains(entry.key) &&
              chinese[entry.key] == entry.value)
            entry.key,
      ];
      expect(untranslated, isEmpty);
    });
  });

  group('choosing a language', () {
    test('matches the region, then the language', () {
      expect(resolveLocale(['de-DE']), 'de-DE');
      expect(resolveLocale(['de-AT']), 'de-DE');
      expect(resolveLocale(['pt_PT']), 'pt-BR');
    });

    test('splits Chinese by script', () {
      expect(resolveLocale(['zh-Hans-CN']), 'zh-CN');
      expect(resolveLocale(['zh-CN']), 'zh-CN');
      expect(resolveLocale(['zh']), 'zh-CN');
      expect(resolveLocale(['zh-Hant-TW']), 'zh-TW');
      expect(resolveLocale(['zh-HK']), 'zh-TW');
    });

    test('takes the first candidate with a catalog, otherwise English', () {
      expect(resolveLocale(['xx-XX', null, '', 'fr-CA']), 'fr-FR');
      expect(resolveLocale(['xx-XX']), 'en-US');
      expect(resolveLocale(const []), 'en-US');
    });

    test('activeLocale follows the device unless a language was picked', () {
      expect(activeLocale('de-DE', const [Locale('fr', 'FR')]), 'de-DE');
      expect(activeLocale(systemLanguage, const [Locale('fr', 'FR')]), 'fr-FR');
    });

    test('every language gives a Flutter locale and date formats', () async {
      for (final locale in supportedLocales.keys) {
        final i18n = await I18n.load(locale: locale, read: readCatalogFile);
        expect(i18n.locale, locale);
        expect(i18n.flutterLocale.toLanguageTag(), locale);
        expect(formatLongDate(i18n, DateTime(2026, 3, 9)), isNotEmpty);
      }
    });
  });

  testWidgets('the app bundles the catalogs', (tester) async {
    final i18n = (await tester.runAsync(() => I18n.load(locale: 'zh-CN')))!;
    expect(i18n.t('mobile:common.cancel'), isNot('mobile:common.cancel'));
    expect(i18n.t('mobile:account.deleteAccount.title'), '删除账户');
    expect(i18n.t('app:placeholder.notice'), contains('占位页'));
  });
}
