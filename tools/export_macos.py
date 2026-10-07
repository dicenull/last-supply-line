#!/usr/bin/env python3
"""Build an actual release-template app and verify it outside the source tree."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
from export_pack import ROOT, run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    args = parser.parse_args()
    godot = str(Path(args.godot).expanduser().resolve())
    version = run([godot, '--version']).strip()
    if not version.startswith('4.7.'):
        raise RuntimeError('Godot 4.7 is required: ' + version)
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    (build / '.gdignore').touch()
    archive = build / 'MFV03.zip'
    run([godot, '--headless', '--path', str(ROOT), '--export-release', 'macOS', str(archive)])
    with tempfile.TemporaryDirectory(prefix='mfv-macos-release-') as directory:
        isolated = Path(directory)
        run(['/usr/bin/ditto', '-x', '-k', str(archive), str(isolated)], cwd=isolated)
        apps = list(isolated.glob('*.app'))
        if len(apps) != 1:
            raise RuntimeError('Expected exactly one exported app')
        app = apps[0]
        with (app / 'Contents/Info.plist').open('rb') as file:
            info = plistlib.load(file)
        binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
        architectures = run(['/usr/bin/lipo', '-archs', str(binary)], cwd=isolated).strip()
        if not all(arch in architectures.split() for arch in ['arm64', 'x86_64']):
            raise RuntimeError('Release must include both Mac architectures')
        # No project path or external Godot runtime is supplied to this launch.
        run([str(binary), '--headless', '--quit-after', '5'], cwd=isolated)
        # Release templates do not support the editor's --script harness.
        run([str(binary), '--audio-driver', 'Dummy', '--quit-after', '10'], cwd=isolated)
    commit = run(['git', 'rev-parse', 'HEAD']).strip()
    dirty = bool(run(['git', 'status', '--porcelain']).strip())
    manifest = {'godot': version, 'source_commit': commit, 'source_dirty': dirty,
                'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                'bytes': archive.stat().st_size, 'architectures': architectures.split(),
                'runtime': 'official release template', 'requires_godot_runtime': False,
                'startup_checks': 2, 'signed': False, 'notarized': False}
    (build / 'mfv03-macos-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Release:', archive)
    print('SHA-256:', manifest['sha256'])


if __name__ == '__main__':
    main()
