"""Asset audit for KoreaLike: VFX sheet/JSON meta checks + palette reservation + sprites dir checks.
Usage: python tools/asset_audit.py  -> writes game/assets/_review/audit.json"""
import json, os, re, glob
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'game', 'assets')
spec = json.load(open(os.path.join(ROOT, 'data', 'art_vfx_list.json'), encoding='utf-8'))
T = spec['tuple']
SPEC = {v[0]: dict(zip(T, v)) for v in spec['vfx']}
BK = (0xf2, 0xec, 0xe0)
VARIANT_SFX = ['_sansin', '_yongwang', '_chilseong', '_janggun', '_barigongju', '_jeseok_daegam']


def near(c, ref, tol=6):
    return all(abs(a - b) <= tol for a, b in zip(c, ref))


def spec_of(vid):
    if vid in SPEC:
        return SPEC[vid]
    for s in VARIANT_SFX:
        if vid.endswith(s) and vid[:-len(s)] in SPEC:
            return SPEC[vid[:-len(s)]]
    return None


def audit_vfx():
    res = {}
    for jp in sorted(glob.glob(os.path.join(A, 'vfx', '*.json'))):
        vid = os.path.basename(jp)[:-5]
        r = {'issues': []}
        raw = open(jp, 'rb').read()
        try:
            d = json.loads(raw.decode('utf-8'))
        except Exception as e:
            r['issues'].append(f'json parse: {e}')
            res[vid] = r
            continue
        if b'\xef\xbf\xbd' in raw:
            r['issues'].append('mojibake U+FFFD in json')
        m = d.get('meta', {})
        px = m.get('pixelfx', {})
        if 'frames' not in d:
            r['kind'] = 'shader' if os.path.exists(os.path.join(A, 'vfx', vid + '.gdshader')) else 'meta-only'
            res[vid] = r
            continue
        r['kind'] = 'sheet'
        png = os.path.join(A, 'vfx', m.get('image') or (vid + '.png'))
        if not os.path.exists(png):
            r['issues'].append('png missing')
            res[vid] = r
            continue
        im = Image.open(png).convert('RGBA')
        W, H = im.size
        fr = d['frames']
        n = len(fr)
        r.update(n=n, size=[W, H], fps=px.get('fps'), loop=px.get('loop'), pivot=px.get('pivot'),
                 columns=px.get('columns'))
        fs = px.get('frameSize') or [None, None]
        fw = px.get('frameWidth') or fs[0] or (fr[0]['frame']['w'] if fr else None)
        fh = px.get('frameHeight') or fs[1] or (fr[0]['frame']['h'] if fr else None)
        for k in ['fps', 'loop', 'columns', 'pivot']:
            if px.get(k) is None:
                r['issues'].append(f'meta.pixelfx.{k} missing')
        if px.get('frameWidth') is None or px.get('frameHeight') is None:
            r['issues'].append('frameWidth/Height missing')
        r['fw'], r['fh'] = fw, fh
        gc = W // fw
        cells = gc * (H // fh)
        cols = px.get('columns')
        if cols and cols != gc:
            r['issues'].append(f'columns {cols} != sheetW/fw {gc}')
        if W % fw or H % fh:
            r['issues'].append(f'sheet {W}x{H} not multiple of {fw}x{fh}')
        if px.get('frames') is not None and px['frames'] != n:
            r['issues'].append(f'meta.frames {px["frames"]} != frames[] {n}')
        for i, f in enumerate(fr):
            q = f['frame']
            if q['w'] != fw or q['h'] != fh:
                r['issues'].append(f'frame{i} size {q["w"]}x{q["h"]}')
                break
            if q['x'] + q['w'] > W or q['y'] + q['h'] > H:
                r['issues'].append(f'frame{i} out of sheet')
                break
            if q['x'] % fw or q['y'] % fh:
                r['issues'].append(f'frame{i} misaligned')
                break
            exp = ((i % gc) * fw, (i // gc) * fh)
            if (q['x'], q['y']) != exp and not r.get('nonlinear'):
                r['nonlinear'] = True
        if cells > n:
            extra = 0
            for c in range(n, cells):
                x, y = (c % gc) * fw, (c // gc) * fh
                if im.crop((x, y, x + fw, y + fh)).getbbox():
                    extra += 1
            if extra:
                r['issues'].append(f'{extra} non-empty cells beyond frames[] (cells={cells}, n={n})')
        empties = []
        counts = []
        bboxes = []
        for i, f in enumerate(fr):
            q = f['frame']
            c = im.crop((q['x'], q['y'], q['x'] + fw, q['y'] + fh))
            a = c.getchannel('A')
            cnt = sum(1 for v in a.get_flattened_data() if v > 0)
            counts.append(cnt)
            bboxes.append(c.getbbox())
            if cnt == 0:
                empties.append(i)
        r['px_counts'] = counts
        r['empty_frames'] = empties
        if empties and empties != [n - 1]:
            r['issues'].append(f'empty frames {empties}')
        pv = px.get('pivot')
        if isinstance(pv, dict):
            r['issues'].append('pivot is dict (expected [x,y])')
            pv = [pv.get('x', 0), pv.get('y', 0)]
        if pv and not (0 <= pv[0] <= fw and 0 <= pv[1] <= fh):
            r['issues'].append(f'pivot {pv} outside frame')
        # first-frame impact: frame0 px vs max
        if counts and max(counts):
            r['f0_ratio'] = round(counts[0] / max(counts), 2)
        sp = spec_of(vid)
        if sp:
            r['spec'] = [sp['canvas'], sp['frames'], sp['timing'], sp['color_role'], sp['max_concurrent'], sp['category']]
            if re.match(r'^\d+x\d+$', str(sp['canvas'])):
                cw, chh = map(int, sp['canvas'].split('x'))
                if (cw, chh) != (fw, fh):
                    r['issues'].append(f'canvas {fw}x{fh} != spec {sp["canvas"]}')
            nonempty = n - (1 if empties == [n - 1] and n > 1 else 0)
            r['trailing_empty'] = (empties == [n - 1] and n > 1)
            if nonempty != sp['frames'] and n != sp['frames']:
                r['issues'].append(f'frames {nonempty}(+{n - nonempty} empty) != spec {sp["frames"]}')
            mt = re.match(r'fps:(\d+)', str(sp['timing']))
            if mt and px.get('fps') and int(mt.group(1)) != px['fps']:
                r['issues'].append(f'fps {px["fps"]} != spec {mt.group(1)}')
        data = list(im.get_flattened_data())
        corners = [im.getpixel((0, 0)), im.getpixel((W - 1, 0)), im.getpixel((0, H - 1)), im.getpixel((W - 1, H - 1))]
        if all(c[3] == 255 for c in corners):
            r['issues'].append('opaque corners (background not transparent?)')
        bk = sum(1 for p in data if p[3] > 0 and near(p[:3], BK, 4))
        white = sum(1 for p in data if p[3] > 0 and min(p[:3]) >= 248)
        r['bk_px'] = bk
        r['white_px'] = white
        role = (sp or {}).get('color_role') or px.get('color_role') or ''
        r['role'] = role
        if bk and 'W' not in role:
            r['issues'].append(f'reserved bk #f2ece0 used {bk}px in role {role}')
        res[vid] = r
    return res


def audit_sprites():
    res = {}
    for sd in sorted(glob.glob(os.path.join(A, 'sprites', '*'))):
        if not os.path.isdir(sd):
            continue
        eid = os.path.basename(sd)
        files = sorted(os.listdir(sd))
        pngs = [f for f in files if f.endswith('.png')]
        s = {'n_png': len(pngs), 'issues': []}
        for dname in ['south', 'east', 'north', 'west']:
            if dname + '.png' not in pngs:
                s['issues'].append(f'missing {dname}.png')
        bad = [f for f in pngs if not re.match(r'^(south|east|north|west)\.png$|^[a-z0-9_]+_(south|east|north|west)_\d+\.png$', f)]
        if bad:
            s['issues'].append(f'nonconforming names ({len(bad)}): {bad[:10]}')
        s['nonconforming'] = bad
        anims = {}
        for f in pngs:
            mm = re.match(r'^([a-z0-9_]+?)_(south|east|north|west)_(\d+)\.png$', f)
            if mm:
                anims.setdefault(mm.group(1), {}).setdefault(mm.group(2), []).append(int(mm.group(3)))
        s['anims'] = {k: {dd: len(v) for dd, v in vv.items()} for k, vv in anims.items()}
        for k, vv in anims.items():
            for dd, v in vv.items():
                if sorted(v) != list(range(len(v))):
                    s['issues'].append(f'{k}_{dd} frame gap {sorted(v)}')
        sizes = {}
        for f in pngs:
            try:
                sz = Image.open(os.path.join(sd, f)).size
                sizes.setdefault(sz, 0)
                sizes[sz] += 1
            except Exception:
                s['issues'].append(f'bad png {f}')
        s['sizes'] = {f'{a}x{b}': c for (a, b), c in sizes.items()}
        s['other'] = [f for f in files if not f.endswith('.png') and not f.endswith('.import')]
        subdirs = [f for f in files if os.path.isdir(os.path.join(sd, f))]
        if subdirs:
            s['subdirs'] = subdirs
        res[eid] = s
    return res


if __name__ == '__main__':
    out = {'vfx': audit_vfx(), 'sprites': audit_sprites()}
    seen = set(out['vfx'])
    out['missing_spec_ids'] = [k for k in SPEC if k not in seen and not os.path.exists(os.path.join(A, 'vfx', k + '.gdshader'))]
    out['shader_only'] = [k for k in SPEC if k not in seen and os.path.exists(os.path.join(A, 'vfx', k + '.gdshader'))]
    out['extra_ids'] = [k for k in seen if spec_of(k) is None]
    os.makedirs(os.path.join(A, '_review'), exist_ok=True)
    json.dump(out, open(os.path.join(A, '_review', 'audit.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    iss = {k: v['issues'] for k, v in out['vfx'].items() if v['issues']}
    print('vfx json:', len(out['vfx']), 'with issues:', len(iss))
    for k, v in iss.items():
        print(' ', k, '|', '; '.join(v))
    print('missing spec ids:', out['missing_spec_ids'])
    print('shader-only:', out['shader_only'])
    print('extra ids:', out['extra_ids'])
    print('sprites:', len(out['sprites']))
    for k, v in out['sprites'].items():
        if v['issues']:
            print(' ', k, '|', '; '.join(v['issues'])[:400])
