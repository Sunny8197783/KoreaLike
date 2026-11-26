#!/usr/bin/env python3
"""vfx_art_fix — 기존 VFX 시트를 ART_STYLE VFX 규격으로 보정(재생성 없음, 리사이즈 없음). 소유: vfx.
  python game/vfx/tools/vfx_art_fix.py [--only id,id] [--dry-run] [--no-backup] [--report r.json]
단계(시트마다, ART_STYLE 3.3·3.4·L19):
  1 알파: blend=normal 시트는 이진화(a>=128 -> 255, 아니면 0). add/multiply 시트는 반투명 유지(L2 WARN 허용), a<16 은 0.
  2 팔레트: 마스터 world 색 최근접(CIEDE2000)으로 스냅. 환경 전용 램프(eg/et) 제외, 예약 백(bk)은 color_role 에 W 가 있을 때만.
  3 색 수: 6색(master per_sprite_color_budget.vfx) 초과면 (빈도 x dE)가 가장 작은 색부터 최근접 남은 색으로 병합.
  4 프레임 크기: 각 변을 {16,32,64,128} 중 가장 작은 값으로 패딩(중앙 정렬, 피벗 같이 이동).
    128 초과(화면 공간·대형)·리본/빔/라인/타일 시트는 예외(크기 유지 — 리사이즈 금지).
  5 duration: art_vfx_list timing 이 fps:N 이면 모든 프레임 round(1000/N), meta.pixelfx.fps = N.
원본은 ../art/_legacy_runtime/vfx/ 에 백업(이미 있으면 덮지 않음 = 최초 원본 보존).
"""
import argparse
import json
import os
import shutil
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import art_common as ac  # noqa: E402
from PIL import Image  # noqa: E402

VFX = os.path.join(ROOT, "game", "assets", "vfx")
BACKUP = os.path.join(ROOT, "art", "_legacy_runtime", "vfx")
SIZES = (16, 32, 64, 128)
NO_PAD_CANVAS = ("ribbon", "beam", "mesh", "cells", "shader", "tile")   # "line" 은 패딩(가로 길이 시트 아님: 끝점 피벗 줄무늬)


def list_entries():
    d = json.load(open(ac.VFX_LIST_JSON, encoding="utf-8"))
    keys = d["tuple"]
    return {r[0]: dict(zip(keys, r)) for r in d["vfx"] if r}


def fit(n):
    for s in SIZES:
        if n <= s:
            return s
    return None


def palette_for(role):
    m = ac.load_master()
    white = ac.hex_to_rgb(m["reserved_white"])
    out = []
    for h in m["world_colors"]:
        r = ac.ramp_of(h)
        if r in ("eg", "et"):
            continue
        c = ac.hex_to_rgb(h)
        if "W" not in role and (r == "bk" or ac.delta_e(c, white) <= m["reserved_white_delta_e"]):
            continue
        out.append(c)
    return out


def reduce_colors(cnt, budget, keep):
    cols = dict(cnt)
    labs = {c: ac.rgb_to_lab(c) for c in cols}
    remap = {c: c for c in cols}
    while len(cols) > budget:
        best = None
        for c, n in cols.items():
            if c in keep:
                continue
            d = min(ac.delta_e2000(labs[c], labs[o]) for o in cols if o != c)
            score = n * d
            if best is None or score < best[0]:
                best = (score, c)
        if best is None:
            break
        c = best[1]
        tgt = min((o for o in cols if o != c), key=lambda o: ac.delta_e2000(labs[c], labs[o]))
        cols[tgt] += cols.pop(c)
        for k, v in remap.items():
            if v == c:
                remap[k] = tgt
    return remap


