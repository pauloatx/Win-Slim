import hashlib
import json
from pathlib import Path
import sys
import subprocess
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
    def test_unexpected_compiled_helper_rejected(self):
        (self.root / 'logs').mkdir()
        (self.root / 'logs/PresentMonHarness.exe').write_bytes(b'INERT FIXTURE - NOT A PE EXECUTABLE')
        out = self.parent / 'result.zip'
        with self.assertRaisesRegex(ValueError, 'executable|binary|compiled'):
            package_release(self.root, 'baseline.json', out)
        self.assertFalse(out.exists())
    def test_renaming_helper_does_not_allow_distribution(self):
        (self.root / 'bin').mkdir()
        (self.root / 'bin/friendly-name.exe').write_bytes(b'INERT FIXTURE - NOT A PE EXECUTABLE')
        with self.assertRaisesRegex(ValueError, 'executable|binary|compiled'):
            package_release(self.root, 'baseline.json', self.parent / 'result.zip')
    def test_pending_security_incident_preserves_prior_zip(self):
        (self.root / 'release').mkdir()
        (self.root / 'release/security-incidents.json').write_text(json.dumps({'schemaVersion':1,'incidents':[{'id':'AV-FIXTURE','status':'investigating','families':['PresentMonHarness']}]}))
        out = self.parent / 'result.zip'; out.write_bytes(b'prior release')
        with self.assertRaisesRegex(ValueError, 'security|incident'):
            package_release(self.root, 'baseline.json', out)
        self.assertEqual(out.read_bytes(), b'prior release')
    def runtime_manifest(self, files):
        for name, content in files.items():
            path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(content)
        name = 'runtime-manifest.json'
        (self.root / name).write_text(json.dumps({'schemaVersion':1,'files':{p:hashlib.sha256(v).hexdigest() for p,v in files.items()}}))
        return name
    def test_runtime_contains_only_reviewed_files(self):
        files = {'bin/WinSlim.UI.Native.R3.2.84.exe':b'INERT REVIEWED APP FIXTURE','resources/theme.xaml':b'<Grid />'}
        manifest = self.runtime_manifest(files)
        (self.root / 'logs').mkdir(); (self.root / 'logs/renamed-helper.exe').write_bytes(b'INERT NOT SELECTED')
        out = self.parent / 'runtime.zip'
        package_release(self.root, 'baseline.json', out, profile='runtime', runtime_manifest=manifest)
        with zipfile.ZipFile(out) as archive:
            self.assertEqual(set(archive.namelist()), {'release/'+p for p in files} | {'release/PACKAGE-PROFILE.json'})
            descriptor = json.loads(archive.read('release/PACKAGE-PROFILE.json'))
            self.assertFalse(descriptor['containsTestTools']); self.assertEqual(descriptor['profile'],'runtime')
            self.assertEqual(archive.read('release/bin/WinSlim.UI.Native.R3.2.84.exe'), files['bin/WinSlim.UI.Native.R3.2.84.exe'])
    def test_runtime_rejects_test_source_even_when_manifest_requests_it(self):
        manifest = self.runtime_manifest({'tests/PresentMonHarness.cs': b'inert test source'})
        with self.assertRaisesRegex(ValueError, 'Test/development'):
            package_release(self.root, 'baseline.json', self.parent/'runtime.zip', profile='runtime', runtime_manifest=manifest)
    def test_runtime_does_not_allow_renamed_helper(self):
        manifest = self.runtime_manifest({'bin/friendly.exe': b'INERT TEST EXECUTABLE FIXTURE'})
        with self.assertRaisesRegex(ValueError, 'Unexpected compiled'):
            package_release(self.root, 'baseline.json', self.parent/'runtime.zip', profile='runtime', runtime_manifest=manifest)
    def test_runtime_requires_manifest(self):
        with self.assertRaisesRegex(ValueError, 'manifest'):
            package_release(self.root, 'baseline.json', self.parent/'runtime.zip', profile='runtime')
    def test_runtime_tamper_preserves_previous_archive(self):
        manifest = self.runtime_manifest({'bin/WinSlim.UI.Native.R3.2.84.exe': b'INERT APP FIXTURE'})
        (self.root/'bin/WinSlim.UI.Native.R3.2.84.exe').write_bytes(b'CHANGED FIXTURE')
        out=self.parent/'runtime.zip';out.write_bytes(b'prior runtime')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            package_release(self.root, 'baseline.json', out, profile='runtime', runtime_manifest=manifest)
        self.assertEqual(out.read_bytes(), b'prior runtime')
    def test_validation_identifies_test_bundle(self):
        out=self.parent/'validation.zip';package_release(self.root, 'baseline.json', out, profile='validation')
        with zipfile.ZipFile(out) as archive:
            descriptor=json.loads(archive.read('release/PACKAGE-PROFILE.json'))
            self.assertTrue(descriptor['containsTestTools']); self.assertEqual(descriptor['profile'],'validation')
            self.assertIn('release/tests/test.ps1', archive.namelist())
    def test_pe_header_under_another_extension_is_rejected(self):
        (self.root/'payload.dat').write_bytes(b'MZ INERT HEADER FIXTURE')
        with self.assertRaisesRegex(ValueError, 'binary'):
            package_release(self.root, 'baseline.json', self.parent/'validation.zip')
    def test_unknown_security_disposition_fails_closed(self):
        (self.root/'release').mkdir()
        for incident in ({'id':'AV-FIXTURE','status':'unknown'}, {'id':'AV-FIXTURE','status':'cleared','resolution':None}, 'invalid-incident'):
            (self.root/'release/security-incidents.json').write_text(json.dumps({'schemaVersion':1,'incidents':[incident]}))
            with self.assertRaisesRegex(ValueError, '[Ss]ecurity'):
                package_release(self.root, 'baseline.json', self.parent/'validation.zip')
            self.assertFalse((self.parent/'validation.zip').exists())
    def test_controlled_local_validation_still_blocks_both_package_profiles(self):
        (self.root/'release').mkdir()
        incident={'id':'AV-FIXTURE','status':'controlled-local-validation',
                  'resolution':'Project-owner local tests only; no vendor verdict',
                  'localValidationAuthorization':{'authority':'project-owner',
                      'assessmentRecord':'release/owner-fixture.json',
                      'allowedScopes':['affected-test-component-generation-and-execution','full-regression-gate'],
                      'blockedScopes':['application-package-publication','production-release'],
                      'productionApproved':False,'stopOnFailure':True}}
        (self.root/'release/security-incidents.json').write_text(json.dumps({'schemaVersion':1,'incidents':[incident]}))
        for profile in ('validation','runtime'):
            out=self.parent/(profile+'.zip');out.write_bytes(b'previous archive')
            with self.assertRaisesRegex(ValueError,'Local validation authorization does not permit packaging'):
                package_release(self.root,'baseline.json',out,profile=profile)
            self.assertEqual(out.read_bytes(),b'previous archive')
    def test_cli_requires_explicit_profile(self):
        result=subprocess.run([sys.executable,str(Path(__file__).resolve().parents[1]/'tools/package_release.py'),str(self.root),'baseline.json',str(self.parent/'out.zip')],capture_output=True,text=True,timeout=15)
        self.assertNotEqual(result.returncode,0);self.assertIn('explicit --profile',result.stderr)
        self.assertFalse((self.parent/'out.zip').exists())
    def test_validation_approved_binary_requires_matching_manifest(self):
        files={'bin/WinSlim.UI.Native.R3.2.84.exe':b'INERT REVIEWED APP FIXTURE'}
        manifest=self.runtime_manifest(files)
        with self.assertRaisesRegex(ValueError,'compiled'):
            package_release(self.root,'baseline.json',self.parent/'out.zip')
        package_release(self.root,'baseline.json',self.parent/'out.zip',profile='validation',runtime_manifest=manifest)
        with zipfile.ZipFile(self.parent/'out.zip') as archive:
            self.assertEqual(archive.read('release/bin/WinSlim.UI.Native.R3.2.84.exe'),files['bin/WinSlim.UI.Native.R3.2.84.exe'])
    def test_nested_archive_cannot_hide_compiled_helper(self):
        with zipfile.ZipFile(self.root/'diagnostic.zip','w') as archive:
            archive.writestr('logs/PresentMonHarness.exe',b'INERT NOT EXECUTABLE')
        with self.assertRaisesRegex(ValueError,'Nested executable'):
            package_release(self.root,'baseline.json',self.parent/'out.zip')
    def test_nested_diagnostic_logs_remain_supported(self):
        with zipfile.ZipFile(self.root/'diagnostic.zip','w') as archive:
            archive.writestr('summary.json',b'{"fixture":true}')
            archive.writestr('evidence.log',b'fixture evidence')
        package_release(self.root,'baseline.json',self.parent/'out.zip')
        with zipfile.ZipFile(self.parent/'out.zip') as archive:
            self.assertIn('release/diagnostic.zip',archive.namelist())

if __name__ == '__main__': unittest.main()
