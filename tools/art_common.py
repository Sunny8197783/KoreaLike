"""art_common — art_lint.py / art_post.py 공용 모듈 (Python 3 + Pillow만 사용).

ART_STYLE.md 1.3(규격표)·3.1(마스터 팔레트)·3.2(색 예산)·3.5(lint 사양)를 코드로 옮긴 것.
마스터 팔레트의 단일 소스는 tools/master_palette.json 이다(build_master_palette()가 생성).
"""
from __future__ import annotations

import json
import math
import os
import re
from collections import Counter

from PIL import Image

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
MASTER_PALETTE_PATH = os.path.join(TOOLS_DIR, "master_palette.json")
ART_STYLE_PATH = os.path.join(ROOT, "ART_STYLE.md")
ART_PALETTE_JSON = os.path.join(ROOT, "data", "art_palette.json")
ANIM_SPECS_JSON = os.path.join(ROOT, "data", "art_anim_specs.json")
VFX_LIST_JSON = os.path.join(ROOT, "data", "art_vfx_list.json")
ANCHORS_DIR = os.path.join(ROOT, "data", "anchors")
PALETTE_STRIP_DIR = os.path.join(ROOT, "art", "palettes")
PALETTE_ASSIGN_JSON = os.path.join(ROOT, "data", "art_palette_assign.json")

OUTLINE_HEX = "#1a1a1a"
RESERVED_WHITE_HEX = "#f2ece0"
PLAYER_MAX_HEX = "#e9dcc0"

DIRS = ("south", "east", "north", "west",
        "south_east", "south_west", "north_east", "north_west",
        "south-east", "south-west", "north-east", "north-west")
FRAME_RE = re.compile(r"^(?P<anim>.+?)_(?P<dir>" + "|".join(sorted(DIRS, key=len, reverse=True)) + r")_(?P<n>\d+)\.png$")
STATIC_RE = re.compile(r"^(?P<dir>" + "|".join(sorted(DIRS, key=len, reverse=True)) + r")\.png$")

