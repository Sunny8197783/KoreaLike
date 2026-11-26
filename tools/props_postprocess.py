"""Post-process PixelLab-generated stage props (art/props_src -> game/assets/props).

Run: python -I tools/props_postprocess.py
- copies finished props, trims nothing (canvas size = spec size)
- adds the 4-frame candle flicker to lm_guksadang_dangjip (window glow recolour)
- adds pixelfx-format flame frames to prop_seokdeung
- builds the obj_gongmulsang 4 states (full, 2/3, 1/3, empty) from prop_gutsang by erasing food regions
"""
import json, os, shutil, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import props_handdrawn as H

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "art", "props_src")
DST = H.PROPS

def load(name): return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")

def copy_plain(names):
    for n in names:
        p = os.path.join(SRC, n + ".png")
        if os.path.exists(p): shutil.copyfile(p, os.path.join(DST, n + ".png"))

def recolor(im, mapping):
    out = im.copy(); px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if p[3] and p[:3] in mapping: px[x, y] = mapping[p[:3]] + (p[3],)
    return out

def h3(s): s = s.lstrip("#"); return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))

def dangjip():
    base = load("lm_guksadang_dangjip")
    g1, g2, g3 = h3("#e1b343"), h3("#ecd37f"), h3("#bb853d")
    frames = [base,
              recolor(base, {g2: g1, g1: h3("#c99a36"), g3: h3("#a2722f")}),
              recolor(base, {g2: h3("#f3e09c"), g1: h3("#e8bd4e")}),
              recolor(base, {g2: h3("#e4c46c"), g1: h3("#d4a83e"), g3: h3("#ad7b35")})]
    frames[0].save(os.path.join(DST, "lm_guksadang_dangjip.png"))
    H.save_sheet(frames, "lm_guksadang_dangjip", fps=6, pivot={"x": 96, "y": 120},
                 extra={"anim": "window candle flicker", "light_color": "#ffb35a", "collision": "foundation rect"})

