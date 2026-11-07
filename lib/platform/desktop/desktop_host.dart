import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

const minimumDesktopWindowSize = Size(960, 700);

Size usableDesktopWindowSize(Size current) => Size(
  max(current.width, minimumDesktopWindowSize.width),
  max(current.height, minimumDesktopWindowSize.height),
);

final isDesktopProvider = Provider<bool>(
  (_) =>
      !kIsWeb &&
      [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ].contains(defaultTargetPlatform),
);

final desktopHostProvider = Provider<DesktopHost>((_) => NativeDesktopHost());

/// The OS boundary. Tests replace this while exercising the actual account and routing logic.
abstract class DesktopHost {
  Future<void> configureWindow();
  Future<void> initializeNotifications(void Function(String? payload) onTap, String actionLabel);
  Future<bool> requestNotificationPermission();
  Future<void> showNotice({
    required int id,
    required String title,
    String? body,
    required String payload,
  });
  Future<void> clearNotices();
  Future<void> foregroundWindow();
}

class NativeDesktopHost implements DesktopHost {
  final _notifications = FlutterLocalNotificationsPlugin();

  @override
  Future<void> configureWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(minimumDesktopWindowSize);
    final current = await windowManager.getSize();
    final size = usableDesktopWindowSize(current);
    if (current != size) await windowManager.setSize(size);
  }

  @override
  Future<void> initializeNotifications(void Function(String?) onTap, String actionLabel) async {
    await _notifications.initialize(
      settings: InitializationSettings(
        macOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: actionLabel),
        windows: const WindowsInitializationSettings(
          appName: 'Kaneo',
          appUserModelId: 'Kaneo.App',
          guid: '90e2e9bd-9f59-4fd7-8bbb-fb71af3f631e',
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
  }

  @override
  Future<bool> requestNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return true;
    return await _notifications
            .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  @override
  Future<void> showNotice({
    required int id,
    required String title,
    String? body,
    required String payload,
  }) => _notifications.show(
    id: id,
    title: title,
    body: body,
    payload: payload,
    notificationDetails: const NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
      ),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    ),
  );

  @override
  Future<void> clearNotices() => _notifications.cancelAll();

  @override
  Future<void> foregroundWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }
}