# --------------------------------------------------------------------------------------------
# ART_STYLE.md 1.3 규격표 (등급별). body = 정지 south 몸 높이 목표 [min,max], margin = (사방, 위)
# pivot = None 이면 캔버스별 pivot_by_canvas 사용. outline: actor=외곽 #1a1a1a 강제, none=외곽선 없음(VFX),
# env=#1a1a1a 사용 금지(타일·프롭)
# --------------------------------------------------------------------------------------------
TIERS = {
    "player":     {"canvas": [64], "body": [44, 48], "pivot": [32, 58], "margin": [2, 3], "budget_key": "player", "kind": "actor", "outline": "actor", "role": "player"},
    "yeongga":    {"canvas": [32], "body": [22, 26], "body_child": [13, 15], "pivot": [16, 29], "margin": [2, 2], "budget_key": "companion_yeongga", "kind": "actor", "outline": "actor", "role": "yeongga"},
    "common_s":   {"canvas": [32], "body": [18, 24], "pivot": [16, 29], "margin": [2, 2], "budget_key": "common_enemy", "kind": "actor", "outline": "actor", "role": "enemy"},
    "common_m":   {"canvas": [40], "body": [26, 32], "pivot": [20, 36], "margin": [2, 2], "budget_key": "common_enemy", "kind": "actor", "outline": "actor", "role": "enemy"},
    "common_l":   {"canvas": [48], "body": [32, 40], "pivot": [24, 44], "margin": [2, 2], "budget_key": "common_enemy", "kind": "actor", "outline": "actor", "role": "enemy"},
    "elite":      {"canvas": [64, 80, 96], "body": [48, 84], "pivot": None, "pivot_rule": "w/2,h-8", "margin": [3, 3], "budget_key": "elite", "kind": "actor", "outline": "actor", "role": "enemy"},
    "midboss":    {"canvas": [128], "body": [96, 116], "pivot": [64, 118], "margin": [4, 4], "budget_key": "midboss", "kind": "actor", "outline": "actor", "role": "enemy"},
    "boss":       {"canvas": [192, 256], "body": [150, 240], "pivot": None, "pivot_by_canvas": {"192": [96, 178], "256": [128, 240]}, "margin": [4, 4], "budget_key": "boss", "kind": "actor", "outline": "actor", "role": "enemy"},
    "avatar":     {"canvas": [48, 96, 128, 160], "body": None, "pivot": None, "pivot_by_canvas": {"48": [24, 44], "96": [48, 88], "128": [64, 118], "160": [80, 156]}, "margin": [3, 3], "budget_key": "avatar", "kind": "actor", "outline": "actor", "role": "player",
                   "note": "1.3 '위와 같은 규칙': 캔버스 48/96/128 피벗은 잡귀L/정예/중간보스 규칙을 따름(추정). 몸 높이 목표 미정 → L11 N/A"},
    "chaser":     {"canvas": [64], "body": [48, 56], "pivot": [32, 58], "margin": [2, 2], "budget_key": "elite", "kind": "actor", "outline": "actor", "role": "neutral",
                   "note": "저승사자. per_sprite_color_budget에 항목이 없어 elite(16) 적용(추정)"},
    "overlay":    {"canvas": [32], "body": None, "pivot": [16, 24], "pivot_is_anchor": True, "margin": [0, 0], "budget_key": "player", "kind": "overlay", "outline": "actor", "role": "player",
                   "note": "머리 오버레이: 피벗=머리 앵커. 발 피벗 검사(L9) 대신 앵커 데이터(L21) 검사"},
    "projectile": {"canvas": [16, 32], "body": None, "pivot": [8, 8], "pivot_is_center": True, "margin": [1, 1], "budget_key": "vfx", "kind": "projectile", "outline": "none", "role": "player_vfx"},
    "vfx":        {"canvas": [16, 32, 64, 128], "body": None, "pivot": None, "margin": [1, 1], "budget_key": "vfx", "kind": "vfx", "outline": "none", "role": "player_vfx"},
    "icon":       {"canvas": [16, 24], "body": None, "pivot": None, "margin": [1, 1], "budget_key": "icon", "kind": "icon", "outline": "actor", "role": "ui", "note": "16px 아이콘은 sel-out 금지 → 외곽은 #1a1a1a 단색"},
    "tile":       {"canvas": [32], "body": None, "pivot": None, "margin": [0, 0], "budget_key": "tile_set", "kind": "env", "outline": "env", "role": "env"},
    "prop":       {"canvas": None, "body": None, "pivot": None, "margin": [1, 1], "budget_key": "prop", "kind": "env", "outline": "env", "role": "env"},
}
SPEC_TIER_MAP = {"player": "player", "companion": "yeongga", "yeongga": "yeongga", "elite": "elite", "midboss": "midboss",
                 "boss": "boss", "chaser": "chaser", "avatar": "avatar", "possession": "overlay"}
COMMON_BY_CANVAS = {32: "common_s", 40: "common_m", 48: "common_l"}
LOOP_EXCLUDE_WORDS = ("attack", "death", "spawn", "intro", "hurt", "slam", "cast", "charge", "summon", "finale",
                      "collapse", "release", "stagger", "phase", "bingui", "split", "emerge", "absorb", "inhale_start")


# --------------------------------------------------------------------------------------------
# 색 변환 / 지각 거리 (CIEDE2000, 순수 파이썬 + 고유색 캐시)
# --------------------------------------------------------------------------------------------
def hex_to_rgb(h: str):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rgb_to_hex(c) -> str:
    return "#%02x%02x%02x" % (c[0], c[1], c[2])


def _lin(v):
    v = v / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def rel_luminance(c) -> float:
    r, g, b = _lin(c[0]), _lin(c[1]), _lin(c[2])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


