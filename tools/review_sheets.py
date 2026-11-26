"""Review contact sheets for KoreaLike assets.
python tools/review_sheets.py vfx      -> game/assets/_review/vfx_<category>.png (all frames in a row per effect)
python tools/review_sheets.py crowd    -> game/assets/_review/crowd_<n>.png (hundreds of instances over ink/hanji ground)
python tools/review_sheets.py sprites  -> game/assets/_review/sprites_<group>.png (4 dirs + first frame of each anim)
python tools/review_sheets.py one <vfx_id> [scale] -> _review/one_<id>.png
"""
import json, os, sys, glob, random
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'game', 'assets')
OUT = os.path.join(A, '_review')
os.makedirs(OUT, exist_ok=True)
INK = (14, 11, 22, 255)
HANJI_GROUND = (58, 50, 44, 255)
spec = json.load(open(os.path.join(ROOT, 'data', 'art_vfx_list.json'), encoding='utf-8'))
SPEC = {v[0]: dict(zip(spec['tuple'], v)) for v in spec['vfx']}
try:
    FONT = ImageFont.truetype(os.path.join(A, 'fonts', 'galmuri', 'Galmuri9.ttf'), 10)
except Exception:
    FONT = ImageFont.load_default()


def load_fx(vid):
    VD = os.environ.get('VFX_DIR') or os.path.join(A, 'vfx')
    jp = os.path.join(VD, vid + '.json')
    d = json.load(open(jp, encoding='utf-8'))
    if not d.get('frames'):
        return None
    im = Image.open(os.path.join(VD, d['meta'].get('image') or vid + '.png')).convert('RGBA')
    frames = [im.crop((f['frame']['x'], f['frame']['y'], f['frame']['x'] + f['frame']['w'], f['frame']['y'] + f['frame']['h'])) for f in d['frames']]
    px = d['meta'].get('pixelfx', {})
    return frames, px, d


def scale_for(w, h):
    m = max(w, h)
    return 6 if m <= 12 else 4 if m <= 24 else 3 if m <= 48 else 2 if m <= 128 else 1


