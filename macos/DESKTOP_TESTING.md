# Desktop runtime checks

The minimum window is 960 × 700 logical pixels. Even after native title-bar insets, its shorter
side stays above the 600-pixel wide-layout breakpoint. Desktop sign-in uses the same system secure
storage as the other platforms.

While the process is running, desktop notifications check every 30 seconds. The first response
only establishes a baseline. Signing out, changing accounts or turning notifications off cancels
pending checks and visible notifications; stale responses and clicks are ignored. Closing the
last window exits the macOS process. There is no tray process or notification service after exit.

The shared switch is `notificationChecksEnabledProvider` (`kaneo.notifications.enabled` in
preferences). The first signed-in desktop launch requests native permission; subsequent launches
respect that saved choice. If permission was denied, enable it in system settings and toggle the
app switch off and on to check again. Permission and the app switch must both be enabled.

## Automated checks

```sh
flutter test test/platform
flutter test test/platform/local_desktop_contract_test.dart \
  --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
```

The local contract test creates its own D- workspace/project and temporary account, delivers a
real assignment notification through the runtime, checks the task ID, and cleans up its data.
It uses password sessions to avoid the API key request limit.

## Login, realtime and account isolation

`integration_test/auth_flow_test.dart` runs against the local server on macOS and iPad. It disables
developer auto-login and uses the real login page, HTTP client and authenticated WebSockets. It
checks API key board updates and incoming inbox notifications without a manual refresh, opens the
notified task, then signs out through the account page and signs in with a second local account.
The former account's private workspace and notifications must be absent, and its disk cache must
be cleared. On macOS it also checks the native minimum window size. It creates and removes only
its own D- workspaces, projects and temporary account.

```sh
# Use the fixed DTest bundle and the same local signing identity for each macOS run (see below).
FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=app.kaneo.kaneoApp.DTest \
  tool/with_device.sh flutter test integration_test/auth_flow_test.dart -d macos \
  --dart-define-from-file=$HOME/.config/kaneo-app/dev.env

tool/with_device.sh --boot "iPad Pro 13-inch (M5)" \
  flutter test integration_test/auth_flow_test.dart -d "iPad Pro 13-inch (M5)" \
  --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
```

The test prints `D_RESULT` timings and `D_SCREENSHOT` paths. PNGs are saved under the test app's
Documents/D-KAN-51 directory, outside the repository. Login screenshots are taken before entering
credentials. Preserve the evidence before uninstalling or replacing the test app.

This flow uses memory session storage to keep account-switch testing separate from system storage.
`integration_test/auth_test.dart` verifies actual secure storage with private `AUTH_TEST_*` defines
and no `KANEO_DEV_*` defines. Use a new `AUTH_TEST_STORAGE_KEY`, run `AUTH_TEST_PHASE=save`, then run
`AUTH_TEST_PHASE=restore` in a separate process with the same bundle ID and signing identity. The
restore pass checks the saved identity against the server and clears the test entry on logout.

An inbox update is not evidence of an OS notification banner. The flow keeps native notifications
off and restores the prior local preference afterwards; native delivery and banner clicking are
covered separately below.

## Native notifications

For macOS native testing, use the D line's fixed test bundle ID and its existing local signing
identity as specified in AGENTS.md. Keep that identity consistent between runs. Do not change the
formal bundle ID or put signing identities or development credentials in the repository.

```sh
FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=app.kaneo.kaneoApp.DTest \
  tool/with_device.sh flutter test integration_test/desktop_test.dart -d macos \
  --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
```

This has separate tests for native window/layout and system notification delivery. The notification
test requires an unlocked macOS GUI session and notification permission for the DTest app
(displayed as kaneo_app in System Settings → Notifications). Without permission, it explicitly reports the notification case as skipped/unverified for manual
acceptance. Once permission is granted, it fails if no native notification is delivered. It uses in-memory sign-in, preserves the previous switch
setting, and cleans up its D- test data.

## Manual acceptance

- On each desktop OS, type Chinese with the system IME, choose candidates, and resize the window
  while composing. Widget tests also check that composing text survives a layout change.
- With the app running, assign a task from another account; click the real system notification
  and confirm the corresponding task opens. The native macOS test checks delivery and the
  registered click handler, while the actual OS banner click remains a manual check.
- For Windows and Linux, also confirm minimum window size and secure-session persistence on the
  installed build. Their compilation is checked in CI; native interaction requires those systems.
