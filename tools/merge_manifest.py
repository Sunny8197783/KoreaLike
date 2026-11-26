"""Merge game/assets/manifest_parts/*.json -> game/assets/ASSET-MANIFEST.json (+ missing lists).
python tools/merge_manifest.py
Items are normalised to {id, path, kind, source, license, status, agent, ...extras}; paths are checked on disk;
the review stage's own changes (renames, splits, re-renders) are applied on top. Missing = spec ids with no file."""
import json, os, re, glob
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'game', 'assets')
PARTS = os.path.join(A, 'manifest_parts')
KEEP = ('json', 'source_file', 'note', 'license_file', 'frames', 'fps', 'loop', 'blend', 'layer', 'color_role', 'pixellab_id', 'pixellab_character_id')
VARIANTS = ['_sansin', '_yongwang', '_chilseong', '_janggun', '_barigongju', '_jeseok_daegam']
OBANG = ['cheong', 'jeok', 'hwang', 'baek', 'heuk']
LICENSE_BAD = re.compile(r'\b(NC|ND|noncommercial|non-commercial|NoDerivs)\b', re.I)


def jl(p):
    return json.load(open(p, encoding='utf-8'))


def exists(rel):
    return os.path.exists(os.path.join(ROOT, rel.rstrip('/')))


