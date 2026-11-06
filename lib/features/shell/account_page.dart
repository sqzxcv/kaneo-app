import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';

/// Placeholder until KAN-25 lays it out. Language and theme stay here; they have no other home.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final i18n = I18nScope.of(context);
    final mode = ref.watch(themeModeProvider);
    return PlaceholderPage(
      title: context.t('mobile:account.title'),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(session?.userName ?? '', style: Theme.of(context).textTheme.titleSmall),
          Text(session?.userEmail ?? '', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('settings:preferencesPage.language')),
            trailing: DropdownButton<String>(
              key: const ValueKey('language'),
              value: ref.watch(languageChoiceProvider),
              onChanged: (value) => ref.read(languageChoiceProvider.notifier).select(value),
              items: [
                DropdownMenuItem(
                  value: systemLanguage,
                  child: Text(context.t('app:language.system')),
                ),
                for (final entry in supportedLocales.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('settings:preferencesPage.theme')),
            trailing: DropdownButton<ThemeMode>(
              key: const ValueKey('theme'),
              value: mode,
              onChanged: (value) => ref.read(themeModeProvider.notifier).select(value!),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(context.t('settings:preferencesPage.themeSystem')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(context.t('settings:preferencesPage.themeLight')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(context.t('settings:preferencesPage.themeDark')),
                ),
              ],
            ),
          ),
          Text(i18n.locale, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: () async {
                final confirmed = await showConfirm(
                  context,
                  title: context.t('mobile:account.signOut.title'),
                  message: context.t('mobile:account.signOut.message'),
                  confirmLabel: context.t('mobile:account.signOut.button'),
                  destructive: true,
                );
                if (confirmed) await ref.read(sessionProvider.notifier).signOut();
              },
              child: Text(context.t('mobile:account.signOut.button')),
            ),
          ),
        ],
      ),
    );
  }
}
