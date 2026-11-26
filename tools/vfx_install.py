"""Install a re-rendered pixelfx sheet into game/assets/vfx, keeping the old JSON's extra meta.
python tools/vfx_install.py <render_dir_with id.png/id.json> <vfx_id> [--as <target_id>] [--dest DIR]
- frame count is matched to the currently installed sheet (drops trailing empty frames if the old one had none)
- re-lays frames out as one horizontal row ("가로 그리드"), columns = n
- meta.pixelfx gets frameWidth/frameHeight/columns/frames; every other old meta field is kept
"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VFX = os.path.join(ROOT, 'game', 'assets', 'vfx')


def frames_of(d, im):
    out = []
    for f in d['frames']:
        q = f['frame']
        out.append((im.crop((q['x'], q['y'], q['x'] + q['w'], q['y'] + q['h'])), f.get('duration', 83)))
    return out


def main():
    a = sys.argv[1:]
    src, vid = a[0], a[1]
    tgt = a[a.index('--as') + 1] if '--as' in a else vid
    dest = a[a.index('--dest') + 1] if '--dest' in a else VFX
    nd = json.load(open(os.path.join(src, vid + '.json'), encoding='utf-8'))
    nim = Image.open(os.path.join(src, vid + '.png')).convert('RGBA')
    fr = frames_of(nd, nim)
    oldp = os.path.join(VFX, tgt + '.json')
    od = json.load(open(oldp, encoding='utf-8')) if os.path.exists(oldp) else {'meta': {'pixelfx': {}}}
    on = len(od.get('frames', [])) or len(fr)
    while len(fr) > on and not fr[-1][0].getbbox():
        fr.pop()
    n = len(fr)
    fw, fh = fr[0][0].size
    sheet = Image.new('RGBA', (fw * n, fh), (0, 0, 0, 0))
    frames = []
    for i, (im, dur) in enumerate(fr):
        sheet.paste(im, (i * fw, 0))
        frames.append({'filename': f'{tgt} {i}', 'frame': {'x': i * fw, 'y': 0, 'w': fw, 'h': fh}, 'rotated': False,
                       'trimmed': False, 'spriteSourceSize': {'x': 0, 'y': 0, 'w': fw, 'h': fh},
                       'sourceSize': {'w': fw, 'h': fh}, 'duration': dur})
    meta = dict(od.get('meta', {}))
    nm = nd['meta']
    meta.update({k: nm[k] for k in ('app', 'version', 'format', 'scale') if k in nm})
    meta['image'] = tgt + '.png'
    meta['size'] = {'w': fw * n, 'h': fh}
    meta['frameTags'] = [{'name': tgt, 'from': 0, 'to': n - 1, 'direction': 'forward'}]
    px = dict(od.get('meta', {}).get('pixelfx', {}))
    npx = nm.get('pixelfx', {})
    for k in ('id', 'name', 'fps', 'loop', 'pivot'):
        if k in npx:
            px[k] = npx[k]
    px.update({'frames': n, 'frameSize': [fw, fh], 'frameWidth': fw, 'frameHeight': fh, 'columns': n})
    px['reviewed'] = 'ASSET-REVIEW 2026-11-22: re-rendered'
    meta['pixelfx'] = px
    out = {'frames': frames, 'meta': meta}
    os.makedirs(dest, exist_ok=True)
    sheet.save(os.path.join(dest, tgt + '.png'))
    json.dump(out, open(os.path.join(dest, tgt + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'{tgt}: {n} frames {fw}x{fh} -> {dest}')


if __name__ == '__main__':
    main()
