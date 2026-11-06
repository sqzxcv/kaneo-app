/// The catalogs in `assets/i18n`, with each language's name in that language.
const Map<String, String> supportedLocales = {
  'az-AZ': 'Azərbaycanca',
  'de-DE': 'Deutsch',
  'el-GR': 'Ελληνικά',
  'en-US': 'English',
  'es-ES': 'Español',
  'fr-FR': 'Français',
  'hi-IN': 'हिन्दी',
  'id-ID': 'Bahasa Indonesia',
  'it-IT': 'Italiano',
  'ja-JP': '日本語',
  'ko-KR': '한국어',
  'mk-MK': 'Македонски',
  'nl-NL': 'Nederlands',
  'pl-PL': 'Polski',
  'pt-BR': 'Português (Brasil)',
  'ru-RU': 'Русский',
  'tr-TR': 'Türkçe',
  'uk-UA': 'Українська',
  'vi-VN': 'Tiếng Việt',
  'zh-CN': '简体中文',
  'zh-TW': '繁體中文',
};

const String defaultLocale = 'en-US';

String _language(String locale) => locale.toLowerCase().split(RegExp('[-_]')).first;

/// Chinese splits by script, not region: iOS reports `zh-Hant-TW` or `zh-HK`, which must not fall
/// through to the first Chinese catalog (Simplified).
String? _chineseCatalog(String normalized) {
  if (_language(normalized) != 'zh') return null;
  return RegExp(r'-(hant|tw|hk|mo)\b').hasMatch(normalized) ? 'zh-TW' : 'zh-CN';
}

/// Picks the first candidate with a catalog, matching the region first, then the language.
String resolveLocale(Iterable<String?> candidates) {
  for (final candidate in candidates) {
    if (candidate == null || candidate.isEmpty) continue;
    final normalized = candidate.replaceAll('_', '-').toLowerCase();
    final chinese = _chineseCatalog(normalized);
    if (chinese != null) return chinese;
    for (final locale in supportedLocales.keys) {
      if (locale.toLowerCase() == normalized) return locale;
    }
    for (final locale in supportedLocales.keys) {
      if (_language(locale) == _language(candidate)) return locale;
    }
  }
  return defaultLocale;
}
