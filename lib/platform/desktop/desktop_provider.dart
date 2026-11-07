import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/settings.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/ui/toast.dart';
import '../../features/task/open_task.dart';
import 'desktop_host.dart';
import 'desktop_runtime.dart';

/// Tied to the router's lifetime, so desktop checks stop when the app closes.
final desktopRuntimeProvider = Provider.autoDispose.family<DesktopRuntime?, GoRouter>((
  ref,
  router,
) {
  if (!ref.watch(isDesktopProvider)) return null;
  final i18n = ref.watch(i18nProvider);
  final runtime = DesktopRuntime(
    host: ref.watch(desktopHostProvider),
    load: () => ref.read(kaneoApiProvider).notifications(),
    open: (taskId) {
      if (taskId == null) {
        router.go(AppRoutes.inbox);
        return;
      }
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (context != null && context.mounted) openTask(context, taskId);
    },
    hasPreference: () => ref.read(prefsProvider).containsKey(notificationChecksEnabledKey),
    rememberPermission: (allowed) =>
        ref.read(notificationChecksEnabledProvider.notifier).setEnabled(allowed),
    actionLabel: i18n.t('app:desktop.openNotification'),
    fallbackBody: i18n.t('app:desktop.newActivity'),
    summary: (count) => i18n.t('mobile:background.summary', {'count': count}),
    onUnavailable: () => showGlobalToast(i18n.t('app:desktop.unavailable'), kind: ToastKind.error),
  );
  ref.listen(
    sessionProvider,
    (_, session) => unawaited(runtime.setSession(session)),
    fireImmediately: true,
  );
  ref.listen(
    notificationChecksEnabledProvider,
    (_, enabled) => unawaited(runtime.setEnabled(enabled)),
    fireImmediately: true,
  );
  ref.onDispose(runtime.dispose);
  unawaited(runtime.start());
  return runtime;
});
