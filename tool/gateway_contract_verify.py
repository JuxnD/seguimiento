"""Verify the pinned four-file PHP contract; never calls provider or backend."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / 'test/fixtures/gateway_contract'
FILES = frozenset((
    'app/services/SeguimientoAssistantService.php',
    'app/services/SeguimientoAiService.php',
    'app/services/SeguimientoAiTransport.php',
    'scripts/seguimiento_estimate_test.php',
))


def verify(bundle=BUNDLE, source=None):
    bundle = Path(bundle)
    errors = []
    try:
        manifest = json.loads((bundle / 'manifest.json').read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return ['MANIFEST_INVALID']
    if not isinstance(manifest, dict) or set(manifest) != {
            'contract', 'source_commit', 'reviewed_head', 'files'}:
        return ['MANIFEST_INVALID']
    hashes = manifest['files']
    if (manifest['contract'] != 2 or not isinstance(hashes, dict)
            or set(hashes) != FILES
            or any(not isinstance(v, str) or not re.fullmatch('[a-f0-9]{64}', v)
                   for v in hashes.values())
            or any(not isinstance(manifest[k], str)
                   or not re.fullmatch('[a-f0-9]{40}', manifest[k])
                   for k in ('source_commit', 'reviewed_head'))):
        return ['MANIFEST_INVALID']
    actual = {p.relative_to(bundle).as_posix() for p in bundle.rglob('*') if p.is_file()}
    for name in sorted(actual - FILES - {'manifest.json'}):
        errors.append('EXTRA:' + name)
    for name in sorted(FILES):
        path = bundle / name
        if not path.is_file():
            errors.append('MISSING:' + name)
        elif path.is_symlink() or any(p.is_symlink() for p in path.parents if p != bundle.parent):
            errors.append('SYMLINK:' + name)
        elif hashlib.sha256(path.read_bytes()).hexdigest() != hashes[name]:
            errors.append('HASH:' + name)
    if source is not None:
        # Git blobs give platform-independent exact bytes: working copies may
        # have native CRLF. Clean scoped checkout is required before comparing.
        try:
            def git(*args):
                return subprocess.check_output(['git', '-C', str(source), *args], stderr=subprocess.DEVNULL)
            if git('rev-parse', 'HEAD').decode().strip() != manifest['reviewed_head']:
                errors.append('SOURCE_HEAD')
            if git('status', '--porcelain', '--', *sorted(FILES)):
                errors.append('SOURCE_DIRTY')
            for name in sorted(FILES):
                raw = git('show', manifest['source_commit'] + ':' + name)
                if hashlib.sha256(raw).hexdigest() != hashes[name]:
                    errors.append('SOURCE_HASH:' + name)
                current = git('show', 'HEAD:' + name)
                if raw != current:
                    errors.append('SOURCE_DRIFT:' + name)
        except (OSError, subprocess.CalledProcessError):
            errors.append('SOURCE_UNAVAILABLE')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, default=BUNDLE)
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    errors = verify(args.bundle, args.source)
    print(json.dumps({'status': 'FAIL' if errors else 'PASS', 'errors': errors}))
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
