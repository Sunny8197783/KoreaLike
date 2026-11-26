#!/usr/bin/env python3
"""PixelLab 2x2 뷰 시트(64x64: 좌상=정면, 우상=우측, 좌하=뒤, 우하=좌측) -> 32px 4방향 오버레이.
사용: python tools/overlay_slice.py <sheet.png> <overlay_kind(head|jimul)> <name> [--gaho]
 출력: game/assets/sprites/overlay_<kind>/<name>_{south,east,north,west}.png  (west = east 좌우반전; 생성된 좌측 뷰는 품질이 들쭉날쭉해 미사용)
 --north-br: 뒤 뷰로 우하 칸 사용(좌하 칸이 엉뚱할 때)
 --map=south:TR,east:TR,north:BL : 칸 직접 지정
 --gaho: 가호(보호) 면 변형 = 금빛 테두리 1px + 채도 낮춤 (무료) -> <name>_gaho_<dir>.png, 기본은 <name>_wieom_<dir>.png
"""
import sys, colorsys
from pathlib import Path
from PIL import Image, ImageOps
ROOT = Path(__file__).resolve().parent.parent
sheet, kind, name = sys.argv[1], sys.argv[2], sys.argv[3]
OUT = ROOT / "game/assets/sprites" / f"overlay_{kind}"; OUT.mkdir(parents=True, exist_ok=True)
im = Image.open(sheet).convert("RGBA"); W, H = im.size; cw, ch = W // 2, H // 2
cells = {"south": (0, 0), "east": (1, 0), "north": (1, 1) if "--north-br" in sys.argv else (0, 1)}

def crop_center(c):
    x, y = c; t = im.crop((x*cw, y*ch, (x+1)*cw, (y+1)*ch)); bb = t.getbbox()
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    if not bb: return out
    t = t.crop(bb)
    if t.width > 32 or t.height > 32:
        s = min(32 / t.width, 32 / t.height); t = t.resize((max(1, int(t.width*s)), max(1, int(t.height*s))), Image.NEAREST)
    out.alpha_composite(t, ((32 - t.width)//2, (32 - t.height)//2)); return out

def gaho(t):
    t = t.copy(); p = t.load(); w, h = t.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = p[x, y]
            if a == 0: continue
            hh, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255); s *= 0.55; v = min(1, v*1.08)
            r2, g2, b2 = colorsys.hsv_to_rgb(hh, s, v); p[x, y] = (int(r2*255), int(g2*255), int(b2*255), a)
    gold = (232, 185, 49, 255); edge = []
    for y in range(h):
        for x in range(w):
            if p[x, y][3] == 0 and any(0 <= x+dx < w and 0 <= y+dy < h and p[x+dx, y+dy][3] > 0 for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))):
                edge.append((x, y))
    for x, y in edge: p[x, y] = gold
    return t

Q = {"TL": (0, 0), "TR": (1, 0), "BL": (0, 1), "BR": (1, 1)}
for a in sys.argv:
    if a.startswith("--map="):  # 예: --map=south:TR,east:TR,north:BL
        for kv in a[6:].split(","):
            d, q = kv.split(":"); cells[d] = Q[q]
views = {d: crop_center(c) for d, c in cells.items()}
views["west"] = ImageOps.mirror(views["east"])
for d, t in views.items():
    t.save(OUT / (f"{name}_wieom_{d}.png" if kind == "head" else f"{name}_{d}.png"))
    if "--gaho" in sys.argv: gaho(t).save(OUT / f"{name}_gaho_{d}.png")
print("ok", name)
