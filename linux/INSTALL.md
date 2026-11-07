# Kaneo for Linux

Download `linux-installer-<commit>` from a successful CI run and verify the supplied SHA-256 file.
The DEB targets the Ubuntu version used by CI (currently Ubuntu 24.04) and its stated CPU
architecture. Its exact minimum runtime library versions are recorded in the package dependencies.
It is not a universal package for every Linux distribution.

```sh
sudo apt install ./kaneo-*-linux-amd64.deb
kaneo
sudo apt remove kaneo
```

The installer puts the application and its Flutter libraries under `/usr/lib/kaneo`, adds the
`kaneo` command and a desktop menu entry, and lets apt install the required system libraries.
A running Secret Service provider (such as GNOME Keyring) is needed for secure saved sessions;
a desktop notification service is needed for system notifications. CI installs the DEB on its
clean runner and checks application startup under Xvfb/DBus. Actual desktop installation,
notification clicks, secure storage and Chinese IME remain for administrator acceptance.
Uninstalling the package leaves preferences and saved credentials; sign out first to clear login.

To reproduce, build `flutter build linux --release`, then run
`python3 .github/scripts/package_desktop.py linux` with `dpkg-dev` installed. The packager includes
the whole Flutter bundle and derives dependencies from every native shared library. Package,
checksum and version/build metadata are uploaded together and retained in CI for three days.
