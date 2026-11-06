import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'resolve_locale.dart';

/// Reads a JSON asset, or null when it does not exist.
typedef CatalogReader = Future<Map<String, dynamic>?> Function(String asset);

Future<Map<String, dynamic>?> _readBundled(String asset) async {
  try {
    final data = await rootBundle.load(asset);
    final text = utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    return jsonDecode(text) as Map<String, dynamic>;
  } on FlutterError {
    return null;
  }
}

Map<String, String> _flatten(Map<String, dynamic>? tree) {
  final out = <String, String>{};
  void walk(Map<String, dynamic> node, String prefix) {
    node.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        walk(value, '$prefix$key.');
      } else if (value is String) {
        out['$prefix$key'] = value;
      }
    });
  }

  if (tree != null) walk(tree, '');
  return out;
}

/// Translates with the same key format as the web app's i18next catalogs.
///
/// Keys look like `mobile:errors.notFound`; without a namespace, `mobile` is assumed. Passing
/// `count` selects the plural form for the active language, and `{{name}}` placeholders are filled
/// from the arguments. Lookup order: the app's override for the active language, its catalog, the
/// English override, the English catalog.
///
/// In widgets use `context.t(...)`, which rebuilds when the language changes.
class I18n extends ChangeNotifier {
  I18n._(this._read, this._english);

  final CatalogReader _read;
  final Map<String, String> _english;
  Map<String, String> _active = const {};
  String _locale = defaultLocale;

  static Future<I18n> load({String locale = defaultLocale, CatalogReader? read}) async {
    final reader = read ?? _readBundled;
    final i18n = I18n._(reader, await _loadCatalog(reader, defaultLocale));
    await i18n.setLocale(locale);
    return i18n;
  }

  static Future<Map<String, String>> _loadCatalog(CatalogReader read, String locale) async {
    return {
      ..._flatten(await read('assets/i18n/$locale.json')),
      ..._flatten(await read('assets/i18n/overrides/$locale.json')),
    };
  }

  /// The active catalog, such as `zh-CN`.
  String get locale => _locale;

  /// The active catalog as a Flutter locale.
  Locale get flutterLocale => localeFromTag(_locale);

  /// The active catalog in the form `intl` formatters take, such as `zh_CN`.
  String get intlLocale => _locale.replaceAll('-', '_');

  Future<void> setLocale(String locale) async {
    final catalog = locale == defaultLocale ? _english : await _loadCatalog(_read, locale);
    await initializeDateFormatting(locale.replaceAll('-', '_'));
    _active = catalog;
    _locale = locale;
    notifyListeners();
  }

  String t(String key, [Map<String, Object?> args = const {}]) {
    final path = key.contains(':') ? key.replaceFirst(':', '.') : 'mobile.$key';
    final template = _pluralized(path, args['count']) ?? _lookup(path);
    if (template == null) return key;
    return _interpolate(template, args);
  }

  String? _lookup(String path) => _active[path] ?? _english[path];

  String? _pluralized(String path, Object? count) {
    if (count is! num) return null;
    if (count == 0) {
      final zero = _lookup('${path}_zero');
      if (zero != null) return zero;
    }
    final form = Intl.pluralLogic<String>(
      count,
      zero: 'zero',
      one: 'one',
      two: 'two',
      few: 'few',
      many: 'many',
      other: 'other',
      locale: intlLocale,
      useExplicitNumberCases: false,
    );
    return _active['${path}_$form'] ??
        _active['${path}_other'] ??
        _english['${path}_$form'] ??
        _english['${path}_other'];
  }

  static final _placeholder = RegExp(r'\{\{\s*([\w.]+)\s*(?:,\s*(\w+)\s*)?\}\}');

  String _interpolate(String template, Map<String, Object?> args) {
    return template.replaceAllMapped(_placeholder, (match) {
      final value = args[match.group(1)];
      if (value == null) return '';
      return switch (match.group(2)) {
        'number' when value is num => NumberFormat.decimalPattern(intlLocale).format(value),
        'list' when value is Iterable => value.join(_locale.startsWith('zh') ? '、' : ', '),
        _ => value.toString(),
      };
    });
  }
}

/// Turns `zh-CN` into a Flutter locale.
Locale localeFromTag(String tag) {
  final parts = tag.split('-');
  return Locale(parts.first, parts.length > 1 ? parts[1] : null);
}

/// Makes the active [I18n] available to `context.t(...)`, and rebuilds readers on language changes.
class I18nScope extends InheritedNotifier<I18n> {
  const I18nScope({super.key, required I18n i18n, required super.child}) : super(notifier: i18n);

  static I18n of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<I18nScope>();
    assert(scope != null, 'No I18nScope above this widget.');
    return scope!.notifier!;
  }
}

extension I18nContext on BuildContext {
  /// Translates [key]. See [I18n.t].
  String t(String key, [Map<String, Object?> args = const {}]) => I18nScope.of(this).t(key, args);
}