def flame_on(name, points, fps=8, extra=None):
    """Composite the 4-frame flame (vfx_candle_flame_s) at given (x,y) top-left points."""
    p = os.path.join(SRC, name + ".png")
    if not os.path.exists(p): return False
    base = load(name); frames = []
    for i in range(4):
        f = base.copy()
        for k, (x, y) in enumerate(points): f.alpha_composite(H.flame_frame((i + k) % 4), (x, y))
        frames.append(f)
    frames[0].save(os.path.join(DST, name + ".png"))
    H.save_sheet(frames, name, fps=fps, pivot={"x": base.width // 2, "y": base.height - 2}, extra=extra)
    return True

import colorsys

def ramp_map(im, select, ramp):
    """Pixels for which select(h,s,v) is true are re-mapped onto `ramp` (dark->light hex list) by their value rank."""
    out = im.copy(); px = out.load(); R = [h3(c) for c in ramp]
    vals = sorted({colorsys.rgb_to_hsv(*[c / 255 for c in px[x, y][:3]])[2]
                   for y in range(out.height) for x in range(out.width)
                   if px[x, y][3] and select(*colorsys.rgb_to_hsv(*[c / 255 for c in px[x, y][:3]]))})
    if not vals: return out
    lo, hi = vals[0], vals[-1]
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if not p[3]: continue
            h, s, v = colorsys.rgb_to_hsv(*[c / 255 for c in p[:3]])
            if select(h, s, v):
                t = 0 if hi == lo else (v - lo) / (hi - lo)
                px[x, y] = R[min(len(R) - 1, int(t * len(R)))] + (p[3],)
    return out

def hsv_scale(im, select, ks=1.0, kv=1.0):
    out = im.copy(); px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if not p[3]: continue
            h, s, v = colorsys.rgb_to_hsv(*[c / 255 for c in p[:3]])
            if select(h, s, v):
                r, g, b = colorsys.hsv_to_rgb(h, min(1, s * ks), min(1, v * kv))
                px[x, y] = (round(r * 255), round(g * 255), round(b * 255), p[3])
    return out

BARK = ["#1b1511", "#2c221a", "#433426", "#5e4b36", "#7c674b"]
STONE = ["#26292e", "#3a3f46", "#535a62", "#6f7780", "#8f979e"]
OBANG = ["#2a5caa", "#c8322d", "#e8b931", "#e9dcc0", "#3f3654"]   # 청 적 황 백(한지톤) 흑(먹 보라: 밤 배경 위 가독)

def cloth_strips(base, anchors, frames=2):
    """Hang 1px-wide five-colour cloth strips from anchor points; frame 1 sways the lower half by 1px."""
    out = []
    for f in range(frames):
        im = base.copy()
        for k, (x, y, ln) in enumerate(anchors):
            c = h3(OBANG[k % 5]); dark = tuple(max(0, int(v * 0.7)) for v in c)
            for i in range(ln):
                dx = (1 if (f == 1 and i >= ln // 2) else 0) * (1 if k % 2 else -1)
                H.put(im, x + dx, y + i, (c if i < ln - 1 else dark) + (255,))
            H.put(im, x - 1 + (1 if f == 1 else 0) * (1 if k % 2 else -1), y + ln - 1, H.OL)
        out.append(im)
    return out

def doltap():
    p = os.path.join(SRC, "prop_seonang_doltap.png")
    if not os.path.exists(p): return
    im = load("prop_seonang_doltap")
    im = ramp_map(im, lambda h, s, v: s > 0.2 and (h < 0.1 or h > 0.9), BARK[1:])
    im = ramp_map(im, lambda h, s, v: s <= 0.2 and v > 0.2, STONE)
    anchors = [(10, 20, 5), (14, 19, 6), (19, 16, 5), (30, 11, 6), (35, 11, 5), (38, 6, 4), (25, 13, 6)]
    frames = cloth_strips(im, anchors)
    frames[0].save(os.path.join(DST, "prop_seonang_doltap.png"))
    H.save_sheet(frames, "prop_seonang_doltap", fps=1, pivot={"x": 24, "y": 44},
                 extra={"anim": "five-colour cloth sway, 2 frames, 1 beat each"})

def erase_regions(im, regions):
    out = im.copy(); px = out.load()
    for (x0, y0, x1, y1, fill) in regions:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if px[x, y][3]: px[x, y] = fill
    return out

def seokdeung():
    """Flatten the up-turned roof horns (reads Japanese toro otherwise) + 4-frame window flame flicker."""
    p = os.path.join(SRC, "prop_seokdeung.png")
    if not os.path.exists(p): return
    im = load("prop_seokdeung"); px = im.load()
    edge = px[7, 8]                                    # roof outline colour
    for (x, y) in [(3, 7), (2, 8), (3, 8), (4, 8), (28, 7), (27, 8), (28, 8), (29, 8)]: px[x, y] = (0, 0, 0, 0)
    for x in list(range(2, 7)) + list(range(25, 30)): px[x, 9] = edge
    im = ramp_map(im, lambda h, s, v: s <= 0.25, STONE)  # granite to the shared cold-grey ramp (prop luminance cap)
    a, b, c, d = h3("#fefcaf"), h3("#f6c57f"), h3("#c48154"), h3("#aa6b4b")
    frames = [im,
              recolor(im, {a: b, b: c, c: d}),
              recolor(im, {a: h3("#fff1b8"), b: h3("#ffb35a")}),
              recolor(im, {a: h3("#f5d66b"), b: h3("#e8a04a"), c: h3("#b47248")})]
    frames[0].save(os.path.join(DST, "prop_seokdeung.png"))
    H.save_sheet(frames, "prop_seokdeung", fps=8, pivot={"x": 16, "y": 45},
                 extra={"light_color": "#ffb35a", "light_radius_u": 2, "light_point": [16, 18]})

def stairs():
    p = os.path.join(SRC, "prop_stone_stairs.png")
    if not os.path.exists(p): return
    im = load("prop_stone_stairs")
    im = ramp_map(im, lambda h, s, v: True, STONE)
    H.outline(im)
    im.save(os.path.join(DST, "prop_stone_stairs.png"))

def sinjangdae():
    """Crop the PixelLab bamboo to 16x64 and tie five-colour cloth + hanji tassels on (2 frames)."""
    p = os.path.join(SRC, "prop_sinjangdae_raw.png")
    if not os.path.exists(p): return
    im = load("prop_sinjangdae_raw").crop((7, 0, 23, 64))
    im = hsv_scale(im, lambda h, s, v: 0.15 < h < 0.45, ks=0.8, kv=0.75)   # quieter bamboo green at night
    anchors = [(6, 16, 12), (10, 16, 13), (5, 17, 10), (11, 17, 11), (4, 18, 9)]
    frames = cloth_strips(im, anchors)
    for f, fr in enumerate(frames):              # hanji tassels (zig-zag paper) on both sides
        for k, x in enumerate((3, 12)):
            for i in range(6):
                dx = (i % 2) * (1 if k else -1) + (1 if f and i > 2 else 0)
                H.put(fr, x + dx, 18 + i, H.HJ[0] if i % 3 else H.HJ[1])
    frames[0].save(os.path.join(DST, "prop_sinjangdae.png"))
    H.save_sheet(frames, "prop_sinjangdae", fps=1, pivot={"x": 8, "y": 60},
                 extra={"anim": "cloth sway 2 frames, 1 beat each"})

def wind_frame(im, rows_frac=0.55, dx=1):
    """2nd wind frame: shift the upper part of the sprite 1px sideways (top rows only, base stays planted)."""
    out = H.canvas(*im.size); h = im.height
    bbox = im.getbbox()
    if not bbox: return im.copy()
    top, bot = bbox[1], bbox[3]
    cut = top + int((bot - top) * rows_frac)
    for y in range(h):
        for x in range(im.width):
            p = im.getpixel((x, y))
            if not p[3]: continue
            nx = x + (dx if y < cut else 0)
            if 0 <= nx < im.width: out.putpixel((nx, y), p)
    return out

def bushes():
    names = []
    for src, tags in (("_bush_pair_ab", ("a", "b")), ("_bush_pair_cd", ("c", "d"))):
        p = os.path.join(SRC, src + ".png")
        if not os.path.exists(p): continue
        pair = load(src)
        for i, tag in enumerate(tags):
            half = pair.crop((i * 32, 0, i * 32 + 32, 32))
            bb = half.getbbox()
            if not bb: continue
            name = f"prop_bush_{tag}"
            frames = [half, wind_frame(half)]
            half.save(os.path.join(DST, name + ".png"))
            H.save_sheet(frames, name, fps=2, pivot={"x": 16, "y": bb[3] - 1},
                         extra={"collision": "none", "anim": "wind 2 frames"})
            names.append(name)
    return names

GREEN = lambda h, s, v: 0.17 < h < 0.48 and s > 0.15
BARKSEL = lambda h, s, v: (h < 0.09 or h > 0.9) and s > 0.2

NIGHT_RULES = {   # night-yard grading so props sit under environment_prop_max_relative_luminance
    "prop_pine_a": [("hsv", GREEN, 0.75, 0.72), ("hsv", BARKSEL, 0.72, 0.75)],
    "prop_pine_b": [("hsv", GREEN, 0.75, 0.72), ("hsv", BARKSEL, 0.72, 0.75)],
    "prop_pine_c": [("hsv", GREEN, 0.75, 0.72), ("hsv", BARKSEL, 0.72, 0.75)],
    "lm_guksadang_pine_hill": [("hsv", GREEN, 0.8, 0.8), ("hsv", BARKSEL, 0.75, 0.8)],
    "prop_rock_s": [("ramp", lambda h, s, v: s <= 0.35, STONE)],
    "prop_rock_m": [("ramp", lambda h, s, v: s <= 0.35, STONE)],
    "prop_rock_l": [("ramp", lambda h, s, v: s <= 0.35, STONE)],
    "prop_jangseung_pair": [("hsv", lambda h, s, v: (h < 0.04 or h > 0.93) and s > 0.4, 0.85, 0.9)],
}

def night(names):
    for n in names:
        p = os.path.join(SRC, n + ".png")
        if not os.path.exists(p): continue
        im = load(n)
        for rule in NIGHT_RULES.get(n, []):
            if rule[0] == "hsv": im = hsv_scale(im, rule[1], rule[2], rule[3])
            else: im = ramp_map(im, rule[1], rule[2])
        im.save(os.path.join(DST, n + ".png"))

def bush_grade():
    for t in "abcd":
        for suffix in ("", "_sheet"):
            p = os.path.join(DST, f"prop_bush_{t}{suffix}.png")
            if os.path.exists(p):
                hsv_scale(Image.open(p).convert("RGBA"), GREEN, 0.75, 0.7).save(p)

def gongmulsang():
    """obj_gongmulsang 4 states from prop_gutsang: full, 2/3, 1/3, empty (offerings erased, table top restored)."""
    p = os.path.join(SRC, "prop_gutsang.png")
    if not os.path.exists(p): return
    base = load("prop_gutsang")
    groups = {"fruit_l": (9, 16), "tteok": (17, 25), "center": (26, 38), "fruit_r": (39, 49), "bottle": (50, 55)}
    def clear(im, names):
        out = im.copy(); px = out.load()
        for n in names:
            a, b = groups[n]
            for x in range(a, b + 1):
                for y in range(0, 13): px[x, y] = (0, 0, 0, 0)
                px[x, 13] = h3("#6b4251") + (255,)
                for y in range(14, 18): px[x, y] = h3("#7c5057") + (255,)
        return out
    states = [base, clear(base, ["fruit_l", "fruit_r"]), clear(base, ["fruit_l", "fruit_r", "tteok", "bottle"]),
              clear(base, list(groups))]
    base.save(os.path.join(DST, "prop_gutsang.png"))
    for name, im in zip(["full", "2_3", "1_3", "empty"], states):
        im.save(os.path.join(DST, f"obj_gongmulsang_{name}.png"))
    H.save_sheet(states, "obj_gongmulsang", fps=1, loop=False, pivot={"x": 32, "y": 24},
                 extra={"states": ["full", "2_3", "1_3", "empty"], "source_prop": "prop_gutsang"})

if __name__ == "__main__":
    if "gongmulsang" in sys.argv: gongmulsang()
    if "seokdeung" in sys.argv: seokdeung()
    if "stairs" in sys.argv: stairs()
    if "bushes" in sys.argv: print(bushes()); bush_grade()
    what = sys.argv[1:] or ["dangjip"]
    if "dangjip" in what: dangjip()
    if "doltap" in what: doltap()
    if "copy" in what:   # props used as generated (no post-process step)
        copy_plain(["lm_guksadang_seonbawi", "lm_guksadang_pine_hill", "prop_pine_a", "prop_pine_b", "prop_pine_c",
                    "prop_rock_s", "prop_rock_m", "prop_rock_l", "prop_jangseung_pair", "prop_musindo_hanging",
                    "prop_jangdok"])
        night(list(NIGHT_RULES))
    print("done", what)
