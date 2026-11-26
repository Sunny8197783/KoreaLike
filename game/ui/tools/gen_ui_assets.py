# -*- coding: utf-8 -*-
"""UI 스킨·아이콘 생성기. 소유: ui.
실행: python ui/tools/gen_ui_assets.py   (game/ 기준, PIL 필요)
출력:
  ui/icons/<id>.png        아이콘 시트(assets/icons/icons_sheet_*.png) 슬라이스 — 배경 투명, 원본 픽셀 그대로(약 38px)
  ui/icons/<id>_16.png     HUD 슬롯용 16px 축소본(면적 평균 + 알파 문턱)
  ui/theme/skin/*.png      한지·먹·단청 9-patch 패널, 버튼, 카드 띠, 단청 띠, 인장, 한지 바탕 타일
색은 캐논 팔레트(core/k.gd, design/11 §2.4)만 쓴다. 백(#f2ece0)은 쓰지 않는다(월드 전용).
"""
import os
import random
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # game/
ICON_SRC = os.path.join(ROOT, "assets", "icons")
ICON_OUT = os.path.join(ROOT, "ui", "icons")
SKIN_OUT = os.path.join(ROOT, "ui", "theme", "skin")

MEOK = (14, 11, 22)
MEOK2 = (34, 28, 46)
PANEL = (42, 34, 56)
HANJI = (233, 220, 192)
HANJI_DK = (178, 157, 118)
HANJI_MID = (210, 193, 156)
INK = (58, 47, 42)
JEOK = (200, 50, 45)
JEOK_DK = (140, 31, 34)
HWANG = (232, 185, 49)
HWANG_DK = (138, 116, 64)
NOK = (62, 106, 90)       # 단청 뇌록(dc 램프)
NOK_HI = (85, 184, 170)
CHEONG_DC = (59, 79, 110)  # 단청 청(dc 램프, 예약 청 아님)
DANJU = (122, 58, 44)      # 단청 석간주

SHEETS = {
    "icons_sheet_1.png": ["wpn_bangul", "wpn_buchae", "wpn_sinkal", "wpn_woldo",
                          "wpn_samjichang", "wpn_jakdu", "wpn_myeongdu", "wpn_obanggi"],
    "icons_sheet_2.png": ["wpn_janggu", "ico_jing", "wpn_sainsageom", "wpn_gakgung",
                          "wpn_jangchang", None, None, "ico_yeopjeon"],  # 철질려(폐기)·부적(호작도 사용 금지) 제외
}


def _near(c, ref, tol):
    return abs(c[0] - ref[0]) <= tol and abs(c[1] - ref[1]) <= tol and abs(c[2] - ref[2]) <= tol


