#!/usr/bin/env python3
"""Draws every platform's app icon from the Kaneo mobile app's artwork.

Run from the repository root, after `git submodule update --init --depth 1 kaneo`:

    python3 tool/generate_app_icons.py [artwork directory]

The artwork defaults to kaneo/apps/mobile/assets/images. Needs Pillow.
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ART = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'kaneo/apps/mobile/assets/images'
BACKGROUND = '#141414'
MASTER = 1024
ANDROID_DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
LINUX_SIZES = [32, 48, 64, 128, 256, 512]


def artwork(name):
    return Image.open(ART / name)


def resized(image, size):
    return image.resize((size, size), Image.Resampling.LANCZOS)


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(path.relative_to(ROOT))


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print(path.relative_to(ROOT))


def rounded(icon, body, radius, shadow=False):
    """The square [icon] shrunk to [body] pixels with rounded corners, centred on a clear master."""
    scale = 4
    mask = Image.new('L', (MASTER * scale,) * 2, 0)
    inset = (MASTER - body) / 2 * scale
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, MASTER * scale - inset - 1, MASTER * scale - inset - 1),
        radius=radius * scale,
        fill=255,
    )
    mask = mask.resize((MASTER, MASTER), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (MASTER, MASTER), (0, 0, 0, 0))
    if shadow:
        # As Apple's macOS template draws it: straight down, soft, faint.
        drop = Image.new('RGBA', (MASTER, MASTER), (0, 0, 0, 0))
        drop.paste((0, 0, 0, 77), (0, 12), mask)
        canvas = Image.alpha_composite(canvas, drop.filter(ImageFilter.GaussianBlur(14)))
    face = Image.new('RGBA', (MASTER, MASTER), (0, 0, 0, 0))
    offset = (MASTER - body) // 2
    face.paste(resized(icon, body).convert('RGBA'), (offset, offset))
    face.putalpha(mask)
    return Image.alpha_composite(canvas, face)


def asset_catalog(directory, master, opaque=False):
    contents = json.loads((directory / 'Contents.json').read_text())
    for entry in contents['images']:
        points = float(entry['size'].split('x')[0])
        pixels = round(points * int(entry['scale'].rstrip('x')))
        image = resized(master, pixels)
        # The App Store turns down an iOS icon with an alpha channel.
        save(image.convert('RGB') if opaque else image, directory / entry['filename'])


def main():
    icon = artwork('icon.png').convert('RGB')
    # macOS draws its icons as a rounded square inside the canvas, with a shadow.
    mac = rounded(icon, body=824, radius=185, shadow=True)
    # Windows, Linux and older Android launchers show the shape as it is drawn.
    tile = rounded(icon, body=960, radius=192)

    asset_catalog(ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset', icon, opaque=True)
    asset_catalog(ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset', mac)

    res = ROOT / 'android/app/src/main/res'
    foreground = artwork('android-icon-foreground.png').convert('RGBA')
    monochrome = artwork('android-icon-monochrome.png').convert('RGBA')
    notification = artwork('notification-icon.png').convert('RGBA')
    for density, factor in ANDROID_DENSITIES.items():
        save(resized(tile, round(48 * factor)), res / f'mipmap-{density}/ic_launcher.png')
        save(resized(foreground, round(108 * factor)), res / f'mipmap-{density}/ic_launcher_foreground.png')
        save(resized(monochrome, round(108 * factor)), res / f'mipmap-{density}/ic_launcher_monochrome.png')
        save(resized(notification, round(24 * factor)), res / f'drawable-{density}/ic_notification.png')
    write(res / 'mipmap-anydpi-v26/ic_launcher.xml', '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''')
    write(res / 'values/ic_launcher_background.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{BACKGROUND}</color>
</resources>
''')
    write(res / 'raw/keep.xml', '''<?xml version="1.0" encoding="utf-8"?>
<!-- Only Dart names the notification icon, so resource shrinking would drop it. -->
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_notification" />
''')

    ico = ROOT / 'windows/runner/resources/app_icon.ico'
    tile.save(ico, sizes=[(n, n) for n in [16, 20, 24, 32, 40, 48, 64, 128, 256]])
    print(ico.relative_to(ROOT))

    for size in LINUX_SIZES:
        save(resized(tile, size), ROOT / f'linux/packaging/icons/{size}.png')


if __name__ == '__main__':
    main()
