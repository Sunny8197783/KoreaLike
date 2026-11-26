"""Procedural pixel sprite for enm_dokkaebi_bul (도깨비불, blue-green will-o'-wisp). Free, deterministic.

Output (asset contract): game/assets/sprites/enm_dokkaebi_bul/{south,east,north,west}.png,
float_<dir>_<n> (4f), split_<dir>_<n> (6f), spawn_<dir>_<n> (4f), anims.json
and enm_dokkaebi_bul__small/ (0.6x, nearest-neighbour of a 20px redraw).
Round orb head with two laughing eye-arcs, wavering flame tail below; teal ramp + dark outline.
"""
import json, math, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'sprites')
RAMP = [(11, 59, 62), (23, 128, 122), (47, 196, 178), (127, 240, 214), (226, 255, 246)]  # outline..core
EYE = (8, 40, 44)
DIRS = ['south', 'east', 'north', 'west']


def wisp(n, t, scale=1.0, split=0.0, alpha=1.0, grow=1.0):
    """t in [0,1) animation phase. split: 0..1 separates into two orbs. grow: spawn scale."""
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    px = img.load()
    cx0, cy = n / 2 - 0.5, n * 0.40
    r = n * 0.25 * scale * grow
    centres = [(cx0, cy)] if split <= 0 else [(cx0 - split * n * 0.28, cy - split * 2), (cx0 + split * n * 0.28, cy + split * 1)]
    rr = r if split <= 0 else r * (1 - 0.3 * split)
    field = [[0.0] * n for _ in range(n)]
    for (cx, cyy) in centres:
        for y in range(n):
            for x in range(n):
                dx, dy = x - cx, y - cyy
                d = math.hypot(dx, dy) / max(rr, 0.5)
                v = max(0.0, 1.2 - d)
                # flame tail below the orb, wavering sideways with phase
                if dy > 0:
                    k = dy / (rr * 2.4)
                    if k < 1:
                        sway = math.sin(t * 2 * math.pi + k * 3.2) * rr * 0.45 * k
                        w = rr * (1 - k) ** 1.3
                        tv = max(0.0, 1.0 - abs(dx - sway) / max(w, 0.3)) * (1 - k) * 1.1
                        v = max(v, tv)
                # top flicker tongues
                if dy < 0:
                    tongue = 0.12 * math.sin(t * 2 * math.pi * 2 + dx * 0.9)
                    v += tongue * max(0, 1 - d)
                field[y][x] = max(field[y][x], v)
    for y in range(n):
        for x in range(n):
            v = field[y][x]
            if v <= 0.18:
                continue
            idx = 1 if v < 0.38 else 2 if v < 0.62 else 3 if v < 0.85 else 4
            c = RAMP[idx]
            px[x, y] = (*c, int(255 * alpha))
    # 1px dark outline
    out = img.copy()
    op = out.load()
    for y in range(n):
        for x in range(n):
            if px[x, y][3] == 0:
                for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + ax, y + ay
                    if 0 <= xx < n and 0 <= yy < n and px[xx, yy][3] > 0:
                        op[x, y] = (*RAMP[0], int(255 * alpha))
                        break
    # laughing eyes: small upward arcs (^ ^) on each orb
    for (cx, cyy) in centres:
        if grow < 0.6:
            continue
        ey = int(round(cyy - rr * 0.05 + math.sin(t * 2 * math.pi) * 0.6))
        for sx in (-1, 1):
            ex = int(round(cx + sx * rr * 0.42))
            for ox, oy in ((-1, 0), (0, -1), (1, 0)):
                xx, yy = ex + ox, ey + oy
                if 0 <= xx < n and 0 <= yy < n and op[xx, yy][3] > 0:
                    op[xx, yy] = (*EYE, int(255 * alpha))
    return out


def save_set(eid, n, scale):
    d = os.path.join(OUT, eid)
    os.makedirs(d, exist_ok=True)
    anims = {}
    base = wisp(n, 0.0, scale)
    for dr in DIRS:
        base.save(os.path.join(d, f'{dr}.png'))
    seqs = {
        'float': [wisp(n, i / 4, scale) for i in range(4)],
        'split': [wisp(n, i / 6, scale, split=i / 5) for i in range(6)],
        'spawn': [wisp(n, i / 4, scale, grow=0.25 + 0.25 * i, alpha=0.4 + 0.2 * i) for i in range(4)],
    }
    for name, frames in seqs.items():
        anims[name] = {}
        for dr in DIRS:
            for i, f in enumerate(frames):
                f.save(os.path.join(d, f'{name}_{dr}_{i}.png'))
            anims[name][dr] = len(frames)
    json.dump({'size': [n, n], 'anims': anims, 'source': 'procedural tools/gen_dokkaebi_bul.py',
               'frame_size': {k: [n, n] for k in anims}}, open(os.path.join(d, 'anims.json'), 'w'), indent=1)
    print(eid, anims)


if __name__ == '__main__':
    save_set('enm_dokkaebi_bul', 32, 1.0)
    save_set('enm_dokkaebi_bul__small', 20, 1.0)