_LAB_CACHE: dict = {}


def rgb_to_lab(c):
    v = _LAB_CACHE.get(c)
    if v is not None:
        return v
    r, g, b = _lin(c[0]), _lin(c[1]), _lin(c[2])
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    v = (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    _LAB_CACHE[c] = v
    return v


def delta_e2000(lab1, lab2) -> float:
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1 = math.hypot(a1, b1)
    C2 = math.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7))) if Cb > 0 else 0.0
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if C1p else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if C2p else 0.0
    dLp = L2 - L1
    dCp = C2p - C1p
    if C1p * C2p == 0:
        dhp = 0.0
    else:
        dhp = h2p - h1p
        if dhp > 180:
            dhp -= 360
        elif dhp < -180:
            dhp += 360
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp / 2))
    Lbp = (L1 + L2) / 2
    Cbp = (C1p + C2p) / 2
    if C1p * C2p == 0:
        hbp = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hbp = (h1p + h2p) / 2
    else:
        hbp = (h1p + h2p + 360) / 2 if (h1p + h2p) < 360 else (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hbp - 30)) + 0.24 * math.cos(math.radians(2 * hbp))
         + 0.32 * math.cos(math.radians(3 * hbp + 6)) - 0.20 * math.cos(math.radians(4 * hbp - 63)))
    dtheta = 30 * math.exp(-(((hbp - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7)) if Cbp > 0 else 0.0
    Sl = 1 + (0.015 * (Lbp - 50) ** 2) / math.sqrt(20 + (Lbp - 50) ** 2)
    Sc = 1 + 0.045 * Cbp
    Sh = 1 + 0.015 * Cbp * T
    Rt = -math.sin(math.radians(2 * dtheta)) * Rc
    return math.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))


def delta_e(c1, c2) -> float:
    return delta_e2000(rgb_to_lab(c1), rgb_to_lab(c2))


class Snapper:
    """팔레트 최근접색(CIEDE2000). 고유색 단위 캐시."""

    def __init__(self, palette_rgb, lscale=1.0):
        self.pal = [tuple(c) for c in palette_rgb]
        self.labs = [rgb_to_lab(c) for c in self.pal]
        self.cache = {}
        self.lscale = lscale  # 명도 맞춤(--lum-fit): 원본 L* 에 곱한 뒤 최근접

    def nearest(self, c):
        c = (c[0], c[1], c[2])
        r = self.cache.get(c)
        if r is None:
            lab = rgb_to_lab(c)
            if self.lscale != 1.0:
                lab = (lab[0] * self.lscale, lab[1], lab[2])
            best, bd = None, 1e9
            for p, pl in zip(self.pal, self.labs):
                d = delta_e2000(lab, pl)
                if d < bd:
                    best, bd = p, d
            r = (best, bd)
            self.cache[c] = r
        return r


# --------------------------------------------------------------------------------------------
# 마스터 팔레트: ART_STYLE.md 3.1 ↔ data/art_palette.json 대조 → tools/master_palette.json
# --------------------------------------------------------------------------------------------
HEX_RE = re.compile(r"#[0-9a-fA-F]{6}")


def parse_art_style_palette(md_text: str):
    """3.1 표에서 램프별 색을 읽는다. 괄호 안 색은 특수(UI 전용/플래시 코어 전용)로 분리."""
    sec = md_text.split("### 3.1", 1)[1].split("### 3.2", 1)[0]
    ramps, specials = {}, {}
    for line in sec.splitlines():
        m = re.match(r"^\|\s*`(\w+)`\s*([^|]*)\|([^|]*)\|", line)
        if not m:
            continue
        key, col = m.group(1), m.group(3)
        inside = " ".join(re.findall(r"\(([^)]*)\)", col))
        outside = re.sub(r"\([^)]*\)", "", col)
        ramps[key] = [h.lower() for h in HEX_RE.findall(outside)]
        for h in HEX_RE.findall(inside):
            label = "ui_only" if "UI" in inside else ("flash_core_only" if "플래시" in inside else "special")
            specials[h.lower()] = {"ramp": key, "use": label}
    return ramps, specials


