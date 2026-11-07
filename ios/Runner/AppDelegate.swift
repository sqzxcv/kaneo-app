import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Tapping a local notification reaches the plugin through this.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // The background check for notifications runs on an engine of its own, which needs the plugins.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // iOS only accepts this before launching finishes. Keep the id in step with Info.plist and
    // notificationCheckTask, and the delay with notificationCheckInterval.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "app.kaneo.kaneoApp.notificationCheck",
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
