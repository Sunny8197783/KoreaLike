"""손에 든 무기 아틀라스 만들기(design/19 §6.5, 새 그림 생성 없음 — 기존 아이콘을 잘라 다듬는다).

실행: python tools/build_held_atlas.py   (Pillow 필요)
출력: held_atlas.png + held_atlas.json (sprites: name -> rect [x, y, w, h]).

손질 규칙(design/19 §5.0·6.5, 견본 리뷰 A):
- 아이콘 테두리(틀 선)·배경을 지운다. 41px 그림은 틀 선(가장자리 긴 줄)을 지우고 작은 조각을 버린다.
- 어두운 그림(각궁)은 밝힌다(명도 ×LIFT, 팔레트 색상은 유지).
- 날·가장자리 1px 한지(#e9dcc0) 하이라이트: 빛 쪽(위·왼쪽)이 바깥인 안쪽 가장자리 픽셀 중 채도가 낮은 것(쇠·나무·종이).
- 1px 먹(#0e0b16) 외곽선을 바깥에 두른다(몸과 분리). 금(#f5d66b)은 무당 테 전용이라 쓰지 않는다.
- 진화 변형 <name>_evo: 바깥 외곽선을 황(#e8b931)으로(design/19 §5.2 H '손 무기 황 외곽선').
"""
from collections import deque
from pathlib import Path
import colorsys
import json

from PIL import Image

GAME = Path(__file__).resolve().parents[1] / "game"
HERE = GAME / "assets" / "sprites" / "held"
ICONS = GAME / "ui" / "icons"
SHEET2 = GAME / "assets" / "icons" / "icons_sheet_2.png"

INK = (14, 11, 22, 255)
HANJI = (233, 220, 192, 255)
HWANG = (232, 185, 49, 255)
WOOD = (122, 92, 60, 255)
WOOD_DK = (78, 56, 36, 255)
GOURD = (196, 160, 92, 255)
GOURD_DK = (150, 112, 58, 255)
IRON = (96, 96, 108, 255)
IRON_HI = (160, 160, 172, 255)
RED = (200, 50, 45, 255)


def load(p):
    return Image.open(p).convert("RGBA")


def opaque(px, x, y, w, h):
    return 0 <= x < w and 0 <= y < h and px[x, y][3] > 0


def strip_frame(im, band=5):
    """아이콘 틀 지우기: 가장자리 band 줄 안에서 75% 이상 채워진 줄이 이어진 묶음이고, 그 안쪽 줄이 비어 있으면(30% 미만)
    틀로 보고 그 줄들의 무채색 픽셀을 지운다(장구 북통처럼 그림이 가장자리까지 차 있으면 안쪽 줄도 차 있어 남는다).
    그 뒤 6px 미만 조각을 버린다."""
    im = im.copy()
    w, h = im.size
    px = im.load()
    def frac_col(x):
        return sum(1 for y in range(h) if px[x, y][3] > 0) / h
    def frac_row(y):
        return sum(1 for x in range(w) if px[x, y][3] > 0) / w
    def scan(lines, frac):
        grp = []
        for k, ln in enumerate(lines):
            f = frac(ln)
            if f >= 0.75 and (grp or k < 3) and len(grp) < band:
                grp.append(ln)
            elif grp:
                return grp if f < 0.3 else []
            elif k >= 2:
                return []
        return []
    for _pass in range(2):   # 가로 틀을 지운 뒤 세로 틀을 다시 본다(모서리가 겹쳐 간격 판정이 흐려지지 않게)
        rows = scan(list(range(h)), frac_row) + scan(list(range(h - 1, -1, -1)), frac_row)
        for y in rows:
            for x in range(w):
                px[x, y] = (0, 0, 0, 0)
        cols = scan(list(range(w)), frac_col) + scan(list(range(w - 1, -1, -1)), frac_col)
        for x in cols:
            for y in range(h):
                px[x, y] = (0, 0, 0, 0)
    return keep_components(im, 6)