def main():
    items, seen, notes = [], {}, []
    for pf in sorted(glob.glob(os.path.join(PARTS, '*.json'))):
        d = jl(pf)
        agent = d.get('agent') or os.path.basename(pf)[:-5]
        for it in d.get('items', []):
            o = {k: it.get(k) for k in ('id', 'path', 'kind', 'source', 'license', 'status')}
            o['agent'] = agent
            for k in KEEP:
                if k in it:
                    o[k] = it[k]
            if 'frame_size' in it or 'frameSize' in it:
                o['frame_size'] = it.get('frame_size') or it.get('frameSize')
            items.append(o)
    # ---- review-stage corrections
    by = {i['id']: i for i in items}
    if 'vfx_hojakdo_talisman' in by:
        i = by.pop('vfx_hojakdo_talisman')
        i.update(id='vfx_hojakdo_sehwa', path='game/assets/vfx/vfx_hojakdo_sehwa.png', json='game/assets/vfx/vfx_hojakdo_sehwa.json',
                 note='renamed from vfx_hojakdo_talisman to the spec id (review)')
        by[i['id']] = i
    for base, n in (('vfx_obanggi_flag', 4), ('vfx_obangjin_pillar', 6)):
        if base in by:
            by[base]['note'] = (by[base].get('note', '') + ' | review: split per colour; base = cheong, use <id>_<colour>').strip(' |')
            by[base]['frames'] = n
            for c in OBANG:
                vid = f'{base}_{c}'
                v = dict(by[base], id=vid, path=f'game/assets/vfx/{vid}.png', json=f'game/assets/vfx/{vid}.json', note=f'{c} variant split by review')
                by[vid] = v
    rerender = ['vfx_jakdu_blades', 'vfx_daejakdu_blades', 'vfx_orb_small', 'vfx_orb_mid', 'vfx_orb_large',
                'vfx_sal_grain_idle', 'vfx_sal_grain_idle_s', 'vfx_sal_grain_idle_l']
    for v in rerender:
        if v in by:
            by[v]['review'] = 're-rendered by review 2026-11-22 (see ASSET-REVIEW.md)'
    # deity variant sheets exported by G5 are not in its part: add them
    for jp in glob.glob(os.path.join(A, 'vfx', '*.json')):
        vid = os.path.basename(jp)[:-5]
        if vid in by:
            continue
        for s in VARIANTS + ['_s', '_l', '_end', '_fill', '_tiles', '_petal']:
            if vid.endswith(s) and vid[:-len(s)] in by:
                b = by[vid[:-len(s)]]
                png = f'game/assets/vfx/{vid}.png'
                by[vid] = dict(b, id=vid, path=png if exists(png) else f'game/assets/vfx/{vid}.json',
                               json=f'game/assets/vfx/{vid}.json', note=f'variant of {b["id"]} (added by review: was on disk, not in part)')
                break
        else:
            png = f'game/assets/vfx/{vid}.png'
            by[vid] = {'id': vid, 'path': png if exists(png) else f'game/assets/vfx/{vid}.json', 'json': f'game/assets/vfx/{vid}.json',
                       'kind': 'vfx', 'source': 'pixelfx', 'license': 'original (project-made; pixelfx tool MIT)',
                       'status': 'unlisted', 'agent': 'review', 'note': 'on disk but in no manifest part'}
    for i in list(by.values()):
        if i['id'] == 'comp_dongja':
            i['note'] = (i.get('note') or '') + ' | review: clone_strike moved to art/_deprecated (canon v1.2 cut)'
    items = sorted(by.values(), key=lambda i: (i.get('kind') or '', i['id']))
    # ---- checks
    problems = []
    for i in items:
        p = i.get('path') or ''
        i['exists'] = bool(p) and exists(p)
        if not i['exists']:
            problems.append(f"{i['id']}: path missing on disk ({p})")
        lic = i.get('license') or ''
        if not lic:
            problems.append(f"{i['id']}: no license")
        elif LICENSE_BAD.search(lic):
            problems.append(f"{i['id']}: license looks NC/ND ({lic})")
    # ---- missing vs specs
    spec = jl(os.path.join(ROOT, 'data', 'art_vfx_list.json'))
    sp_ids = [v[0] for v in spec['vfx']]
    sp_scope = {v[0]: v[11] for v in spec['vfx']}
    missing_vfx = [v for v in sp_ids if not (os.path.exists(os.path.join(A, 'vfx', v + '.json')) or os.path.exists(os.path.join(A, 'vfx', v + '.gdshader')))]
    anim = jl(os.path.join(ROOT, 'data', 'art_anim_specs.json'))
    DIRS = {'4': ['south', 'east', 'north', 'west'], '3': ['south', 'east', 'north'], '2': ['south', 'east'], '1': ['south'], '8': ['south', 'east', 'north', 'west']}
    missing_entities, missing_anims, frame_mismatch = [], {}, {}
    sm = jl(os.path.join(A, 'sprites', 'manifest.json'))['entities']
    for e in anim['entities']:
        eid = e['id']
        if eid not in sm:
            missing_entities.append(f"{eid} ({e.get('scope')})")
            continue
        have = sm[eid].get('anims', {})
        for a in e['anims']:
            name, nf, dirs = a[0], a[1], str(a[2])
            if eid.startswith('overlay_'):
                continue
            need = DIRS.get(dirs, ['south'])
            got = have.get(name, {})
            miss = [d for d in need if not got.get(d)]
            if dirs in ('3', '2'):
                miss = [d for d in miss if d != 'west']  # W = E mirror allowed
            if miss:
                missing_anims.setdefault(eid, []).append(f"{name}[{','.join(miss)}]")
            for d in need:
                if got.get(d) and got[d] != nf:
                    frame_mismatch.setdefault(eid, []).append(f'{name}_{d}:{got[d]}/{nf}')
                    break
    sfx_spec = jl(os.path.join(ROOT, 'data', 'audio_sfx.json'))['sfx']
    sfx_dir = os.listdir(os.path.join(A, 'sfx'))
    missing_sfx = {}
    for e in sfx_spec:
        sid = e['id']
        if e.get('scope') not in (None, 'v1'):
            continue
        ok = any(f == sid + '.ogg' or f.startswith(sid + '__') and f.endswith('.ogg') for f in sfx_dir)
        if not ok:
            missing_sfx.setdefault(e.get('priority', '?'), []).append(sid)
    out = {
        'generated_by': 'tools/merge_manifest.py (review stage, 2026-11-22)',
        'schema': '{id, path, kind, source, license, status, agent, exists, ...}',
        'counts': {'items': len(items), 'by_kind': dict(Counter(i.get('kind') for i in items)),
                   'by_status': dict(Counter(i.get('status') for i in items)), 'by_agent': dict(Counter(i['agent'] for i in items))},
        'problems': problems,
        'missing': {
            'vfx_spec_ids_without_file': missing_vfx,
            'sprite_entities_without_dir': missing_entities,
            'sprite_anims_missing_vs_art_anim_specs': missing_anims,
            'sprite_anim_frame_count_vs_spec': frame_mismatch,
            'sfx_v1_ids_without_ogg_by_priority': missing_sfx,
        },
        'items': items,
    }
    json.dump(out, open(os.path.join(A, 'ASSET-MANIFEST.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(json.dumps(out['counts'], ensure_ascii=False))
    print('problems', len(problems), problems[:15])
    print('missing vfx', missing_vfx)
    print('missing entities', missing_entities)
    print('missing anim entities', len(missing_anims), 'anim gaps', sum(len(v) for v in missing_anims.values()))
    print('sfx missing by priority', {k: len(v) for k, v in missing_sfx.items()}, missing_sfx.get('P0'), missing_sfx.get('P1'))


if __name__ == '__main__':
    main()
