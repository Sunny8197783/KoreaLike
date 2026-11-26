"""가시성 수치(전/후 비교). tools/vis_capture.sh 출력 폴더를 읽어 시점별 표를 낸다.

사용: python tools/vis_measure.py game/captures/vis/before [game/captures/vis/after]
- 게임 수치(vis_stats.jsonl): 화면 안 적, 플레이어 반경 32/64px 적, 원귀, 적·내 투사체, vfx, 피해 숫자, 화면 글.
- 그림 수치(PNG, 640×360 내부 픽셀로 환산):
  p_red   플레이어 상자(발 기준 가로 ±9, 위 38px) 안 주색(무당 홍철릭) 픽셀 수 — 적이 위에 덮이면 줄어든다(0.3초 찾기 대리 지표)
  p_con   플레이어 상자 평균 명도 vs 둘레(±40 x -70..+30) 평균 명도의 차(0..255)
  white%  놀이 영역(위 HUD 46px 아래) 흰빛(V>.82, S<.18) 비율 — 흰 무구·흰 귀신·영가가 같은 층에 섞이는 정도
  red%    놀이 영역 진한 붉은빛(H<15|>345, S>.45, V>.35) 비율 — 합일 바닥·붉은 무구·위험 색이 겹치는 정도
  busy    가운데 320×200 의 평균 명도 기울기(값이 클수록 잘게 어지러움)
  p_gold  플레이어 둘레 상자(발 기준 가로 ±16, 위 46 ~ 아래 10px) 안 무당 금(#f5d66b ±12 + 조명 받은 같은 금) 픽셀 수 — 금 테·발밑 표지(design/18 ①)
  white_sat 놀이 영역 순백(#ffffff) 픽셀 수 — '백 = 해원' 한 뜻인지(②)
  hj_area 놀이 영역 한지(#e9dcc0 ±14) 픽셀 수 — 흰 무구 스파크·피격 외곽선 면적(②)
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

HUD_TOP = 46


def hsv(a):
    a = a.astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(-1)
    mn = a.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    h = np.zeros_like(mx)
    m = d > 1e-6
    rr = (mx == r) & m
    gg = (mx == g) & m & ~rr
    bb = m & ~rr & ~gg
    h[rr] = (60 * ((g - b)[rr] / d[rr])) % 360
    h[gg] = 60 * ((b - r)[gg] / d[gg]) + 120
    h[bb] = 60 * ((r - g)[bb] / d[bb]) + 240
    return h, s, mx


def lum(a):
    a = a.astype(np.float32)
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def measure(png, st):
    im = Image.open(png).convert("RGB")
    sc = int(st.get("scale", 3))
    if sc > 1:
        im = im.resize((im.width // sc, im.height // sc), Image.NEAREST)
    a = np.asarray(im)
    H, W = a.shape[:2]
    L = lum(a)
    h, s, v = hsv(a)
    px, py = st["player_screen"]
    x0, x1, y0, y1 = max(0, px - 9), min(W, px + 10), max(0, py - 38), min(H, py + 1)
    box = (slice(y0, y1), slice(x0, x1))
    red = ((h < 15) | (h > 345)) & (s > 0.45) & (v > 0.35)
    p_red = int(red[box].sum())
    sx0, sx1, sy0, sy1 = max(0, px - 40), min(W, px + 41), max(0, py - 70), min(H, py + 31)
    mask = np.zeros((H, W), bool)
    mask[sy0:sy1, sx0:sx1] = True
    mask[box] = False
    p_con = float(abs(L[box].mean() - L[mask].mean())) if mask.any() else 0.0
    play = (slice(HUD_TOP, H), slice(0, W))
    white = (v > 0.82) & (s < 0.18)
    white_p = float(white[play].mean() * 100)
    red_p = float(red[play].mean() * 100)
    c = (slice(H // 2 - 100, H // 2 + 100), slice(W // 2 - 160, W // 2 + 160))
    Lc = L[c]
    busy = float((np.abs(np.diff(Lc, axis=0)).mean() + np.abs(np.diff(Lc, axis=1)).mean()) / 2)
    gx0, gx1, gy0, gy1 = max(0, px - 16), min(W, px + 17), max(0, py - 46), min(H, py + 11)
    ai = a.astype(np.int16)
    # 금 = #f5d66b ±12, 또는 후처리 촛불 조명으로 밝아진 같은 금(색상 40~62°, 채도 .42~.66, 명도 ≥.80).
    # #e8b931(엽전·황, 채도 .79)·한지(채도 .18)는 빠진다.
    gold = np.all(np.abs(ai - np.array([0xF5, 0xD6, 0x6B], np.int16)) <= 12, axis=-1)
    gold |= (h >= 40) & (h <= 62) & (s >= 0.42) & (s <= 0.66) & (v >= 0.80)
    p_gold = int(gold[gy0:gy1, gx0:gx1].sum())
    white_sat = int(np.all(a[play] == 255, axis=-1).sum())
    hj = np.all(np.abs(ai - np.array([0xE9, 0xDC, 0xC0], np.int16)) <= 14, axis=-1)
    hj_area = int(hj[play].sum())
    return {"p_red": p_red, "p_con": p_con, "white%": white_p, "red%": red_p, "busy": busy,
            "p_gold": p_gold, "white_sat": white_sat, "hj_area": hj_area}


KEYS_G = ["en_screen", "near32", "near64", "wongwi", "eproj", "pproj", "vfx", "particles", "dmgnum", "dmglabel", "yeongga", "texts_n", "center_n"]
KEYS_I = ["p_red", "p_con", "white%", "red%", "busy", "p_gold", "white_sat", "hj_area"]
KEYS_MIN = ("p_red", "p_con", "p_gold")


def run(folder):
    folder = Path(folder)
    rows = [json.loads(x) for x in (folder / "vis_stats.jsonl").read_text(encoding="utf-8").splitlines() if x.strip()]
    by = defaultdict(list)
    for r in rows:
        r.update(measure(folder / r["file"], r))
        by[r["at"]].append(r)
    print(f"\n## {folder}")
    hdr = ["at", "n", "lv"] + [f"{k}(avg/max)" for k in KEYS_G] + [f"{k}(avg/min)" if k in KEYS_MIN else f"{k}(avg)" for k in KEYS_I]
    print("| " + " | ".join(hdr) + " |")
    print("|" + "---|" * len(hdr))
    out = {}
    for at in sorted(by):
        rs = by[at]
        cells = [at[:2] + ":" + at[2:], str(len(rs)), str(rs[-1].get("lv", ""))]
        agg = {}
        for k in KEYS_G:
            vals = [float(r.get(k, 0)) for r in rs]
            agg[k] = (sum(vals) / len(vals), max(vals))
            cells.append(f"{agg[k][0]:.1f}/{agg[k][1]:.0f}")
        for k in KEYS_I:
            vals = [float(r[k]) for r in rs]
            agg[k] = (sum(vals) / len(vals), min(vals))
            if k in KEYS_MIN:
                cells.append(f"{agg[k][0]:.1f}/{agg[k][1]:.0f}")
            elif k in ("white_sat", "hj_area"):
                cells.append(f"{agg[k][0]:.0f}")
            else:
                cells.append(f"{agg[k][0]:.2f}")
        out[at] = agg
        print("| " + " | ".join(cells) + " |")
    texts = defaultdict(set)
    for r in rows:
        for t in r.get("texts", []):
            texts[r["at"]].add(t.split(" '")[0])
    for at in sorted(texts):
        print(f"- {at}: 글 종류 = {', '.join(sorted(texts[at]))}")
    return out


if __name__ == "__main__":
    for f in sys.argv[1:]:
        run(f)