def _frameish(c):
    r, g, b, a = c
    if a == 0:
        return False
    hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return ss < 0.45 or vv < 0.25   # 틀 선: 회색·갈색·검정(붉은 술·금 장식은 남긴다)


def components(im):
    w, h = im.size
    px = im.load()
    seen = set()
    comps = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 or (x, y) in seen:
                continue
            q = deque([(x, y)])
            seen.add((x, y))
            c = []
            while q:
                cx, cy = q.popleft()
                c.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if (nx, ny) not in seen and opaque(px, nx, ny, w, h):
                            seen.add((nx, ny))
                            q.append((nx, ny))
            comps.append(c)
    return comps


def keep_components(im, min_n, only=None):
    comps = components(im)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    src = im.load()
    dst = out.load()
    for i, c in enumerate(comps):
        if only is not None and i not in only:
            continue
        if len(c) < min_n:
            continue
        for (x, y) in c:
            dst[x, y] = src[x, y]
    return out


def crop_box(im, box):
    return im.crop(box)


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def lift(im, k):
    """명도 ×k(색상·채도 유지)."""
    im = im.copy()
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ll, ss = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            ll = min(0.85, ll * k + 0.04)
            rr, gg, bb = colorsys.hls_to_rgb(hh, ll, ss)
            px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), a)
    return im


def highlight(im, sat_max=0.45, mix=0.75, l_min=0.12):
    """빛 쪽(위·왼쪽·왼위)이 바깥인 안쪽 가장자리 → 한지 쪽으로. 먹에 가까운 픽셀(원래 외곽선)은 그대로."""
    im = im.copy()
    px = im.load()
    w, h = im.size
    src = im.copy().load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            hh, ll, ss = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if ll < l_min or ss > sat_max:
                continue
            edge = False
            for dx, dy in ((0, -1), (-1, 0), (-1, -1), (1, -1)):
                nx, ny = x + dx, y + dy
                if not opaque(src, nx, ny, w, h) or _is_dark(src[nx, ny]):
                    edge = True
                    break
            if edge:
                px[x, y] = tuple(int(src[x, y][i] * (1 - mix) + HANJI[i] * mix) for i in range(3)) + (a,)
    return im


def _is_dark(c):
    return c[3] > 0 and (c[0] + c[1] + c[2]) < 90


