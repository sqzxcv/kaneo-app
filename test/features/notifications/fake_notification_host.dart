import 'package:kaneo_app/features/notifications/notification_check.dart';

class FakeNotificationHost implements NotificationHost {
  bool allowed = true;

  /// What the OS answers with instead, as `MissingPluginException` or a `PlatformException` would.
  Exception? failure;
  String? launch;
  bool initialized = false;
  bool scheduled = false;
  int permissionRequests = 0;
  int schedules = 0;
  final notices = <({int id, String title, String? body, String payload})>[];
  final channels = <String>{};
  void Function(String?)? onTap;

  @override
  Future<void> initialize(void Function(String? payload)? onTap) async {
    initialized = true;
    // The background task's isolate has its own plugin, and it doesn't replace the app's.
    if (onTap != null) this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    if (failure case final failure?) throw failure;
    return allowed;
  }

  @override
  Future<void> schedule() async {
    schedules++;
    if (failure case final failure?) throw failure;
    scheduled = true;
  }

  @override
  Future<void> unschedule() async => scheduled = false;

  @override
  Future<void> show({
    required int id,
    required String title,
    String? body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async {
    channels.add(channelName);
    notices.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> clear() async => notices.clear();
}
