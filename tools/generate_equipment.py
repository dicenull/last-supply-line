#!/usr/bin/env python3
"""Generate 28 current mechanisms plus historical IDs for save compatibility.

Current accessories override representative archetypes; legacy minor variants
remain readable but never appear in new loot, rewards, shops, or the catalog.
"""
import argparse
import csv
import io
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTITIES = json.loads((ROOT / 'data/equipment_identity.json').read_text())
LEVELS = {'secondary': [1, 3, 5, 7, 10], 'protection': list(range(1, 11)),
          'engine': list(range(1, 11)), 'support': [1, 4, 7, 10]}
PROFILES = {
    'secondary': [('balanced', '標準'), ('focus', '長射程'), ('rapid', '速射')],
    'protection': [('balanced', '標準'), ('heavy', '重防護'), ('mobile', '機動')],
    'engine': [('balanced', '標準'), ('power', '高出力'), ('economy', '省燃費')],
    'support': [('balanced', '標準'), ('focus', '高性能'), ('efficient', '省力')],
}
EFFECT_KEYS = ['damage_reduction', 'speed_bonus', 'fuel_bonus', 'range_bonus',
               'turn_bonus', 'reload_bonus', 'splash_bonus', 'salvage_rate',
               'drive_turn_bonus', 'offroad_bonus', 'main_reload_bonus', 'main_range_bonus', 'main_splash_bonus', 'blast_reduction', 'ammo_tax', 'shot_fuel']
PRIMARY = {'armor': ('damage_reduction', .25), 'skirts': ('damage_reduction', .20),
           'supercharger': ('speed_bonus', .20), 'economizer': ('fuel_bonus', -.20),
           'rangefinder': ('range_bonus', 6.0), 'servo': ('turn_bonus', .60),
           'salvage_arm': ('salvage_rate', 1 / 3), 'blast_fuse': ('splash_bonus', 4.0),
           'drum_loader': ('reload_bonus', .20)}


def rounded(value):
    return round(value, 6)


def design(family, base, level, profile, profile_index):
    item = {k: v for k, v in base.items() if k != 'port'}
    original = level == 1 and profile == 'balanced'
    item['id'] = family if original else f'{family}_{profile}_l{level:02d}'
    item.update(family=family, level=level, profile=profile, visual=profile_index)
    label = dict(PROFILES[base['genre']])[profile]
    identity = IDENTITIES[family]
    item['name'] = identity['name'] if original else f'{identity["name"]} {identity["code"]}-{level:02d}{["A", "B", "C"][profile_index]}'
    item['inspiration'] = identity['inspiration']
    item['scrap'] = math.ceil(base['scrap'] * (1 + .07 * (level - 1)))
    item['coal'] = math.ceil(base['coal'] * (1 + .05 * (level - 1)))
    item['shop_price'] = 32 + 4 * (level - 1)
    item['effects'] = {}
    growth = 1 + .025 * (level - 1)
    if base['genre'] == 'secondary':
        rate, reach, turn = {'balanced': (1, 1, 1), 'focus': (1.14, 1.18, .82),
                             'rapid': (.82, .85, 1.15)}[profile]
        item['interval'] = rounded(base['interval'] * rate / growth)
        item['range'] = rounded(base['range'] * reach * (1 + .01 * (level - 1)))
        # Starboard traverse differs from port traverse, even at level one.
        base_turn = base.get('turn', 3.4 if family == 'right_gun' else 3.2)
        item['turn'] = rounded(base_turn * turn * (1 + .02 * (level - 1)))
        if base.get('splash', 0): item['splash'] = rounded(base['splash'] * (1 + .01 * (level - 1)))
        item['effect'] = f'独立給弾 / {label}型 / 装備Lv.{level}'
    else:
        key, value = PRIMARY[family]
        effects = {key: value * growth}
        if family == 'supercharger': effects['fuel_bonus'] = .10
        if base['genre'] == 'protection':
            if profile == 'heavy':
                effects[key] *= 1.12
                effects.update(speed_bonus=-.08, fuel_bonus=.05)
            elif profile == 'mobile':
                effects[key] *= .82
                effects['speed_bonus'] = .04
        elif base['genre'] == 'engine':
            if family == 'supercharger':
                if profile == 'power': effects.update(speed_bonus=effects[key] * 1.18, fuel_bonus=.20)
                elif profile == 'economy': effects.update(speed_bonus=effects[key] * .78, fuel_bonus=.02)
            else:
                if profile == 'power': effects.update(fuel_bonus=effects[key] * .75, speed_bonus=.06)
                elif profile == 'economy': effects.update(fuel_bonus=effects[key] * 1.18, speed_bonus=-.06)
        elif profile != 'balanced':
            focused = profile == 'focus'
            effects[key] *= 1.12 if focused else .82
            secondary = {
                'rangefinder': ('turn_bonus', -.12, .18),
                'servo': ('speed_bonus', -.04, .03),
                'salvage_arm': ('speed_bonus', -.06, .04),
                'blast_fuse': ('reload_bonus', -.06, .04),
                'drum_loader': ('fuel_bonus', .12, -.05),
            }[family]
            effects[secondary[0]] = secondary[1] if focused else secondary[2]
        item['effects'] = {k: v if k == 'salvage_rate' else rounded(v) for k, v in effects.items()}
        item['effect'] = f'{label}型 / 装備Lv.{level}'
    if original: item['effect'] = base['effect']
    return item


