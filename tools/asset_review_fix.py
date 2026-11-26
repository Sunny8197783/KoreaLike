"""One-shot mechanical fixes from ASSET-REVIEW 2026-11-22 (idempotent). Backups go to art/_review_backup/.
python tools/asset_review_fix.py vfx      # meta fixes, rename, variant split, reserved-white remap
python tools/asset_review_fix.py sprites  # anim renames to match data/art_anim_specs.json, overlay naming, deprecated anims
"""
import json, os, re, shutil, sys, glob
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'game', 'assets')
VFX = os.path.join(A, 'vfx')
SPR = os.path.join(A, 'sprites')
BK = os.path.join(ROOT, 'art', '_review_backup')
LOG = []


def log(s):
    LOG.append(s)
    print(s)


def jload(p):
    return json.load(open(p, encoding='utf-8'))


def jsave(p, d):
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


def backup(path, sub):
    d = os.path.join(BK, sub)
    os.makedirs(d, exist_ok=True)
    dst = os.path.join(d, os.path.basename(path))
    if not os.path.exists(dst):
        shutil.copy2(path, dst)


def drop_import(png):
    imp = png + '.import'
    if os.path.exists(imp):
        os.remove(imp)


# ---------------------------------------------------------------- VFX
def vfx_meta():
    for jp in sorted(glob.glob(os.path.join(VFX, '*.json'))):
        d = jload(jp)
        if not d.get('frames'):
            continue
        px = d.setdefault('meta', {}).setdefault('pixelfx', {})
        ch = []
        f0 = d['frames'][0]['frame']
        if px.get('frameWidth') is None or px.get('frameHeight') is None:
            fs = px.get('frameSize') or [f0['w'], f0['h']]
            px['frameWidth'], px['frameHeight'] = fs[0], fs[1]
            ch.append('frameWidth/Height')
        if px.get('frameSize') is None:
            px['frameSize'] = [px['frameWidth'], px['frameHeight']]
            ch.append('frameSize')
        if isinstance(px.get('pivot'), dict):
            px['pivot'] = [px['pivot'].get('x', 0), px['pivot'].get('y', 0)]
            ch.append('pivot dict->list')
        if px.get('frames') != len(d['frames']):
            px['frames'] = len(d['frames'])
            ch.append('frames')
        if px.get('id') is None:
            px['id'] = 'korealike/' + os.path.basename(jp)[:-5]
            ch.append('id')
        if ch:
            backup(jp, 'vfx_sheets')
            jsave(jp, d)
            log(f'[vfx meta] {os.path.basename(jp)}: +{", ".join(ch)}')


def relayout(vid, frames_imgs, durations, d, tgt):
    """Write frames as one horizontal row under id tgt, keeping meta."""
    n = len(frames_imgs)
    fw, fh = frames_imgs[0].size
    sheet = Image.new('RGBA', (fw * n, fh), (0, 0, 0, 0))
    fr = []
    for i, im in enumerate(frames_imgs):
        sheet.paste(im, (i * fw, 0))
        fr.append({'filename': f'{tgt} {i}', 'frame': {'x': i * fw, 'y': 0, 'w': fw, 'h': fh}, 'rotated': False,
                   'trimmed': False, 'spriteSourceSize': {'x': 0, 'y': 0, 'w': fw, 'h': fh},
                   'sourceSize': {'w': fw, 'h': fh}, 'duration': durations[i]})
    meta = json.loads(json.dumps(d['meta']))
    meta['image'] = tgt + '.png'
    meta['size'] = {'w': fw * n, 'h': fh}
    meta['frameTags'] = [{'name': tgt, 'from': 0, 'to': n - 1, 'direction': 'forward'}]
    px = meta.setdefault('pixelfx', {})
    px.update({'frames': n, 'frameSize': [fw, fh], 'frameWidth': fw, 'frameHeight': fh, 'columns': n})
    sheet.save(os.path.join(VFX, tgt + '.png'))
    jsave(os.path.join(VFX, tgt + '.json'), {'frames': fr, 'meta': meta})


def crop_frames(vid):
    d = jload(os.path.join(VFX, vid + '.json'))
    im = Image.open(os.path.join(VFX, d['meta'].get('image') or vid + '.png')).convert('RGBA')
    ims, durs = [], []
    for f in d['frames']:
        q = f['frame']
        ims.append(im.crop((q['x'], q['y'], q['x'] + q['w'], q['y'] + q['h'])))
        durs.append(f.get('duration', 83))
    return d, ims, durs


def vfx_rename(old, new):
    jo = os.path.join(VFX, old + '.json')
    if not os.path.exists(jo):
        return
    backup(jo, 'vfx_sheets')
    backup(os.path.join(VFX, old + '.png'), 'vfx_sheets')
    d, ims, durs = crop_frames(old)
    d['meta'].setdefault('pixelfx', {})['renamed_from'] = old
    relayout(old, ims, durs, d, new)
    os.remove(jo)
    os.remove(os.path.join(VFX, old + '.png'))
    drop_import(os.path.join(VFX, old + '.png'))
    log(f'[vfx rename] {old} -> {new} (spec id)')