def parse_pilot_palettes(md_text: str):
    sec = md_text.split("### 6.3", 1)[1].split("### 6.4", 1)[0]
    out = {}
    for line in sec.splitlines():
        if line.startswith("| P1"):
            out["char_mansin__pilot"] = [h.lower() for h in HEX_RE.findall(line)]
        elif line.startswith("| P2"):
            out["enm_dalgyal_gwisin__pilot"] = [h.lower() for h in HEX_RE.findall(line)]
        elif line.startswith("| P3"):
            parts = line.split("스파크:")
            out["vfx_sinkal_proj__pilot"] = [h.lower() for h in HEX_RE.findall(parts[0])]
            if len(parts) > 1:
                # '순백 #f2ece0 금지' 주석은 제외
                sp = parts[1].split("(순백")[0]
                out["vfx_hit_spark_red__pilot"] = [h.lower() for h in HEX_RE.findall(sp)]
    return out


def build_master_palette(write=True):
    md = open(ART_STYLE_PATH, encoding="utf-8").read()
    js = json.load(open(ART_PALETTE_JSON, encoding="utf-8"))
    md_ramps, md_specials = parse_art_style_palette(md)
    js_ramps = {k: [c.lower() for c in v["colors"]] for k, v in js["ramps"].items()}
    js_specials = {}
    for k, v in js["ramps"].items():
        if v.get("ui_only_highlight"):
            js_specials[v["ui_only_highlight"].lower()] = {"ramp": k, "use": "ui_only"}
        if v.get("flash_core_only"):
            js_specials[v["flash_core_only"].lower()] = {"ramp": k, "use": "flash_core_only"}

    diffs = []
    for k in sorted(set(md_ramps) | set(js_ramps)):
        a, b = set(md_ramps.get(k, [])), set(js_ramps.get(k, []))
        if a != b:
            diffs.append({"ramp": k, "only_in_ART_STYLE": sorted(a - b), "only_in_art_palette_json": sorted(b - a)})
    if set(md_specials) != set(js_specials):
        diffs.append({"specials": True, "ART_STYLE": sorted(md_specials), "art_palette_json": sorted(js_specials)})

    ramps = {}
    for k in js_ramps:  # 정본 순서 = json 키 순서, 램프 내부는 어두움→밝음으로 정렬
        cols = sorted(js_ramps[k], key=lambda h: rel_luminance(hex_to_rgb(h)))
        ramps[k] = {"name": js["ramps"][k]["name"], "colors": cols}
    world = []
    for k in ramps:
        for c in ramps[k]["colors"]:
            if c not in world:
                world.append(c)
    data = {
        "schema_version": 1,
        "doc": "tools/art_common.py build_master_palette() 생성. 수정은 data/art_palette.json(+사용자 승인) 후 재생성. 직접 편집 금지",
        "sources": {"ART_STYLE.md": "§3.1, §3.2, §6.3", "data/art_palette.json": "ramps, per_sprite_color_budget, luminance_caps"},
        "cross_check": {"status": "MATCH" if not diffs else "MISMATCH", "diffs": diffs,
                        "art_style_count": sum(len(v) for v in md_ramps.values()),
                        "art_palette_json_count": sum(len(v) for v in js_ramps.values())},
        "outline": OUTLINE_HEX,
        "reserved_white": RESERVED_WHITE_HEX,
        "reserved_white_delta_e": 6,
        "player_max_hex": js["luminance_caps"]["player_body_max_hex"].lower(),
        "enemy_body_max_relative_luminance": js["luminance_caps"]["enemy_body_max_relative_luminance"],
        "player_blue_ramp": "ch",
        "player_blue_max_ratio": 0.02,
        "env_only_ramps": ["eg", "et", "dc"],
        "ramps": ramps,
        "world_colors": world,
        "world_color_count": len(world),
        "special_colors": js_specials,
        "per_sprite_color_budget": js["per_sprite_color_budget"],
        "entity_palettes": parse_pilot_palettes(md),
        "entity_palette_note": "ART_STYLE 6.3 파일럿 팔레트 초안. 정식 스트립은 art/palettes/<id>.png (art_lint --emit-palette)",
    }
    if write:
        with open(MASTER_PALETTE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
    return data


_MASTER = None


def load_master():
    global _MASTER
    if _MASTER is None:
        if not os.path.exists(MASTER_PALETTE_PATH):
            build_master_palette(write=True)
        _MASTER = json.load(open(MASTER_PALETTE_PATH, encoding="utf-8"))
    return _MASTER


def ramp_of(hexc: str):
    m = load_master()
    for k, v in m["ramps"].items():
        if hexc in v["colors"]:
            return k
    return None


def load_palette_arg(arg: str | None, entity_id: str | None = None, role: str | None = None):
    """--palette 해석: None/'auto' → art/palettes/<id>.png 있으면 그것, 없으면 마스터 world 색.
    'master' | 'entity:<id>'(master_palette.json entity_palettes) | PNG 경로(N×M 스트립) | '#hex,#hex,...'.
    반환: (rgb 리스트, 설명 문자열)"""
    m = load_master()
    master = [hex_to_rgb(h) for h in m["world_colors"]]
    if role:
        master = allowed_master(role)[0]
    if arg == "master-all":
        allm = [hex_to_rgb(h) for h in m["world_colors"]]
        return allm, "master-all(%d)" % len(allm)
    if arg in (None, "auto"):
        if entity_id:
            p = os.path.join(PALETTE_STRIP_DIR, entity_id + ".png")
            if os.path.exists(p):
                return strip_colors(p), "strip:" + os.path.relpath(p, ROOT)
        return master, "master%s(%d)" % ("/" + role if role else "", len(master))
    if arg == "master":
        return master, "master%s(%d)" % ("/" + role if role else "", len(master))
    if arg.startswith("entity:"):
        k = arg.split(":", 1)[1]
        cols = m["entity_palettes"].get(k)
        if not cols:
            raise SystemExit("entity palette not found in master_palette.json: " + k)
        return [hex_to_rgb(h) for h in cols], "entity:%s(%d)" % (k, len(cols))
    if arg.lower().endswith(".png"):
        return strip_colors(arg), "strip:" + arg
    cols = HEX_RE.findall(arg)
    if cols:
        return [hex_to_rgb(h) for h in cols], "hex(%d)" % len(cols)
    raise SystemExit("bad --palette: " + arg)


def allowed_master(role: str):
    """등급 역할별로 쓸 수 있는 마스터 부분집합(스냅 대상). 반환 (rgb 리스트, 제외 사유 dict)
    - 행위자(player/enemy/neutral): 환경 전용 램프(eg, et) 제외, 예약 백 bk 제외(±ΔE6 포함)
    - player: #e9dcc0 보다 밝은 색 제외 / enemy: 상대휘도 > 0.45 제외
    - yeongga: bk 허용(영가는 예약 백 사용처), 나머지는 player 규칙
    - env: 행위자 외곽선 #1a1a1a·bk 제외
    """
    m = load_master()
    excl = {}
    white = hex_to_rgb(m["reserved_white"])
    pmax = rel_luminance(hex_to_rgb(m["player_max_hex"]))
    out = []
    for h in m["world_colors"]:
        c = hex_to_rgb(h)
        r = ramp_of(h)
        why = None
        if role in ("player", "enemy", "neutral", "yeongga", "player_vfx", "ui"):
            if r in ("eg", "et"):
                why = "env_only"
        if role in ("player", "enemy", "neutral", "player_vfx", "env"):
            if r == "bk" or delta_e(c, white) <= m["reserved_white_delta_e"]:
                why = "reserved_white"
        if role == "player" and rel_luminance(c) > pmax + 1e-9:
            why = "above_player_max"
        if role == "enemy" and rel_luminance(c) > m["enemy_body_max_relative_luminance"]:
            why = "above_enemy_lum"
        if role == "env" and h == m["outline"]:
            why = "outline_actor_only"
        if why:
            excl[h] = why
        else:
            out.append(c)
    return out, excl


def strip_colors(path):
    im = Image.open(path).convert("RGBA")
    out = []
    for px in pixels(im):
        if px[3] == 255 and px[:3] not in out:
            out.append(px[:3])
    return out


# --------------------------------------------------------------------------------------------
# 엔티티 / 프레임 로딩
# --------------------------------------------------------------------------------------------
def pixels(im):
    """Pillow 13+ get_flattened_data 우선(getdata 폐기 예정)"""
    f = getattr(im, "get_flattened_data", None)
    return list(f()) if f else list(im.getdata())


class Frame:
    __slots__ = ("name", "anim", "dir", "n", "img", "w", "h", "px", "path")

    def __init__(self, name, anim, d, n, img, path=None):
        self.name, self.anim, self.dir, self.n, self.path = name, anim, d, n, path
        self.img = img.convert("RGBA")
        self.w, self.h = self.img.size
        self.px = pixels(self.img)

    def a(self, x, y):
        return self.px[y * self.w + x][3]


def load_entity_frames(entity_dir):
    frames = []
    for fn in sorted(os.listdir(entity_dir)):
        if not fn.lower().endswith(".png"):
            continue
        m = FRAME_RE.match(fn)
        p = os.path.join(entity_dir, fn)
        if m:
            frames.append(Frame(fn, m.group("anim"), m.group("dir"), int(m.group("n")), Image.open(p), p))
            continue
        m = STATIC_RE.match(fn)
        if m:
            frames.append(Frame(fn, "rot", m.group("dir"), 0, Image.open(p), p))
    frames.sort(key=lambda f: (f.anim != "rot", f.anim, DIRS.index(f.dir) if f.dir in DIRS else 99, f.n))
    return frames


def anim_specs():
    try:
        return json.load(open(ANIM_SPECS_JSON, encoding="utf-8"))
    except Exception:
        return {"entities": []}


def find_spec(entity_id):
    base = entity_id.split("__")[0]
    for e in anim_specs().get("entities", []):
        if e.get("id") == entity_id:
            return e
    for e in anim_specs().get("entities", []):
        if e.get("id") == base:
            return e
    return None


def detect_tier(entity_id, canvas_hint=None):
    spec = find_spec(entity_id)
    t = spec.get("tier") if spec else None
    if t == "common":
        c = spec.get("canvas") or canvas_hint
        return COMMON_BY_CANVAS.get(c, "common_l"), spec
    if t in SPEC_TIER_MAP:
        return SPEC_TIER_MAP[t], spec
    base = entity_id.split("__")[0]
    for pre, tier in (("char_", "player"), ("yeongga_", "yeongga"), ("comp_", "yeongga"), ("elite_", "elite"),
                      ("mboss_", "midboss"), ("boss_", "boss"), ("avatar_", "avatar"), ("overlay_", "overlay"),
                      ("vfx_", "vfx"), ("chaser_", "chaser")):
        if base.startswith(pre):
            return tier, spec
    if base.startswith("enm_"):
        return COMMON_BY_CANVAS.get(canvas_hint, "common_l"), spec
    return None, spec


def tier_pivot(tier, canvas_w, canvas_h):
    t = TIERS[tier]
    if t.get("pivot"):
        return tuple(t["pivot"])
    pbc = t.get("pivot_by_canvas")
    if pbc and str(canvas_w) in pbc:
        return tuple(pbc[str(canvas_w)])
    if t.get("pivot_rule") == "w/2,h-8":
        return (canvas_w // 2, canvas_h - 8)
    return None


def spec_canvas(tier, spec):
    """엔티티 사양 캔버스(1.3 표 + art_anim_specs.canvas). 반환: 허용 캔버스 리스트"""
    t = TIERS[tier]
    if spec and spec.get("canvas") and tier not in ("elite", "avatar", "boss"):
        return [spec["canvas"]]
    if spec and spec.get("canvas") and tier in ("elite", "avatar", "boss"):
        if spec.get("size_stages"):
            return list(spec["size_stages"])
        return [spec["canvas"]]
    return t["canvas"]


# --------------------------------------------------------------------------------------------
# 픽셀 기하 도우미
# --------------------------------------------------------------------------------------------
def bbox(fr: Frame):
    xs0, ys0, xs1, ys1 = fr.w, fr.h, -1, -1
    w = fr.w
    for i, p in enumerate(fr.px):
        if p[3]:
            x, y = i % w, i // w
            if x < xs0: xs0 = x
            if x > xs1: xs1 = x
            if y < ys0: ys0 = y
            if y > ys1: ys1 = y
    if xs1 < 0:
        return None
    return (xs0, ys0, xs1, ys1)


def opaque_count(fr: Frame):
    return sum(1 for p in fr.px if p[3])


def outer_mask(px, w, h):
    """실루엣 외곽 픽셀(4이웃 중 투명 또는 캔버스 밖이 있는 불투명 픽셀) 집합 index"""
    out = set()
    for i, p in enumerate(px):
        if not p[3]:
            continue
        x, y = i % w, i // w
        if (x == 0 or y == 0 or x == w - 1 or y == h - 1 or not px[i - 1][3] or not px[i + 1][3]
                or not px[i - w][3] or not px[i + w][3]):
            out.add(i)
    return out


N8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))


