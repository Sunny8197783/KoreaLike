#!/usr/bin/env python3
"""무료 팔레트 변형: 한 엔티티 스프라이트 폴더 전체를 HSV 시프트/틴트해 새 엔티티 폴더로 복제.
사용: python tools/palette_variant.py <src_entity> <dst_entity> --hue H --sat S --val V [--tint #rrggbb --tint-amt 0.5] [--bright-to #rrggbb --bright-thresh 0.85]
 hue: 0..360 절대 색상(채도 있는 픽셀을 이 색상으로), sat: 채도 배수, val: 명도 배수
 tint: 결과에 색을 섞음.  bright-to: 명도>thresh 인 저채도 픽셀(눈·하이라이트)을 지정 색으로.
 외곽선(명도<0.12)은 보존.
"""
import argparse, colorsys, shutil
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent
SP = ROOT / "game" / "assets" / "sprites"

def hexrgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--hue", type=float); ap.add_argument("--sat", type=float, default=1.0)
    ap.add_argument("--val", type=float, default=1.0); ap.add_argument("--min-sat", type=float, default=0.0)
    ap.add_argument("--tint"); ap.add_argument("--tint-amt", type=float, default=0.0)
    ap.add_argument("--bright-to"); ap.add_argument("--bright-thresh", type=float, default=0.85)
    ap.add_argument("--root", default=str(SP))
    ap.add_argument("--src-hue", type=str, help="lo,hi (도) 이 색상 범위 + 채도>=src-min-sat 픽셀만 변경 (예: 330,25 = 붉은색)")
    ap.add_argument("--src-min-sat", type=float, default=0.35)
    a = ap.parse_args()
    src = Path(a.root) / a.src; dst = Path(a.root) / a.dst
    dst.mkdir(parents=True, exist_ok=True)
    tint = hexrgb(a.tint) if a.tint else None
    bto = hexrgb(a.bright_to) if a.bright_to else None
    n = 0
    for f in sorted(src.glob("*.png")):
        im = Image.open(f).convert("RGBA"); px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                r, g, b, al = px[x, y]
                if al == 0: continue
                h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                if v < 0.12: continue
                if a.src_hue:
                    lo, hi = [float(x) for x in a.src_hue.split(",")]; hd = h * 360
                    inr = (lo <= hd <= hi) if lo <= hi else (hd >= lo or hd <= hi)
                    if not inr or s < a.src_min_sat: continue
                if bto and v > a.bright_thresh and s < 0.25:
                    nr, ng, nb = bto
                else:
                    if a.hue is not None: h = (a.hue % 360) / 360
                    s = min(1, max(a.min_sat, s * a.sat)); v = min(1, v * a.val)
                    nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
                    if tint:
                        t = a.tint_amt
                        nr = nr * (1 - t) + tint[0] * v * t; ng = ng * (1 - t) + tint[1] * v * t; nb = nb * (1 - t) + tint[2] * v * t
                px[x, y] = (int(nr * 255 + .5), int(ng * 255 + .5), int(nb * 255 + .5), al)
        im.save(dst / f.name); n += 1
    print(f"{a.src} -> {a.dst}: {n} files")

if __name__ == "__main__":
    main()
