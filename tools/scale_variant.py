#!/usr/bin/env python3
"""무료 축소 단계 변형: 스프라이트 폴더 전체를 비율 축소 -> 알파 이진화 -> 원본 팔레트로 재양자화 -> 1px 외곽선 정리.
사용: python tools/scale_variant.py <src_entity> <dst_entity> <scale(0~1)>"""
import sys
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent; SP = ROOT / "game/assets/sprites"
src, dst, sc = sys.argv[1], sys.argv[2], float(sys.argv[3])
S, D = SP / src, SP / dst; D.mkdir(parents=True, exist_ok=True)

def palette_of(im):
    cols = {}
    for c in im.getdata():
        if c[3] > 0: cols[c[:3]] = cols.get(c[:3], 0) + 1
    return [c for c, _ in sorted(cols.items(), key=lambda x: -x[1])[:48]]

def nearest(c, pal):
    return min(pal, key=lambda p: (p[0]-c[0])**2*2 + (p[1]-c[1])**2*4 + (p[2]-c[2])**2*3)

n = 0
for f in sorted(S.glob("*.png")):
    im = Image.open(f).convert("RGBA"); pal = palette_of(im)
    w, h = im.size; nw, nh = max(1, round(w*sc)), max(1, round(h*sc))
    small = im.resize((nw, nh), Image.BOX); px = small.load()
    out = Image.new("RGBA", (nw, nh), (0, 0, 0, 0)); po = out.load(); cache = {}
    for y in range(nh):
        for x in range(nw):
            r, g, b, a = px[x, y]
            if a < 110: continue
            if a < 255:  # 반투명 가장자리 -> 알파 보정된 색
                r, g, b = [min(255, int(v * 255 / a)) for v in (r, g, b)]
            k = (r >> 2, g >> 2, b >> 2)
            if k not in cache: cache[k] = nearest((r, g, b), pal)
            po[x, y] = cache[k] + (255,)
    # 1px 외곽선 정리: 실루엣 경계 픽셀을 원본의 가장 어두운 색으로
    dark = min(pal, key=lambda c: sum(c)) if pal else (0, 0, 0)
    edge = []
    for y in range(nh):
        for x in range(nw):
            if po[x, y][3] == 0: continue
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                xx, yy = x+dx, y+dy
                if not (0 <= xx < nw and 0 <= yy < nh) or po[xx, yy][3] == 0:
                    edge.append((x, y)); break
    for x, y in edge: po[x, y] = dark + (255,)
    out.save(D / f.name); n += 1
print(f"{src} -> {dst} x{sc}: {n} files")
