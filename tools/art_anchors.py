"""art_anchors — 프레임별 앵커를 픽셀에서 측정해 data/anchors/<id>.json 으로 저장 (13장 4.1.5, ART_STYLE 4.2).
손 계산 금지 규칙에 따라 좌표는 모두 이 도구가 그림에서 직접 찍는다. Python 3 + Pillow만.

사용:  python tools/art_anchors.py <entity_dir> --id <entity_id> [--out data/anchors/<file>.json] [--skin '#hex,..']

측정 정의(64px 무당 기준, 다른 등급도 같은 규칙):
  foot   = anims.json 피벗 (발 앵커)
  head   = 불투명 상단 12행(모자 몸통·챙)의 x 중심, y = 상단 + 12  (머리 오버레이 앵커)
  face   = 상단 24행 안 피부 램프(sk) 픽셀의 무게중심. 뒷모습(피부 없음)이면 null
  hand_l / hand_r = 상단+20 ~ 피벗-6 구간 피부 픽셀 덩어리 중 화면 왼쪽/오른쪽 끝 덩어리의 무게중심. 없으면 null
  aura   = 불투명 bbox 중심 (오라·버프 발생점)
"""
import argparse
import glob
import json
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SK = ["#3b2219", "#6e4330", "#a5704f", "#d29d7a", "#efcdb0"]
FR = re.compile(r"^(?P<a>.+?)_(?P<d>south|east|north|west)_(?P<n>\d+)\.png$")


def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def clusters(pts):
    pts = set(pts)
    out = []
    while pts:
        s = pts.pop()
        st, c = [s], [s]
        while st:
            x, y = st.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q in pts:
                        pts.remove(q)
                        st.append(q)
                        c.append(q)
        out.append(c)
    return out


def cen(c):
    return [int(round(sum(p[0] for p in c) / len(c))), int(round(sum(p[1] for p in c) / len(c)))]


def measure(path, pivot, skin):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    bb = im.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()
    if not bb:
        return None
    top = bb[1]
    xs = [x for y in range(top, min(top + 12, h)) for x in range(w) if px[x, y][3] >= 128]
    head = [int(round((min(xs) + max(xs)) / 2)), top + 12]
    face_pts = [(x, y) for y in range(top, min(top + 24, h)) for x in range(w) if px[x, y][3] >= 128 and px[x, y][:3] in skin]
    face = cen(face_pts) if len(face_pts) >= 3 else None
    lo, hi = top + 20, pivot[1] - 6
    hand_pts = [(x, y) for y in range(lo, hi) for x in range(w) if px[x, y][3] >= 128 and px[x, y][:3] in skin]
    cl = [c for c in clusters(hand_pts) if len(c) >= 2]
    hand_l = hand_r = None
    aura = [(bb[0] + bb[2] - 1) // 2, (bb[1] + bb[3] - 1) // 2]
    if len(cl) > 1:
        cl.sort(key=lambda c: cen(c)[0])
        hand_l, hand_r = cen(cl[0]), cen(cl[-1])
    elif cl:  # 한 손만 보이면 몸 중심 기준 좌/우로 배정
        c = cen(cl[0])
        if c[0] < aura[0]:
            hand_l = c
        else:
            hand_r = c
    return {"foot": list(pivot), "head": head, "face": face, "hand_l": hand_l, "hand_r": hand_r, "aura": aura}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("entity_dir")
    ap.add_argument("--id", required=True)
    ap.add_argument("--out")
    ap.add_argument("--skin", default=",".join(SK))
    o = ap.parse_args(argv)
    meta = json.load(open(os.path.join(o.entity_dir, "anims.json"), encoding="utf-8"))
    pivot = meta.get("pivot", [32, 58])
    skin = {hx(h) for h in re.findall(r"#[0-9a-fA-F]{6}", o.skin)}
    frames = {}
    for p in sorted(glob.glob(os.path.join(o.entity_dir, "*.png"))):
        m = FR.match(os.path.basename(p))
        if not m:
            continue
        r = measure(p, pivot, skin)
        if r:
            frames[os.path.basename(p)[:-4]] = r
    out = o.out or os.path.join(ROOT, "data", "anchors", o.id + ".json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    doc = {o.id: {"source": os.path.relpath(os.path.abspath(o.entity_dir), ROOT).replace("\\", "/"),
                  "tool": "tools/art_anchors.py", "canvas": meta.get("size"), "pivot": pivot,
                  "frames": frames}}
    json.dump(doc, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    nulls = {k: sum(1 for f in frames.values() if f[k] is None) for k in ("face", "hand_l", "hand_r")}
    print("wrote %s: %d frames, null counts %s" % (out, len(frames), nulls))
    return 0


if __name__ == "__main__":
    sys.exit(main())
