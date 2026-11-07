#!/usr/bin/env python3
"""Run the installed Debian app inside the CI Xvfb/DBus session."""
import json
from pathlib import Path
import subprocess
import time

output = Path('build/installers')
with (output / 'linux-startup.log').open('w') as log:
    app = subprocess.Popen(['/usr/bin/kaneo'], stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 45
        result = None
        while time.monotonic() < deadline:
            if app.poll() is not None:
                raise RuntimeError(f'Installed Linux app exited with {app.returncode}')
            found = subprocess.run(['xdotool', 'search', '--onlyvisible', '--pid', str(app.pid)],
                                   capture_output=True, text=True, check=False)
            for window in found.stdout.split():
                geometry = subprocess.check_output(['xdotool', 'getwindowgeometry', '--shell',
                                                    window], text=True)
                fields = dict(line.split('=', 1) for line in geometry.splitlines() if '=' in line)
                if int(fields['WIDTH']) >= 960 and int(fields['HEIGHT']) >= 700:
                    result = {'windowId': window, 'width': int(fields['WIDTH']),
                              'height': int(fields['HEIGHT']), 'installed': '/usr/bin/kaneo'}
                    break
            if result:
                break
            time.sleep(1)
        if not result:
            raise RuntimeError('Installed Linux app never produced its minimum Flutter window')
        (output / 'linux-startup.json').write_text(json.dumps(result, indent=2) + '\n')
        print('Installed Debian app launched and configured its desktop window.')
    finally:
        if app.poll() is None:
            app.terminate()
            try:
                app.wait(timeout=10)
            except subprocess.TimeoutExpired:
                app.kill()
                app.wait()
