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


def package_release(root, baseline, destination):
    root = Path(root).resolve()
    destination = Path(destination).resolve()
    if destination.is_relative_to(root):
        raise ValueError('ZIP destination must be outside release source')
    verified = validate_release(root, baseline)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.winslim-package-', suffix='.zip', dir=destination.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(root.rglob('*')):
                if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
                    archive.write(path, root.name + '/' + path.relative_to(root).as_posix())
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError('ZIP CRC check failed')
            for name, expected in verified['hashes'].items():
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
    args = parser.parse_args()
    try:
        result = package_release(args.root, args.baseline, args.destination) if args.destination else validate_release(args.root, args.baseline)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        parser.exit(1, 'REJECTED: ' + str(error) + '\n')
    print('Validated: ' + str(result['cases']) + ' unique regression cases; ' + str(len(result['hashes'])) + ' hashes.')


if __name__ == '__main__':
    main()