def slice_icons():
    os.makedirs(ICON_OUT, exist_ok=True)
    bgs = [(21, 22, 29), (30, 32, 39)]
    for sheet, ids in SHEETS.items():
        im = Image.open(os.path.join(ICON_SRC, sheet)).convert("RGBA")
        for i, wid in enumerate(ids):
            if wid is None:
                continue
            cx, cy = (i % 4) * 50, (i // 4) * 50
            cell = im.crop((cx + 4, cy + 4, cx + 45, cy + 45))
            w, h = cell.size
            px = cell.load()
            # 테두리에서 배경색 범람 채우기 → 투명
            seen = set()
            stack = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + \
                    [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
            while stack:
                x, y = stack.pop()
                if (x, y) in seen or x < 0 or y < 0 or x >= w or y >= h:
                    continue
                seen.add((x, y))
                c = px[x, y]
                if any(_near(c, b, 14) for b in bgs) or c[3] == 0:
                    px[x, y] = (0, 0, 0, 0)
                    stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            bbox = cell.getbbox()
            if bbox:
                cell = cell.crop(bbox)
            # 정사각 캔버스 가운데
            s = max(cell.size)
            sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            sq.paste(cell, ((s - cell.size[0]) // 2, (s - cell.size[1]) // 2))
            sq.save(os.path.join(ICON_OUT, wid + ".png"))
            small = sq.resize((16, 16), Image.BOX)
            sp = small.load()
            for y in range(16):
                for x in range(16):
                    r, g, b, a = sp[x, y]
                    sp[x, y] = (r, g, b, 255 if a >= 110 else 0)
            small.save(os.path.join(ICON_OUT, wid + "_16.png"))
            print("icon", wid, sq.size)


# ─── 스킨 ──────────────────────────────────────────────────────────────

def noise_fill(img, box, base, var, seed, fibers=0, fiber_col=None):
    rnd = random.Random(seed)
    d = img.load()
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            k = rnd.randint(-var, var)
            d[x, y] = (max(0, min(255, base[0] + k)), max(0, min(255, base[1] + k)), max(0, min(255, base[2] + k)), 255)
    # 한지 섬유: 짧은 굽은 털
    for _ in range(fibers):
        x = rnd.randint(x0, x1 - 1)
        y = rnd.randint(y0, y1 - 1)
        ln = rnd.randint(2, 5)
        dx, dy = rnd.choice([(1, 0), (0, 1), (1, 1), (1, -1)])
        for j in range(ln):
            xx, yy = x + dx * j, y + dy * j + (1 if j == ln // 2 and rnd.random() < 0.5 else 0)
            if x0 <= xx < x1 and y0 <= yy < y1:
                d[xx, yy] = fiber_col + (255,)


def corner_dancheong(img, x, y, flip_x, flip_y):
    """4×4 단청 모서리 장식(design/11 pal_focus: 단청 모서리 4 lpx)."""
    pat = [
        [HWANG, HWANG, NOK, None],
        [HWANG, DANJU, NOK, None],
        [NOK, NOK, CHEONG_DC, None],
        [None, None, None, None],
    ]
    d = img.load()
    for j in range(4):
        for i in range(4):
            c = pat[j][i]
            if c is None:
                continue
            xx = x + (3 - i if flip_x else i)
            yy = y + (3 - j if flip_y else j)
            d[xx, yy] = c + (255,)


def rect_outline(img, box, col):
    dr = ImageDraw.Draw(img)
    dr.rectangle(box, outline=col + (255,) if len(col) == 3 else col)


def panel_meok(name, size=24, alpha=236, corners=True, inner=HANJI_DK):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    noise_fill(img, (1, 1, size - 1, size - 1), (27, 21, 38), 2, 11)
    # 반투명 바탕
    d = img.load()
    for y in range(1, size - 1):
        for x in range(1, size - 1):
            r, g, b, _ = d[x, y]
            d[x, y] = (r, g, b, alpha)
    rect_outline(img, (0, 0, size - 1, size - 1), MEOK)
    rect_outline(img, (1, 1, size - 2, size - 2), inner)
    rect_outline(img, (2, 2, size - 3, size - 3), (20, 15, 28))
    if corners:
        corner_dancheong(img, 1, 1, False, False)
        corner_dancheong(img, size - 5, 1, True, False)
        corner_dancheong(img, 1, size - 5, False, True)
        corner_dancheong(img, size - 5, size - 5, True, True)
    img.save(os.path.join(SKIN_OUT, name))


def panel_hanji(name, size=32, seed=3, border=INK, corners=True):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    noise_fill(img, (1, 1, size - 1, size - 1), HANJI, 4, seed, fibers=10, fiber_col=HANJI_MID)
    rect_outline(img, (0, 0, size - 1, size - 1), border)
    rect_outline(img, (1, 1, size - 2, size - 2), HANJI_DK)
    if corners:
        corner_dancheong(img, 1, 1, False, False)
        corner_dancheong(img, size - 5, 1, True, False)
        corner_dancheong(img, 1, size - 5, False, True)
        corner_dancheong(img, size - 5, size - 5, True, True)
    img.save(os.path.join(SKIN_OUT, name))


def button(name, fill, fill_a, border, border2=None, corners=False, size=16):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    noise_fill(img, (1, 1, size - 1, size - 1), fill, 2, 5)
    d = img.load()
    for y in range(1, size - 1):
        for x in range(1, size - 1):
            r, g, b, _ = d[x, y]
            d[x, y] = (r, g, b, fill_a)
    rect_outline(img, (0, 0, size - 1, size - 1), border)
    if border2:
        rect_outline(img, (1, 1, size - 2, size - 2), border2)
    if corners:
        corner_dancheong(img, 0, 0, False, False)
        corner_dancheong(img, size - 4, 0, True, False)
        corner_dancheong(img, 0, size - 4, False, True)
        corner_dancheong(img, size - 4, size - 4, True, True)
    img.save(os.path.join(SKIN_OUT, name))


def dancheong_strip(name):
    """가로 이음 단청 띠 16×6: 녹·주·황 반복(머리초 단순화)."""
    w, h = 16, 6
    img = Image.new("RGBA", (w, h), MEOK + (255,))
    d = img.load()
    for x in range(w):
        d[x, 0] = DANJU + (255,)
        d[x, 5] = MEOK + (255,)
        d[x, 1] = NOK + (255,)
        d[x, 4] = NOK + (255,)
    # 가운데 연화 점 + 주 사선
    for x in range(w):
        m = x % 8
        c = [CHEONG_DC, NOK_HI, HWANG, JEOK_DK, JEOK_DK, HWANG, NOK_HI, CHEONG_DC][m]
        d[x, 2] = c + (255,)
        d[x, 3] = (c if m in (2, 5) else NOK) + (255,)
    img.save(os.path.join(SKIN_OUT, name))


def seal(name, size=14):
    """붉은 인장(낙관): 거친 가장자리 적색 정사각."""
    rnd = random.Random(7)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = img.load()
    for y in range(size):
        for x in range(size):
            edge = x in (0, size - 1) or y in (0, size - 1)
            if edge and rnd.random() < 0.35:
                continue
            k = rnd.randint(-10, 10)
            d[x, y] = (min(255, JEOK[0] + k), JEOK[1], JEOK[2], 255 if not edge else 220)
    img.save(os.path.join(SKIN_OUT, name))


def hanji_tile(name, size=64):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    noise_fill(img, (0, 0, size, size), (38, 31, 48), 2, 21, fibers=40, fiber_col=(52, 43, 60))
    img.save(os.path.join(SKIN_OUT, name))


def hanji_tile_light(name, size=64):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    noise_fill(img, (0, 0, size, size), HANJI, 4, 31, fibers=60, fiber_col=HANJI_MID)
    img.save(os.path.join(SKIN_OUT, name))


def bar_frame(name):
    """게이지 테: 먹 2겹 + 황동 모서리 점. 10×8, 여백 3."""
    w, h = 10, 8
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.rectangle((0, 0, w - 1, h - 1), outline=MEOK + (255,))
    dr.rectangle((1, 1, w - 2, h - 2), outline=HWANG_DK + (255,))
    d = img.load()
    for (x, y) in [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]:
        d[x, y] = HWANG + (255,)
    img.save(os.path.join(SKIN_OUT, name))


def vignette(name, w=160, h=90):
    """화면 가장자리 먹 비네트(타이틀·정산 위)."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = img.load()
    for y in range(h):
        for x in range(w):
            nx = (x + 0.5) / w * 2 - 1
            ny = (y + 0.5) / h * 2 - 1
            r = (nx * nx * 0.9 + ny * ny * 1.1) ** 0.5
            a = max(0.0, min(1.0, (r - 0.55) / 0.6))
            d[x, y] = MEOK + (int(235 * a * a),)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    img.save(os.path.join(SKIN_OUT, name))


def make_skin():
    os.makedirs(SKIN_OUT, exist_ok=True)
    panel_meok("panel_meok.png")
    panel_meok("panel_meok_plain.png", corners=False, alpha=220, inner=(74, 60, 52))
    panel_hanji("panel_hanji.png")
    panel_hanji("panel_hanji_plain.png", corners=False, seed=9)
    button("btn_normal.png", (32, 25, 44), 200, (74, 60, 52))
    button("btn_hover.png", (48, 38, 62), 230, HWANG_DK)
    button("btn_focus.png", (52, 40, 64), 240, HWANG, MEOK, corners=True)
    button("btn_pressed.png", (70, 30, 34), 240, HWANG, MEOK, corners=True)
    button("btn_disabled.png", (24, 20, 30), 150, (50, 44, 50))
    button("chip_meok.png", (24, 19, 33), 210, (20, 15, 28), (74, 60, 52), size=10)
    dancheong_strip("dancheong_strip.png")
    seal("seal_red.png")
    hanji_tile("tile_meok_paper.png")
    hanji_tile_light("tile_hanji_paper.png")
    bar_frame("bar_frame.png")
    vignette("vignette.png")
    print("skin ok")


# 아이콘 시트에 없는 무구: 무구 이펙트 스프라이트(마스터 팔레트·이진 알파)에서 한 프레임을 잘라 HUD 16px 로.
# 나머지(평곤·철질려·길베·쑥물·소금)는 런타임 대체 표지(UiKit.draw_glyph_medallion)를 쓴다.
VFX_ICONS = {
    "wpn_neokjeon": ("vfx_neokjeon_doll.png", (0, 0, 16, 16)),
    "wpn_hojakdo": ("vfx_hojakdo_sehwa.png", (0, 8, 16, 24)),
    "wpn_jijeon": ("vfx_jijeon_bill.png", (0, 0, 16, 16)),
}


def vfx_icons():
    src = os.path.join(ROOT, "assets", "vfx")
    for wid, (fn, box) in VFX_ICONS.items():
        im = Image.open(os.path.join(src, fn)).convert("RGBA").crop(box)
        bb = im.getbbox()
        out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        if bb:
            part = im.crop(bb)
            out.paste(part, ((16 - part.width) // 2, (16 - part.height) // 2))
        px = out.load()
        for y in range(16):
            for x in range(16):
                r, g, b_, a = px[x, y]
                px[x, y] = (r, g, b_, 255) if a >= 128 else (0, 0, 0, 0)
        out.save(os.path.join(ICON_OUT, wid + "_16.png"))
        print("vfx icon", wid, bb)


if __name__ == "__main__":
    import sys
    if "--vfx-icons" in sys.argv:
        vfx_icons()
    else:
        slice_icons()
        vfx_icons()
        make_skin()
