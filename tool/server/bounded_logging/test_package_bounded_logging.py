"""Portable overlay tests plus an optional real packaged-runtime check."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import warnings
import zipfile

from package_bounded_logging import package, OWNERS, METADATA

ROOT = Path(__file__).resolve().parents[3]
PATCH = Path(__file__).with_name('bounded-logging-v2.4.2366.patch')


class PackageTests(unittest.TestCase):
    def test_overlay_preserves_duplicates_and_rejects_unreviewed_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = root / 'base.jar'
            class_name = OWNERS[0] + '.class'
            bytecode = b'\xca\xfe\xba\xbe\0\0\0\x41'
            with warnings.catch_warnings(), zipfile.ZipFile(base, 'w') as archive:
                warnings.simplefilter('ignore', UserWarning)
                archive.writestr(class_name, bytecode + b'old')
                archive.writestr(OWNERS[0] + '$Obsolete.class', bytecode + b'old nested')
                archive.writestr('META-INF/MANIFEST.MF', 'custom version and Android patches')
                archive.writestr('resource', 'first occurrence')
                archive.writestr('resource', 'second occurrence')
            classes = root / 'classes'
            compiled = classes / class_name
            compiled.parent.mkdir(parents=True)
            compiled.write_bytes(bytecode + b'new')
            expected = hashlib.sha256(base.read_bytes()).hexdigest()
            output = root / 'candidate.jar'
            with self.assertRaises(ValueError):
                package(base, classes, output, PATCH)
            self.assertFalse(output.exists())
            digest = package(base, classes, output, PATCH, expected_sha=expected)
            second = root / 'second.jar'
            self.assertEqual(digest, package(base, classes, second, PATCH, expected_sha=expected))
            with zipfile.ZipFile(base) as old, zipfile.ZipFile(output) as new:
                preserved = lambda archive: [(info.filename, archive.read(info)) for info in archive.infolist() if not info.filename.endswith('.class') and info.filename != METADATA]
                self.assertEqual(preserved(old), preserved(new))
                self.assertNotIn(OWNERS[0] + '$Obsolete.class', new.namelist())
                self.assertEqual(new.read(class_name), bytecode + b'new')
            with self.assertRaises(ValueError):
                package(base, classes, output, PATCH, expected_sha=expected)
            compiled.write_bytes(b'wrong bytecode')
            with self.assertRaises(ValueError):
                package(base, classes, root / 'bad.jar', PATCH, expected_sha=expected)

    def test_packaged_runtime_file_appender_behavior(self):
        candidate = Path(os.environ.get('TSUMIRU_BOUNDED_SERVER_JAR', ROOT / '.superpowers/bounded-logging/suwayomi-bounded-candidate.jar'))
        if not candidate.exists():
            self.skipTest('Set TSUMIRU_BOUNDED_SERVER_JAR to run the private JAR integration check')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = Path(__file__).with_name('LoggingProbe.java')
            subprocess.run(['javac', '--release', '21', '-cp', str(candidate), '-d', str(root), str(source)], check=True, capture_output=True)
            for mode in ('normal', 'property', 'environment'):
                environment = dict(os.environ)
                environment.pop('SUWAYOMI_BOUNDED_LOGGING', None)
                arguments = ['java']
                if mode == 'property':
                    arguments += ['-Dsuwayomi.tachidesk.config.server.boundedLogging=true']
                if mode == 'environment':
                    environment['SUWAYOMI_BOUNDED_LOGGING'] = '1'
                arguments += ['-cp', f'{root}{os.pathsep}{candidate}', 'LoggingProbe', str(root / mode)]
                result = subprocess.run(arguments, env=environment, check=True, capture_output=True, text=True)
                self.assertIn('FILE_APPENDER=' + ('true' if mode == 'normal' else 'false'), result.stdout)


if __name__ == '__main__':
    unittest.main()
