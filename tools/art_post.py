#!/usr/bin/env python3
"""art_post — ART_STYLE.md §3.4 로컬 후처리 단계 ([1] 정규화, [5] 최종 스냅, [6] 피벗 정렬 + West flip + 파일명 규약).
PixelLab 단계([2] reduce_colors, [3] correct_pixelart, [4] workbench)는 이 도구 밖에서 [1]과 [5] 사이에 실행한다.
Python 3 + Pillow만. 입력 파일은 절대 수정하지 않는다(출력 폴더가 입력과 같거나 런타임 폴더면 거부).

사용법
  python tools/art_post.py normalize <in_dir> <out_dir> [opts]   # [1] 알파 이진화 → 캔버스 통일(피벗 기준 패딩, 리사이즈 금지)
  python tools/art_post.py finalize  <in_dir> <out_dir> [opts]   # [5] 팔레트 스냅 → 외곽 #1a1a1a → 고립 픽셀 제거 → [6] 피벗 정렬
                                                                  #     → East→West flip → 프레임/시트/anims.json 출력
  python tools/art_post.py run       <in_dir> <out_dir> [opts]   # [1]+[5]+[6] (PixelLab 없이 후처리만)
  python tools/art_post.py run       <in_dir> <out_dir> --dry-run --report r.json

옵션
  --tier T / --pivot x,y / --canvas N   (생략 시 data/art_anim_specs.json + ART_STYLE 1.3 표)
  --palette auto|master|master-all|entity:<id>|strip.png|'#hex,..'
        auto(기본) = art/palettes/<id>.png 있으면 그것, 없으면 등급 역할로 거른 마스터(예약 백·환경 전용·명도 상한 제외)
  --west flip|keep|none   (기본 flip: 모든 *_west_* / west.png 를 flip_h(east)로 대체. 'keep'은 독립 west 유지 → L15 FAIL)
  --protect '#hex,..'     고립 픽셀 제거에서 보호할 색(예: 1px 눈)
  --iso-passes N          고립 픽셀 제거 반복(기본 2)
  --iso-keep-de X         다수결 색과 ΔE2000 ≥ X 인 고립 픽셀은 유지(눈·하이라이트 보호). 기본 0 = 문서 규칙대로 전부 제거
  --lum-fit               (확장, 문서 외) 엔티티 최고 L* 가 팔레트 최고 L* 보다 밝으면 L* 를 비례 압축한 뒤 스냅.
                          명도 상한(적 0.45, 플레이어 #e9dcc0)에 걸린 밝은 영역이 한 색으로 뭉개지는 것을 막는다
  --fit grow|clip         사양 캔버스에 몸이 안 들어갈 때: grow(기본) = 더 큰 표준 캔버스로 패딩(리사이즈 없음, 보고서에 표시)
                          clip = 사양 캔버스 유지, 넘친 픽셀 잘림(수 보고)
  --anims a,b / --dirs d,e  일부만 처리   --sheets  애니·방향별 가로 스트립 _sheets/ 출력
  --id ID  --report path.json  --allow-runtime-write(게임 런타임 폴더 출력 허용 — 사용자 OK 후에만)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as ac  # noqa: E402
from PIL import Image  # noqa: E402

CANVAS_LADDER = [16, 24, 32, 40, 48, 64, 80, 96, 128, 160, 192, 256]
RUNTIME_DIRS = [os.path.join(ac.ROOT, "game", "assets", "sprites"), os.path.join(ac.ROOT, "game", "assets", "vfx"),
                os.path.join(ac.ROOT, "art", "raw")]


class F:
    """가변 프레임: px 리스트(RGBA 튜플), w, h, 이름 메타"""
    __slots__ = ("anim", "dir", "n", "w", "h", "px")

    def __init__(self, anim, d, n, w, h, px):
        self.anim, self.dir, self.n, self.w, self.h, self.px = anim, d, n, w, h, px

    @property
    def name(self):
        return "%s.png" % self.dir if self.anim == "rot" else "%s_%s_%d.png" % (self.anim, self.dir, self.n)

    def bbox(self):
        x0, y0, x1, y1 = self.w, self.h, -1, -1
        for i, p in enumerate(self.px):
            if p[3]:
                x, y = i % self.w, i // self.w
                x0, x1 = min(x0, x), max(x1, x)
                y0, y1 = min(y0, y), max(y1, y)
        return None if x1 < 0 else (x0, y0, x1, y1)


# ------------------------------------------------------------------------------------------------
# 단계별 연산
# ------------------------------------------------------------------------------------------------
def binarize(fr: F):
    """a ≥ 128 → 255, a < 128 → 0 (투명 RGB는 0으로)"""
    n = 0
    out = []
    for p in fr.px:
        a = p[3]
        if 0 < a < 255:
            n += 1
        out.append((p[0], p[1], p[2], 255) if a >= 128 else (0, 0, 0, 0))
    fr.px = out
    return n


def place(fr: F, W, H, dx, dy):
    """정수 이동 + 캔버스 변경(패딩/크롭). 리사이즈 없음. 잘린 불투명 픽셀 수 반환"""
    out = [(0, 0, 0, 0)] * (W * H)
    clipped = 0
    for i, p in enumerate(fr.px):
        if not p[3]:
            continue
        x, y = i % fr.w + dx, i // fr.w + dy
        if 0 <= x < W and 0 <= y < H:
            out[y * W + x] = p
        else:
            clipped += 1
    fr.px, fr.w, fr.h = out, W, H
    return clipped


def snap(fr: F, snapper: ac.Snapper, stat: Counter):
    out = []
    for p in fr.px:
        if p[3]:
            c, d = snapper.nearest(p[:3])
            stat["de_sum"] += d
            stat["px"] += 1
            if d > 0:
                stat["changed"] += 1
            out.append((c[0], c[1], c[2], 255))
        else:
            out.append(p)
    fr.px = out


def recolor_outline(fr: F, outline_rgb):
    outer = ac.outer_mask(fr.px, fr.w, fr.h)
    n = 0
    px = fr.px
    for i in outer:
        if px[i][:3] != outline_rgb:
            px[i] = outline_rgb + (255,)
            n += 1
    return n, outer


def remove_isolated(fr: F, protect, passes=2, keep_de=0.0):
    """[5] 8이웃에 같은 색이 없는 내부(외곽 제외) 픽셀 → 이웃 다수결 색(외곽선 픽셀은 표에서 제외, 동률은 원색과 ΔE 최소)"""
    total = 0
    w, h = fr.w, fr.h
    for _ in range(passes):
        outer = ac.outer_mask(fr.px, w, h)
        iso, _, _ = ac.isolated_stats(fr.px, w, h, outer)
        if not iso:
            break
        px = fr.px
        changes = {}
        for i in iso:
            rgb = px[i][:3]
            if rgb in protect:
                continue
            x, y = i % w, i // w
            votes, votes_all = Counter(), Counter()
            for dx, dy in ac.N8:
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h:
                    k = yy * w + xx
                    q = px[k]
                    if q[3]:
                        votes_all[q[:3]] += 1
                        if k not in outer:
                            votes[q[:3]] += 1
            v = votes or votes_all
            if not v:
                continue
            top = max(v.values())
            cands = [c for c, n in v.items() if n == top]
            best = min(cands, key=lambda c: ac.delta_e(c, rgb)) if len(cands) > 1 else cands[0]
            if keep_de and ac.delta_e(best, rgb) >= keep_de:
                continue  # 고대비 단일 픽셀(눈·하이라이트)은 의도된 디테일로 보고 유지
            changes[i] = best + (255,)
        if not changes:
            break
        for i, c in changes.items():
            px[i] = c
        total += len(changes)
    return total


def flip_h(fr: F):
    w = fr.w
    out = []
    for y in range(fr.h):
        row = fr.px[y * w:(y + 1) * w]
        out.extend(reversed(row))
    return F(fr.anim, "west", fr.n, fr.w, fr.h, out)


# ------------------------------------------------------------------------------------------------
def resolve_layout(frames, tier, opts, spec):
    """목표 캔버스·피벗 결정. 몸이 사양 캔버스에 안 들어가면 --fit 정책 적용"""
    T = ac.TIERS[tier]
    canv = [opts.canvas] if opts.canvas else (ac.spec_canvas(tier, spec) or [max(max(f.w, f.h) for f in frames)])
    target = canv[0]
    if opts.pivot:
        pv = tuple(int(v) for v in opts.pivot.split(","))
    else:
        pv = ac.tier_pivot(tier, target, target)
    if pv is None:  # 피벗 없는 등급(VFX·아이콘·타일): 중심 유지
        pv = (target // 2, target // 2)
    bottom_off = target - pv[1]
    side_m, top_m = T["margin"]
    foot_based = T["kind"] == "actor"
    # 필요한 반폭·높이
    need_w = need_h = 0
    for f in frames:
        b = f.bbox()
        if not b:
            continue
        need_w = max(need_w, b[2] - b[0] + 1)
        need_h = max(need_h, b[3] - b[1] + 1)

    def fits(S):
        p = (S // 2, S - bottom_off) if not opts.pivot else pv
        return (need_w + 2 * side_m <= S) and (not foot_based or (p[1] - need_h + 1) >= top_m)
    info = {"spec_canvas": canv, "target": target, "pivot_spec": list(pv), "need_w": need_w, "need_h": need_h, "fallback": None}
    if fits(target) or opts.fit == "clip" or opts.canvas:
        return target, pv, info
    for S in CANVAS_LADDER:
        if S > target and fits(S):
            info["fallback"] = "몸 %dx%d가 사양 캔버스 %d·피벗 %s·여백(사방 %d/위 %d)에 안 들어감 → %d 캔버스로 패딩(리사이즈 금지). 7.2 조건 1 재생성 대상" % (
                need_w, need_h, target, list(pv), side_m, top_m, S)
            return S, (S // 2, S - bottom_off), info
    return target, pv, info


def check_out_dir(in_dir, out_dir, allow_runtime):
    a, b = os.path.normcase(os.path.abspath(in_dir)), os.path.normcase(os.path.abspath(out_dir))
    if a == b or b.startswith(a + os.sep):
        raise SystemExit("refuse: out_dir must not be the input dir (원본 수정 금지)")
    if not allow_runtime:
        for r in RUNTIME_DIRS:
            rr = os.path.normcase(os.path.abspath(r))
            if b == rr or b.startswith(rr + os.sep):
                raise SystemExit("refuse: %s 는 런타임/원본 폴더. 사용자 OK 후 --allow-runtime-write" % out_dir)


def load_frames(in_dir, opts):
    out = []
    for fr in ac.load_entity_frames(in_dir):
        if opts.anims and fr.anim not in opts.anims:
            continue
        if opts.dirs and fr.dir not in opts.dirs:
            continue
        out.append(F(fr.anim, fr.dir, fr.n, fr.w, fr.h, list(fr.px)))
    return out


def process(mode, in_dir, out_dir, opts):
    entity = opts.id or os.path.basename(os.path.normpath(in_dir))
    if not opts.dry_run:
        check_out_dir(in_dir, out_dir, opts.allow_runtime_write)
    frames = load_frames(in_dir, opts)
    if not frames:
        raise SystemExit("no frames in " + in_dir)
    sizes = Counter((f.w, f.h) for f in frames)
    tier, spec = (opts.tier, ac.find_spec(entity)) if opts.tier else ac.detect_tier(entity, sizes.most_common(1)[0][0][0])
    if tier not in ac.TIERS:
        raise SystemExit("tier unknown (use --tier)")
    T = ac.TIERS[tier]
    master = ac.load_master()
    rep = {"entity": entity, "mode": mode, "in": os.path.abspath(in_dir), "out": os.path.abspath(out_dir), "tier": tier,
           "frames_in": len(frames), "sizes_in": {"%dx%d" % s: n for s, n in sizes.items()},
           "colors_in": len(ac.color_counter(frames)), "steps": []}

    def step(name, **kw):
        rep["steps"].append(dict(step=name, **kw))

    do_norm = mode in ("normalize", "run")
    do_final = mode in ("finalize", "run")

    # [1] 알파 이진화
    if do_norm:
        semi = sum(binarize(f) for f in frames)
        step("[1] alpha_binarize", semi_px_fixed=semi, rule="a>=128→255, a<128→0")

    # 레이아웃(캔버스·피벗)
    W, pv, lay = resolve_layout(frames, tier, opts, spec)
    rep["canvas"], rep["pivot"], rep["layout"] = W, list(pv), lay
    foot_based = T["kind"] == "actor"

    def align_all(label):
        groups = {}
        for f in frames:
            groups.setdefault((f.anim, f.dir), []).append(f)
        clipped, shifts = 0, []
        for (anim, d), g in groups.items():
            g.sort(key=lambda f: f.n)
            b0 = next((f.bbox() for f in g if f.bbox()), None)
            if not b0:
                continue
            # x: 애니·방향 묶음 단위(0프레임 bbox 중심 → 피벗 x, 루프 안 흔들림 보존). 소스 캔버스 차는 같은 이동에 포함
            cx0 = (b0[0] + b0[2]) / 2.0
            dx = int(round(pv[0] - cx0 - 0.01))  # .5 는 왼쪽으로(일관 규칙)
            for f in g:
                b = f.bbox()
                if not foot_based:              # 피벗 없는 등급(VFX·아이콘·타일·오버레이): 중앙 패딩만
                    ddx, dy = (W - f.w) // 2, (W - f.h) // 2
                elif not b:
                    ddx, dy = dx, 0
                else:
                    ddx, dy = dx, pv[1] - b[3]  # y: 프레임별 발끝 행 = 피벗 y
                clipped += place(f, W, W, ddx, dy)
                shifts.append((ddx, dy))
        sx = [abs(s[0]) for s in shifts]
        sy = [abs(s[1]) for s in shifts]
        step(label, canvas=W, pivot=list(pv), clipped_px=clipped, max_shift_x=max(sx or [0]), max_shift_y=max(sy or [0]),
             fallback=lay.get("fallback"))

    if do_norm:
        align_all("[1] canvas_unify(pivot pad, no resize)")

    if do_final:
        role = T["role"]
        pal, pal_desc = ac.load_palette_arg(opts.palette or "auto", entity, role=role)
        lscale = 1.0
        if opts.lum_fit:
            ent_max = max((ac.rgb_to_lab(p[:3])[0] for f in frames for p in f.px if p[3]), default=0)
            pal_max = max(ac.rgb_to_lab(c)[0] for c in pal)
            if ent_max > pal_max:
                lscale = pal_max / ent_max
        snapper = ac.Snapper(pal, lscale)
        st = Counter()
        for f in frames:
            snap(f, snapper, st)
        step("[5a] palette_snap", palette=pal_desc, metric="CIEDE2000 nearest", lum_fit_scale=round(lscale, 3), px=st["px"], changed_px=st["changed"],
             mean_de=round(st["de_sum"] / st["px"], 3) if st["px"] else 0)
        ol = ac.hex_to_rgb(master["outline"])
        if T["outline"] == "actor":
            n = sum(recolor_outline(f, ol)[0] for f in frames)
            step("[5b] outline_1a1a1a", recolored_px=n, rule="실루엣 외곽(4이웃 투명) 전부 #1a1a1a (sel-out 없음, 16px 아이콘 포함)")
        elif T["outline"] == "env":
            alt = ac.Snapper([c for c in pal if c != ol] or pal)
            n = 0
            for f in frames:
                for i, p in enumerate(f.px):
                    if p[3] and p[:3] == ol:
                        f.px[i] = alt.nearest(ol)[0] + (255,)
                        n += 1
            step("[5b] outline_env", removed_1a1a1a_px=n)
        else:
            step("[5b] outline", skipped="외곽선 없는 등급(VFX/투사체)")
        protect = {ac.hex_to_rgb(h) for h in ac.HEX_RE.findall(opts.protect or "")}
        n = sum(remove_isolated(f, protect, opts.iso_passes, opts.iso_keep_de) for f in frames)
        step("[5c] isolated_removal", replaced_px=n, passes=opts.iso_passes, keep_de=opts.iso_keep_de, protect=sorted(ac.rgb_to_hex(c) for c in protect))
        align_all("[6] pivot_align")

    # West 정책
    if opts.west != "keep":
        before = sum(1 for f in frames if f.dir == "west")
        frames = [f for f in frames if f.dir != "west"]
        made = 0
        if opts.west == "flip":
            for f in [f for f in frames if f.dir == "east"]:
                frames.append(flip_h(f))
                made += 1
        step("west_policy", mode=opts.west, removed_original_west=before, generated_from_east=made)

    # 출력
    frames.sort(key=lambda f: (f.anim != "rot", f.anim, ac.DIRS.index(f.dir), f.n))
    anims = {}
    for f in frames:
        if f.anim == "rot":
            continue
        anims.setdefault(f.anim, {}).setdefault(f.dir, 0)
        anims[f.anim][f.dir] += 1
    cc = Counter()
    for f in frames:
        for p in f.px:
            if p[3]:
                cc[p[:3]] += 1
    rep["colors_out"] = len(cc)
    rep["frames_out"] = len(frames)
    rep["files"] = []
    if not opts.dry_run:
        os.makedirs(out_dir, exist_ok=True)
        for f in frames:
            ac.save_rgba(f.px, f.w, f.h, os.path.join(out_dir, f.name))
            rep["files"].append(f.name)
        meta = {"size": [W, W], "pivot": list(pv), "anims": anims, "frame_size": {a: [W, W] for a in anims},
                "post": {"tool": "tools/art_post.py", "mode": mode, "tier": tier, "source": os.path.relpath(os.path.abspath(in_dir), ac.ROOT)}}
        src_meta = os.path.join(in_dir, "anims.json")
        if os.path.exists(src_meta):
            try:
                sm = json.load(open(src_meta, encoding="utf-8"))
                if "pixellab_id" in sm:
                    meta["pixellab_id"] = sm["pixellab_id"]
            except Exception:
                pass
        json.dump(meta, open(os.path.join(out_dir, "anims.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        if opts.sheets:
            sd = os.path.join(out_dir, "_sheets")
            os.makedirs(sd, exist_ok=True)
            idx = {}
            groups = {}
            for f in frames:
                groups.setdefault((f.anim, f.dir), []).append(f)
            for (anim, d), g in groups.items():
                g.sort(key=lambda f: f.n)
                sheet = Image.new("RGBA", (W * len(g), W), (0, 0, 0, 0))
                for k, f in enumerate(g):
                    im = Image.new("RGBA", (W, W))
                    im.putdata(f.px)
                    sheet.paste(im, (k * W, 0))
                nm = "%s__%s_%s.png" % (entity, anim, d) if anim != "rot" else "%s__rot_%s.png" % (entity, d)
                sheet.save(os.path.join(sd, nm))
                idx[nm] = {"anim": anim, "dir": d, "frames": len(g), "frame_size": [W, W], "pivot": list(pv)}
            json.dump(idx, open(os.path.join(sd, "sheets.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    if opts.report:
        os.makedirs(os.path.dirname(os.path.abspath(opts.report)), exist_ok=True)
        json.dump(rep, open(opts.report, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return rep, frames


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["normalize", "finalize", "run"])
    ap.add_argument("in_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--tier", choices=sorted(ac.TIERS))
    ap.add_argument("--pivot")
    ap.add_argument("--canvas", type=int)
    ap.add_argument("--palette")
    ap.add_argument("--west", choices=["flip", "keep", "none"], default="flip")
    ap.add_argument("--protect")
    ap.add_argument("--iso-passes", type=int, default=2)
    ap.add_argument("--iso-keep-de", type=float, default=0.0)
    ap.add_argument("--lum-fit", action="store_true")
    ap.add_argument("--fit", choices=["grow", "clip"], default="grow")
    ap.add_argument("--anims", type=lambda s: s.split(","))
    ap.add_argument("--dirs", type=lambda s: s.split(","))
    ap.add_argument("--sheets", action="store_true")
    ap.add_argument("--id")
    ap.add_argument("--report")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--allow-runtime-write", action="store_true")
    o = ap.parse_args(argv)
    if not os.path.isdir(o.in_dir):
        print("input dir not found: " + o.in_dir, file=sys.stderr)
        return 2
    rep, _ = process(o.mode, o.in_dir, o.out_dir, o)
    print("art_post %s %s: tier=%s canvas=%s pivot=%s frames %d→%d colors %d→%d" % (
        o.mode, rep["entity"], rep["tier"], rep["canvas"], rep["pivot"], rep["frames_in"], rep["frames_out"], rep["colors_in"], rep["colors_out"]))
    for s in rep["steps"]:
        print("  " + json.dumps(s, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