def outline(im, col=INK):
    """바깥 1px 외곽선(4방향). 캔버스를 1px씩 넓힌다."""
    w, h = im.size
    out = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    out.paste(im, (1, 1))
    src = out.copy().load()
    px = out.load()
    for y in range(h + 2):
        for x in range(w + 2):
            if src[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if opaque(src, x + dx, y + dy, w + 2, h + 2):
                    px[x, y] = col
                    break
    return out


def recolor_outer(im, col):
    """가장 바깥 외곽선 픽셀(투명과 4방향으로 닿은 불투명)만 col 로."""
    im = im.copy()
    src = im.copy().load()
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if not opaque(src, x + dx, y + dy, w, h):
                    px[x, y] = col
                    break
    return im


def remove_bg(im, tol=40):
    """칸 바탕(가장자리에서 닿는 어두운 남색)을 지운다."""
    im = im.copy()
    w, h = im.size
    px = im.load()
    ref = px[0, 0]
    q = deque()
    seen = set()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        c = px[x, y]
        if c[3] == 0 or sum(abs(c[i] - ref[i]) for i in range(3)) <= tol:
            px[x, y] = (0, 0, 0, 0)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q.append((x + dx, y + dy))
    return im


# ─── 코드 그림(편곤 자루·쑥물 바가지·장구채) ─────────────────────────

def draw_px(im, pts, col):
    px = im.load()
    for (x, y) in pts:
        px[x, y] = col


# 검토 11-26: 어두운 흙 위에서 날·몸이 묻혔다(meanL 48~67) → 명도 올림(목표 meanL ≥95). 색상·채도는 유지.
JAKDU_LIFT = 1.9
LONG_LIFT = 1.9
WOLDO_LIFT = 1.6
BANGUL_LIFT = 1.7


def make_pyeongon_handle():
    """편곤 자루(14px 나무 막대, 동쪽 향함 — 축 0°). 사슬·도리깨 머리는 held_weapon.gd 가 그린다."""
    im = Image.new("RGBA", (15, 3), (0, 0, 0, 0))
    for x in range(15):
        draw_px(im, [(x, 0)], HANJI_DK if x > 2 else RED)     # 윗면 한지_dk(빛 쪽) — 나무 2색만으로는 흙 위에 묻혔다
        draw_px(im, [(x, 1)], WOOD if x > 2 else RED)
    draw_px(im, [(14, 0), (14, 1)], IRON_HI)
    return im


def make_bagaji():
    """쑥물 바가지(반원 7×4 + 손잡이 4px, 동쪽 향함)."""
    im = Image.new("RGBA", (11, 5), (0, 0, 0, 0))
    rows = ["....GGGGGGG", "hhhhGgggggG", "....GgggggG", ".....GgggG.", "......GGG.."]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "G":
                draw_px(im, [(x, y)], GOURD_DK)
            elif ch == "g":
                draw_px(im, [(x, y)], GOURD)
            elif ch == "h":
                draw_px(im, [(x, y)], WOOD)
    # 물(쑥물 = 황록 대신 팔레트 황 — 청 금지)
    draw_px(im, [(5, 1), (6, 1), (7, 1), (8, 1), (9, 1)], (169, 124, 27, 255))
    return im


def make_janggu_stick():
    """장구채(열채, 12px 가는 대 + 끝 마디, 동쪽 향함)."""
    im = Image.new("RGBA", (12, 2), (0, 0, 0, 0))
    for x in range(12):
        draw_px(im, [(x, 0)], WOOD if x < 10 else HANJI)
    draw_px(im, [(10, 1), (11, 1)], HANJI_DK)
    return im


HANJI_DK = (178, 157, 118, 255)


# ─── 본 그림 ───────────────────────────────────────────────────────

def from16(name, **kw):
    im = trim(strip_frame(load(ICONS / f"wpn_{name}_16.png"), band=4))
    return finish(im, **kw)


def from41(name, box=None, comp=None, **kw):
    im = strip_frame(load(ICONS / f"wpn_{name}.png"))
    if comp is not None:
        cs = sorted(components(im), key=len, reverse=True)
        keep = Image.new("RGBA", im.size, (0, 0, 0, 0))
        src = im.load()
        dst = keep.load()
        for (x, y) in comp(cs):
            dst[x, y] = src[x, y]
        im = keep
    if box is not None:
        im = im.crop(box)
    return finish(trim(im), **kw)


def finish(im, lift_k=None, hl=True, sat_max=0.45):
    if lift_k:
        im = lift(im, lift_k)
    if hl:
        im = highlight(im, sat_max=sat_max)
    out = outline(im)
    return soften_inner(out) if lift_k else out


def soften_inner(im, l_to=0.36):
    """겹 외곽선 풀기(검토 11-26): 바깥 먹 외곽선 바로 안쪽의 원래 아이콘 외곽선(어두운 픽셀)을 같은 색상의 중간 명도로.
    먹 1px 테는 바깥 하나만 남아 몸과 분리되고, 날·자루 면적은 어두운 흙 위에서도 읽힌다."""
    im = im.copy()
    px = im.load()
    src = im.copy().load()
    w, h = im.size
    def luma(c):
        return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    for y in range(h):
        for x in range(w):
            c = src[x, y]
            if c[3] == 0 or luma(c) >= 60:
                continue
            nb = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            if any(not opaque(src, nx, ny, w, h) for nx, ny in nb):
                continue                      # 바깥 외곽선(투명과 닿음)은 그대로
            hh, ll, ss = colorsys.rgb_to_hls(c[0] / 255, c[1] / 255, c[2] / 255)
            rr, gg, bb = colorsys.hls_to_rgb(hh, max(ll, l_to), min(ss, 0.35))
            px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), c[3])
    return im


