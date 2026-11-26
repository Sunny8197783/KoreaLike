"""Hand-drawn (code-drawn) pixel props for stage Guksadang.

Run:  python -I tools/props_handdrawn.py
Writes game/assets/props/<prop_id>.png (+ _sheet.png/.json for animated props)
and game/assets/vfx/vfx_candle_flame_s.png/.json (pixelfx --sheet compatible).
Free (no PixelLab generations). Palette follows game/data/art_palette.json.
"""
import json, os, random
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PROPS = os.path.join(ROOT, "game", "assets", "props")
VFX = os.path.join(ROOT, "game", "assets", "vfx")
os.makedirs(PROPS, exist_ok=True); os.makedirs(VFX, exist_ok=True)

def hx(s, a=255):
    s = s.lstrip("#"); return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)

OL = hx("#1a1a1a")                      # hk outline
HJ = [hx(c) for c in ["#e9dcc0", "#d2c19c", "#b29d76", "#857154", "#5a4a37"]]   # hanji / straw
JK = [hx(c) for c in ["#f4a183", "#e4604f", "#c8322d", "#8c1f22", "#561318"]]   # red
HW = [hx(c) for c in ["#fff1b8", "#f5d66b", "#e8b931", "#a97c1b", "#6a4a12"]]   # yellow / brass
CH = [hx(c) for c in ["#a9caf5", "#5f93de", "#2a5caa", "#1b3a70", "#0f2142"]]   # blue
GH = [hx(c) for c in ["#26292e", "#3a3f46", "#535a62", "#6f7780"]]              # grey (charcoal)
EG = [hx(c) for c in ["#111a14", "#1a2a1e", "#26402b", "#3a5a3c", "#557652"]]   # env green
ET = [hx(c) for c in ["#1b1511", "#2c221a", "#433426", "#5e4b36", "#7c674b"]]   # earth
MK = [hx(c) for c in ["#0e0b16", "#17131f", "#221c2e", "#2f2840", "#3f3654", "#544a6b"]]
LIGHT = hx("#ffb35a")
T = (0, 0, 0, 0)

def canvas(w, h): return Image.new("RGBA", (w, h), T)

