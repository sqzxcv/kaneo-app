# Kaneo for macOS

Download the `macos-installer-<commit>` artifact from a successful GitHub Actions CI run. It
contains the DMG, its SHA-256 file, version/architecture metadata, and installation/startup evidence.
Open the DMG and drag Kaneo.app into Applications. Open that copy to start. Quit the app before
replacing it with a newer version. Remove the application to uninstall; stored login data and
preferences are not erased by deleting the application.

The filename says whether the build is universal, arm64 (Apple Silicon), or x86_64 (Intel).
The minimum macOS version is recorded in the application's `LSMinimumSystemVersion`.

These are internal test packages. CI does not hold an Apple Developer ID certificate or notarize
them. macOS may require the administrator to approve the downloaded app in Privacy & Security.
CI checks bundle signature integrity, installs the DMG into a fresh directory on its macOS runner,
launches the installed executable, and checks that Flutter has configured the desktop window.
This does not verify Gatekeeper approval for an internet download, notification banners, IME, or
other manual acceptance items. See DESKTOP_TESTING.md for those checks. A future trusted public
release needs an administrator-provided Developer ID identity and notarization credentials.

A stable signing identity is also important for upgrades: replacing a sandboxed app with an
unrelated signature can make macOS reject access to its existing container/keychain. Do not use
CI test packages to replace a signed daily-use installation. Never delete an existing application
container or keychain entry merely to make a test build launch.

To reproduce packaging on a Mac, use the device queue and no private development defines:

```sh
tool/with_device.sh flutter build macos --release
python3 .github/scripts/package_desktop.py macos
```

The packager rejects device-test bundle IDs and mismatched build versions. It leaves the input
bundle and signature unchanged. CI artifacts are retained for three days; archive a release's
installer, manifest and checksum together when distributing an internal test build.

References: [Flutter macOS release guide](https://docs.flutter.dev/deployment/macos).