def isolated_stats(px, w, h, outer=None):
    """외곽선을 뺀 내부 불투명 픽셀 중 8이웃에 같은 RGB가 없는 픽셀. 반환 (isolated idx 리스트, interior 수, 평균 클러스터)"""
    if outer is None:
        outer = outer_mask(px, w, h)
    iso, interior = [], 0
    for i, p in enumerate(px):
        if not p[3] or i in outer:
            continue
        interior += 1
        x, y = i % w, i // w
        rgb = p[:3]
        same = False
        for dx, dy in N8:
            xx, yy = x + dx, y + dy
            if 0 <= xx < w and 0 <= yy < h:
                q = px[yy * w + xx]
                if q[3] and q[:3] == rgb:
                    same = True
                    break
        if not same:
            iso.append(i)
    # 같은 색 8연결 클러스터 평균 크기 (내부 픽셀 기준)
    seen = set()
    sizes = []
    for i, p in enumerate(px):
        if not p[3] or i in outer or i in seen:
            continue
        rgb = p[:3]
        stack = [i]
        seen.add(i)
        n = 0
        while stack:
            j = stack.pop()
            n += 1
            x, y = j % w, j // w
            for dx, dy in N8:
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h:
                    k = yy * w + xx
                    if k not in seen and k not in outer:
                        q = px[k]
                        if q[3] and q[:3] == rgb:
                            seen.add(k)
                            stack.append(k)
        sizes.append(n)
    avg = (sum(sizes) / len(sizes)) if sizes else 0.0
    return iso, interior, avg


def save_rgba(px, w, h, path):
    im = Image.new("RGBA", (w, h))
    im.putdata(px)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    im.save(path)
    return im


def color_counter(frames, opaque_only=True):
    c = Counter()
    for fr in frames:
        for p in fr.px:
            if p[3] or not opaque_only:
                c[p[:3]] += 1
    return c
