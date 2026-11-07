import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'resolve_locale.dart';

/// Where the choice is kept, for code that runs without the providers.
const languageChoiceKey = 'kaneo.language';

/// The value of [languageChoiceProvider] that means "follow the device".
const String systemLanguage = 'system';

/// The language the person picked, or [systemLanguage]. Setting it switches the app's catalog.
final languageChoiceProvider = NotifierProvider<LanguageChoice, String>(LanguageChoice.new);

class LanguageChoice extends Notifier<String> {
  @override
  String build() => ref.watch(prefsProvider).getString(languageChoiceKey) ?? systemLanguage;

  Future<void> select(String? choice) async {
    final value = choice ?? systemLanguage;
    state = value;
    await ref.read(prefsProvider).setString(languageChoiceKey, value);
    await ref.read(i18nProvider).setLocale(activeLocale(value));
  }
}

/// The catalog for [choice], given the device's languages.
String activeLocale(String choice, [List<Locale>? deviceLocales]) {
  if (choice != systemLanguage) return choice;
  final locales = deviceLocales ?? WidgetsBinding.instance.platformDispatcher.locales;
  return resolveLocale(locales.map((l) => l.toLanguageTag()));
}