def strip(vid, maxw=1800, bg=INK):
    r = load_fx(vid)
    if not r:
        return None
    frames, px, d = r
    fw, fh = frames[0].size
    s = scale_for(fw, fh)
    pad = 4
    cw, ch = fw * s + pad, fh * s + pad
    n = len(frames)
    per_row = max(1, min(n, (maxw - 8) // cw))
    rows = (n + per_row - 1) // per_row
    W = max(per_row * cw + 8, 360)
    H = rows * ch + 30
    img = Image.new('RGBA', (W, H), (40, 36, 48, 255))
    dr = ImageDraw.Draw(img)
    sp = SPEC.get(vid, {})
    label = f"{vid}  {fw}x{fh} n={n} fps={px.get('fps')} loop={px.get('loop')} pv={px.get('pivot')} role={sp.get('color_role', px.get('color_role'))} blend={sp.get('blend', px.get('blend'))} max={sp.get('max_concurrent')}"
    dr.text((4, 2), label, fill=(233, 220, 192, 255), font=FONT)
    pv = px.get('pivot')
    if isinstance(pv, dict):
        pv = [pv.get('x', 0), pv.get('y', 0)]
    for i, f in enumerate(frames):
        x, y = 4 + (i % per_row) * cw, 16 + (i // per_row) * ch
        cell = Image.new('RGBA', (fw * s, fh * s), bg)
        big = f.resize((fw * s, fh * s), Image.NEAREST)
        cell.alpha_composite(big)
        img.paste(cell, (x, y))
        dr.rectangle([x - 1, y - 1, x + fw * s, y + fh * s], outline=(90, 80, 100, 255))
        if pv:
            px_, py_ = x + int(pv[0] * s), y + int(pv[1] * s)
            dr.line([px_ - 2, py_, px_ + 2, py_], fill=(0, 255, 120, 255))
            dr.line([px_, py_ - 2, px_, py_ + 2], fill=(0, 255, 120, 255))
    return img


def stack(imgs, out):
    imgs = [i for i in imgs if i is not None]
    if not imgs:
        return
    W = max(i.width for i in imgs)
    H = sum(i.height + 2 for i in imgs)
    sheet = Image.new('RGBA', (W, H), (24, 20, 30, 255))
    y = 0
    for i in imgs:
        sheet.paste(i, (0, y))
        y += i.height + 2
    sheet.save(out)
    print(out, sheet.size)


def ids_by_category():
    cats = {}
    for jp in sorted(glob.glob(os.path.join(A, 'vfx', '*.json'))):
        vid = os.path.basename(jp)[:-5]
        base = vid
        for s in ['_sansin', '_yongwang', '_chilseong', '_janggun', '_barigongju', '_jeseok_daegam']:
            if vid.endswith(s):
                base = None
        if base is None:
            continue
        sp = SPEC.get(vid)
        cat = sp['category'] if sp else 'extra'
        cats.setdefault(cat, []).append(vid)
    return cats


def do_vfx():
    cats = ids_by_category()
    for cat, ids in cats.items():
        # split long categories into chunks to keep images readable
        chunk = 8
        for k in range(0, len(ids), chunk):
            stack([strip(v) for v in ids[k:k + chunk]], os.path.join(OUT, f'vfx_{cat}_{k // chunk}.png'))


def crowd(ids, out, n_each=60, size=(640, 360), ground=INK, seed=1, frame='mid'):
    rnd = random.Random(seed)
    img = Image.new('RGBA', size, ground)
    # fake ground texture dots
    dr = ImageDraw.Draw(img)
    for _ in range(900):
        x, y = rnd.randrange(size[0]), rnd.randrange(size[1])
        dr.point((x, y), fill=(ground[0] + 10, ground[1] + 9, ground[2] + 8, 255))
    for vid in ids:
        r = load_fx(vid)
        if not r:
            continue
        frames = [f for f in r[0] if f.getbbox()]
        for _ in range(n_each):
            f = rnd.choice(frames) if frame == 'rand' else frames[0]
            x, y = rnd.randrange(-8, size[0]), rnd.randrange(-8, size[1])
            img.alpha_composite(f, (x, y)) if x >= 0 and y >= 0 else None
    img = img.resize((size[0] * 2, size[1] * 2), Image.NEAREST)
    img.save(out)
    print(out)


def do_sprites():
    root = os.path.join(A, 'sprites')
    groups = {}
    for d in sorted(os.listdir(root)):
        p = os.path.join(root, d)
        if not os.path.isdir(p):
            continue
        g = d.split('_')[0]
        groups.setdefault(g, []).append(d)
    for g, ents in groups.items():
        rows = []
        for e in ents:
            p = os.path.join(root, e)
            files = sorted(f for f in os.listdir(p) if f.endswith('.png'))
            pick = [f for f in ['south.png', 'east.png', 'north.png', 'west.png'] if f in files]
            anims = sorted({f.rsplit('_', 2)[0] for f in files if f.count('_') >= 2 and f.rsplit('_', 2)[1] in ('south', 'east', 'north', 'west')})
            for a in anims:
                for dd in ('south', 'east'):
                    fr = sorted([f for f in files if f.startswith(a + '_' + dd + '_')], key=lambda s: int(s.rsplit('_', 1)[1][:-4]))
                    if fr:
                        pick.append(fr[len(fr) // 2])
                        break
            if not pick:
                pick = files[:12]
            ims = [Image.open(os.path.join(p, f)).convert('RGBA') for f in pick[:16]]
            mh = max(i.height for i in ims)
            s = 2 if mh <= 100 else 1
            W = sum(i.width * s + 4 for i in ims) + 8
            row = Image.new('RGBA', (max(W, 300), mh * s + 26), (40, 36, 48, 255))
            dr = ImageDraw.Draw(row)
            dr.text((4, 2), f'{e}: ' + ' '.join(x[:-4] for x in pick[:16]), fill=(233, 220, 192, 255), font=FONT)
            x = 4
            for im in ims:
                cell = Image.new('RGBA', (im.width * s, im.height * s), (78, 68, 58, 255))
                cell.alpha_composite(im.resize((im.width * s, im.height * s), Image.NEAREST))
                row.paste(cell, (x, 16 + (mh * s - im.height * s)))
                x += im.width * s + 4
            rows.append(row)
        for k in range(0, len(rows), 6):
            stack(rows[k:k + 6], os.path.join(OUT, f'sprites_{g}_{k // 6}.png'))


if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'vfx':
        do_vfx()
    elif mode == 'sprites':
        do_sprites()
    elif mode == 'one':
        stack([strip(sys.argv[2])], os.path.join(OUT, f'one_{sys.argv[2]}.png'))
    elif mode == 'crowd':
        crowd(['vfx_sinkal_proj', 'vfx_orb_small', 'vfx_orb_mid', 'vfx_sal_grain_idle', 'vfx_cheonyeo_bullet', 'vfx_samjichang_mark', 'vfx_toechi_burst', 'vfx_pullil_enter'],
              os.path.join(OUT, 'crowd_mixed.png'), n_each=45, frame='rand')
        crowd(['vfx_sinkal_proj', 'vfx_manwoldo_crescent', 'vfx_gakgung_arrow', 'vfx_jusahwajeon_arrow', 'vfx_toechi_burst', 'vfx_gakgung_hit'],
              os.path.join(OUT, 'crowd_player_red.png'), n_each=50, frame='rand')
        crowd(['vfx_cheonyeo_bullet', 'vfx_cheonyeo_bullet_petal', 'vfx_boss_tidal_bullet', 'vfx_sal_grain_idle', 'vfx_sal_grain_idle_s', 'vfx_orb_small'],
              os.path.join(OUT, 'crowd_enemy.png'), n_each=60, frame='rand')