def put(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height: im.putpixel((x, y), c)

def rect(im, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1): put(im, x, y, c)

def outline(im, color=OL):
    """1px outside outline around every opaque pixel (4-neighbour)."""
    src = im.copy(); w, h = im.size
    for y in range(h):
        for x in range(w):
            if src.getpixel((x, y))[3]: continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src.getpixel((nx, ny))[3] and src.getpixel((nx, ny)) != color:
                    im.putpixel((x, y), color); break
    return im

def save(im, name): im.save(os.path.join(PROPS, name + ".png"))

def save_sheet(frames, name, fps, loop=True, pivot=None, folder=PROPS, extra=None):
    """Horizontal grid sheet + Aseprite-style JSON with meta.pixelfx (same shape as pixelfx --sheet)."""
    fw, fh = frames[0].size; n = len(frames)
    sheet = Image.new("RGBA", (fw * n, fh), T)
    for i, f in enumerate(frames): sheet.paste(f, (i * fw, 0))
    sheet.save(os.path.join(folder, name + ".png" if folder == VFX else name + "_sheet.png"))
    dur = round(1000 / fps)
    meta = {
        "frames": [{"filename": f"{name}_{i}", "frame": {"x": i * fw, "y": 0, "w": fw, "h": fh},
                    "rotated": False, "trimmed": False,
                    "spriteSourceSize": {"x": 0, "y": 0, "w": fw, "h": fh},
                    "sourceSize": {"w": fw, "h": fh}, "duration": dur} for i in range(n)],
        "meta": {"app": "KoreaLike tools/props_handdrawn.py", "image": (name + ".png") if folder == VFX else (name + "_sheet.png"),
                 "format": "RGBA8888", "size": {"w": fw * n, "h": fh}, "scale": "1",
                 "pixelfx": {"fps": fps, "loop": loop, "frameWidth": fw, "frameHeight": fh, "columns": n,
                             "pivot": pivot or {"x": fw // 2, "y": fh - 1}}}}
    if extra: meta["meta"]["korealike"] = extra
    json.dump(meta, open(os.path.join(folder, name + ".json" if folder == VFX else name + "_sheet.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

# ---------------------------------------------------------------- flame (4f)
# 5x7 flame, strong first frame, warm hanji-light palette. Used by chotdae, seokdeung, dangjip windows.
FLAME_ROWS = [
    # each frame: list of rows, chars: . empty, o outer(#e4604f), m mid(#ffb35a), y (#f5d66b), w core(#fff1b8)
    [".....", "..m..", ".mym.", ".myym", "myywm", "mywwm", ".mwm."],
    [".....", ".m...", ".mm..", ".mym.", "myyym", "mywwm", ".mwm."],
    ["..m..", "..m..", ".mym.", ".myym", "mywym", "mywwm", ".mwm."],
    [".....", "...m.", "..mm.", ".mym.", "myyym", "mywwm", ".mwm."],
]
FC = {"o": JK[1], "m": LIGHT, "y": HW[1], "w": HW[0]}

def flame_frame(i):
    im = canvas(5, 7)
    for y, row in enumerate(FLAME_ROWS[i]):
        for x, ch in enumerate(row):
            if ch != ".": im.putpixel((x, y), FC[ch])
    return im

def flame_vfx():
    frames = []
    for i in range(4):
        f = canvas(7, 9); f.alpha_composite(flame_frame(i), (1, 1))
        # tiny glow pixels at base sides on even frames
        if i % 2 == 0: put(f, 0, 7, hx("#ffb35a", 120)); put(f, 6, 7, hx("#ffb35a", 120))
        frames.append(f)
    save_sheet(frames, "vfx_candle_flame_s", fps=8, folder=VFX, pivot={"x": 3, "y": 8},
               extra={"light_color": "#ffb35a", "usage": "chotdae/seokdeung/dangjip window flicker"})
    return frames

# ---------------------------------------------------------------- geumjul segment 32x16
def geumjul():
    im = canvas(32, 16)
    # left-twisted straw rope (왼새끼): strands slant '\' ; rope y=3..6, tiles seamlessly every 4 px
    for x in range(32):
        for y in range(3, 7):
            phase = (x + y) % 4            # x+y => strands run down-left (left twist)
            c = HJ[1] if phase in (0, 1) else HJ[2]
            if phase == 3: c = HJ[3]
            put(im, x, y, c)
        put(im, x, 2, OL); put(im, x, 7, OL)
    def hang_string(x, y0, y1):
        for y in range(y0, y1 + 1): put(im, x, y, HJ[3])
    # red pepper (고추) at x=6
    hang_string(6, 8, 8); put(im, 6, 9, EG[3]); rect(im, 5, 10, 7, 12, JK[2]); put(im, 6, 13, JK[2]); put(im, 6, 14, JK[3])
    put(im, 5, 10, JK[1]); put(im, 7, 12, JK[3])
    # charcoal (숯) at x=16
    hang_string(16, 8, 9); rect(im, 15, 10, 17, 12, GH[1]); put(im, 15, 10, GH[2]); put(im, 17, 12, GH[0]); put(im, 16, 11, GH[0])
    # hanji paper tuft (한지 매듭) at x=25: folded zig-zag strip
    hang_string(25, 8, 8)
    for i, (dx, c) in enumerate([(0, HJ[0]), (1, HJ[0]), (0, HJ[1]), (-1, HJ[0]), (0, HJ[1]), (1, HJ[0])]):
        put(im, 25 + dx, 9 + i, c); put(im, 25 + dx + (1 if dx <= 0 else -1), 9 + i, HJ[1] if c == HJ[0] else HJ[2])
    # outline hanging items only (rope already outlined, keep it tileable)
    body = im.copy(); rope_band = canvas(32, 16)
    items = canvas(32, 16)
    for y in range(8, 16):
        for x in range(32):
            p = body.getpixel((x, y))
            if p[3]: items.putpixel((x, y), p)
    outline(items)
    for y in range(8, 16):
        for x in range(32):
            p = items.getpixel((x, y))
            if p[3]: im.putpixel((x, y), p)
    save(im, "prop_geumjul_seg")
    return im

# ---------------------------------------------------------------- chotdae pair 16x24, 4f flame
def chotdae_body():
    im = canvas(16, 24)
    for cx in (3, 12):
        # base (2 rows wide), stem, drip pan, candle
        rect(im, cx - 2, 21, cx + 2, 22, HW[3]); put(im, cx - 2, 21, HW[2]); put(im, cx + 2, 22, HW[4])
        rect(im, cx, 14, cx, 20, HW[3]); put(im, cx, 15, HW[2]); put(im, cx, 18, HW[2])
        rect(im, cx - 2, 13, cx + 2, 13, HW[2]); put(im, cx + 2, 13, HW[3])
        rect(im, cx - 1 + 0, 7, cx + 0, 12, HJ[0]); put(im, cx, 12, HJ[1]); put(im, cx, 8, HJ[1])
        # wax drip
        put(im, cx - 1, 9, HJ[0])
    outline(im)
    return im

def chotdae():
    base = chotdae_body(); frames = []
    for i in range(4):
        f = base.copy()
        for k, cx in enumerate((3, 12)):
            fl = flame_frame((i + k * 2) % 4)          # the two candles flicker out of phase
            f.alpha_composite(fl, (cx - 2 - 0, 0))
        frames.append(f)
    save(frames[0], "prop_chotdae_pair")
    save_sheet(frames, "prop_chotdae_pair", fps=8, pivot={"x": 8, "y": 22},
               extra={"light_color": "#ffb35a", "light_radius_u": 2, "light_points": [[3, 3], [12, 3]]})

# ---------------------------------------------------------------- yeondeung / chorong 16x24, off/on
def yeondeung():
    states = []
    for lit in (False, True):
        im = canvas(16, 24)
        rect(im, 7, 0, 8, 2, ET[3])                          # hanging hook / cord
        rect(im, 4, 3, 11, 4, ET[2]); put(im, 4, 3, ET[3])   # wooden top cap
        body = [HJ[0], HJ[0], HJ[1]] if lit else [HJ[3], HJ[3], HJ[4]]
        for y in range(5, 18):
            w = 4 if y in (5, 17) else 5
            for x in range(8 - w, 8 + w):
                edge = x in (8 - w, 8 + w - 1)
                c = body[2] if edge else body[0]
                if lit and not edge and 9 <= y <= 13 and 6 <= x <= 9: c = HW[0]
                put(im, x, y, c)
        for x in range(4, 12):                                # red silk bands (top/bottom)
            put(im, x, 6, JK[2] if lit else JK[3]); put(im, x, 16, JK[2] if lit else JK[3])
        for y in range(7, 16, 3):                             # ribs
            for x in (5, 10): put(im, x, y, HJ[2] if lit else HJ[4])
        rect(im, 5, 18, 10, 18, ET[2])                        # bottom cap
        rect(im, 7, 19, 8, 22, JK[2] if lit else JK[3])       # red tassel
        put(im, 6, 22, JK[3]); put(im, 9, 22, JK[3])
        outline(im)
        if lit:
            for (x, y) in ((2, 10), (13, 10), (2, 12), (13, 12)): put(im, x, y, hx("#ffb35a", 110))
        states.append(im)
    save(states[0], "prop_yeondeung_off"); save(states[1], "prop_yeondeung")
    save_sheet(states, "prop_yeondeung", fps=1, loop=False, pivot={"x": 8, "y": 0},
               extra={"object": "obj_gutpan_deungbul", "states": ["off", "on"], "light_color": "#ffb35a", "light_radius_u": 2})

# ---------------------------------------------------------------- neokjeon line 64x16, 2f sway
def neokjeon_figure(im, x, y, sway):
    # 넋전: 사람 모양 한지 오림 (머리 2x2, 팔 벌린 몸, 치마형 하단)
    rect(im, x + 1 + sway, y, x + 2 + sway, y + 1, HJ[0])
    rect(im, x - 0 + sway, y + 2, x + 3 + sway, y + 2, HJ[0])
    rect(im, x + 1 + sway, y + 3, x + 2 + sway, y + 4, HJ[0])
    rect(im, x + sway, y + 5, x + 3 + sway, y + 7, HJ[1]); put(im, x + 1 + sway, y + 6, HJ[2])

def jijeon_strip(im, x, y, sway, length=8):
    # 지전: 엽전 구멍 오림이 있는 한지 띠, 끝이 톱니
    for i in range(length):
        s = sway if i > 3 else 0
        rect(im, x + s, y + i, x + 2 + s, y + i, HJ[1] if i % 3 else HJ[0])
        if i % 3 == 1: put(im, x + 1 + s, y + i, HJ[3])   # coin hole
    put(im, x + sway, y + length, HJ[1]); put(im, x + 2 + sway, y + length, HJ[1])

def neokjeon():
    frames = []
    for f in range(2):
        im = canvas(64, 16)
        for x in range(64):                                    # straw string, slight sag
            y = 1 + (1 if 16 <= x < 48 else 0)
            put(im, x, y, HJ[3])
        items = canvas(64, 16)
        for k, x in enumerate(range(3, 62, 10)):
            sway = (1 if (k + f) % 2 else 0)
            ytop = 3 + (1 if 16 <= x < 48 else 0)
            if k % 2 == 0: neokjeon_figure(items, x, ytop, sway)
            else: jijeon_strip(items, x, ytop, sway, length=9)
        outline(items)
        im.alpha_composite(items)
        frames.append(im)
    save(frames[0], "prop_neokjeon_line")
    save_sheet(frames, "prop_neokjeon_line", fps=2, pivot={"x": 32, "y": 1})

# ---------------------------------------------------------------- obanggi bundle 32x64, 2f wave
def obanggi():
    # 청 적 황 백 흑 (백은 한지톤 #e9dcc0 — 예약 백 #f2ece0 금지, 흑은 먹보라+외곽선으로 밤 배경 위 가독)
    flags = [(CH[2], CH[3]), (JK[2], JK[3]), (HW[2], HW[3]), (HJ[0], HJ[2]), (MK[4], MK[3])]
    frames = []
    for f in range(2):
        im = canvas(32, 64)
        # wooden stand
        rect(im, 4, 56, 27, 59, ET[3]); rect(im, 4, 59, 27, 59, ET[2]); rect(im, 5, 56, 26, 56, ET[4])
        poles = [3, 8, 13, 18, 23]
        tops = [8, 5, 2, 5, 8]                            # fan shape: centre pole tallest
        for k, (px_, (c1, c2)) in enumerate(zip(poles, flags)):
            top = tops[k]
            rect(im, px_, top, px_, 55, HJ[2])           # bamboo pole
            put(im, px_, top - 1, HW[2])                 # finial
            fw, fh = 4, 20
            for yy in range(fh):
                for xx in range(fw):
                    # cloth: swallow-tail bottom edge + 1px wave in the free (right) half, alternating per frame
                    if yy >= fh - 2 and xx in (1, 2) and yy == fh - 1: continue
                    wave = 1 if (xx >= 2 and ((yy // 5 + f + k) % 2 == 0)) else 0
                    x = px_ + 1 + xx; y = top + 1 + yy
                    shade = c2 if (xx == fw - 1 or (yy // 5 + f) % 2 and xx == 2) else c1
                    put(im, x, y, shade)
                    if wave and yy == fh - 1: put(im, x, y + 1, c2)   # wave = cloth tip dips 1px
            put(im, px_ + 1, top + 1, HW[2])             # brass ring on pole
        outline(im)
        frames.append(im)
    save(frames[0], "prop_obanggi_bundle")
    save_sheet(frames, "prop_obanggi_bundle", fps=1, pivot={"x": 16, "y": 59},
               extra={"anim": "flag wave 2 frames, 1 beat each", "colors": ["청", "적", "황", "백", "흑"]})

# ---------------------------------------------------------------- sinjangdae 16x64, 2f cloth sway
OBANG5 = [CH[2], JK[2], HW[2], HJ[0], MK[4]]   # 청 적 황 백(한지톤) 흑(먹보라)

def sinjangdae():
    frames = []
    for f in range(2):
        im = canvas(16, 64)
        rect(im, 4, 60, 11, 61, ET[2]); rect(im, 5, 59, 10, 59, ET[3])            # earth mound
        for y in range(7, 60):                                                    # bamboo pole, 2px
            node = (y - 7) % 8 == 0
            put(im, 7, y, EG[2] if node else EG[3]); put(im, 8, y, EG[1] if node else EG[2])
            if node: put(im, 6, y, EG[2]); put(im, 9, y, EG[1])
        # bamboo leaf sprigs at the top (narrow leaves angled down, NOT a palm crown)
        leaves = [((7, 6), (-1, 1), 4), ((8, 5), (1, 1), 4), ((7, 3), (-1, 1), 3), ((8, 2), (1, 1), 3),
                  ((7, 1), (0, -1), 1), ((6, 9), (-1, 1), 3), ((9, 8), (1, 1), 3)]
        for (sx, sy), (dx, dy), n in leaves:
            for i in range(n + 1):
                put(im, sx + dx * i + (1 if f and i == n and dx else 0) * dx, sy + dy * i, EG[4] if i < n else EG[3])
        put(im, 7, 4, EG[3]); put(im, 8, 4, EG[3]); put(im, 7, 5, EG[3]); put(im, 8, 6, EG[2])
        # tie knot + five-colour cloth strips hanging both sides
        rect(im, 6, 11, 9, 12, JK[3])
        strips = [(5, 13, 14), (10, 13, 15), (4, 13, 11), (11, 13, 12), (3, 13, 9)]
        for k, (x, y, ln) in enumerate(strips):
            c = OBANG5[k]
            for i in range(ln):
                dx = (1 if f and i > ln // 2 else 0) * (1 if x > 8 else -1)
                put(im, x + dx, y + i, c)
        for k, x in enumerate((2, 13)):                                            # hanji zig-zag tassels
            for i in range(7):
                put(im, x + (i % 2) * (1 if k else -1) + ((1 if k else -1) if f and i > 3 else 0), 14 + i,
                    HJ[0] if i % 3 else HJ[1])
        outline(im)
        frames.append(im)
    save(frames[0], "prop_sinjangdae")
    save_sheet(frames, "prop_sinjangdae", fps=1, pivot={"x": 8, "y": 61},
               extra={"anim": "cloth sway 2 frames, 1 beat each"})

# ---------------------------------------------------------------- sotdae 16x64 (pole + 3 wooden ducks)
def sotdae():
    im = canvas(16, 64)
    rect(im, 5, 61, 10, 62, ET[2])
    for y in range(12, 61):
        put(im, 7, y, ET[4] if y % 9 else ET[3]); put(im, 8, y, ET[3])
    for i in range(5): put(im, 7 - i, 12 - i, ET[3]); put(im, 8 + i, 12 - i, ET[3])   # Y fork
    rect(im, 7, 4, 8, 11, ET[4]); put(im, 8, 6, ET[3])
    def duck(x, y):   # facing right: tail, body, raised head, beak
        rect(im, x, y + 1, x + 4, y + 2, HJ[2]); put(im, x, y + 1, HJ[3]); put(im, x + 1, y + 2, HJ[3])
        put(im, x + 3, y, HJ[1]); put(im, x + 4, y, HJ[1]); put(im, x + 4, y - 1, HJ[1]); put(im, x + 5, y - 1, HW[3])
        put(im, x + 2, y + 1, HJ[1])
    duck(0, 5); duck(9, 5); duck(5, 1)
    outline(im)
    save(im, "prop_sotdae")

# ---------------------------------------------------------------- decals
def decals():
    rnd = random.Random(7); out = {}
    flower_cols = [(CH[1], CH[2]), (HJ[1], HJ[2]), (HW[2], HW[3]), (MK[5], MK[4]), (JK[1], JK[3]), (hx("#8a6aa8"), MK[5])]
    for i, (c1, c2) in enumerate(flower_cols):
        im = canvas(8, 8)
        for (x, y) in ((2, 5), (3, 6), (5, 4), (4, 7)): put(im, x, y, EG[3])        # stems/leaves
        put(im, 1, 6, EG[2]); put(im, 6, 6, EG[2])
        for (px, py) in ((3, 3), (5, 2)) if i % 2 == 0 else ((2, 3), (5, 3)):
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)): put(im, px + dx, py + dy, c1)
            put(im, px, py, HW[1] if c1 != HW[2] else HJ[0]); put(im, px + 1, py + 1, c2)
        out[f"decal_flower_{i+1}"] = im
    for i in range(3):
        im = canvas(12, 12)
        for n in range(5 + i):                                  # pine needle pairs (V shapes)
            x, y = rnd.randint(1, 9), rnd.randint(2, 10)
            d = rnd.choice((-1, 1))
            for k in range(3): put(im, x + k * d, y - k, ET[4] if k else ET[3]); put(im, x + k * d, y + 0 - k // 2 + 1, ET[3])
        out[f"decal_needles_{i+1}"] = im
    leaf_cols = [(hx("#8a4a2a"), hx("#5e2e1c")), (HW[3], HW[4]), (ET[4], ET[3])]
    for i, (c1, c2) in enumerate(leaf_cols):
        im = canvas(8, 8)
        shape = ["........", "...xx...", "..xxxx..", ".xxxxxx.", ".xxxxx..", "..xxx...", "...x....", "..x....."]
        for y, row in enumerate(shape):
            for x, ch in enumerate(row):
                if ch == "x": put(im, x, y, c1 if (x + y) % 3 else c2)
        for k in range(2, 6): put(im, 6 - k, k + 1, c2)       # midrib
        im = im.rotate([0, 90, 200][i], expand=False)
        outline(im, MK[1])
        out[f"decal_leaf_{i+1}"] = im
    # also one atlas
    keys = list(out); atlas = canvas(12 * len(keys), 12)
    for k, key in enumerate(keys):
        save(out[key], key); atlas.alpha_composite(out[key], (k * 12, 0))
    atlas.save(os.path.join(PROPS, "decal_set_atlas.png"))
    json.dump({"cell": 12, "order": keys}, open(os.path.join(PROPS, "decal_set_atlas.json"), "w"), indent=1)
    return keys

if __name__ == "__main__":
    flame_vfx(); geumjul(); chotdae(); yeondeung(); neokjeon(); obanggi(); sinjangdae(); sotdae(); keys = decals()
    print("ok", keys)
