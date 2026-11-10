"""Collect current-run text evidence only; never package or approve a release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from datetime import datetime, timezone

TEXT_SUFFIXES = {'.log', '.json', '.txt', '.csv', '.xml'}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def inside(root, relative):
    candidate = root / relative
    if not candidate.resolve().is_relative_to(root):
        raise ValueError('Evidence input outside root: ' + relative)
    return candidate


def text_logs(root):
    logs = root / 'logs'
    if not logs.exists():
        return {}
    result = {}
    for path in sorted(logs.rglob('*')):
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES:
            relative = path.relative_to(root).as_posix()
            inside(root, relative)
            with path.open('rb') as stream:
                if stream.read(2) in (b'MZ', b'PK'):
                    continue
            result[relative] = digest(path)
    return result


def input_hashes(root):
    names = {'.gitattributes', '.github/workflows/windows-candidate.yml',
             'tests/regression/cases.json', 'release/review.json',
             'release/security-incidents.json', 'specs/FASE7-R3.2.84-baseline.json',
             'Iniciar-Validacao.bat', 'Validar-Candidato-R3.2.84.ps1',
             'tools/ReleasePipeline.ps1', 'tools/ci_evidence.py'}
    baseline = root / 'specs/FASE7-R3.2.84-baseline.json'
    if baseline.exists():
        data = json.loads(baseline.read_text(encoding='utf-8-sig'))
        names.update(data['r3284Files'])
    return {name: digest(inside(root, name)) for name in sorted(names)
            if inside(root, name).is_file()}


def runner_context():
    # Explicit allowlist: never dump the process environment or credentials.
    names = ('GITHUB_SERVER_URL', 'GITHUB_REPOSITORY', 'GITHUB_RUN_ID',
             'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA', 'GITHUB_WORKFLOW_REF',
             'GITHUB_WORKFLOW_SHA', 'GITHUB_EVENT_NAME', 'GITHUB_REF',
             'RUNNER_OS', 'RUNNER_ARCH', 'RUNNER_ENVIRONMENT', 'ImageOS', 'ImageVersion')
    context = {name: os.environ.get(name) for name in names}
    context['Hosted'] = (os.environ.get('GITHUB_ACTIONS') == 'true'
                         and context['RUNNER_ENVIRONMENT'] == 'github-hosted'
                         and context['RUNNER_OS'] == 'Windows')
    context['RunURL'] = None
    if context['Hosted'] and all(context[key] for key in ('GITHUB_SERVER_URL', 'GITHUB_REPOSITORY', 'GITHUB_RUN_ID')):
        context['RunURL'] = (context['GITHUB_SERVER_URL'] + '/' + context['GITHUB_REPOSITORY']
                             + '/actions/runs/' + context['GITHUB_RUN_ID'])
    context['Python'] = sys.version
    context['PythonExecutableSHA256'] = digest(Path(sys.executable))
    context['Utc'] = datetime.now(timezone.utc).isoformat()
    return context


def initialize(root, output, context=None):
    root, output = Path(root).resolve(), Path(output).resolve()
    if output.is_relative_to(root):
        raise ValueError('Evidence output must be outside project root')
    output.mkdir(parents=True, exist_ok=False)
    write_json(output / 'context.json', runner_context() if context is None else context)
    write_json(output / 'inputs-SHA256.json', input_hashes(root))
    write_json(output / 'before.json', {'Root': str(root), 'Logs': text_logs(root)})


def collect(root, output, outcome):
    root, output = Path(root).resolve(), Path(output).resolve()
    if output.is_relative_to(root):
        raise ValueError('Evidence output must be outside project root')
    if (output / 'collection.json').exists():
        raise FileExistsError('Evidence collection already completed')
    before = json.loads((output / 'before.json').read_text(encoding='utf-8'))
    if before['Root'] != str(root):
        raise ValueError('Evidence root differs from initialized root')
    current = text_logs(root)
    changed = {name: sha for name, sha in current.items() if before['Logs'].get(name) != sha}
    for name, sha in changed.items():
        source = inside(root, name)
        destination = inside(output, name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source.read_bytes())
        if digest(destination) != sha:
            raise ValueError('Evidence changed during collection: ' + name)
    # This checks transport freshness, not regression acceptance. The official
    # pipeline remains responsible for IDs, delegation, outcomes and WPF.
    new = set(current) - set(before['Logs'])
    fresh_candidate = any(name.startswith('logs/candidato-r3284-') and name.endswith('/summary.json')
                          and name.removesuffix('summary.json') + 'regressions.json' in new for name in new)
    if outcome == 'success' and not fresh_candidate:
        raise ValueError('Successful gate has no fresh candidate evidence')
    artifacts = {}
    for name in ('bin/WinSlim.UI.Native.R3.2.84.exe', 'bin/WinSlim.UI.Native.R3.2.84.exe.config',
                 'WinSlim-Diagnostico-R3.2.84.zip'):
        path = inside(root, name)
        if path.is_file():
            artifacts[name] = digest(path)
    write_json(output / 'collection.json', {
        'Utc': datetime.now(timezone.utc).isoformat(), 'GateStepOutcome': outcome,
        'FreshCandidateEvidence': fresh_candidate, 'ChangedTextLogs': len(changed),
        'BuildOutputsSHA256': artifacts, 'ProductionApproved': False,
        'PhysicalAcceptance': 'NotPerformed', 'DistributionPackageCreated': False,
        'AcceptanceAuthority': 'Iniciar-Validacao.bat /ci (official pipeline only)',
    })
    hashes = {path.relative_to(output).as_posix(): digest(path)
              for path in sorted(output.rglob('*')) if path.is_file() and path != output / 'SHA256.json'}
    write_json(output / 'SHA256.json', hashes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('start', 'collect'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--outcome', choices=('success', 'failure', 'cancelled', 'skipped'), default='skipped')
    args = parser.parse_args()
    try:
        if args.phase == 'start':
            initialize(args.root, args.output)
        else:
            collect(args.root, args.output, args.outcome)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, 'CI evidence failed: ' + str(error) + '\n')
    print('CI evidence ' + args.phase + ': ' + str(args.output))


if __name__ == '__main__':
    main()
