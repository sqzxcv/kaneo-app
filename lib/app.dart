import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/core.dart';

class KaneoApp extends ConsumerStatefulWidget {
  const KaneoApp({super.key});

  @override
  ConsumerState<KaneoApp> createState() => _KaneoAppState();
}

class _KaneoAppState extends ConsumerState<KaneoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ref.read(sessionProvider) == null && ref.read(devConfigProvider).isConfigured) {
      unawaited(_devSignIn());
    }
  }

  Future<void> _devSignIn() async {
    try {
      await ref.read(sessionProvider.notifier).devSignIn();
    } on ApiError catch (error) {
      showGlobalToast(error.message, kind: ToastKind.error);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    final choice = ref.read(languageChoiceProvider);
    if (choice == systemLanguage) {
      unawaited(ref.read(i18nProvider).setLocale(activeLocale(choice, locales)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    return I18nScope(
      i18n: i18n,
      child: ListenableBuilder(
        listenable: i18n,
        builder: (context, _) => MaterialApp.router(
          scaffoldMessengerKey: rootMessengerKey,
          routerConfig: ref.watch(routerProvider),
          onGenerateTitle: (context) => context.t('common:appName'),
          debugShowCheckedModeBanner: false,
          theme: kaneoLightTheme,
          darkTheme: kaneoDarkTheme,
          themeMode: ref.watch(themeModeProvider),
          locale: i18n.flutterLocale,
          supportedLocales: supportedLocales.keys.map(localeFromTag),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      ),
    );
  }
}
