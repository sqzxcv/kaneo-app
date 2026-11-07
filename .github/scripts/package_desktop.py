#!/usr/bin/env python3
"""Package an existing release build; never sign, upload, or read private configuration."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BUNDLE_ID = 'app.kaneo.kaneoApp'


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def version_info(pubspec, build_number=None):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', pubspec, re.M)
    if not match:
        raise ValueError('pubspec.yaml must have a numeric version and build number')
    number = build_number or match[2]
    if not re.fullmatch(r'[1-9][0-9]*', number):
        raise ValueError('Build number must be a positive integer')
    return match[1], number


def require(path):
    if not path.exists():
        raise ValueError(f'Missing release input: {path.name}')
    return path


def validate_bundle(source, platform):
    for path in source.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(source.resolve()):
            raise ValueError(f'Bundle symlink points outside the application: {path.name}')
    if platform == 'macos':
        info = plistlib.loads(require(source / 'Contents/Info.plist').read_bytes())
        if info.get('CFBundleIdentifier') != BUNDLE_ID:
            raise ValueError('Distribution requires the formal bundle ID, not a device-test ID')
        require(source / 'Contents/MacOS' / info['CFBundleExecutable'])
        require(source / 'Contents/Frameworks/FlutterMacOS.framework')
        require(source / 'Contents/Frameworks/App.framework')
        return info
    require(source / 'data/icudtl.dat')
    require(source / 'data/flutter_assets/AssetManifest.bin')
    if platform == 'windows':
        for name in ['kaneo_app.exe', 'flutter_windows.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll']:
            require(source / name)
        require(source / 'data/app.so')
    elif platform == 'linux':
        for name in ['kaneo_app', 'lib/libapp.so', 'lib/libflutter_linux_gtk.so']:
            require(source / name)
    else:
        raise ValueError(f'Unknown platform: {platform}')
    return None


def manifest(artifact, platform, architecture, version, build):
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    data = {
        'file': artifact.name, 'platform': platform, 'architecture': architecture,
        'version': version, 'build': build, 'sha256': digest,
        'commit': os.environ.get('GITHUB_SHA') or subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'distributionSigning': 'CI does not supply distribution certificates or notarization',
    }
    artifact.with_suffix(artifact.suffix + '.json').write_text(json.dumps(data, indent=2) + '\n')
    artifact.with_suffix(artifact.suffix + '.sha256').write_text(f'{digest}  {artifact.name}\n')
    print(f'Packaged {artifact.name} ({artifact.stat().st_size} bytes)')


def package_macos(source, output, version, build):
    info = validate_bundle(source, 'macos')
    if (info['CFBundleShortVersionString'], info['CFBundleVersion']) != (version, build):
        raise ValueError('Built macOS app version differs from the package version')
    run('codesign', '--verify', '--deep', '--strict', source)
    binary = source / 'Contents/MacOS' / info['CFBundleExecutable']
    arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    architecture = 'universal' if set(arches) == {'arm64', 'x86_64'} else '-'.join(arches)
    artifact = output / f'kaneo-{version}+{build}-macos-{architecture}.dmg'
    with tempfile.TemporaryDirectory(prefix='kaneo-dmg-') as temp:
        stage = Path(temp) / 'image'
        stage.mkdir()
        run('ditto', source, stage / 'Kaneo.app')
        (stage / 'Applications').symlink_to('/Applications')
        shutil.copy2(ROOT / 'macos/INSTALL.md', stage / 'INSTALL.md')
        run('hdiutil', 'create', '-volname', 'Kaneo', '-srcfolder', stage,
            '-format', 'UDZO', '-ov', artifact)
    manifest(artifact, 'macos', architecture, version, build)
    return artifact


def package_linux(source, output, version, build):
    validate_bundle(source, 'linux')
    architecture = subprocess.check_output(['dpkg', '--print-architecture'], text=True).strip()
    artifact = output / f'kaneo-{version}+{build}-linux-{architecture}.deb'
    with tempfile.TemporaryDirectory(prefix='kaneo-deb-') as temp:
        stage = Path(temp) / 'root'
        installed = stage / 'usr/lib/kaneo'
        shutil.copytree(source, installed, symlinks=True)
        (stage / 'usr/bin').mkdir(parents=True)
        (stage / 'usr/bin/kaneo').symlink_to('../lib/kaneo/kaneo_app')
        applications = stage / 'usr/share/applications'
        applications.mkdir(parents=True)
        shutil.copy2(ROOT / 'linux/packaging/kaneo.desktop', applications)
        docs = stage / 'usr/share/doc/kaneo'
        docs.mkdir(parents=True)
        shutil.copy2(ROOT / 'linux/INSTALL.md', docs / 'README.md')
        # Ask Debian to derive exact runtime dependency versions, including every native plugin.
        # Bundled Flutter libraries have no package metadata and are deliberately ignored.
        debian = Path(temp) / 'debian'
        debian.mkdir()
        (debian / 'control').write_text(
            'Source: kaneo\nSection: utils\nPriority: optional\nMaintainer: Kaneo App contributors <noreply@localhost>\n\n'
            'Package: kaneo\nArchitecture: any\nDescription: Flutter client for Kaneo\n')
        binaries = [installed / 'kaneo_app', *sorted((installed / 'lib').glob('*.so'))]
        dependencies = subprocess.check_output(
            ['dpkg-shlibdeps', '--ignore-missing-info', '-O', f'-l{installed / "lib"}',
             *[f'-e{path}' for path in binaries]], cwd=temp, text=True)
        dependency_line = next(line.removeprefix('shlibs:Depends=') for line in
                               dependencies.splitlines() if line.startswith('shlibs:Depends='))
        control = stage / 'DEBIAN'
        control.mkdir()
        (control / 'control').write_text(
            f'Package: kaneo\nVersion: {version}+{build}\nArchitecture: {architecture}\n'
            'Section: utils\nPriority: optional\nMaintainer: Kaneo App contributors <noreply@localhost>\n'
            f'Depends: {dependency_line}\n'
            'Description: Flutter client for self-hosted Kaneo\n'
            ' Projects, boards, tasks and notifications in a native desktop application.\n')
        for directory in [stage, control, *[p for p in stage.rglob('*') if p.is_dir()]]:
            directory.chmod(0o755)
        run('dpkg-deb', '--root-owner-group', '--build', stage, artifact)
        run('dpkg-deb', '--info', artifact)
    manifest(artifact, 'linux', architecture, version, build)
    return artifact


def package_windows(source, output, version, build):
    validate_bundle(source, 'windows')
    compiler = shutil.which('iscc') or str(Path(os.environ.get('ProgramFiles(x86)',
                                                              'C:/Program Files (x86)')) /
                                         'Inno Setup 6/ISCC.exe')
    name = f'kaneo-{version}+{build}-windows-x64-setup'
    run(compiler, '/Qp', f'/DBundleDir={source}', f'/DOutputDir={output}',
        f'/DOutputName={name}', f'/DAppVersion={version}', f'/DBuildNumber={build}',
        ROOT / 'windows/packaging/kaneo.iss')
    artifact = require(output / (name + '.exe'))
    manifest(artifact, 'windows', 'x64', version, build)
    return artifact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['macos', 'windows', 'linux'])
    parser.add_argument('--source', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/installers')
    parser.add_argument('--build-number')
    args = parser.parse_args()
    defaults = {
        'macos': ROOT / 'build/macos/Build/Products/Release/kaneo_app.app',
        'windows': ROOT / 'build/windows/x64/runner/Release',
        'linux': ROOT / 'build/linux/x64/release/bundle',
    }
    source = (args.source or defaults[args.platform]).resolve()
    output = args.output.resolve()
    if output == source or source in output.parents:
        raise ValueError('Output must be outside the input bundle')
    output.mkdir(parents=True, exist_ok=True)
    version, build = version_info((ROOT / 'pubspec.yaml').read_text(), args.build_number)
    globals()[f'package_{args.platform}'](source, output, version, build)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Packaging failed: {error}', file=sys.stderr)
        sys.exit(1)
