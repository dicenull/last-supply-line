#!/usr/bin/env python3
"""Export and independently launch the pack without relying on loose project assets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    if result.returncode or 'ERROR:' in output or 'instances were leaked' in output:
        raise RuntimeError(output)
    return output

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, help='Godot 4.7 executable')
    args = parser.parse_args()
    executable = str(Path(args.godot).expanduser().resolve())
    version = run([executable, '--version']).strip()
    if not version.startswith('4.7.'):
        raise RuntimeError('This project targets Godot 4.7: ' + version)
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    (build / ".gdignore").touch()
    pack = build / 'mfv03.pck'
    run([executable, '--headless', '--path', str(ROOT), '--export-pack', 'macOS', str(pack)])
    with tempfile.TemporaryDirectory(prefix='mfv-isolated-pack-') as directory:
        isolated = Path(directory)
        shutil.copyfile(ROOT / 'tests/pack_smoke_test.gd', isolated / 'check.gd')
        output = run([executable, '--headless', '--path', str(isolated), '--main-pack', str(pack),
                      '--script', str(isolated / 'check.gd')], cwd=isolated)
    result = re.search(r'PACK RESULT: (\d+) checks, 0 failures', output)
    if not result:
        raise RuntimeError('Packed build did not finish its verification: ' + output)
    commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True)
    status = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT, capture_output=True, text=True)
    manifest = {'godot': version, 'sha256': hashlib.sha256(pack.read_bytes()).hexdigest(),
                'bytes': pack.stat().st_size, 'checks': int(result.group(1)),
                'requires_godot_runtime': True,
                'source_commit': commit.stdout.strip() if commit.returncode == 0 else None,
                'source_dirty': bool(status.stdout) if status.returncode == 0 else None}
    (build / 'mfv03-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(result.group(0))
    print('Pack:', pack)
    print('SHA-256:', manifest['sha256'])

if __name__ == '__main__':
    main()
