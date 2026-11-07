# Kaneo for Windows

Download `windows-installer-<commit>` from a successful CI run, verify the supplied SHA-256 file,
and run the `windows-x64-setup.exe` installer. It installs for the current user under
`%LOCALAPPDATA%\Programs\Kaneo`, creates a Start menu shortcut, and includes the Visual C++
application-local runtime DLLs. It does not need Flutter, Visual Studio, or a separate runtime
installation. Use Windows Settings → Apps to uninstall. User preferences and saved credentials
are retained; sign out in the app before uninstalling when you want to remove the saved login.

The installer targets x64 Windows 10 version 1809 or later. It is an unsigned internal test build;
SmartScreen/publisher approval and actual installation/interaction on the administrator's Windows
system remain manual acceptance items. CI silently installs into an empty directory, launches the
installed app, checks its native window, and uninstalls it.

The shortcut uses Kaneo's notification AppUserModelID and toast activator. This is a traditional
installer, not an MSIX package: the current notifications plugin cannot remove notification history
for unpackaged applications. The app rejects clicks from a previous signed-in session, but Windows
may retain those older banners in Notification Center. Native notification behavior and secure
storage must be checked by the administrator; supporting complete notification-history removal
requires package identity or a Windows native implementation.

Build with `flutter build windows --release`, copy the redistributable runtime with
`.github/scripts/copy_windows_runtime.ps1`, then run
`python .github/scripts/package_desktop.py windows` with Inno Setup 6 installed. No private config,
certificate or key is required for this internal installer. Installer checksums and version/build
metadata are shipped beside it. CI retains these artifacts for three days.

References: [Flutter Windows packaging](https://docs.flutter.dev/deployment/windows),
[Inno Setup shortcut metadata](https://jrsoftware.org/ishelp/topic_iconssection.htm).
