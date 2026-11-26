#!/usr/bin/env python3
"""art_post_review — 원본 vs art_post 후처리-only 결과 비교 시트(PNG).

  python tools/art_post_review.py <orig_dir> <out.png> --variant 라벨=후처리폴더 [--variant ...]
         [--frames south.png,idle_south_0.png,...] [--scale 4] [--title T] [--workbench-score 82.6]

셀: 모든 프레임을 같은 칸(가장 큰 캔버스)에 '피벗 정렬'로 배치한다. 원본은 사양 피벗이 후처리 피벗과 같은 화면 위치에 오도록
      (원본 캔버스 좌하단 기준) 놓고, 파란 선 = 피벗 y. 자홍 = 고립 픽셀(외곽 제외, 8이웃 같은 색 없음).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as ac  # noqa: E402
import art_lint  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

BG = (23, 19, 31, 255)        # mk #17131f
BG2 = (133, 113, 84, 255)     # hj #857154 (밝은 배경 확인용)
PANEL = (63, 54, 84, 255)     # mk #3f3654 (외곽선 #1a1a1a가 보이도록)
TXT = (233, 220, 192, 255)    # hj #e9dcc0
DIM = (143, 151, 158, 255)
BAD = (228, 96, 79, 255)
GOOD = (85, 184, 170, 255)
PIVOT = (95, 147, 222, 255)
MAGENTA = (255, 0, 255, 255)


def font(sz=11):
    for p in (os.path.join(ac.ROOT, "game", "assets", "fonts", "galmuri", "Galmuri11.ttf"), "C:/Windows/Fonts/malgun.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def frame_img(path):
    return Image.open(path).convert("RGBA")


def iso_overlay(im):
    px = ac.pixels(im)
    w, h = im.size
    outer = ac.outer_mask(px, w, h)
    iso, interior, _ = ac.isolated_stats(px, w, h, outer)
    o = im.copy()
    for i in iso:
        o.putpixel((i % w, i // w), MAGENTA)
    return o, (100.0 * len(iso) / interior if interior else 0)


def gray(im):
    out = Image.new("RGBA", im.size)
    src = ac.pixels(im)
    out.putdata([(int(255 * ac.rel_luminance(p[:3]) ** (1 / 2.2)),) * 3 + (p[3],) if p[3] else (0, 0, 0, 0) for p in src])
    return out


def palette_strip(colors, cell=6, maxn=64):
    cols = sorted(colors, key=lambda c: ac.rel_luminance(c))[:maxn]
    im = Image.new("RGBA", (max(1, len(cols)) * cell, cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, c in enumerate(cols):
        d.rectangle([i * cell, 0, i * cell + cell - 1, cell - 1], fill=tuple(c) + (255,))
    return im


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("orig")
    ap.add_argument("out")
    ap.add_argument("--variant", action="append", default=[])
    ap.add_argument("--frames", required=True)
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--title", default="")
    ap.add_argument("--workbench-score", type=float)
    ap.add_argument("--id")
    o = ap.parse_args(argv)
    names = o.frames.split(",")
    entity = o.id or os.path.basename(os.path.normpath(o.orig))
    variants = [("원본 (game/assets/sprites)", o.orig, "master-all")]
    for v in o.variant:  # 라벨=폴더[@lint팔레트]
        lab, path = v.split("=", 1)
        pal = "master-all"
        if "@" in path:
            path, pal = path.split("@", 1)
        variants.append((lab, path, pal))

    # 피벗/캔버스
    tier, spec = ac.detect_tier(entity, None)
    canv = ac.spec_canvas(tier, spec)[0]
    spec_pv = ac.tier_pivot(tier, canv, canv)
    imgs = {}
    cell = 0
    for lab, path, _ in variants:
        for n in names:
            p = os.path.join(path, n)
            if os.path.exists(p):
                im = frame_img(p)
                imgs[(lab, n)] = im
                cell = max(cell, im.size[0])
    post_pv = None
    for lab, path, _ in variants[1:]:
        aj = os.path.join(path, "anims.json")
        if os.path.exists(aj):
            post_pv = json.load(open(aj, encoding="utf-8")).get("pivot")
    post_pv = post_pv or [cell // 2, cell - (canv - spec_pv[1])]
    S = o.scale
    F = font(11)
    FS = font(11)
    gap = 4
    label_w = 150
    cols = len(names)
    cw = cell * S
    # 레이아웃 높이 계산
    rows = []
    for lab, path, _ in variants:
        rows.append(("frames", lab, path))
    width = label_w + cols * (cw + gap) + 16
    row_h = cw + 18
    # 추가 패널: 고립 픽셀·그레이·밝은 배경 (첫 프레임), 팔레트, 지표 표
    extra_h = cw + 40 + 30 * len(variants) + 26 * 16 + 40
    height = 34 + len(rows) * (row_h + gap) + extra_h
    sheet = Image.new("RGBA", (width, height), BG)
    d = ImageDraw.Draw(sheet)
    d.fontmode = "1"
    d.text((8, 8), o.title or ("post_only — %s (tier %s, 사양 캔버스 %d, 피벗 %s)" % (entity, tier, canv, list(spec_pv))), font=F, fill=TXT)
    y = 30
    for ci, n in enumerate(names):
        d.text((label_w + ci * (cw + gap), y), n.replace(".png", ""), font=FS, fill=DIM)
    y += 14

    def place_in_cell(im, is_orig):
        w, h = im.size
        c = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        if is_orig and w == canv:
            # 원본 사양 피벗 → 후처리 피벗 위치
            ox, oy = post_pv[0] - spec_pv[0], post_pv[1] - spec_pv[1]
        else:
            ox, oy = (cell - w) // 2, cell - h if is_orig else (cell - w) // 2
            if not is_orig:
                oy = (cell - h) // 2
        c.alpha_composite(im, (max(0, ox), max(0, oy)))
        return c, (ox, oy, w, h)

    for vi, (lab, path, _) in enumerate(variants):
        d.text((8, y + cw // 2 - 6), lab, font=F, fill=TXT)
        for ci, n in enumerate(names):
            im = imgs.get((lab, n))
            x0 = label_w + ci * (cw + gap)
            d.rectangle([x0, y, x0 + cw - 1, y + cw - 1], fill=PANEL)
            if im is None:
                d.text((x0 + 4, y + 4), "없음", font=FS, fill=BAD)
                continue
            c, (ox, oy, w, h) = place_in_cell(im, vi == 0)
            big = c.resize((cw, cw), Image.NEAREST)
            sheet.alpha_composite(big, (x0, y))
            # 캔버스 테두리 + 피벗 선
            d.rectangle([x0 + ox * S, y + oy * S, x0 + (ox + w) * S - 1, y + (oy + h) * S - 1], outline=(84, 74, 107, 255))
            py = y + post_pv[1] * S + S - 1
            d.line([x0, py, x0 + cw - 1, py], fill=PIVOT)
        y += row_h + gap

    # 1프레임 확대 패널
    first = names[0]
    d.text((8, y), "%s: 고립 픽셀(자홍) / 그레이스케일 / 밝은 배경 / 1배" % first, font=F, fill=TXT)
    y += 16
    x = 8
    for vi, (lab, path, _) in enumerate(variants):
        im = imgs.get((lab, first))
        if im is None:
            continue
        ov, isop = iso_overlay(im)
        for k, panel in enumerate((ov, gray(im))):
            big = panel.resize((im.size[0] * 3, im.size[1] * 3), Image.NEAREST)
            sheet.paste(PANEL, [x, y, x + big.size[0], y + big.size[1]])
            sheet.alpha_composite(big, (x, y))
            x += big.size[0] + 4
        bg = Image.new("RGBA", (im.size[0] * 3, im.size[1] * 3), BG2)
        bg.alpha_composite(im.resize(bg.size, Image.NEAREST))
        sheet.alpha_composite(bg, (x, y))
        x += bg.size[0] + 4
        sheet.alpha_composite(im, (x, y))
        d.text((x, y + im.size[1] + 2), "iso %.1f%%" % isop, font=FS, fill=DIM)
        x += im.size[0] + 18
    y += cell * 3 + 20

    # 팔레트 스트립 (엔티티 전체 사용색)
    reports = []
    for vi, (lab, path, _) in enumerate(variants):
        frames = ac.load_entity_frames(path)
        cc = ac.color_counter(frames)
        strip = palette_strip(list(cc), cell=7, maxn=150)
        d.text((8, y + 1), "%s — 엔티티 사용색 %d" % (lab.split(" ")[0], len(cc)), font=FS, fill=TXT)
        sheet.alpha_composite(strip.crop((0, 0, min(strip.size[0], width - label_w - 100), strip.size[1])), (label_w + 90, y + 3))
        y += 16
        ns = art_lint.argparse.Namespace(tier=None, pivot=None, palette=variants[vi][2], id=entity, strict=False,
                                         allow_west=False, strict_west=False, require_anchors=False, workbench=None,
                                         workbench_score=(o.workbench_score if vi == 0 else None))
        reports.append(art_lint.lint_entity(path, ns))
    y += 8

    # 지표 표
    keys = ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10", "L11", "L12", "L13", "L14", "L15", "L18"]
    colw = (width - 220) // max(1, len(variants))
    d.text((8, y), "lint (art_lint.py)", font=F, fill=TXT)
    for vi, (lab, _, _) in enumerate(variants):
        d.text((220 + vi * colw, y), lab[:34], font=FS, fill=TXT)
    y += 16

    def short(ch):
        v = ch["value"]
        cid = ch["id"]
        try:
            if cid == "L1":
                return ",".join(v.keys())
            if cid == "L2":
                return "반투명 %d px" % v["semi_px"]
            if cid == "L3":
                return "준수 %.1f%% (밖 %d색)" % (v["compliance_pct"], v["off_colors"])
            if cid == "L4":
                return "%d색 / 예산 %s (프레임 최대 %d)" % (v["entity_colors"], v["budget"], v["frame_max"])
            if cid == "L5":
                return "%d px" % v["px"]
            if cid == "L6":
                return "ch %.1f%%" % max(v["exact_pct"], v["nearest_snap_pct"])
            if cid == "L7":
                return "#1a1a1a %.1f%%" % v["outline_1a1a1a_pct"]
            if cid == "L8":
                return "좌%d 우%d 위%d 아래%d" % (v["left"], v["right"], v["top"], v["bottom"])
            if cid == "L9":
                return "발끝 %d~%d (피벗 %d)" % (v["foot_min"], v["foot_max"], v["pivot_y"])
            if cid == "L10":
                return "방향 cx 범위 %.1f px" % v["worst_range_px"]
            if cid == "L11":
                return "몸 %d (목표 %d~%d)" % (v["height"], v["target"][0], v["target"][1])
            if cid == "L12":
                return " ".join("%s:dh%+d/df%+d" % (k[0].upper(), r["dh"], r["dfoot"]) for k, r in v.items())
            if cid == "L13":
                return "면적 %.1f%% cx %.1f" % (v["area_var_pct"], v["cx_range"])
            if cid == "L14":
                return "고립 %.1f%% 클러스터 %.1f" % (v["isolated_pct"], v["avg_cluster_px"])
            if cid == "L15":
                return "west %d (flip %d / 독립 %d)" % (v["west_files"], v.get("flip_of_east", 0), v.get("independent", 0))
            if cid == "L18":
                return "최대 휘도 %.3f (상한 %.3f)" % (v["max_lum"], v["cap"])
        except Exception:
            pass
        return str(v)[:40]

    for k in keys:
        d.text((8, y), "%s %s" % (k, art_lint.CHECK_NAMES[k]), font=FS, fill=DIM)
        for vi, r in enumerate(reports):
            ch = next(c for c in r.checks if c["id"] == k)
            col = GOOD if ch["status"] == "PASS" else (BAD if ch["status"] == "FAIL" else (DIM if ch["status"] == "N/A" else (232, 185, 49, 255)))
            d.text((220 + vi * colw, y), "%-4s %s" % (ch["status"], short(ch) if ch["value"] is not None else ""), font=FS, fill=col)
        y += 15
    y += 4
    for vi, r in enumerate(reports):
        c = r.counts()
        d.text((220 + vi * colw, y), "PASS %d FAIL %d WARN %d" % (c["PASS"], c["FAIL"], c["WARN"]), font=F, fill=TXT)
    y += 22
    sheet = sheet.crop((0, 0, width, min(height, y + 6)))
    os.makedirs(os.path.dirname(os.path.abspath(o.out)), exist_ok=True)
    sheet.save(o.out)
    print("wrote", o.out, sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
