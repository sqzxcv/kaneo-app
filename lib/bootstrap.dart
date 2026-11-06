import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/core.dart';

/// Reads everything the first frame needs: preferences, the language and the saved session.
Future<ProviderContainer> bootstrap({SessionStorage? sessionStorage}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final storage = sessionStorage ?? SecureSessionStorage();
  final choice = prefs.getString('kaneo.language') ?? systemLanguage;
  final i18n = await I18n.load(locale: activeLocale(choice));
  final cacheRoot = await defaultCacheRoot();

  Session? session;
  try {
    session = await storage.read();
  } on Exception {
    session = null;
  }

  return ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      i18nProvider.overrideWithValue(i18n),
      sessionStorageProvider.overrideWithValue(storage),
      initialSessionProvider.overrideWithValue(session),
      cacheRootProvider.overrideWithValue(cacheRoot),
    ],
  );
}
