"""Batch-1 sprite converter: PixelLab character ZIP/extracted dir -> game/assets/sprites/<entity_id>/

Usage: python tools/sprites_b1_convert.py <src_dir_or_zip> <entity_id> [--map name=anim,...] [--pad N]
       [--fade] [--recolor-white] [--scale F] [--only-state NAME]

Rules (asset contract):
  <dir>.png (south/east/north/west), walk_<dir>_<n>.png, <anim>_<dir>_<n>.png
  Missing west on an animation that has east -> mirrored from east.
  Writes anims.json {anim: {dir: frame_count}, size:[w,h]} beside the frames.
"""
import json, os, sys, zipfile, shutil, argparse
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(ROOT, 'game', 'assets', 'sprites')
DIRS = ['south', 'east', 'north', 'west']


def norm_anim(name, mapping):
    if name in mapping:
        return mapping[name]
    low = name.lower()
    if low.startswith('walk') or low == 'walking':
        return 'walk'
    return low.replace('-', '_').replace(' ', '_')


def fade_lower(img, start=0.62):
    """Ghost legs: alpha ramps from 1 at `start` of the opaque bbox height to 0.15 at the bottom."""
    img = img.convert('RGBA')
    bbox = img.getbbox()
    if not bbox:
        return img
    top, bot = bbox[1], bbox[3]
    h = bot - top
    px = img.load()
    for y in range(top, bot):
        t = (y - top) / max(1, h)
        if t <= start:
            continue
        k = 1.0 - (t - start) / (1.0 - start) * 0.85
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (r, g, b, int(a * k))
    return img


def recolor_white(img, target=(150, 168, 186)):
    """Swap near-white cloth (reserved #f2ece0 family) to grey-blue, keep shading ratio."""
    img = img.convert('RGBA')
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and min(r, g, b) > 170 and max(r, g, b) - min(r, g, b) < 40:
                lum = (r + g + b) / 3 / 255
                px[x, y] = (int(target[0] * lum), int(target[1] * lum), int(target[2] * lum + 20 * lum), a)
    return img


def ghostify(img, tint=(242, 236, 224), k=0.38, alpha=0.88):
    """Yeongga look: pull colours toward hanji-white #f2ece0 (reserved for yeongga) and thin the alpha."""
    img = img.convert('RGBA')
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r + (tint[0] - r) * k), int(g + (tint[1] - g) * k), int(b + (tint[2] - b) * k), int(a * alpha))
    return img


def pad_to(img, n):
    if img.width >= n and img.height >= n:
        return img
    c = Image.new('RGBA', (max(n, img.width), max(n, img.height)), (0, 0, 0, 0))
    # bottom-centre anchor so feet stay on the ground line
    c.paste(img, ((c.width - img.width) // 2, c.height - img.height - (c.height - img.height) // 4))
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('entity')
    ap.add_argument('--map', default='')
    ap.add_argument('--pad', type=int, default=0)
    ap.add_argument('--fade', action='store_true')
    ap.add_argument('--ghost', action='store_true')
    ap.add_argument('--recolor-white', action='store_true')
    ap.add_argument('--state', default=None)
    ap.add_argument('--skip', default='', help='comma list of anim names to skip')
    ap.add_argument('--clean', action='store_true')
    a = ap.parse_args()
    mapping = dict(kv.split('=', 1) for kv in a.map.split(',') if '=' in kv)
    skip = set(s for s in a.skip.split(',') if s)

    src = a.src
    if src.endswith('.zip'):
        dst = src[:-4]
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        with zipfile.ZipFile(src) as z:
            z.extractall(dst)
        src = dst
    meta = json.load(open(os.path.join(src, 'metadata.json'), encoding='utf-8'))
    states = meta['states']
    st = states[0]
    if a.state:
        st = next(s for s in states if s['character']['name'] == a.state)
    frames = st['frames']
    out = os.path.join(OUT_ROOT, a.entity)
    if a.clean and os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out, exist_ok=True)

    def post(p):
        im = Image.open(os.path.join(src, p)).convert('RGBA')
        if a.recolor_white:
            im = recolor_white(im)
        if a.ghost:
            im = ghostify(im)
        if a.fade:
            im = fade_lower(im)
        if a.pad:
            im = pad_to(im, a.pad)
        return im

    rot = frames['rotations']
    for d in DIRS:
        if d in rot:
            post(rot[d]).save(os.path.join(out, f'{d}.png'))
    if 'west' not in rot and 'east' in rot:
        post(rot['east']).transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(out, 'west.png'))

    info = {'size': [st['character']['size']['width'], st['character']['size']['height']], 'anims': {},
            'pixellab_id': st['character']['id']}
    for name, dirs in frames.get('animations', {}).items():
        if name in skip:
            continue
        anim = norm_anim(name, mapping)
        info['anims'].setdefault(anim, {})
        for d in DIRS:
            flip = False
            lst = dirs.get(d)
            if lst is None and d == 'west' and 'east' in dirs:
                lst, flip = dirs['east'], True
            if lst is None:
                continue
            for i, p in enumerate(lst):
                im = post(p)
                if flip:
                    im = im.transpose(Image.FLIP_LEFT_RIGHT)
                im.save(os.path.join(out, f'{anim}_{d}_{i}.png'))
            info['anims'][anim][d] = len(lst)
            info.setdefault('frame_size', {})[anim] = [im.width, im.height]
    with open(os.path.join(out, 'anims.json'), 'w', encoding='utf-8') as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    print(a.entity, json.dumps(info['anims']))


if __name__ == '__main__':
    main()