def vfx_split_tags(vid):
    jp = os.path.join(VFX, vid + '.json')
    d = jload(jp)
    tags = d['meta'].get('frameTags', [])
    if len(tags) <= 1:
        return
    backup(jp, 'vfx_sheets')
    backup(os.path.join(VFX, vid + '.png'), 'vfx_sheets')
    d, ims, durs = crop_frames(vid)
    names = []
    for t in tags:
        tgt = f"{vid}_{t['name']}"
        dd = json.loads(json.dumps(d))
        dd['meta']['pixelfx']['variant'] = t['name']
        relayout(vid, ims[t['from']:t['to'] + 1], durs[t['from']:t['to'] + 1], dd, tgt)
        names.append(tgt)
    t0 = tags[0]
    dd = json.loads(json.dumps(d))
    dd['meta']['pixelfx']['variants'] = names
    dd['meta']['pixelfx']['variant'] = t0['name']
    dd['meta']['pixelfx']['note_review'] = ('ASSET-REVIEW: multi-colour sheet split; VfxLib plays every frame in frames[], '
                                           'so the base id now holds the first colour only. Use <id>_<colour>. '
                                           'Combined sheet archived in art/_review_backup/vfx_sheets/.')
    relayout(vid, ims[t0['from']:t0['to'] + 1], durs[t0['from']:t0['to'] + 1], dd, vid)
    log(f'[vfx split] {vid}: {len(ims)} frames in {len(tags)} colour rows -> base(={t0["name"]}) + {names}')


def vfx_drop_extra_empty(vid, keep):
    d, ims, durs = crop_frames(vid)
    if len(ims) <= keep:
        return
    while len(ims) > keep and not ims[-1].getbbox():
        ims.pop(); durs.pop()
    backup(os.path.join(VFX, vid + '.json'), 'vfx_sheets')
    backup(os.path.join(VFX, vid + '.png'), 'vfx_sheets')
    relayout(vid, ims, durs, d, vid)
    log(f'[vfx frames] {vid}: trimmed extra empty trailing frame(s) -> {len(ims)}')


TINT = {'B': (206, 226, 252), 'R': (255, 224, 196), 'D': (255, 243, 200), 'Y': (255, 243, 200), 'H': (250, 240, 214), 'M': (206, 200, 222)}


def vfx_white_remap():
    spec = jload(os.path.join(ROOT, 'data', 'art_vfx_list.json'))
    SP = {v[0]: dict(zip(spec['tuple'], v)) for v in spec['vfx']}
    for jp in sorted(glob.glob(os.path.join(VFX, '*.json'))):
        vid = os.path.basename(jp)[:-5]
        base = vid
        for s in ['_sansin', '_yongwang', '_chilseong', '_janggun', '_barigongju', '_jeseok_daegam', '_cheong', '_jeok', '_hwang', '_baek', '_heuk', '_s', '_l']:
            if vid.endswith(s) and vid[:-len(s)] in SP:
                base = vid[:-len(s)]
        sp = SP.get(base)
        d = jload(jp)
        if not d.get('frames'):
            continue
        role = (sp or {}).get('color_role') or d['meta'].get('pixelfx', {}).get('color_role') or ''
        if 'W' in role or not role:
            continue
        pp = os.path.join(VFX, d['meta'].get('image') or vid + '.png')
        im = Image.open(pp).convert('RGBA')
        px = im.load()
        tint = TINT.get(role[0], (255, 243, 200))
        n = 0
        for y in range(im.height):
            for x in range(im.width):
                r, g, b, a = px[x, y]
                if a and min(r, g, b) >= 240:
                    px[x, y] = (*tint, a)
                    n += 1
        if n:
            backup(pp, 'vfx_sheets')
            im.save(pp)
            log(f'[vfx palette] {vid} (role {role}): {n} px of near-pure white -> {"#%02x%02x%02x" % tint} (white is reserved for haewon)')


# ---------------------------------------------------------------- sprites
def spec_anims():
    d = jload(os.path.join(ROOT, 'data', 'art_anim_specs.json'))
    return {e['id']: [a[0] for a in e['anims']] for e in d['entities']}


def rename_anim(eid, old, new, why):
    p = os.path.join(SPR, eid)
    if not os.path.isdir(p):
        return 0
    files = [f for f in os.listdir(p) if re.match(rf'^{re.escape(old)}_(south|east|north|west)_\d+\.png$', f)]
    if not files:
        return 0
    if any(f.startswith(new + '_') and re.match(rf'^{re.escape(new)}_(south|east|north|west)_\d+\.png$', f) for f in os.listdir(p)):
        log(f'[sprite] SKIP {eid}: {new}_* already exists')
        return 0
    for f in files:
        os.rename(os.path.join(p, f), os.path.join(p, new + f[len(old):]))
        drop_import(os.path.join(p, f))
    aj = os.path.join(p, 'anims.json')
    if os.path.exists(aj):
        d = jload(aj)
        for k in ('anims', 'frame_size'):
            if isinstance(d.get(k), dict) and old in d[k]:
                d[k][new] = d[k].pop(old)
        jsave(aj, d)
    log(f'[sprite rename] {eid}: {old}_* -> {new}_* ({len(files)} files; {why})')
    return len(files)


