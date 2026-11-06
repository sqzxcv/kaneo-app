import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/core.dart';

/// Reads everything the first frame needs: preferences, the language and the saved session.
Future<ProviderContainer> bootstrap({SessionStorage? sessionStorage}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // A build with dev.env signs in by itself on every launch, so it has nothing to keep. Staying out
  // of the Keychain also avoids its permission prompts, which block the first frame on macOS when
  // the build's signature changes, and leaves no development key behind.
  final storage =
      sessionStorage ??
      (DevConfig.fromEnvironment().isConfigured ? MemorySessionStorage() : SecureSessionStorage());
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