def process(fx_id, entry, opts, budget, report):
    png = os.path.join(VFX, fx_id + ".png")
    js = os.path.join(VFX, fx_id + ".json")
    meta = json.load(open(js, encoding="utf-8"))
    frames = meta.get("frames", [])
    hashed = isinstance(frames, dict)
    if hashed:
        keys = list(frames.keys())
        flist = [frames[k] for k in keys]
    else:
        flist = frames
    if not flist:
        report[fx_id] = "no frames"
        return
    sheet = Image.open(png).convert("RGBA")
    entry = entry or {}
    # 0 끝 빈 프레임(pixelfx 종료 표식) 제거: 프레임 수가 목록 +1 이고 마지막 프레임이 완전 투명일 때
    want = entry.get("frames")
    if isinstance(want, int) and want > 0 and len(flist) == want + 1:
        r = flist[-1]["frame"]
        last = sheet.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]))
        if last.getbbox() is None:
            flist = flist[:-1]
            if hashed:
                keys = keys[:-1]
    blend = entry.get("blend", "normal")
    role = str(entry.get("color_role", ""))
    canvas = str(entry.get("canvas", ""))
    snap = ac.Snapper(palette_for(role))
    crops = []
    for f in flist:
        r = f["frame"]
        crops.append(sheet.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))
    cnt = Counter()
    out_px = []
    semi_before = 0
    for im in crops:
        new = []
        for p in list(im.getdata()):
            a = p[3]
            if 0 < a < 255:
                semi_before += 1
            if blend == "normal":
                a = 255 if a >= 128 else 0
            elif a < 16:
                a = 0
            if a == 0:
                new.append((0, 0, 0, 0))
                continue
            c = snap.nearest(p[:3])[0]
            cnt[c] += 1
            new.append((c[0], c[1], c[2], a))
        out_px.append(new)
    n_before = len(cnt)
    if len(cnt) > budget:
        keep = set()
        if "W" in role:
            keep.add(ac.hex_to_rgb(ac.load_master()["reserved_white"]))
        keep &= set(cnt)
        remap = reduce_colors(cnt, budget, keep)
        out_px = [[(remap[p[:3]] + (p[3],)) if p[3] else p for p in px] for px in out_px]
    w0, h0 = crops[0].size
    pad = not any(k in canvas for k in NO_PAD_CANVAS)
    W, H = (fit(w0), fit(h0)) if pad else (None, None)
    if W is None or H is None:
        W, H = w0, h0
        size_note = "keep %dx%d" % (w0, h0)
    else:
        size_note = "%dx%d->%dx%d" % (w0, h0, W, H) if (W, H) != (w0, h0) else "ok"
    ox, oy = (W - w0) // 2, (H - h0) // 2
    y0 = min(f["frame"]["y"] for f in flist)
    cols = max(1, sum(1 for f in flist if f["frame"]["y"] == y0))
    rows = (len(flist) + cols - 1) // cols
    new_sheet = Image.new("RGBA", (cols * W, rows * H), (0, 0, 0, 0))
    fps_list = None
    tm = str(entry.get("timing", ""))
    if tm.startswith("fps:"):
        try:
            fps_list = float(tm.split(":")[1])
        except ValueError:
            fps_list = None
    for i, (f, px) in enumerate(zip(flist, out_px)):
        im = Image.new("RGBA", (w0, h0))
        im.putdata(px)
        cx, cy = (i % cols) * W, (i // cols) * H
        new_sheet.paste(im, (cx + ox, cy + oy))
        f["frame"] = {"x": cx, "y": cy, "w": W, "h": H}
        if "sourceSize" in f:
            f["sourceSize"] = {"w": W, "h": H}
        if "spriteSourceSize" in f:
            f["spriteSourceSize"] = {"x": 0, "y": 0, "w": W, "h": H}
        if fps_list:
            f["duration"] = int(round(1000.0 / fps_list))
    m = meta.setdefault("meta", {})
    pfx = m.setdefault("pixelfx", {})
    pv = pfx.get("pivot")
    if isinstance(pv, list) and len(pv) >= 2:
        pfx["pivot"] = [pv[0] + ox, pv[1] + oy]
    elif isinstance(pv, dict):
        pfx["pivot"] = [pv.get("x", w0 // 2) + ox, pv.get("y", h0 // 2) + oy]
    else:
        pfx["pivot"] = [w0 // 2 + ox, h0 // 2 + oy]
    pfx["frameSize"] = [W, H]
    pfx["columns"] = cols
    pfx["frames"] = len(flist)
    if fps_list:
        pfx["fps"] = fps_list
    m["size"] = {"w": new_sheet.size[0], "h": new_sheet.size[1]}
    pfx["art_fix"] = {"tool": "game/vfx/tools/vfx_art_fix.py", "colors": [n_before, min(n_before, budget)],
                      "semi_before": semi_before, "blend": blend, "size": size_note}
    if hashed:
        meta["frames"] = {k: f for k, f in zip(keys, flist)}
    else:
        meta["frames"] = flist      # 끝 빈 프레임을 뺀 목록을 JSON 에도 반영(안 하면 frames N+1 로 남아 L19 FAIL)
    report[fx_id] = {"colors": "%d->%d" % (n_before, min(n_before, budget)), "semi_before": semi_before,
                     "blend": blend, "size": size_note, "fps": fps_list}
    if opts.dry_run:
        out = getattr(opts, "preview_dir", None)
        if out:
            os.makedirs(out, exist_ok=True)
            new_sheet.save(os.path.join(out, fx_id + ".png"))
        return
    if not opts.no_backup:
        os.makedirs(BACKUP, exist_ok=True)
        for p in (png, js):
            dst = os.path.join(BACKUP, os.path.basename(p))
            if not os.path.exists(dst):
                shutil.copy2(p, dst)
    new_sheet.save(png)
    json.dump(meta, open(js, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--preview-dir")
    ap.add_argument("--no-backup", action="store_true")
    ap.add_argument("--report")
    o = ap.parse_args()
    ents = list_entries()
    budget = ac.load_master()["per_sprite_color_budget"]["vfx"]
    ids = sorted(os.path.splitext(f)[0] for f in os.listdir(VFX) if f.endswith(".json"))
    ids = [i for i in ids if os.path.exists(os.path.join(VFX, i + ".png"))]
    if o.only:
        want = set(o.only.split(","))
        ids = [i for i in ids if i in want]
    report = {}
    for i in ids:
        try:
            process(i, ents.get(i), o, budget, report)
        except Exception as e:  # noqa: BLE001
            report[i] = "ERR %r" % e
    txt = json.dumps(report, ensure_ascii=False, indent=1)
    if o.report:
        open(o.report, "w", encoding="utf-8").write(txt)
    print("processed", len(report), "errors", sum(1 for v in report.values() if isinstance(v, str)))


if __name__ == "__main__":
    main()
