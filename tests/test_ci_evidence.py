"""Hosted CI transport tests. All repositories and logs are disposable fixtures."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class GitBytesTests(unittest.TestCase):
    def test_checkout_preserves_both_line_endings_with_autocrlf(self):
        with tempfile.TemporaryDirectory(prefix='winslim-ci-git-') as temporary:
            base = Path(temporary)
            source = base / 'source'
            source.mkdir()
            original = {'lf.ps1': b'first\nsecond\n', 'crlf.json': b'{\r\n}\r\n'}
            attributes = PROJECT / '.gitattributes'
            if attributes.exists():
                shutil.copyfile(attributes, source / '.gitattributes')
            for name, data in original.items():
                (source / name).write_bytes(data)
            def git(*args, cwd=source):
                return subprocess.run(['git', *args], cwd=cwd, check=True,
                                      capture_output=True, text=True)
            git('init', '--quiet')
            git('-c', 'core.autocrlf=false', 'add', '.')
            git('-c', 'user.name=CI fixture', '-c', 'user.email=fixture@example.invalid',
                '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'fixture')
            git('-c', 'core.autocrlf=true', 'clone', '--quiet', str(source), str(base / 'checkout'))
            for name, data in original.items():
                self.assertEqual(data, (base / 'checkout' / name).read_bytes(), name)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('ci_evidence', PROJECT / 'tools/ci_evidence.py')
        self.ci = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.ci)
        self.temporary = tempfile.TemporaryDirectory(prefix='winslim-ci-evidence-')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'project with spaces'
        (self.root / 'logs').mkdir(parents=True)
        self.output = self.base / 'evidence'
        self.old = self.root / 'logs/old-run.json'
        self.old.write_text('{"Passed":true}', encoding='utf-8')
        self.original = self.old.read_bytes()

    def start(self):
        self.ci.initialize(self.root, self.output, context={'Hosted': False})

    def fresh_gate(self):
        run = self.root / 'logs/candidato-r3284-fresh'
        run.mkdir()
        (run / 'summary.json').write_text('{"TechnicalPassed":true,"ProductionApproved":false}')
        (run / 'regressions.json').write_text('{"Passed":true}')

    def test_only_current_text_is_uploaded_and_hashes_match(self):
        self.start()
        self.fresh_gate()
        fresh = self.root / 'logs/current.stdout.log'
        fresh.write_text('fixture checks passed\n', encoding='utf-8')
        (self.root / 'logs/nested').mkdir()
        (self.root / 'logs/nested/SHA256.json').write_text('{"fixture":"nested integrity log"}')
        (self.root / 'logs/fixture.dll').write_bytes(b'MZcompiled fixture')
        (self.root / 'logs/disguised.json').write_bytes(b'MZnot text')
        (self.root / 'logs/distribution.zip').write_bytes(b'PKfixture')
        (self.root / 'logs/secret.bin').write_bytes(b'fixture')
        (self.root / 'bin').mkdir()
        (self.root / 'bin/WinSlim.UI.Native.R3.2.84.exe').write_bytes(b'MZapplication')
        self.ci.collect(self.root, self.output, 'success')
        copied = self.output / 'logs/current.stdout.log'
        self.assertEqual(copied.read_bytes(), fresh.read_bytes())
        self.assertFalse((self.output / 'logs/old-run.json').exists())
        for name in ('fixture.dll', 'disguised.json', 'distribution.zip', 'secret.bin'):
            self.assertFalse((self.output / 'logs' / name).exists(), name)
        self.assertFalse((self.output / 'bin').exists())
        self.assertEqual(self.original, self.old.read_bytes())
        receipt = json.loads((self.output / 'collection.json').read_text())
        self.assertFalse(receipt['ProductionApproved'])
        self.assertEqual('NotPerformed', receipt['PhysicalAcceptance'])
        self.assertNotIn('CIApproved', receipt)
        hashes = json.loads((self.output / 'SHA256.json').read_text())
        self.assertEqual(set(hashes), {path.relative_to(self.output).as_posix()
                                      for path in self.output.rglob('*')
                                      if path.is_file() and path != self.output / 'SHA256.json'})
        for relative, expected in hashes.items():
            self.assertEqual(expected, hashlib.sha256((self.output / relative).read_bytes()).hexdigest())
        self.assertIn('bin/WinSlim.UI.Native.R3.2.84.exe', receipt['BuildOutputsSHA256'])

    def test_failure_preserves_diagnostics_without_approval(self):
        self.start()
        (self.root / 'logs/failure.stderr.log').write_text('simulated compiler unavailable')
        self.ci.collect(self.root, self.output, 'failure')
        receipt = json.loads((self.output / 'collection.json').read_text())
        self.assertEqual('failure', receipt['GateStepOutcome'])
        self.assertFalse(receipt['ProductionApproved'])
        self.assertTrue((self.output / 'logs/failure.stderr.log').exists())
        self.assertEqual(self.original, self.old.read_bytes())

    def test_changed_log_is_collected_but_old_success_cannot_supply_fresh_gate(self):
        self.start()
        self.old.write_text('changed failure')
        with self.assertRaisesRegex(ValueError, 'fresh candidate'):
            self.ci.collect(self.root, self.output, 'success')
        self.assertEqual('changed failure', (self.output / 'logs/old-run.json').read_text())
        self.assertFalse((self.output / 'collection.json').exists())

    def test_missing_state_wrong_root_and_existing_destination_fail_closed(self):
        with self.assertRaises((FileNotFoundError, ValueError)):
            self.ci.collect(self.root, self.output, 'success')
        self.start()
        state = (self.output / 'before.json').read_bytes()
        with self.assertRaises(FileExistsError):
            self.start()
        self.assertEqual(state, (self.output / 'before.json').read_bytes())
        other = self.base / 'other'
        other.mkdir()
        with self.assertRaisesRegex(ValueError, 'root'):
            self.ci.collect(other, self.output, 'failure')
        self.assertEqual(self.original, self.old.read_bytes())

    def test_output_cannot_be_inside_project_and_input_cannot_escape(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.ci.initialize(self.root, self.root / 'logs/evidence', context={})
        (self.root / 'specs').mkdir()
        (self.root / 'specs/FASE7-R3.2.84-baseline.json').write_text(
            json.dumps({'r3284Files': {'../outside.txt': '0' * 64}}))
        (self.base / 'outside.txt').write_text('preserve')
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.start()
        self.assertEqual('preserve', (self.base / 'outside.txt').read_text())

    def test_host_context_never_exports_credentials(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
                        'RUNNER_OS': 'Windows', 'GITHUB_REPOSITORY': 'fixture/repo',
                        'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '2',
                        'GITHUB_SERVER_URL': 'https://github.com', 'GITHUB_TOKEN': 'DO-NOT-EXPORT'}, clear=True):
            context = self.ci.runner_context()
        self.assertTrue(context['Hosted'])
        self.assertEqual('https://github.com/fixture/repo/actions/runs/123', context['RunURL'])
        self.assertNotIn('DO-NOT-EXPORT', json.dumps(context))

    def test_cli_failure_is_nonzero(self):
        result = subprocess.run([os.sys.executable, str(PROJECT / 'tools/ci_evidence.py'),
                                 'collect', '--root', str(self.root), '--output', str(self.output),
                                 '--outcome', 'success'], capture_output=True, text=True)
        self.assertNotEqual(0, result.returncode)
        self.assertFalse((self.output / 'collection.json').exists())


if __name__ == '__main__':
    unittest.main()
