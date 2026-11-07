import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

const notificationChecksEnabledKey = 'kaneo.notifications.enabled';

/// Shared by the desktop runtime and mobile background checks. Native permission is separate.
final notificationChecksEnabledProvider = NotifierProvider<NotificationChecksEnabled, bool>(
  NotificationChecksEnabled.new,
);

class NotificationChecksEnabled extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).getBool(notificationChecksEnabledKey) ?? false;

  Future<void> setEnabled(bool enabled) async {
    await ref.read(prefsProvider).setBool(notificationChecksEnabledKey, enabled);
    state = enabled;
  }
}
