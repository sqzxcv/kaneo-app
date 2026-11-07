#!/usr/bin/env python3
"""Build signed mobile releases using administrator-provided files outside the repository."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BUNDLE_ID = 'app.kaneo.kaneoApp'


def private_file(path):
    path = Path(path).expanduser().resolve()
    if ROOT == path or ROOT in path.parents:
        raise ValueError('Signing files must be stored outside this public repository.')
    if not path.is_file():
        raise ValueError(f'Missing administrator-provided file: {path}')
    return path


def android_plan(config):
    path = private_file(config / 'android-signing.json')
    try:
        values = json.loads(path.read_text())
    except (ValueError, OSError):
        raise ValueError('android-signing.json must contain a JSON object.') from None
    fields = ['storeFile', 'storePassword', 'keyAlias', 'keyPassword']
    if not isinstance(values, dict) or any(not isinstance(values.get(k), str) or not values[k] for k in fields):
        raise ValueError('android-signing.json needs storeFile, storePassword, keyAlias and keyPassword.')
    key_path = Path(values['storeFile']).expanduser()
    if not key_path.is_absolute():
        key_path = path.parent / key_path
    keystore = private_file(key_path)
    return {
        'KANEO_ANDROID_KEYSTORE': str(keystore),
        'KANEO_ANDROID_STORE_PASSWORD': values['storePassword'],
        'KANEO_ANDROID_KEY_ALIAS': values['keyAlias'],
        'KANEO_ANDROID_KEY_PASSWORD': values['keyPassword'],
    }, None


def ios_plan(config, run=subprocess.run):
    export = private_file(config / 'ios-export-options.plist')
    profile = private_file(config / 'ios-app-store.mobileprovision')
    try:
        options = plistlib.loads(export.read_bytes())
    except (ValueError, plistlib.InvalidFileException):
        raise ValueError('ios-export-options.plist is not a valid property list.') from None
    if not isinstance(options, dict):
        raise ValueError('Export options must be a property-list dictionary.')
    if options.get('method') != 'app-store-connect' or options.get('signingStyle') != 'manual':
        raise ValueError('Export options must use method app-store-connect and signingStyle manual.')
    if options.get('destination', 'export') != 'export':
        raise ValueError('Use destination export; uploading to TestFlight is a separate step.')
    decoded = run(['security', 'cms', '-D', '-i', str(profile)], capture_output=True)
    if decoded.returncode:
        raise ValueError('Could not decode the administrator-provided provisioning profile.')
    try:
        data = plistlib.loads(decoded.stdout)
    except (ValueError, plistlib.InvalidFileException):
        raise ValueError('Invalid provisioning profile data.') from None
    team = options.get('teamID')
    entitlements = data.get('Entitlements', {})
    if not isinstance(team, str) or not team or team not in data.get('TeamIdentifier', []):
        raise ValueError('Export teamID must match the provisioning profile.')
    if entitlements.get('application-identifier') != f'{team}.{BUNDLE_ID}':
        raise ValueError(f'An App Store profile for {BUNDLE_ID} is required.')
    if ('iOS' not in data.get('Platform', []) or data.get('ProvisionedDevices') or
            data.get('ProvisionsAllDevices') or entitlements.get('get-task-allow')):
        raise ValueError('Use an iOS App Store distribution profile, not development or ad hoc.')
    expires = data.get('ExpirationDate')
    if not isinstance(expires, datetime.datetime) or expires.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('The provisioning profile is expired or has no expiry date.')
    uuid = data.get('UUID', '')
    if not isinstance(uuid, str) or not re.fullmatch(r'[0-9A-Fa-f-]{36}', uuid):
        raise ValueError('The provisioning profile has no valid UUID.')
    mappings = options.get('provisioningProfiles', {})
    if not isinstance(mappings, dict) or not mappings.get(BUNDLE_ID) or mappings.get(BUNDLE_ID) not in [uuid, data.get('Name')]:
        raise ValueError('Export provisioningProfiles must map the app bundle ID to this profile.')
    identities = run(['security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True)
    certificate_hashes = {hashlib.sha1(cert).hexdigest().upper() for cert in data.get('DeveloperCertificates', [])}
    identity = None
    for digest, name in re.findall(rb'([0-9A-F]{40})\s+"([^"]+)"', identities.stdout):
        if digest.decode() in certificate_hashes and name.startswith((b'Apple Distribution:', b'iPhone Distribution:')):
            identity = digest.decode()
            break
    if identity is None:
        raise ValueError('Install the matching Apple Distribution certificate and its private key in Keychain.')
    return {
        'FLUTTER_XCODE_KANEO_IOS_TEAM_ID': team,
        'FLUTTER_XCODE_KANEO_IOS_SIGNING_STYLE': 'Manual',
        'FLUTTER_XCODE_KANEO_IOS_SIGNING_IDENTITY': identity,
        'FLUTTER_XCODE_KANEO_IOS_PROFILE': uuid,
    }, (profile, export, uuid)


def build_command(platform, number, profile):
    command = [str(ROOT / 'tool/with_device.sh'), 'flutter', 'build',
               'ipa' if platform == 'ios' else 'apk', '--release', f'--build-number={number}']
    if profile:
        command.append(f'--export-options-plist={profile[1]}')
    return command


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['ios', 'android'])
    parser.add_argument('--config-dir', type=Path, default=Path.home() / '.config/kaneo-app')
    parser.add_argument('--build-number', type=int, required=True, help='A number greater than the previously distributed build.')
    parser.add_argument('--check', action='store_true', help='Validate signing inputs without building.')
    args = parser.parse_args(argv)
    try:
        if args.build_number < 1:
            raise ValueError('The build number must be positive.')
        if args.platform == 'ios' and sys.platform != 'darwin':
            raise ValueError('TestFlight builds require macOS and Xcode.')
        settings, profile = (ios_plan if args.platform == 'ios' else android_plan)(args.config_dir)
        if args.check:
            print('Signing inputs are ready; no build or upload was performed.')
            return 0
        if profile:
            destination = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles' / f'{profile[2]}.mobileprovision'
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists() and destination.read_bytes() != profile[0].read_bytes():
                raise ValueError('A different profile with this UUID is already installed.')
            shutil.copyfile(profile[0], destination)
            destination.chmod(0o600)
        environment = os.environ.copy()
        environment.update(settings)
        # Passwords are passed only through the environment, never command arguments or logs.
        artifact_dir = ROOT / ('build/ios/ipa' if profile else 'build/app/outputs/flutter-apk')
        pattern = '*.ipa' if profile else '*release.apk'
        previous = {path: path.stat().st_mtime_ns for path in artifact_dir.glob(pattern)}
        subprocess.run(build_command(args.platform, args.build_number, profile), cwd=ROOT, env=environment, check=True)
        artifacts = [path for path in artifact_dir.glob(pattern)
                     if previous.get(path) != path.stat().st_mtime_ns]
        if not artifacts:
            raise ValueError('The build did not produce a release package.')
        print('Release package created. Upload/install and upgrade verification remain separate steps.')
        return 0
    except (ValueError, OSError) as error:
        print(f'Release not built: {error}', file=sys.stderr)
        return 2
    except subprocess.CalledProcessError:
        print('Release build failed. No upload was performed.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
