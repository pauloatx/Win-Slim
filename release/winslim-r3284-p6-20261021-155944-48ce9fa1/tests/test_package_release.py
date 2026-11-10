import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from package_release import package_release, validate_release

class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.parent = Path(self.temp.name)
        self.root = self.parent / 'release'
        (self.root / 'tests/regression').mkdir(parents=True)
        (self.root / 'tests/test.ps1').write_text('exit 0')
        self.case = dict(id='REG-REPORT-001', bugs=['fixture'], scenario='Fixture', script='tests/test.ps1', timeoutSeconds=30)
        self.manifest = dict(schemaVersion=1, cases=[self.case])
        self.save()
    def tearDown(self):
        self.temp.cleanup()
    def save(self):
        (self.root / 'tests/regression/cases.json').write_text(json.dumps(self.manifest))
        hashes = {n: hashlib.sha256((self.root / n).read_bytes()).hexdigest() for n in ['tests/regression/cases.json', 'tests/test.ps1']}
        (self.root / 'baseline.json').write_text(json.dumps({'r3278Files': hashes}))
    def test_valid_zip(self):
        out = self.parent / 'result.zip'
        result = package_release(self.root, 'baseline.json', out)
        self.assertEqual(result['cases'], 1)
        with zipfile.ZipFile(out) as archive:
            self.assertEqual(archive.read('release/tests/test.ps1'), b'exit 0')
    def test_duplicate_rejected_before_archive(self):
        self.manifest['cases'].append(dict(self.case)); self.save()
        out = self.parent / 'result.zip'
        with self.assertRaisesRegex(ValueError, 'duplicate.*REG-REPORT-001'):
            package_release(self.root, 'baseline.json', out)
        self.assertFalse(out.exists())
    def test_invalid_id_rejected(self):
        self.case['id'] = 'REG-REPORT-001\n'; self.save()
        with self.assertRaises(ValueError): validate_release(self.root, 'baseline.json')
    def test_missing_script_rejected(self):
        (self.root / 'tests/test.ps1').unlink()
        with self.assertRaises(ValueError): validate_release(self.root, 'baseline.json')
    def test_outside_script_rejected(self):
        (self.parent / 'outside.ps1').write_text('exit 0')
        self.case['script'] = '../outside.ps1'; self.save()
        with self.assertRaises(ValueError): validate_release(self.root, 'baseline.json')
    def test_tampered_hash_preserves_prior_zip(self):
        out = self.parent / 'result.zip'; out.write_bytes(b'prior release')
        (self.root / 'tests/test.ps1').write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            package_release(self.root, 'baseline.json', out)
        self.assertEqual(out.read_bytes(), b'prior release')

if __name__ == '__main__': unittest.main()
