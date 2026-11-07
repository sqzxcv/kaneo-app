#!/usr/bin/env python3
"""Install a DMG into an empty directory and require the packaged Flutter window to start."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dmg', type=Path)
    args = parser.parse_args()
    # The public app ID needs a fresh user/container; local device work uses each line's test ID.
    if os.environ.get('CI') != 'true':
        parser.error('Run this clean-install check on the fresh macOS CI runner.')
    evidence = ROOT / 'build/installers'
    with tempfile.TemporaryDirectory(prefix='kaneo-install-') as temp:
        temp = Path(temp)
        mount = temp / 'volume'
        mount.mkdir()
        subprocess.run(['hdiutil', 'attach', str(args.dmg.resolve()), '-readonly', '-nobrowse',
                        '-mountpoint', str(mount)], check=True)
        try:
            installed = temp / 'Applications/Kaneo.app'
            subprocess.run(['ditto', str(mount / 'Kaneo.app'), str(installed)], check=True)
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(installed)], check=True)
        info = plistlib.loads((installed / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'app.kaneo.kaneoApp'
        probe = temp / 'window-probe'
        subprocess.run(['xcrun', 'swiftc', str(ROOT / '.github/scripts/macos_window_probe.swift'),
                        '-o', str(probe)], check=True)
        with (evidence / 'macos-startup.log').open('w') as log:
            process = subprocess.Popen([str(installed / 'Contents/MacOS' /
                                           info['CFBundleExecutable'])], stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                deadline = time.monotonic() + 45
                result = None
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError(f'Installed app exited with {process.returncode}')
                    checked = subprocess.run([str(probe), str(process.pid)], capture_output=True,
                                             text=True, check=False)
                    if checked.returncode == 0:
                        result = json.loads(checked.stdout)
                        break
                    time.sleep(1)
                if result is None:
                    raise RuntimeError('The installed Flutter app never produced its minimum window')
                result.update(bundleId=info['CFBundleIdentifier'], installedFrom=args.dmg.name,
                              check='Fresh directory install, launch and Dart window initialization')
                (evidence / 'macos-startup.json').write_text(json.dumps(result, indent=2) + '\n')
                capture = subprocess.run(['screencapture', '-x', '-l', str(result['windowId']),
                                          str(evidence / 'macos-startup.png')], check=False)
                print('Installed macOS app launched and configured its desktop window.')
                if capture.returncode:
                    print('Screenshot unavailable on this CI session; native window check passed.')
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == '__main__':
    main()
