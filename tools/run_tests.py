#!/usr/bin/env python3
"""Run native regressions with bounded parallelism and isolated visual suites."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
HEADLESS = (
    'factory', 'run', 'checkpoint', 'supply_recovery', 'soak', 'expansion',
    'enemy_roles', 'balance', 'tank_steering', 'local_damage', 'armor_block',
    'ballistics', 'feedback', 'arsenal_feedback', 'vehicle_collision',
    'course_goal', 'supply_point', 'resource_storage', 'course_obstacles',
    'field_course', 'ui_architecture', 'campaign_variety', 'equipment_catalog',
    'inventory_model', 'factory_layout', 'equipment_geometry', 'equipment_save',
    'equipment_campaign', 'equipment_inventory', 'equipment_feed',
    'equipment_feedback', 'equipment_bulk', 'equipment_pilot',
)
VISUAL = (
    'menu_pages', 'field_landscape', 'field_surface', 'field_services',
    'pipe_connections', 'placement_preview', 'tank_ui', 'battle', 'run_ui',
    'item_rewards', 'research', 'auxiliary_ports', 'menu', 'history', 'blueprint',
    'variety', 'logistics', 'audio', 'window', 'content_ui', 'phase_movement',
    'equipment_ui', 'footer_tools', 'equipment_audio',
)
# These need their own invocation or are aliases; never silently count them twice.
SPECIAL = {'crafting', 'exit_save', 'overnight_soak', 'pack_smoke'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--suite', action='append', choices=HEADLESS + VISUAL, help='Select one suite; repeat for related regressions')
    parser.add_argument('--headless-only', action='store_true')
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=2, help='Parallel headless processes; visual tests remain serial')
    parser.add_argument('--timeout', type=float, default=180, help='Seconds per suite')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/test-results')
    parser.add_argument('--list', action='store_true')
    args = parser.parse_args()
    discovered = {p.name.removesuffix('_test.gd') for p in (ROOT / 'tests').glob('*_test.gd')}
    missing = discovered - set(HEADLESS + VISUAL) - SPECIAL
    if missing:
        parser.error('Classify new suites before running: ' + ', '.join(sorted(missing)))
    chosen = set(args.suite or (HEADLESS if args.headless_only else HEADLESS + VISUAL))
    if args.headless_only and chosen.intersection(VISUAL):
        parser.error('Selected suites require a real display')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    if args.list:
        for name in HEADLESS + VISUAL:
            if name in chosen: print(name, 'headless' if name in HEADLESS else 'display')
        return 0
    godot = shutil.which(args.godot) or str(Path(args.godot).expanduser())
    if not Path(godot).is_file():
        parser.error('Godot executable not found; pass --godot /path/to/Godot')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/.gdignore').touch()
    version = subprocess.run([godot, '--version'], capture_output=True, text=True, check=True).stdout.strip()
    with (output / 'import.log').open('w') as log:
        imported = subprocess.run([godot, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'],
                                  stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
    import_text = (output / 'import.log').read_text(errors='replace')
    if imported.returncode or 'ERROR:' in import_text:
        print('Godot import failed; see', output / 'import.log')
        return 1
    started = datetime.now(timezone.utc).isoformat()
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ['scripts', 'scenes', 'tests'] for p in sorted((ROOT / folder).rglob('*'))
              if p.is_file() and p.suffix in {'.gd', '.tscn'}}
    for name in ['main.tscn', 'project.godot']:
        hashes[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    (output / 'source-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')

    def run(name):
        command = [godot] + (['--headless'] if name in HEADLESS else [])
        command += ['--path', str(ROOT), '--script', 'res://tests/' + name + '_test.gd']
        before = time.monotonic()
        with (output / (name + '.log')).open('w') as log:
            try:
                code = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout).returncode
            except subprocess.TimeoutExpired:
                code = 'timeout'
        text = (output / (name + '.log')).read_text(errors='replace')
        match = re.search(r'RESULT: (\d+) checks, (\d+) failures', text)
        errors = [line for line in text.splitlines() if 'ERROR:' in line or 'instances were leaked' in line]
        ok = code == 0 and match is not None and int(match[2]) == 0 and not errors
        result = {'suite': name, 'passed': ok, 'exit': code,
                  'checks': int(match[1]) if match else 0,
                  'seconds': round(time.monotonic() - before, 2), 'errors': errors}
        print(json.dumps(result), flush=True)
        return result

    results = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for result in pool.map(run, [name for name in HEADLESS if name in chosen]):
            results.append(result)
    for name in VISUAL:
        if name in chosen: results.append(run(name))
    changed = [name for name, digest in hashes.items()
               if not (ROOT / name).is_file() or hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
    summary = {'started_utc': started, 'finished_utc': datetime.now(timezone.utc).isoformat(), 'godot': version,
               'suites': len(results), 'checks': sum(r['checks'] for r in results),
               'failures': sum(not r['passed'] for r in results),
               'changed_sources': changed, 'results': results}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('NATIVE RESULT: %d suites, %d checks, %d failed suites' % (summary['suites'], summary['checks'], summary['failures']))
    if changed: print('Source files changed during the run; see summary.json')
    return 1 if summary['failures'] or changed else 0


if __name__ == '__main__':
    raise SystemExit(main())
