import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../notifications/notification_runtime.dart';

/// A dropdown's width. Fixed, so that a long option never pushes out the row's title on the
/// narrowest page, which is what a wide window leaves next to the sidebar.
const double _controlWidth = 160;

DropdownMenuItem<T> _option<T>(T value, String label) => DropdownMenuItem(
  value: value,
  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
);

/// The account, language, theme, notifications and signing out. Everything else about the account
/// is in KAN-16.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('mobile:account.title')),
        // The sidebar already leads everywhere from here.
        automaticallyImplyLeading: !context.isWide,
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(session?.userName ?? '', style: Theme.of(context).textTheme.titleSmall),
            Text(session?.userEmail ?? '', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.t('settings:preferencesPage.language')),
              trailing: SizedBox(
                width: _controlWidth,
                child: DropdownButton<String>(
                  key: const ValueKey('language'),
                  isExpanded: true,
                  value: ref.watch(languageChoiceProvider),
                  onChanged: (value) => ref.read(languageChoiceProvider.notifier).select(value),
                  items: [
                    _option(systemLanguage, context.t('app:language.system')),
                    for (final entry in supportedLocales.entries) _option(entry.key, entry.value),
                  ],
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.t('settings:preferencesPage.theme')),
              trailing: SizedBox(
                width: _controlWidth,
                child: DropdownButton<ThemeMode>(
                  key: const ValueKey('theme'),
                  isExpanded: true,
                  value: mode,
                  onChanged: (value) => ref.read(themeModeProvider.notifier).select(value!),
                  items: [
                    _option(ThemeMode.system, context.t('settings:preferencesPage.themeSystem')),
                    _option(ThemeMode.light, context.t('settings:preferencesPage.themeLight')),
                    _option(ThemeMode.dark, context.t('settings:preferencesPage.themeDark')),
                  ],
                ),
              ),
            ),
            const _NotificationSwitch(),
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
      ),
    );
  }
}

/// Turns notifications on and off. The desktop apps check while they run instead of about every 15
/// minutes, so they leave out the part that says so.
class _NotificationSwitch extends ConsumerWidget {
  const _NotificationSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = ref.watch(isDesktopProvider);
    return SwitchListTile(
      key: const ValueKey('notification-checks'),
      contentPadding: EdgeInsets.zero,
      title: Text(
        context.t(
          desktop ? 'mobile:account.notifications.title' : 'mobile:account.notifications.phone',
        ),
      ),
      subtitle: desktop ? null : Text(context.t('mobile:account.notifications.phoneHint')),
      value: ref.watch(notificationChecksEnabledProvider),
      onChanged: (enabled) => _change(context, ref, enabled),
    );
  }

  Future<void> _change(BuildContext context, WidgetRef ref, bool enabled) async {
    if (enabled && !await _allowed(ref)) {
      if (context.mounted) {
        showToast(
          context,
          context.t('mobile:account.notifications.permissionDenied'),
          kind: ToastKind.error,
        );
      }
      return;
    }
    await ref.read(notificationChecksEnabledProvider.notifier).setEnabled(enabled);
  }

  Future<bool> _allowed(WidgetRef ref) async {
    try {
      return await ref.read(notificationPermissionProvider)();
    } on Exception {
      return false;
    }
  }
}