def sprites():
    sp = spec_anims()
    # locomotion name must match the per-entity spec (data/art_anim_specs.json)
    for eid in sorted(os.listdir(SPR)):
        p = os.path.join(SPR, eid)
        if not os.path.isdir(p):
            continue
        base = eid.split('__')[0]
        want = sp.get(base)
        if not want:
            continue
        have = {m.group(1) for f in os.listdir(p) for m in [re.match(r'^([a-z0-9_]+?)_(south|east|north|west)_\d+\.png$', f)] if m}
        loco = [a for a in ('walk', 'move', 'float', 'glide', 'run', 'chase') if a in want]
        if not loco:
            continue
        target = loco[0]
        if target in have:
            continue
        for cand in ('walk', 'move', 'glide', 'float', 'chase'):
            if cand in have and cand not in want:
                rename_anim(eid, cand, target, f'spec locomotion name is "{target}"')
                break
        # bulgasari stage variants: absorb -> spec name is absorb_s<size>
    # comp_dongja.clone_strike was cut by canon v1.2 (D-27/C-28): move out of runtime
    p = os.path.join(SPR, 'comp_dongja')
    dep = os.path.join(ROOT, 'art', '_deprecated', 'comp_dongja')
    moved = 0
    for f in sorted(os.listdir(p)) if os.path.isdir(p) else []:
        if f.startswith('clone_strike_') and f.endswith('.png'):
            os.makedirs(dep, exist_ok=True)
            shutil.move(os.path.join(p, f), os.path.join(dep, f))
            drop_import(os.path.join(p, f))
            moved += 1
    if moved:
        aj = os.path.join(p, 'anims.json')
        if os.path.exists(aj):
            d = jload(aj)
            for k in ('anims', 'frame_size'):
                if isinstance(d.get(k), dict):
                    d[k].pop('clone_strike', None)
            jsave(aj, d)
        log(f'[sprite deprecate] comp_dongja: clone_strike ({moved} files) -> art/_deprecated/comp_dongja/ (canon v1.2 D-27/C-28 cut it)')
    # overlays: <deity>_<face>_<dir>.png -> <deity>_<face>_<dir>_0.png (<anim>_<dir>_<n> rule)
    for ov in ('overlay_head', 'overlay_jimul'):
        p = os.path.join(SPR, ov)
        if not os.path.isdir(p):
            continue
        n = 0
        for f in sorted(os.listdir(p)):
            m = re.match(r'^([a-z0-9_]+)_(south|east|north|west)\.png$', f)
            if m:
                os.rename(os.path.join(p, f), os.path.join(p, f'{m.group(1)}_{m.group(2)}_0.png'))
                drop_import(os.path.join(p, f))
                n += 1
        if n:
            log(f'[sprite rename] {ov}: {n} files <variant>_<dir>.png -> <variant>_<dir>_0.png (anim = variant id)')


def refresh_sprite_manifest():
    sys.path.insert(0, os.path.join(ROOT, 'tools'))
    import sync_art
    mp = os.path.join(SPR, 'manifest.json')
    m = jload(mp)
    sync_art.rescan_sprites(m)
    for k in list(m['entities']):
        if not os.path.isdir(os.path.join(SPR, k)):
            m['entities'].pop(k)
    m['vfx'] = sorted(os.path.basename(j)[:-5] for j in glob.glob(os.path.join(VFX, '*.json'))
                      if (jload(j).get('frames')))
    jsave(mp, m)
    log(f'[manifest] sprites/manifest.json rescanned: {len(m["entities"])} entities, {len(m["vfx"])} vfx sheets')


if __name__ == '__main__':
    what = sys.argv[1]
    if what == 'vfx':
        vfx_meta()
        vfx_rename('vfx_hojakdo_talisman', 'vfx_hojakdo_sehwa')
        vfx_split_tags('vfx_obanggi_flag')
        vfx_split_tags('vfx_obangjin_pillar')
        vfx_drop_extra_empty('vfx_go_maedeup_untie', 8)
        vfx_white_remap()
    elif what == 'sprites':
        sprites()
    elif what == 'manifest':
        refresh_sprite_manifest()
    os.makedirs(os.path.join(A, '_review'), exist_ok=True)
    with open(os.path.join(A, '_review', f'fixlog_{what}.txt'), 'a', encoding='utf-8') as fh:
        fh.write('\n'.join(LOG) + '\n')
