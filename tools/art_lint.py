#!/usr/bin/env python3
"""art_lint — ART_STYLE.md §3.5 자동 검사(L1~L22). Python 3 + Pillow만, 네트워크 없음.

사용법
  python tools/art_lint.py <entity_dir> [--tier T] [--pivot 32,58] [--palette P] [--json out.json] [--text out.txt]
                          [--strict] [--allow-west] [--workbench-score 82.6 | --workbench wb.json] [--id ID]
  python tools/art_lint.py <vfx_sheet.png>                # VFX 시트(+같은 이름 .json) 검사
  python tools/art_lint.py --all game/assets/sprites [--json all.json]   # 전수 검사 표
  python tools/art_lint.py --emit-palette <id> [--out path.png]           # art/palettes/<id>.png 생성
  python tools/art_lint.py --imports game/                                # L20 .import/.tscn 회귀 검사
  python tools/art_lint.py --build-palette                                # tools/master_palette.json 재생성(대조 포함)

종료 코드: 0 = FAIL 없음(--strict면 WARN도 없음), 1 = FAIL 있음, 2 = 입력 오류.
상태: PASS / FAIL / WARN / N/A (N/A 는 이 등급·입력에 해당 없음).
--palette: auto(기본: art/palettes/<id>.png → 없으면 마스터 65색) | master | master-all | entity:<id> | strip.png | '#hex,...'
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as ac  # noqa: E402
from PIL import Image  # noqa: E402

CHECK_NAMES = {
    "L1": "캔버스", "L2": "알파", "L3": "팔레트 소속", "L4": "색 수", "L5": "예약 백", "L6": "예약 청",
    "L7": "외곽선", "L8": "여백", "L9": "피벗", "L10": "방향 중심", "L11": "몸 높이", "L12": "정지↔이동",
    "L13": "루프 일관성", "L14": "고립 픽셀", "L15": "미러 정책", "L16": "방향 의상 일관성", "L17": "광원",
    "L18": "명도 띠", "L19": "VFX", "L20": "import 회귀", "L21": "앵커", "L22": "workbench 점수",
    "L23": "끓음",
}
# L23 끓음(파일럿 r3 리뷰 motion#3): 루프 애니 인접 프레임 변경 픽셀 / 앞 프레임 불투명 픽셀.
#   변경 = 두 프레임을 ±1px 정수 이동으로 최선 정렬한 뒤 RGBA 가 다른 칸(몸 전체 1px 바운스·보폭 이동은 끓음이 아니므로 보정).
#   보정 없는 원시 값도 함께 기록한다(raw). 임계: idle >25% FAIL, walk/move/glide/float >45% FAIL, idle_0↔이동_0 >20% FAIL.
BOIL_IDLE, BOIL_MOVE, BOIL_IDLE_MOVE = 0.25, 0.45, 0.20


def _frame_map(fr):
    return {(i % fr.w, i // fr.w): p for i, p in enumerate(fr.px) if p[3]}


def boil_ratio(fa, fb, comp=True):
    a, b = _frame_map(fa), _frame_map(fb)
    best = None
    rng = (-1, 0, 1) if comp else (0,)
    for dx in rng:
        for dy in rng:
            bb = {(x + dx, y + dy): c for (x, y), c in b.items()}
            n = sum(1 for k in set(a) | set(bb) if a.get(k) != bb.get(k))
            best = n if best is None else min(best, n)
    return best / max(len(a), 1)
MOVE_ANIMS = ("walk", "move", "glide", "float")


class Report:
    def __init__(self, entity, kind):
        self.entity = entity
        self.kind = kind
        self.meta = {}
        self.checks = []

    def add(self, cid, status, value=None, detail=""):
        self.checks.append({"id": cid, "name": CHECK_NAMES[cid], "status": status, "value": value, "detail": detail})

    def counts(self):
        c = Counter(ch["status"] for ch in self.checks)
        return {k: c.get(k, 0) for k in ("PASS", "FAIL", "WARN", "N/A")}

    def to_dict(self):
        return {"entity": self.entity, "kind": self.kind, "meta": self.meta, "summary": self.counts(), "checks": self.checks}

    def text(self):
        m = self.meta
        lines = ["== art_lint: %s  (tier=%s, canvas=%s, pivot=%s, palette=%s, frames=%s)" % (
            self.entity, m.get("tier"), m.get("canvas_actual"), m.get("pivot"), m.get("palette"), m.get("frames"))]
        for ch in self.checks:
            v = ch["value"]
            if isinstance(v, float):
                v = round(v, 3)
            vs = json.dumps(v, ensure_ascii=False) if not isinstance(v, str) else v
            if len(vs) > 60:
                vs = vs[:57] + "..."
            lines.append("  %-4s %-14s %-5s %-60s %s" % (ch["id"], ch["name"], ch["status"], vs, ch["detail"]))
        c = self.counts()
        lines.append("  -> PASS %d / FAIL %d / WARN %d / N/A %d" % (c["PASS"], c["FAIL"], c["WARN"], c["N/A"]))
        return "\n".join(lines)


def pct(a, b):
    return (100.0 * a / b) if b else 0.0


# ------------------------------------------------------------------------------------------------
# 프레임 측정 캐시
# ------------------------------------------------------------------------------------------------
class FM:
    def __init__(self, fr):
        self.fr = fr
        self.bb = ac.bbox(fr)
        self.area = ac.opaque_count(fr)
        self._outer = None

    @property
    def outer(self):
        if self._outer is None:
            self._outer = ac.outer_mask(self.fr.px, self.fr.w, self.fr.h)
        return self._outer

    @property
    def foot(self):
        return self.bb[3] if self.bb else None

    @property
    def top(self):
        return self.bb[1] if self.bb else None

    @property
    def height(self):
        return (self.bb[3] - self.bb[1] + 1) if self.bb else 0

    @property
    def cx(self):
        return ((self.bb[0] + self.bb[2]) / 2.0) if self.bb else None


def _loop_anims(spec, anims):
    loops = {}
    if spec:
        for t in spec.get("anims", []):
            if isinstance(t, list) and len(t) >= 4:
                loops[t[0]] = bool(t[3])
    out = []
    for a in anims:
        if a == "rot":
            continue
        if a in loops:
            if loops[a]:
                out.append(a)
        elif not any(w in a for w in ac.LOOP_EXCLUDE_WORDS):
            out.append(a)
    return out


def _flip_px(fr):
    im = fr.img.transpose(Image.FLIP_LEFT_RIGHT)
    return ac.pixels(im)


def load_workbench(opts, entity):
    if opts.workbench_score is not None:
        return float(opts.workbench_score)
    if opts.workbench and os.path.exists(opts.workbench):
        d = json.load(open(opts.workbench, encoding="utf-8"))
        if isinstance(d, (int, float)):
            return float(d)
        if "score" in d and isinstance(d["score"], (int, float)):
            return float(d["score"])
        v = d.get(entity)
        if isinstance(v, dict):
            v = v.get("score")
        if isinstance(v, (int, float)):
            return float(v)
    return None


def check_imports_dir(root, files=None):
    """L20: .import compress/mode≠0, mipmaps/generate=true / .tscn texture_filter 덮어쓰기"""
    bad = []
    n = 0
    if files is None:
        files = []
        for dp, dn, fn in os.walk(root):
            if ".godot" in dp.split(os.sep):
                continue
            for f in fn:
                if f.endswith(".import") or f.endswith(".tscn"):
                    files.append(os.path.join(dp, f))
    for p in files:
        n += 1
        try:
            txt = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if p.endswith(".import"):
            for line in txt.splitlines():
                s = line.strip()
                if s.startswith("compress/mode=") and s != "compress/mode=0":
                    bad.append((p, s))
                if s == "mipmaps/generate=true":
                    bad.append((p, s))
        else:
            for line in txt.splitlines():
                if line.strip().startswith("texture_filter"):
                    bad.append((p, line.strip()))
    return n, bad


# ------------------------------------------------------------------------------------------------
# 엔티티 검사
# ------------------------------------------------------------------------------------------------
def lint_entity(entity_dir, opts):
    entity = opts.id or os.path.basename(os.path.normpath(entity_dir))
    frames = ac.load_entity_frames(entity_dir)
    if not frames:
        raise ValueError("no <anim>_<dir>_<n>.png / <dir>.png frames in " + entity_dir)
    sizes = Counter((f.w, f.h) for f in frames)
    (cw, chh), _ = sizes.most_common(1)[0]
    tier, spec = (opts.tier, ac.find_spec(entity)) if opts.tier else ac.detect_tier(entity, cw)
    if tier not in ac.TIERS:
        raise ValueError("tier unknown for %s (use --tier)" % entity)
    T = ac.TIERS[tier]
    role = T["role"]
    master = ac.load_master()
    allowed_canvas = ac.spec_canvas(tier, spec) if not opts.tier else T["canvas"]
    if opts.pivot:
        pivot = tuple(int(v) for v in opts.pivot.split(","))
        pivot_src = "arg"
    else:
        if allowed_canvas and cw in allowed_canvas:
            pivot = ac.tier_pivot(tier, cw, chh)
            pivot_src = "tier"
        else:
            base = ac.tier_pivot(tier, allowed_canvas[0], allowed_canvas[0]) if allowed_canvas else None
            pivot = (cw // 2, chh - (allowed_canvas[0] - base[1])) if base else None
            pivot_src = "derived(캔버스 불일치: 사양 %s 기준 하단 오프셋)" % (allowed_canvas[0] if allowed_canvas else "-")
    pal, pal_desc = ac.load_palette_arg(opts.palette if opts.palette else "auto", entity)
    pal_set = set(pal)
    full_snap = ac.Snapper([ac.hex_to_rgb(h) for h in master["world_colors"]])

    R = Report(entity, "sprite")
    R.meta = {"dir": os.path.abspath(entity_dir), "tier": tier, "role": role, "canvas_spec": allowed_canvas,
              "canvas_actual": "%dx%d" % (cw, chh), "pivot": list(pivot) if pivot else None, "pivot_src": pivot_src,
              "palette": pal_desc, "frames": len(frames), "anims": sorted({f.anim for f in frames})}
    fms = [FM(f) for f in frames]
    by = defaultdict(list)
    for m in fms:
        by[(m.fr.anim, m.fr.dir)].append(m)
    for k in by:
        by[k].sort(key=lambda m: m.fr.n)

    def first(anim, d):
        g = by.get((anim, d))
        return g[0] if g else None

    def static_or(d, fallbacks=("idle",)):
        m = first("rot", d)
        if m:
            return m, "%s.png" % d
        for a in fallbacks:
            m = first(a, d)
            if m:
                return m, m.fr.name
        return None, None

    # L1 캔버스
    bad_sz = {"%dx%d" % s: n for s, n in sizes.items() if not (s[0] == s[1] and (allowed_canvas is None or s[0] in allowed_canvas))}
    mixed = len(sizes) > 1
    st = "FAIL" if (bad_sz or mixed) else "PASS"
    R.add("L1", st, {"%dx%d" % s: n for s, n in sizes.items()},
          "사양 %s%s" % (allowed_canvas, ", 캔버스 혼재" if mixed else ""))

    # L2 알파
    semi = sum(1 for f in frames for p in f.px if 0 < p[3] < 255)
    total_px = sum(f.w * f.h for f in frames)
    semi_frames = sum(1 for f in frames if any(0 < p[3] < 255 for p in f.px))
    R.add("L2", "FAIL" if semi else "PASS", {"semi_px": semi, "semi_frames_pct": round(pct(semi_frames, len(frames)), 1)},
          "0<a<255 픽셀 %d개 (%.2f%% of canvas px)" % (semi, pct(semi, total_px)))

    # 색 집계 (불투명만, 알파 무시 RGB)
    cc = ac.color_counter(frames)
    opaque_total = sum(cc.values())

    # L3 팔레트 소속
    off = {c: n for c, n in cc.items() if c not in pal_set}
    off_px = sum(off.values())
    mean_de = (sum(full_snap.nearest(c)[1] * n for c, n in cc.items()) / opaque_total) if opaque_total else 0
    R.add("L3", "FAIL" if off else "PASS",
          {"off_colors": len(off), "off_px_pct": round(pct(off_px, opaque_total), 2), "compliance_pct": round(100 - pct(off_px, opaque_total), 2)},
          "기준 %s, 마스터 최근접 평균 ΔE2000 %.2f" % (pal_desc, mean_de))

    # L4 색 수
    budget = master["per_sprite_color_budget"].get(T["budget_key"])
    per_frame = [len({p[:3] for p in f.px if p[3]}) for f in frames]
    R.add("L4", "FAIL" if budget is not None and len(cc) > budget else "PASS",
          {"entity_colors": len(cc), "budget": budget, "frame_max": max(per_frame) if per_frame else 0},
          "엔티티 전 프레임·방향 합집합")

    # L5 예약 백
    white = ac.hex_to_rgb(master["reserved_white"])
    if T["kind"] in ("actor", "env", "overlay") and role != "yeongga":
        wc = {c: n for c, n in cc.items() if ac.delta_e(c, white) <= master["reserved_white_delta_e"]}
        n = sum(wc.values())
        R.add("L5", "FAIL" if n else "PASS", {"px": n, "colors": [ac.rgb_to_hex(c) for c in list(wc)[:6]]},
              "#f2ece0 ±ΔE2000 %d" % master["reserved_white_delta_e"])
    else:
        R.add("L5", "N/A", None, "영가·VFX 별도 규칙")

    # L6 예약 청 (플레이어·플레이어 VFX)
    if role in ("player", "player_vfx"):
        ch = set(ac.hex_to_rgb(h) for h in master["ramps"]["ch"]["colors"])
        exact = sum(n for c, n in cc.items() if c in ch)
        near = sum(n for c, n in cc.items() if full_snap.nearest(c)[0] in ch)
        r = max(exact, near) / opaque_total if opaque_total else 0
        R.add("L6", "FAIL" if r > master["player_blue_max_ratio"] else "PASS",
              {"exact_pct": round(pct(exact, opaque_total), 2), "nearest_snap_pct": round(pct(near, opaque_total), 2)},
              "ch 램프 ≤2% (정확 일치 / 마스터 최근접 스냅 기준 중 큰 값)")
    else:
        R.add("L6", "N/A", None, "플레이어 계열만")

    # L7 외곽선
    ol = ac.hex_to_rgb(master["outline"])
    if T["outline"] == "actor":
        tot = exact = dark = 0
        for m in fms:
            for i in m.outer:
                p = m.fr.px[i]
                tot += 1
                if p[:3] == ol:
                    exact += 1
                if ac.rel_luminance(p[:3]) < 0.03:
                    dark += 1
        r = exact / tot if tot else 0
        R.add("L7", "FAIL" if r < 0.95 else "PASS", {"outline_1a1a1a_pct": round(100 * r, 2), "dark_outer_pct": round(pct(dark, tot), 1)},
              "실루엣 외곽(4이웃 투명) 픽셀 %d개 중 #1a1a1a ≥95%%" % tot)
    elif T["outline"] == "env":
        n = cc.get(ol, 0)
        R.add("L7", "FAIL" if n else "PASS", {"px_1a1a1a": n}, "환경은 #1a1a1a 사용 금지")
    else:
        R.add("L7", "N/A", None, "외곽선 없는 등급")

    # L8 여백
    side_min, top_min = T["margin"]
    worst = {"left": 999, "right": 999, "top": 999, "bottom": 999}
    worst_fr = {}
    for m in fms:
        if not m.bb:
            continue
        x0, y0, x1, y1 = m.bb
        vals = {"left": x0, "right": m.fr.w - 1 - x1, "top": y0, "bottom": m.fr.h - 1 - y1}
        for k, v in vals.items():
            if v < worst[k]:
                worst[k] = v
                worst_fr[k] = m.fr.name
    bad = [k for k in worst if worst[k] < (top_min if k == "top" else side_min)]
    R.add("L8", "FAIL" if bad else "PASS", worst, "최소 사방 %d / 위 %d. 위반: %s" % (
        side_min, top_min, ", ".join("%s(%s)" % (k, worst_fr.get(k)) for k in bad) or "-"))

    foot_tier = T["kind"] == "actor" and pivot is not None
    # L9 피벗
    if foot_tier:
        feet = [m.foot for m in fms if m.bb]
        badf = [m.fr.name for m in fms if m.bb and abs(m.foot - pivot[1]) > 1]
        R.add("L9", "FAIL" if badf else "PASS", {"foot_min": min(feet), "foot_max": max(feet), "pivot_y": pivot[1], "bad_frames": len(badf)},
              ("예: " + ", ".join(badf[:4])) if badf else "모든 프레임 발끝 = 피벗 y ±1")
    else:
        R.add("L9", "N/A", None, "발 피벗 없는 등급")

    # L10 방향 중심
    if foot_tier or T["kind"] == "overlay":
        worst_r, worst_a, det = 0.0, None, {}
        for anim in sorted({m.fr.anim for m in fms}):
            cxs = {d: first(anim, d).cx for d in ("south", "east", "north", "west") if first(anim, d) and first(anim, d).bb}
            if len(cxs) >= 2:
                r = max(cxs.values()) - min(cxs.values())
                det[anim] = round(r, 1)
                if r > worst_r:
                    worst_r, worst_a = r, anim
        R.add("L10", "FAIL" if worst_r > 1 else ("PASS" if det else "N/A"), {"worst_range_px": worst_r, "worst_anim": worst_a, "pivot_x": pivot[0] if pivot else None},
              "애니별 0프레임 방향간 bbox 중심 x 범위: " + json.dumps(det, ensure_ascii=False))
    else:
        R.add("L10", "N/A", None, "")

    # L11 몸 높이
    body = T.get("body_child") if ("child" in entity and T.get("body_child")) else T.get("body")
    sm, sname = static_or("south", ("idle",) + MOVE_ANIMS)
    if body and sm:
        h = sm.height
        over = (h - body[1]) / body[1] * 100 if h > body[1] else 0.0
        R.add("L11", "PASS" if body[0] <= h <= body[1] else "FAIL", {"height": h, "target": body, "over_pct": round(over, 1)},
              "%s 기준%s" % (sname, ", +15% 초과 → 7.2 재생성 조건 1" if over > 15 else ""))
    else:
        R.add("L11", "N/A", None, "몸 높이 목표 없음" if not body else "south 프레임 없음")

    # L12 정지↔이동
    if foot_tier:
        rows, badl = {}, []
        for d in ("south", "east", "north"):
            im, iname = (first("idle", d), None)
            iname = im.fr.name if im else None
            if not im:
                im, iname = static_or(d, ())
            mv = None
            for a in MOVE_ANIMS:
                mv = first(a, d)
                if mv:
                    break
            if im and mv and im.bb and mv.bb:
                dh, df = mv.height - im.height, mv.foot - im.foot
                rows[d] = {"idle": iname, "move": mv.fr.name, "dh": dh, "dfoot": df}
                if abs(dh) > 2 or abs(df) > 1:
                    badl.append(d)
        R.add("L12", "FAIL" if badl else ("PASS" if rows else "N/A"), rows, "위반 방향: %s" % (",".join(badl) or "-"))
    else:
        R.add("L12", "N/A", None, "")

    # L13 루프 일관성
    loops = _loop_anims(spec, sorted({m.fr.anim for m in fms}))
    if loops and T["kind"] in ("actor", "overlay"):
        worst_area, worst_cx, wa, wc_, badg = 0.0, 0.0, None, None, []
        for (anim, d), g in by.items():
            if anim not in loops or len(g) < 2:
                continue
            areas = [m.area for m in g]
            cxs = [m.cx for m in g if m.bb]
            av = (max(areas) - min(areas)) / max(areas) if max(areas) else 0
            cr = max(cxs) - min(cxs) if cxs else 0
            if av > worst_area:
                worst_area, wa = av, "%s_%s" % (anim, d)
            if cr > worst_cx:
                worst_cx, wc_ = cr, "%s_%s" % (anim, d)
            if av > 0.12 or cr > 2:
                badg.append("%s_%s" % (anim, d))
        R.add("L13", "FAIL" if badg else "PASS", {"area_var_pct": round(100 * worst_area, 1), "area_worst": wa, "cx_range": worst_cx, "cx_worst": wc_},
              "루프 애니 %s. 위반 %d묶음%s" % (loops, len(badg), (": " + ",".join(badg[:4])) if badg else ""))
    else:
        R.add("L13", "N/A", None, "루프 애니 없음")

    # L14 고립 픽셀
    iso_t = int_t = 0
    worst_iso, worst_iso_f, avg_cl = 0.0, None, []
    for m in fms:
        iso, interior, avg = ac.isolated_stats(m.fr.px, m.fr.w, m.fr.h, m.outer)
        iso_t += len(iso)
        int_t += interior
        avg_cl.append(avg)
        r = len(iso) / interior if interior else 0
        if r > worst_iso:
            worst_iso, worst_iso_f = r, m.fr.name
    ratio = iso_t / int_t if int_t else 0
    avgc = sum(avg_cl) / len(avg_cl) if avg_cl else 0
    st = "FAIL" if ratio > 0.08 else ("WARN" if avgc < 2.5 else "PASS")
    R.add("L14", st, {"isolated_pct": round(100 * ratio, 2), "worst_frame_pct": round(100 * worst_iso, 1), "worst_frame": worst_iso_f,
                      "avg_cluster_px": round(avgc, 2)}, "내부(외곽 제외) 8이웃 같은 RGB 없음 >8% FAIL, 평균 클러스터 <2.5 WARN")

    # L15 미러 정책
    wests = [m for m in fms if m.fr.dir == "west"]
    if wests and T["kind"] in ("actor", "overlay"):
        derived, indep = 0, []
        for m in wests:
            e = None
            for k in by.get((m.fr.anim, "east"), []):
                if k.fr.n == m.fr.n:
                    e = k
            if e and e.fr.w == m.fr.w and e.fr.h == m.fr.h and _flip_px(e.fr) == m.fr.px:
                derived += 1
            else:
                indep.append(m.fr.name)
        if opts.allow_west:
            st = "PASS"
        elif opts.strict_west:
            st = "FAIL"
        else:
            st = "FAIL" if indep else "PASS"
        R.add("L15", st, {"west_files": len(wests), "flip_of_east": derived, "independent": len(indep)},
              "독립 생성 west는 FAIL(flip_h(E)와 픽셀 동일한 파생본은 허용%s)%s" % (
                  ", --strict-west면 전부 FAIL" if not opts.strict_west else "", ("; --allow-west 예외" if opts.allow_west else "")))
    else:
        R.add("L15", "PASS" if T["kind"] in ("actor", "overlay") else "N/A", {"west_files": 0}, "")

    # L16 방향 의상 일관성 (마스터 스냅 후 상위 8색)
    if T["kind"] in ("actor",):
        tops = {}
        for d in ("south", "east", "north"):
            m, _ = static_or(d, ("idle",) + MOVE_ANIMS)
            if m:
                c = Counter()
                for i, p in enumerate(m.fr.px):
                    if p[3] and i not in m.outer:
                        c[full_snap.nearest(p[:3])[0]] += 1
                tops[d] = [k for k, _ in c.most_common(8)]
        ov = {}
        if "south" in tops:
            for d in ("east", "north"):
                if d in tops:
                    a, b = set(tops["south"]), set(tops[d])
                    ov["S-" + d[0].upper()] = round(len(a & b) / max(1, min(len(a), len(b))), 3)
        lo = min(ov.values()) if ov else None
        R.add("L16", "WARN" if lo is not None and lo < 0.75 else ("PASS" if ov else "N/A"), ov,
              "정지 프레임 내부 상위 8색(마스터 스냅) 겹침 <75% WARN → G0 육안 확인")
    else:
        R.add("L16", "N/A", None, "")

    # L17 광원
    if T["kind"] == "actor" and sm and sm.bb:
        mid = sm.cx
        l = [ac.rel_luminance(p[:3]) for i, p in enumerate(sm.fr.px) if p[3] and i not in sm.outer and (i % sm.fr.w) < mid]
        r = [ac.rel_luminance(p[:3]) for i, p in enumerate(sm.fr.px) if p[3] and i not in sm.outer and (i % sm.fr.w) > mid]
        diff = (sum(l) / len(l) if l else 0) - (sum(r) / len(r) if r else 0)
        R.add("L17", "WARN" if diff < 0 else "PASS", round(diff, 4), "%s 좌반−우반 평균 상대휘도(추정 지표)" % sname)
    else:
        R.add("L17", "N/A", None, "")

    # L18 명도 띠
    if role == "enemy":
        cap = master["enemy_body_max_relative_luminance"]
        mx = max((ac.rel_luminance(c) for c in cc), default=0)
        n = sum(v for c, v in cc.items() if ac.rel_luminance(c) > cap)
        R.add("L18", "FAIL" if mx > cap else "PASS", {"max_lum": round(mx, 3), "cap": cap, "px_over": n}, "적 몸 상대휘도 상한")
    elif role == "player":
        cap = ac.rel_luminance(ac.hex_to_rgb(master["player_max_hex"]))
        mx = max((ac.rel_luminance(c) for c in cc), default=0)
        n = sum(v for c, v in cc.items() if ac.rel_luminance(c) > cap + 1e-9)
        R.add("L18", "FAIL" if mx > cap + 1e-9 else "PASS", {"max_lum": round(mx, 3), "cap": round(cap, 3), "px_over": n},
              "플레이어 최고 명도 ≤ #e9dcc0")
    else:
        R.add("L18", "N/A", None, "")

    R.add("L19", "N/A", None, "VFX 시트 입력에서만")

    # L20 import 회귀 (엔티티 폴더 .import)
    imps = [os.path.join(entity_dir, f) for f in os.listdir(entity_dir) if f.endswith(".import")]
    if imps:
        n, bad = check_imports_dir(entity_dir, imps)
        R.add("L20", "FAIL" if bad else "PASS", {"import_files": n, "bad": len(bad)}, "; ".join("%s %s" % (os.path.basename(p), s) for p, s in bad[:3]))
    else:
        R.add("L20", "N/A", {"import_files": 0}, "전역 검사는 --imports game/")

    # L21 앵커
    need = tier in ("player",) or opts.require_anchors
    ap = os.path.join(ac.ANCHORS_DIR, entity.split("__pilot")[0] + ".json")
    if need:
        if not os.path.exists(ap):
            R.add("L21", "FAIL", {"file": os.path.relpath(ap, ac.ROOT)}, "앵커 파일 없음(오버레이·지물·발사 대상)")
        else:
            txt = open(ap, encoding="utf-8").read()
            missing = [f.name for f in frames if f.anim != "rot" and f.name[:-4] not in txt]
            R.add("L21", "FAIL" if missing else "PASS", {"file": os.path.relpath(ap, ac.ROOT), "missing_frames": len(missing)},
                  ("예: " + ", ".join(missing[:3])) if missing else "")
    else:
        R.add("L21", "N/A", None, "앵커 필수 대상 아님(--require-anchors로 강제)")

    # L23 끓음
    if T["kind"] in ("actor", "overlay"):
        rows23, bad23, worst23 = {}, [], (0.0, None)
        for (anim, d), g in by.items():
            if d == "west" or len(g) < 2 or anim not in ("idle",) + MOVE_ANIMS:
                continue
            lim = BOIL_IDLE if anim == "idle" else BOIL_MOVE
            comp = [boil_ratio(g[k].fr, g[(k + 1) % len(g)].fr) for k in range(len(g))]
            raw = [boil_ratio(g[k].fr, g[(k + 1) % len(g)].fr, False) for k in range(len(g))]
            key = "%s_%s" % (anim, d)
            rows23[key] = {"max_pct": round(100 * max(comp), 1), "raw_max_pct": round(100 * max(raw), 1)}
            if max(comp) > worst23[0]:
                worst23 = (max(comp), key)
            if max(comp) > lim:
                bad23.append(key)
        for d in ("south", "east", "north"):
            im = first("idle", d)
            mv = None
            for a in MOVE_ANIMS:
                mv = first(a, d)
                if mv:
                    break
            if im and mv:
                r = boil_ratio(im.fr, mv.fr)
                rows23["idle0_vs_move0_%s" % d] = round(100 * r, 1)
                if r > BOIL_IDLE_MOVE:
                    bad23.append("idle0_vs_move0_%s" % d)
        if rows23:
            R.add("L23", "FAIL" if bad23 else "PASS", rows23,
                  "인접 프레임 변경(±1px 정렬 보정) idle ≤25%%, 이동 ≤45%%, idle_0↔이동_0 ≤20%%. 최악 %s. 위반: %s" % (
                      worst23[1], ",".join(bad23) or "-"))
        else:
            R.add("L23", "N/A", None, "루프 애니 없음")
    else:
        R.add("L23", "N/A", None, "")

    # L22 workbench
    sc = load_workbench(opts, entity)
    if sc is None:
        R.add("L22", "WARN", None, "미측정: pixelart_workbench score 결과를 --workbench-score/--workbench 로 전달")
    else:
        R.add("L22", "FAIL" if sc < 85 else "PASS", sc, "목표 ≥85")
    R.checks.sort(key=lambda c: int(c["id"][1:]))
    return R


# ------------------------------------------------------------------------------------------------
# VFX 시트 검사 (L1~L5 일부 + L19)
# ------------------------------------------------------------------------------------------------
def vfx_list_entry(fx_id):
    try:
        d = json.load(open(ac.VFX_LIST_JSON, encoding="utf-8"))
    except Exception:
        return None
    keys = d.get("tuple", [])
    for row in d.get("vfx", []):
        if row and row[0] == fx_id:
            return dict(zip(keys, row))
    return None


def lint_vfx(png, opts):
    fx_id = opts.id or os.path.splitext(os.path.basename(png))[0]
    js = os.path.splitext(png)[0] + ".json"
    meta = json.load(open(js, encoding="utf-8")) if os.path.exists(js) else {}
    sheet = Image.open(png).convert("RGBA")
    frames_meta = meta.get("frames", [])
    if isinstance(frames_meta, dict):
        frames_meta = list(frames_meta.values())
    rects = [(f["frame"]["x"], f["frame"]["y"], f["frame"]["w"], f["frame"]["h"]) for f in frames_meta] or [(0, 0) + sheet.size]
    durs = [f.get("duration") for f in frames_meta]
    master = ac.load_master()
    entry = vfx_list_entry(fx_id)
    R = Report(fx_id, "vfx")
    R.meta = {"sheet": os.path.abspath(png), "tier": "vfx", "frames": len(rects), "list_entry": entry, "palette": "master"}
    px = []
    for (x, y, w, h) in rects:
        px.extend(ac.pixels(sheet.crop((x, y, x + w, y + h))))
    blend = (entry or {}).get("blend", "normal")
    semi = sum(1 for p in px if 0 < p[3] < 255)
    R.add("L2", "PASS" if not semi else ("WARN" if blend != "normal" else "FAIL"), {"semi_px": semi, "blend": blend},
          "블렌드 지정 시트는 반투명 허용(WARN 기록)")
    cc = Counter(p[:3] for p in px if p[3])
    allm = set(ac.hex_to_rgb(h) for h in master["world_colors"])
    off = sum(n for c, n in cc.items() if c not in allm)
    tot = sum(cc.values())
    R.add("L3", "FAIL" if off else "PASS", {"off_colors": sum(1 for c in cc if c not in allm), "compliance_pct": round(100 - pct(off, tot), 2)}, "마스터")
    budget = master["per_sprite_color_budget"]["vfx"]
    R.add("L4", "FAIL" if len(cc) > budget else "PASS", {"colors": len(cc), "budget": budget}, "")
    role = (entry or {}).get("color_role", "")
    if "W" not in role:
        white = ac.hex_to_rgb(master["reserved_white"])
        n = sum(v for c, v in cc.items() if ac.delta_e(c, white) <= master["reserved_white_delta_e"])
        R.add("L5", "FAIL" if n else "PASS", {"px": n}, "color_role=%s" % role)
    else:
        R.add("L5", "N/A", None, "W 역할")
    sizes = Counter((w, h) for (_, _, w, h) in rects)
    bad_sz = [s for s in sizes if s[0] not in (16, 32, 64, 128) or s[1] not in (16, 32, 64, 128)]
    exp_fps = None
    if entry and str(entry.get("timing", "")).startswith("fps:"):
        exp_fps = float(entry["timing"].split(":")[1])
    pfx = (meta.get("meta") or {}).get("pixelfx") or {}
    dur_bad = []
    if exp_fps and durs and all(d is not None for d in durs):
        exp = round(1000 / exp_fps)
        dur_bad = [d for d in durs if abs(d - exp) > 1]
    probs = []
    if bad_sz:
        probs.append("frame size %s ∉ {16,32,64,128}" % ["%dx%d" % s for s in bad_sz])
    if len(cc) > budget:
        probs.append("colors %d > %d" % (len(cc), budget))
    if dur_bad:
        probs.append("duration %s ≠ %dms(fps %s)" % (sorted(set(dur_bad)), round(1000 / exp_fps), exp_fps))
    if entry and entry.get("frames") and len(rects) != entry["frames"]:
        probs.append("frames %d ≠ list %s" % (len(rects), entry["frames"]))
    R.add("L19", "FAIL" if probs else "PASS", {"sizes": ["%dx%d" % s for s in sizes], "fps_meta": pfx.get("fps"), "fps_list": exp_fps},
          "; ".join(probs) or ("art_vfx_list 항목 없음" if not entry else ""))
    R.checks.sort(key=lambda c: int(c["id"][1:]))
    return R


# ------------------------------------------------------------------------------------------------
def emit_palette(pid, out=None):
    m = ac.load_master()
    src = None
    cols = None
    if os.path.exists(ac.PALETTE_ASSIGN_JSON):
        d = json.load(open(ac.PALETTE_ASSIGN_JSON, encoding="utf-8"))
        v = d.get(pid) or (d.get("entities") or {}).get(pid)
        if isinstance(v, dict):
            v = v.get("colors")
        if v:
            cols, src = [c.lower() for c in v], "data/art_palette_assign.json"
    if cols is None:
        for k in (pid, pid + "__pilot"):
            if k in m["entity_palettes"]:
                cols, src = m["entity_palettes"][k], "master_palette.json entity_palettes[%s] (ART_STYLE 6.3)" % k
                break
    if cols is None:
        print("no palette assignment for %s (data/art_palette_assign.json 없음/미등록)" % pid, file=sys.stderr)
        return 2
    notin = [c for c in cols if c not in m["world_colors"]]
    if notin:
        print("FAIL: master 밖 색 %s" % notin, file=sys.stderr)
        return 1
    out = out or os.path.join(ac.PALETTE_STRIP_DIR, pid + ".png")
    im = Image.new("RGBA", (len(cols), 1))
    im.putdata([ac.hex_to_rgb(c) + (255,) for c in cols])
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    im.save(out)
    print("wrote %s (%d colors, source: %s)" % (out, len(cols), src))
    return 0


def exit_code(reports, strict):
    for r in reports:
        c = r.counts()
        if c["FAIL"] or (strict and c["WARN"]):
            return 1
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", nargs="?")
    ap.add_argument("--tier", choices=sorted(ac.TIERS))
    ap.add_argument("--pivot")
    ap.add_argument("--palette")
    ap.add_argument("--id")
    ap.add_argument("--json")
    ap.add_argument("--text")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--allow-west", action="store_true")
    ap.add_argument("--strict-west", action="store_true", help="flip 파생 west도 FAIL")
    ap.add_argument("--require-anchors", action="store_true")
    ap.add_argument("--workbench")
    ap.add_argument("--workbench-score", type=float)
    ap.add_argument("--all")
    ap.add_argument("--emit-palette")
    ap.add_argument("--out")
    ap.add_argument("--imports")
    ap.add_argument("--build-palette", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    o = ap.parse_args(argv)
    try:
        if o.build_palette:
            d = ac.build_master_palette(write=True)
            print("wrote %s: %d world colors, cross_check=%s %s" % (ac.MASTER_PALETTE_PATH, d["world_color_count"],
                                                                     d["cross_check"]["status"], d["cross_check"]["diffs"] or ""))
            return 0 if d["cross_check"]["status"] == "MATCH" else 1
        if o.emit_palette:
            return emit_palette(o.emit_palette, o.out)
        if o.imports:
            n, bad = check_imports_dir(o.imports)
            print("L20 import 회귀: %d files, %d issues" % (n, len(bad)))
            for p, s in bad[:50]:
                print("  FAIL %s: %s" % (p, s))
            if o.json:
                json.dump({"files": n, "bad": bad}, open(o.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            return 1 if bad else 0
        reports = []
        if o.all:
            for d in sorted(os.listdir(o.all)):
                p = os.path.join(o.all, d)
                if os.path.isdir(p) and any(f.endswith(".png") for f in os.listdir(p)):
                    try:
                        sub = argparse.Namespace(**vars(o))
                        sub.id = None
                        reports.append(lint_entity(p, sub))
                    except ValueError as e:
                        print("skip %s: %s" % (d, e), file=sys.stderr)
            print("%-30s %-10s %4s %4s %4s  %s" % ("entity", "tier", "PASS", "FAIL", "WARN", "FAIL ids"))
            for r in reports:
                c = r.counts()
                print("%-30s %-10s %4d %4d %4d  %s" % (r.entity, r.meta.get("tier"), c["PASS"], c["FAIL"], c["WARN"],
                                                      ",".join(ch["id"] for ch in r.checks if ch["status"] == "FAIL")))
        elif o.target:
            if not os.path.exists(o.target):
                print("input not found: " + o.target, file=sys.stderr)
                return 2
            if os.path.isfile(o.target) and o.target.lower().endswith(".png"):
                reports.append(lint_vfx(o.target, o))
            else:
                reports.append(lint_entity(o.target, o))
            if not o.quiet:
                for r in reports:
                    print(r.text())
        else:
            ap.print_usage()
            return 2
        if o.json:
            os.makedirs(os.path.dirname(os.path.abspath(o.json)), exist_ok=True)
            data = [r.to_dict() for r in reports]
            json.dump(data if (o.all or len(data) > 1) else data[0], open(o.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        if o.text:
            with open(o.text, "w", encoding="utf-8") as f:
                f.write("\n\n".join(r.text() for r in reports) + "\n")
        return exit_code(reports, o.strict)
    except (ValueError, OSError, json.JSONDecodeError) as e:
        print("input error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
