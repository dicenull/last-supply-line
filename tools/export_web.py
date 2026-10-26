#!/usr/bin/env python3
"""Export Godot's single-threaded Web build for Cloudflare Workers Static Assets."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
from export_pack import ROOT, run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--template', type=Path, help='Official web_nothreads_release.zip from matching Godot export templates')
    args = parser.parse_args()
    godot = str(Path(args.godot).expanduser().resolve())
    version = run([godot, '--version']).strip()
    if not version.startswith('4.7.'):
        raise RuntimeError('Godot 4.7 is required: ' + version)
    if (ROOT / 'node_modules').is_dir():
        (ROOT / 'node_modules/.gdignore').touch()
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    (build / '.gdignore').touch()
    template = build / 'web-templates/web_nothreads_release.zip'
    if args.template:
        template.parent.mkdir(parents=True, exist_ok=True)
        if args.template.resolve() != template.resolve():
            shutil.copyfile(args.template, template)
    if not template.is_file():
        raise RuntimeError('Extract web_nothreads_release.zip from the matching official Godot export templates, then pass --template /path/to/web_nothreads_release.zip')
    with zipfile.ZipFile(template) as archive:
        if archive.testzip() is not None or not {'godot.js', 'godot.wasm', 'godot.html'} <= set(archive.namelist()):
            raise RuntimeError('Invalid Web export template')
    # Keep the previous deployable output until a fresh export succeeds.
    staging = build / 'web-staging'
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    run([godot, '--headless', '--path', str(ROOT), '--editor', '--import'])
    output = run([godot, '--headless', '--path', str(ROOT), '--export-release', 'Web', str(staging / 'index.html')])
    (build / 'web-export.log').write_text(output)
    required = ['index.html', 'index.js', 'index.wasm', 'index.pck']
    if any(not (staging / name).is_file() for name in required):
        raise RuntimeError('Incomplete Web export')
    # Workers limits each static asset to 25 MiB. Browsers transparently decode
    # this gzip response before WebAssembly.compileStreaming consumes it.
    wasm = staging / 'index.wasm'
    raw = wasm.read_bytes()
    if raw[:4] != b'\x00asm':
        raise RuntimeError('Invalid WebAssembly module')
    (staging / 'index.wasm.gz').write_bytes(gzip.compress(raw, compresslevel=9, mtime=0))
    wasm.unlink()
    shutil.copyfile(ROOT / 'assets/fonts/OFL.txt', staging / 'NotoSansJP-LICENSE.txt')
    shutil.copyfile(ROOT / 'web/fonts/NotoSansJP.woff2', staging / 'NotoSansJP.woff2')
    files = {}
    for path in sorted(staging.iterdir()):
        if path.stat().st_size > 25 * 1024 * 1024:
            raise RuntimeError(f'Workers asset exceeds 25 MiB: {path.name}')
        files[path.name] = {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    destination = build / 'web'
    if destination.exists():
        shutil.rmtree(destination)
    staging.rename(destination)
    manifest = {'godot': version, 'template_sha256': hashlib.sha256(template.read_bytes()).hexdigest(),
                'thread_support': False, 'wasm_uncompressed_bytes': len(raw), 'files': files,
                'deployment_source_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                    for name in ['cloudflare.config.ts', 'wrangler.config.ts', 'web/worker.js', 'web/shell.html', 'package-lock.json']},
                'source_commit': run(['git', 'rev-parse', 'HEAD']).strip(),
                'source_dirty': bool(run(['git', 'status', '--porcelain']).strip())}
    (build / 'mfv03-web-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.make_archive(str(build / 'MFV03-web'), 'zip', destination)
    print('Web build:', destination)
    print('WASM: %d -> %d bytes (gzip)' % (len(raw), files['index.wasm.gz']['bytes']))
    print('All %d files fit Workers Static Assets limits.' % len(files))


if __name__ == '__main__':
    main()
