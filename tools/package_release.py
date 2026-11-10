"""Validate regression registration and release hashes before atomically publishing a ZIP."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import zipfile


def inside(root, relative):
    path = (root / relative.replace('\\', '/')).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError('Missing or outside release: ' + relative)
    return path


def validate_release(root, baseline):
    root = Path(root).resolve()
    manifest = json.loads((root / 'tests/regression/cases.json').read_text(encoding='utf-8-sig'))
    cases = manifest.get('cases')
    if manifest.get('schemaVersion') != 1 or not isinstance(cases, list) or not cases:
        raise ValueError('Invalid regression registration')
    seen = set()
    for case in cases:
        test_id = case.get('id', '')
        if not isinstance(test_id, str) or not re.fullmatch(r'REG-[A-Z]+-[0-9]{3}', test_id) or test_id in seen:
            raise ValueError('Invalid or duplicate regression ID: ' + str(test_id))
        seen.add(test_id)
        if not case.get('bugs') or not case.get('scenario', '').strip():
            raise ValueError('Missing regression scenario: ' + test_id)
        path = inside(root, case.get('script', ''))
        if path.suffix != '.ps1' or type(case.get('timeoutSeconds')) is not int or not 1 <= case['timeoutSeconds'] <= 1800:
            raise ValueError('Invalid regression execution: ' + test_id)
    spec = json.loads(inside(root, baseline).read_text(encoding='utf-8-sig'))
    fields = [value for key, value in spec.items() if re.fullmatch(r'r[0-9]+Files', key)]
    if len(fields) != 1 or not fields[0]:
        raise ValueError('Missing release hash list')
    hashes = fields[0]
    for name, expected in hashes.items():
        if hashlib.sha256(inside(root, name).read_bytes()).hexdigest() != expected:
            raise ValueError('Release hash mismatch: ' + name)
    return {'cases': len(seen), 'hashes': hashes}


def validate_containment_review(root, incident):
    review = incident.get('scopeReview', {})
    if (review.get('authority') != 'project-owner-authorized-technical-review'
        or review.get('historicalIncidentResolved') is not False or review.get('productionApproved') is not False
        or not review.get('record') or not re.fullmatch('[0-9a-f]{64}', str(review.get('manifestSHA256', '')))):
        raise ValueError('Invalid contained-component security review')
    inside(root, review['record'])
    path = inside(root, review.get('manifest', ''))
    if hashlib.sha256(path.read_bytes()).hexdigest() != review['manifestSHA256']:
        raise ValueError('Security scope review manifest changed')
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    if data.get('schemaVersion') != 1 or data.get('incident') != incident['id'] or not data.get('activeFiles') or not data.get('guardOnlyFiles') or not data.get('requiredIds'):
        raise ValueError('Incomplete security dependency review')
    for group in ('activeFiles', 'guardOnlyFiles', 'heldSourceFiles'):
        for name, expected in data.get(group, {}).items():
            if hashlib.sha256(inside(root, name).read_bytes()).hexdigest() != expected:
                raise ValueError('Reviewed security dependency changed: ' + name)
    registry_path = inside(root, 'tests/regression/cases.json')
    if hashlib.sha256(registry_path.read_bytes()).hexdigest() != data.get('registrySHA256'):
        raise ValueError('Reviewed security registry changed')
    cases = json.loads(registry_path.read_text(encoding='utf-8-sig'))['cases']
    ids = [case['id'] for case in cases]
    if len(set(ids)) != len(ids) or set(ids) != set(data['requiredIds']) or len(ids) != len(data['requiredIds']):
        raise ValueError('Incomplete reviewed case set')
    for case in cases:
        script = case['script'].replace('\\', '/')
        if script not in data['activeFiles'] or script in data['guardOnlyFiles']:
            raise ValueError('Held or unreviewed script in active gate')
    return data


def assert_no_security_hold(root, profile=None):
    policy_path = root / 'release/security-incidents.json'
    if not policy_path.exists():
        return
    policy = json.loads(policy_path.read_text(encoding='utf-8-sig'))
    if policy.get('schemaVersion') != 1 or not isinstance(policy.get('incidents'), list):
        raise ValueError('Invalid security incident policy')
    for incident in policy['incidents']:
        if not isinstance(incident, dict) or not incident.get('id') or incident.get('status') not in ('investigating', 'controlled-local-validation', 'component-contained', 'cleared'):
            raise ValueError('Invalid security incident disposition')
        if incident['status'] == 'investigating':
            raise ValueError('Unresolved security incident blocks packaging: ' + incident['id'])
        if incident['status'] == 'controlled-local-validation':
            raise ValueError('Local validation authorization does not permit packaging: ' + incident['id'])
        if incident['status'] == 'component-contained':
            dependencies = validate_containment_review(root, incident)
            if profile != 'runtime':
                raise ValueError('Contained incident permits only an isolated runtime candidate, not validation/source publication')
            attestation = json.loads(inside(root, 'release/candidate-gate-attestation.json').read_text(encoding='utf-8-sig'))
            gate_path = inside(root, attestation.get('gateReport', ''))
            if (attestation.get('productionApproved') is not False
                or attestation.get('reviewManifestSHA256') != incident['scopeReview']['manifestSHA256']
                or hashlib.sha256(gate_path.read_bytes()).hexdigest() != attestation.get('gateReportSHA256')
                or hashlib.sha256(inside(root, 'bin/WinSlim.UI.Native.R3.2.84.exe').read_bytes()).hexdigest() != attestation.get('uiSHA256')):
                raise ValueError('Candidate gate attestation changed or incomplete')
            gate = json.loads(gate_path.read_text(encoding='utf-8-sig'))
            rows = gate.get('Results', [])
            if (gate.get('Passed') is not True or gate.get('ExitCode') != 0
                or len(rows) != len(dependencies['requiredIds'])
                or {row.get('Id') for row in rows} != set(dependencies['requiredIds'])
                or any(row.get('Status') != 'Passed' or row.get('ExitCode') != 0 for row in rows)):
                raise ValueError('Fresh complete candidate gate required before packaging')
            continue
        if not isinstance(incident.get('resolution'), str) or not incident['resolution'].strip():
            raise ValueError('Security incident lacks review resolution')


def runtime_files(root, manifest):
    if not manifest:
        raise ValueError('Runtime profile requires a reviewed runtime manifest')
    data = json.loads(inside(root, manifest).read_text(encoding='utf-8-sig'))
    if data.get('schemaVersion') != 1 or not isinstance(data.get('files'), dict) or not data['files']:
        raise ValueError('Invalid runtime manifest')
    files = {}
    seen = set()
    for name, expected in data['files'].items():
        name = name.replace('\\', '/')
        lower = name.lower()
        parts = lower.split('/')
        if (lower in seen or any(p in ('tests', 'tools', 'logs', '.git', '.codex', '.agents', '__pycache__') for p in parts)
            or Path(lower).suffix in ('.cs', '.py', '.pyc', '.pdb', '.zip', '.7z', '.rar')
            or re.search(r'harness|reproducer|dev-python|(^|/)(build|test|validar|executar-regressoes)|iniciar-validacao', lower)):
            raise ValueError('Test/development tool forbidden in runtime profile: ' + name)
        if not isinstance(expected, str) or not re.fullmatch('[0-9a-fA-F]{64}', expected):
            raise ValueError('Invalid runtime hash: ' + name)
        if hashlib.sha256(inside(root, name).read_bytes()).hexdigest() != expected.lower():
            raise ValueError('Runtime hash mismatch: ' + name)
        files[name] = expected.lower()
        seen.add(lower)
    return files


def audit_compiled_files(root, names, allowed):
    for name in names:
        path = inside(root, name)
        with path.open('rb') as stream:
            executable = stream.read(2) == b'MZ'
        if path.suffix.lower() in ('.7z', '.rar', '.cab', '.tar', '.gz', '.bz2', '.xz'):
            raise ValueError('Opaque archive cannot be audited for compiled tools: ' + name)
        if path.suffix.lower() == '.zip':
            # Validation diagnostics may be nested; opaque archives must not hide tools.
            try:
                with zipfile.ZipFile(path) as nested:
                    entries = [entry for entry in nested.infolist() if not entry.is_dir()]
                    if len(entries) > 10000 or sum(entry.file_size for entry in entries) > 67108864:
                        raise ValueError('Nested diagnostic archive exceeds audit limits')
                    for entry in entries:
                        if Path(entry.filename).suffix.lower() not in ('.log', '.json', '.txt', '.png', '.xml', '.html', '.csv'):
                            raise ValueError('Nested executable/tool/archive forbidden: ' + entry.filename)
                        with nested.open(entry) as stream:
                            if stream.read(2) == b'MZ':
                                raise ValueError('Nested compiled binary forbidden: ' + entry.filename)
            except (zipfile.BadZipFile, RuntimeError) as error:
                raise ValueError('Nested diagnostic archive cannot be audited') from error
        executable = executable or path.suffix.lower() in ('.exe', '.dll', '.com', '.scr', '.sys', '.msi', '.pyd')
        if not executable:
            continue
        supported = (re.fullmatch(r'bin/WinSlim\.UI\.Native\.R[0-9]+\.[0-9]+\.[0-9]+\.exe', name)
                     or re.fullmatch(r'third_party/PresentMon/PresentMon-[0-9]+\.[0-9]+\.[0-9]+-x64\.exe', name))
        if not supported or name not in allowed:
            raise ValueError('Unexpected compiled executable/binary in package: ' + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != allowed[name]:
            raise ValueError('Approved executable hash mismatch: ' + name)


def package_release(root, baseline, destination, profile='validation', runtime_manifest=None):
    root = Path(root).resolve()
    destination = Path(destination).resolve()
    if destination.is_relative_to(root):
        raise ValueError('ZIP destination must be outside release source')
    assert_no_security_hold(root, profile)
    verified = validate_release(root, baseline)
    if profile not in ('validation', 'runtime'):
        raise ValueError('Unknown package profile')
    allowed = runtime_files(root, runtime_manifest) if runtime_manifest else {}
    if profile == 'runtime':
        if not allowed:
            raise ValueError('Runtime profile requires a reviewed runtime manifest')
        names = sorted(allowed)
    else:
        names = sorted(path.relative_to(root).as_posix() for path in root.rglob('*')
                       if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc')
    if 'PACKAGE-PROFILE.json' in names:
        raise ValueError('Reserved package profile descriptor already exists')
    audit_compiled_files(root, names, allowed)
    descriptor = json.dumps({'schemaVersion': 1, 'profile': profile,
                             'purpose': 'end-user-runtime' if profile == 'runtime' else 'technical-validation-with-test-source',
                             'containsTestTools': profile == 'validation'}, indent=2).encode('utf-8')
    expected_hashes = {name: hashlib.sha256(inside(root, name).read_bytes()).hexdigest() for name in names}
    # Preserve the hashes validated before reading/writing the archive.
    expected_hashes.update({name.replace('\\', '/'): value for name, value in verified['hashes'].items() if name.replace('\\', '/') in names})
    expected_hashes.update({name: value for name, value in allowed.items() if name in names})
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.winslim-package-', suffix='.zip', dir=destination.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name in names:
                archive.write(inside(root, name), root.name + '/' + name)
            archive.writestr(root.name + '/PACKAGE-PROFILE.json', descriptor)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError('ZIP CRC check failed')
            for name, expected in expected_hashes.items():
                archived = archive.read(root.name + '/' + name.replace('\\', '/'))
                if hashlib.sha256(archived).hexdigest() != expected:
                    raise ValueError('Source changed during packaging: ' + name)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return verified


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root')
    parser.add_argument('baseline')
    parser.add_argument('destination', nargs='?')
    parser.add_argument('--profile', choices=('validation', 'runtime'))
    parser.add_argument('--runtime-manifest', help='Reviewed relative file/hash allowlist; required for runtime or compiled binaries')
    args = parser.parse_args()
    if args.destination and not args.profile:
        parser.error('Packaging requires explicit --profile validation or --profile runtime')
    try:
        result = package_release(args.root, args.baseline, args.destination, args.profile, args.runtime_manifest) if args.destination else validate_release(args.root, args.baseline)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        parser.exit(1, 'REJECTED: ' + str(error) + '\n')
    print('Validated: ' + str(result['cases']) + ' unique regression cases; ' + str(len(result['hashes'])) + ' hashes.')


if __name__ == '__main__':
    main()
