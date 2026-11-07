import datetime
import hashlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch

import mobile_release as release


class ReleaseInputsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name)

    def test_missing_files_fail_without_starting_a_build(self):
        output = io.StringIO()
        with patch.object(release.subprocess, 'run') as run, redirect_stderr(output):
            self.assertEqual(release.main(['android', '--config-dir', str(self.config), '--build-number', '2']), 2)
        run.assert_not_called()
        self.assertIn('android-signing.json', output.getvalue())

    def test_android_keeps_passwords_out_of_command_arguments(self):
        key = self.config / 'provided-keystore.jks'
        key.write_bytes(b'unit-test placeholder, not a signing key')
        values = {'storeFile': key.name, 'storePassword': 's=\\quoted-secret', 'keyAlias': 'release', 'keyPassword': 'key-secret'}
        (self.config / 'android-signing.json').write_text(json.dumps(values))
        environment, profile = release.android_plan(self.config)
        self.assertEqual(environment['KANEO_ANDROID_KEYSTORE'], str(key.resolve()))
        self.assertEqual(environment['KANEO_ANDROID_STORE_PASSWORD'], values['storePassword'])
        command = release.build_command('android', 42, profile)
        self.assertIn('--build-number=42', command)
        self.assertTrue(command[0].endswith('tool/with_device.sh'))
        self.assertNotIn(values['storePassword'], ' '.join(command))
        self.assertNotIn(values['keyPassword'], ' '.join(command))

    def test_invalid_or_incomplete_android_config_is_rejected(self):
        for content in ['not json', '[]', '{}', '{"storeFile":"missing"}']:
            (self.config / 'android-signing.json').write_text(content)
            with self.assertRaises(ValueError):
                release.android_plan(self.config)

    def test_signing_material_in_public_repository_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            release.private_file(release.ROOT / 'pubspec.yaml')

    def make_ios_inputs(self):
        uuid = '11111111-2222-3333-4444-555555555555'
        certificate = b'unit-test certificate placeholder'
        profile = {'UUID': uuid, 'Name': 'Test distribution', 'TeamIdentifier': ['TESTTEAM'], 'Platform': ['iOS'],
                   'ExpirationDate': datetime.datetime.now() + datetime.timedelta(days=30),
                   'Entitlements': {'application-identifier': 'TESTTEAM.' + release.BUNDLE_ID, 'get-task-allow': False},
                   'DeveloperCertificates': [certificate]}
        options = {'method': 'app-store-connect', 'signingStyle': 'manual', 'teamID': 'TESTTEAM',
                   'provisioningProfiles': {release.BUNDLE_ID: uuid}}
        (self.config / 'ios-export-options.plist').write_bytes(plistlib.dumps(options))
        (self.config / 'ios-app-store.mobileprovision').write_bytes(b'profile placeholder')
        digest = hashlib.sha1(certificate).hexdigest().upper()
        def run(args, **kwargs):
            body = plistlib.dumps(profile) if args[1] == 'cms' else f'1) {digest} "Apple Distribution: Test"'.encode()
            return subprocess.CompletedProcess(args, 0, stdout=body)
        return profile, run

    def test_ios_requires_distribution_profile_and_matching_private_key(self):
        profile, run = self.make_ios_inputs()
        environment, paths = release.ios_plan(self.config, run=run)
        self.assertEqual(environment['FLUTTER_XCODE_KANEO_IOS_PROFILE'], profile['UUID'])
        self.assertIn('--export-options-plist=' + str(paths[1]), release.build_command('ios', 3, paths))
        profile['DeveloperCertificates'] = []
        with self.assertRaisesRegex(ValueError, 'private key'):
            release.ios_plan(self.config, run=run)

    def test_development_wrong_app_and_expired_profiles_are_rejected(self):
        for mutate in [lambda p: p.update(ProvisionedDevices=['device']),
                       lambda p: p['Entitlements'].update({'get-task-allow': True}),
                       lambda p: p['Entitlements'].update({'application-identifier': 'TESTTEAM.other.app'}),
                       lambda p: p.update(ExpirationDate=datetime.datetime(2000, 1, 1))]:
            profile, run = self.make_ios_inputs()
            mutate(profile)
            with self.assertRaises(ValueError):
                release.ios_plan(self.config, run=run)

    def test_export_cannot_upload_implicitly(self):
        _, run = self.make_ios_inputs()
        file = self.config / 'ios-export-options.plist'
        data = plistlib.loads(file.read_bytes())
        data['destination'] = 'upload'
        file.write_bytes(plistlib.dumps(data))
        with self.assertRaisesRegex(ValueError, 'separate step'):
            release.ios_plan(self.config, run=run)


if __name__ == '__main__':
    unittest.main()
