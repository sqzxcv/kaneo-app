import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('package_desktop', Path(__file__).with_name('package_desktop.py'))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageValidationTest(unittest.TestCase):
    def test_version_rejects_shell_text_and_non_numeric_builds(self):
        for text in ['version: 1.2.3+0', 'version: 1.2.3+$(oops)', 'version: release']:
            with self.assertRaises(ValueError):
                package.version_info(text)
        self.assertEqual(package.version_info('version: 1.2.3+4\n', '51'), ('1.2.3', '51'))

    def test_test_bundle_cannot_be_distributed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'Contents').mkdir()
            (root / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'app.kaneo.kaneoApp.DTest', 'CFBundleExecutable': 'kaneo_app',
            }))
            with self.assertRaisesRegex(ValueError, 'formal bundle ID'):
                package.validate_bundle(root, 'macos')

    def test_bundle_cannot_depend_on_an_external_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'bundle'
            root.mkdir()
            (Path(temp) / 'outside.dll').write_bytes(b'not bundled')
            (root / 'runtime.dll').symlink_to('../outside.dll')
            with self.assertRaisesRegex(ValueError, 'outside the application'):
                package.validate_bundle(root, 'windows')

    def test_macos_bundle_requires_flutter_frameworks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'Contents/MacOS').mkdir(parents=True)
            (root / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': package.BUNDLE_ID, 'CFBundleExecutable': 'kaneo_app',
            }))
            (root / 'Contents/MacOS/kaneo_app').touch()
            with self.assertRaisesRegex(ValueError, 'FlutterMacOS.framework'):
                package.validate_bundle(root, 'macos')

    def test_windows_requires_assets_aot_and_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'data/flutter_assets').mkdir(parents=True)
            for name in ['data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin', 'kaneo_app.exe',
                         'flutter_windows.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll']:
                (root / name).touch()
            with self.assertRaisesRegex(ValueError, 'app.so'):
                package.validate_bundle(root, 'windows')
            (root / 'data/app.so').touch()
            package.validate_bundle(root, 'windows')
            (root / 'msvcp140.dll').unlink()
            with self.assertRaisesRegex(ValueError, 'msvcp140.dll'):
                package.validate_bundle(root, 'windows')

    def test_linux_requires_aot_and_flutter_engine(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'data/flutter_assets').mkdir(parents=True)
            (root / 'lib').mkdir()
            for name in ['data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin', 'kaneo_app',
                         'lib/libapp.so']:
                (root / name).touch()
            with self.assertRaisesRegex(ValueError, 'libflutter_linux_gtk.so'):
                package.validate_bundle(root, 'linux')


if __name__ == '__main__':
    unittest.main()