def signature(item):
    keys = ['interval', 'range', 'ammo', 'turn', 'splash', 'chain', 'pellets', 'ballistics', 'effects']
    return json.dumps({k: item[k] for k in keys if k in item}, sort_keys=True)


def build():
    archetypes = json.loads((ROOT / 'data/equipment_archetypes.json').read_text())
    items = [design(family, base, level, profile, index)
             for family, base in archetypes.items()
             for level in LEVELS[base['genre']]
             for index, (profile, _) in enumerate(PROFILES[base['genre']])]
    assert len(items) == 300 and len({i['id'] for i in items}) == 300
    assert len({i['name'] for i in items}) == 300
    assert len({signature(i) for i in items}) == 300, 'each design must change actual performance'
    for item in items:
        assert 1 <= item['level'] <= 10 and item['scrap'] > 0 and item['coal'] > 0
        for value in item['effects'].values(): assert math.isfinite(value)
        if item['genre'] == 'secondary':
            assert .4 < item['interval'] < 4 and 15 <= item['range'] <= 65
            assert 1 <= item['ammo'] <= 2 and 2 <= item['turn'] <= 9
    parts = json.loads((ROOT / 'data/vehicle_parts.json').read_text())
    assert len(parts) == 12 and {p['slot'] for p in parts} == {'gear', 'engine', 'tracks', 'cannon'}
    overrides = json.loads((ROOT / 'data/equipment_current.json').read_text())
    for item in items:
        item.update(overrides.get(item['id'], {}))
    items += parts
    assert len({i['id'] for i in items}) == len(items)
    assert len({i['name'] for i in items}) == len(items)
    return archetypes, items


def gd(value):
    if isinstance(value, dict):
        return '{' + ','.join(json.dumps(k, ensure_ascii=False) + ':' + gd(v) for k, v in value.items()) + '}'
    if isinstance(value, list): return '[' + ','.join(gd(v) for v in value) + ']'
    return json.dumps(value, ensure_ascii=False)


def outputs(archetypes, items):
    lines = ['extends RefCounted', '## Generated by tools/generate_equipment.py; edit archetypes or balance rules, then regenerate.',
             '## Active designs are curated; all historical IDs remain readable for old saves.', 'const ITEMS = {']
    for item in items:
        spec = {k: v for k, v in item.items() if k != 'id'}
        lines.append('\t' + gd(item['id']) + ':' + gd(spec) + ',')
    lines += ['}', 'const DEFINITIONS = {']
    for i in items:
        lines.append(f'\t{gd(i["id"])}:{{"genre":{gd(i["genre"])},"size":Vector2i({i["size"][0]},{i["size"][1]})}},')
    lines += ['}', 'const GUN_PORTS = {']
    guns = [i for i in items if i['genre'] == 'secondary']
    for i in guns:
        p = archetypes[i['family']]['port']
        lines.append(f'\t{gd(i["id"])}:Vector2i({p[0]},{p[1]}),')
    lines += ['}', 'const GUNS = ' + gd([i['id'] for i in guns]),
              'const ORIGINAL_IDS = ' + gd(list(archetypes)), '']
    active = [i['id'] for i in items if (i['id'] == i['family'] and i['id'] != 'right_gun') or i.get('slot')]
    lines.insert(-1, 'const ACTIVE_IDS = ' + gd(active))
    fields = ['id', 'name', 'family', 'genre', 'level', 'profile', 'size', 'shop_price', 'scrap', 'coal',
              'interval', 'range', 'ammo', 'turn', 'splash', 'chain', 'pellets', 'damage', 'interceptor'] + EFFECT_KEYS
    sheet = io.StringIO(newline='')
    writer = csv.DictWriter(sheet, fieldnames=fields, lineterminator='\n')
    writer.writeheader()
    for item in items:
        if item['id'] not in active: continue
        row = {k: item.get(k, '') for k in fields}
        row.update(item['effects'])
        row['size'] = 'x'.join(map(str, item['size']))
        writer.writerow(row)
    return {ROOT / 'scripts/equipment_data.gd': '\n'.join(lines),
            ROOT / 'data/equipment_items.csv': sheet.getvalue()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Fail when generated files differ; do not modify files')
    args = parser.parse_args()
    archetypes, items = build()
    for path, text in outputs(archetypes, items).items():
        if args.check:
            if not path.exists() or path.read_text() != text: raise SystemExit(f'Out of date: {path.relative_to(ROOT)}')
        else: path.write_text(text)
    print('EQUIPMENT DATA: 16 current accessories + 12 vehicle parts; 312 save-compatible IDs')


if __name__ == '__main__': main()
