import 'package:flutter/widgets.dart';
import 'package:kaneo_app/core/core.dart';

class FakeDesktopHost implements DesktopHost {
  Size size = const Size(800, 600);
  bool allowed = true;
  int permissionRequests = 0;
  int foregrounds = 0;
  int clears = 0;
  final notices = <({int id, String title, String? body, String payload})>[];
  void Function(String?)? onTap;
  @override
  Future<void> configureWindow() async => size = usableDesktopWindowSize(size);
  @override
  Future<void> initializeNotifications(void Function(String?) onTap, String actionLabel) async =>
      this.onTap = onTap;
  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    return allowed;
  }

  @override
  Future<void> showNotice({
    required int id,
    required String title,
    String? body,
    required String payload,
  }) async => notices.add((id: id, title: title, body: body, payload: payload));
  @override
  Future<void> clearNotices() async {
    clears++;
    notices.clear();
  }

  @override
  Future<void> foregroundWindow() async => foregrounds++;
}
