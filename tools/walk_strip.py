"""Builds a south-facing walk-cycle strip for all characters: python tools/walk_strip.py (run from art/)."""
import glob, os
from PIL import Image
rows = []
for c in ['mansin', 'baksu', 'dangol', 'simbang', 'myeongdu']:
    fr = sorted(p.replace(os.sep, '/') for p in glob.glob(f'characters/{c}/**/*.png', recursive=True))
    fr = [f for f in fr if '/animations/' in f and '/south/' in f and 'walk' in f]
    print(c, len(fr))
    rows.append([Image.open(f).convert('RGBA') for f in fr[:8]])
w = max(i.width for r in rows for i in r); h = max(i.height for r in rows for i in r)
s = Image.new('RGBA', (w * 8 * 2, h * len(rows) * 2), (40, 36, 48, 255))
for y, r in enumerate(rows):
    for x, im in enumerate(r):
        s.alpha_composite(im.resize((im.width * 2, im.height * 2), Image.NEAREST), (x * w * 2, y * h * 2))
s.save('characters/_walk_south_all.png')
