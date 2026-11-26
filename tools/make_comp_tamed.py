#!/usr/bin/env python3
"""해원 후 동료(comp_*) = 원본 적 스프라이트 + 한지/백 팔레트 스왑 (무료).
사용: python tools/make_comp_tamed.py [comp_id ...]   (인자 없으면 전체)
- 걷기/정지 등 원본 폴더의 모든 PNG 를 변환해 game/assets/sprites/<comp_id>/ 에 같은 파일명으로 저장.
- 외곽선(아주 어두운 픽셀) -> 먹 보라 #2b2236 (검정보다 부드럽게), 나머지는 명도 기반 한지 램프와 원색을 섞음.
- 백 #f2ece0 은 해원/영가 전용 예약색: 동료는 해원된 영가이므로 하이라이트에 사용.
- 별도 special_south_<n>.png 는 PixelLab v3 (원본 적 캐릭터에 애니) 결과를 같은 변환으로 넣는다(--special-zip).
"""
import sys, colorsys, zipfile, json, io
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent; SP = ROOT / "game/assets/sprites"
MAP = {"comp_dalgyal": "enm_dalgyal_gwisin", "comp_cheonyeo": "enm_cheonyeo_gwisin", "comp_mulgwi": "enm_mul_gwisin",
       "comp_agwi": "enm_agwi", "comp_mongdal": "enm_mongdal_gwisin", "comp_dokkaebi_bul": "enm_dokkaebi_bul",
       "comp_gaekgwi": "enm_gaekgwi", "comp_yeongsan": "enm_yeongsan"}
INK = (43, 34, 54); RAMP = [(0.0, (74, 63, 92)), (0.45, (176, 160, 140)), (0.75, (233, 220, 192)), (1.0, (242, 236, 224))]

def ramp(l):
    for (a, ca), (b, cb) in zip(RAMP, RAMP[1:]):
        if l <= b:
            t = (l - a) / (b - a); return tuple(ca[i] + (cb[i] - ca[i]) * t for i in range(3))
    return RAMP[-1][1]

def tame(im, mix=0.72):
    im = im.convert("RGBA"); p = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = p[x, y]
            if a == 0: continue
            h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
            if v < 0.13: p[x, y] = INK + (a,); continue
            l = (0.3*r + 0.59*g + 0.11*b) / 255; l = min(1, l * 1.15 + 0.08)
            t = ramp(l); nr, ng, nb = [int(t[i]*mix + c*(1-mix)) for i, c in enumerate((r, g, b))]
            p[x, y] = (nr, ng, nb, a)
    return im

def main():
    ids = [a for a in sys.argv[1:] if not a.startswith("--")] or list(MAP)
    for cid in ids:
        src = SP / MAP[cid]
        if not src.exists(): print("skip (no source yet):", cid, MAP[cid]); continue
        dst = SP / cid; dst.mkdir(parents=True, exist_ok=True); n = 0
        for f in src.glob("*.png"):
            if f.name.startswith(("touch_", "attack", "curse", "spawn_")): continue  # 적 전용 공격 애니 제외
            tame(Image.open(f)).save(dst / f.name); n += 1
        print(cid, "<-", MAP[cid], n, "files")

if __name__ == "__main__":
    main()