def caltrop():
    s = load(SHEET2).crop((55, 57, 78, 80))
    px = s.load()
    for y in range(s.size[1]):
        for x in range(s.size[0]):
            c = px[x, y]
            if sum(c[:3]) < 15 or abs(c[0] - 22) + abs(c[1] - 28) + abs(c[2] - 35) < 18:
                px[x, y] = (0, 0, 0, 0)
    cs = sorted(components(s), key=len, reverse=True)
    one = Image.new("RGBA", s.size, (0, 0, 0, 0))
    dst = one.load()
    for (x, y) in cs[0]:
        dst[x, y] = px[x, y]
    one = trim(one)
    one = one.resize((max(1, one.size[0] // 2), max(1, one.size[1] // 2)), Image.NEAREST)   # 손에 쥘 크기(약 11px)
    return finish(one, lift_k=1.25)


def jakdu_blade():
    """41px 작두 그림 = 날 두 자루(손잡이·날 끝이 서로 닿음). x + y ≤ 40 쪽(왼쪽 위 날) 하나만, 자루 끝을 조금 잘라 26px 판."""
    im = strip_frame(load(ICONS / "wpn_jakdu.png"))
    px = im.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            if x + y > 40:
                px[x, y] = (0, 0, 0, 0)
    im = keep_components(im.crop((5, 3, 32, 30)), 6)
    return finish(trim(im), lift_k=JAKDU_LIFT)


def main():
    sprites = {
        # 붉은 무기
        "sinkal": from16("sinkal"),
        "jakdu": jakdu_blade(),
        "woldo": from41("woldo", box=(10, 0, 41, 31), lift_k=WOLDO_LIFT),
        "samjichang": from41("samjichang", box=(10, 0, 41, 31), lift_k=WOLDO_LIFT),
        "jangchang": from41("jangchang", box=(10, 0, 41, 31), lift_k=LONG_LIFT),
        "sainsageom": from16("sainsageom"),
        "gakgung": from16("gakgung", lift_k=1.9, sat_max=0.7),
        "pyeongon": outline(make_pyeongon_handle()),
        "maleumsoe": caltrop(),
        "hojakdo": from16("hojakdo"),
        # 흰 무기
        "bangul": from16("bangul", lift_k=BANGUL_LIFT),
        "buchae": from16("buchae", hl=False),
        "neokjeon": from16("neokjeon"),
        "jijeon": from16("jijeon"),
        "bagaji": outline(make_bagaji()),
        "myeongdu": from16("myeongdu", lift_k=1.1),
        "janggu": from16("janggu", lift_k=1.15),
        "janggu_chae": outline(make_janggu_stick()),
        "obanggi": from16("obanggi"),
    }
    # 진화 변형: 바깥 외곽선 황
    for k in list(sprites.keys()):
        sprites[k + "_evo"] = recolor_outer(sprites[k], HWANG)
    # 선반 배치(높이순)
    order = sorted(sprites.keys(), key=lambda k: (-sprites[k].size[1], k))
    W = 192
    x = y = row_h = 0
    rects = {}
    for k in order:
        w, h = sprites[k].size
        if x + w > W:
            x = 0
            y += row_h + 1
            row_h = 0
        rects[k] = [x, y, w, h]
        x += w + 1
        row_h = max(row_h, h)
    H = y + row_h
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for k, r in rects.items():
        atlas.paste(sprites[k], (r[0], r[1]))
    atlas.save(HERE / "held_atlas.png")
    meta = {
        "_doc": "손에 든 무기 아틀라스(design/19 §6.5). build_held_atlas.py 가 기존 ui/icons/wpn_*(16·41px)·icons_sheet_2 마름쇠를 잘라 "
                "틀 제거 + 한지 1px 하이라이트 + 먹 1px 외곽선. *_evo = 황 외곽선. 편곤 자루·바가지·장구채는 코드 그림. 쥐는 점·축은 data/held_weapons.json.",
        "sprites": {k: {"rect": rects[k]} for k in sorted(rects)},
    }
    (HERE / "held_atlas.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    print("atlas", W, H, {k: rects[k][2:] for k in sorted(rects) if not k.endswith("_evo")})


if __name__ == "__main__":
    main()
