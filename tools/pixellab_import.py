#!/usr/bin/env python3
"""PixelLab character ZIP -> art/sprites_v2/<entity_id>/ (원본) -> game/assets/sprites/<entity_id>/ (런타임 4방향).

사용:
  python tools/pixellab_import.py <entity_id> <zip_path> [--anim pixellab_name=runtime_name ...]
                                 [--mirror-west] [--north-from-south] [--only-dirs south,east]

규약:
  {south,east,north,west}.png            정지 4방향 (rotations)
  <anim>_<dir>_<n>.png                   애니 프레임 (n=0..)
  애니 이름 매핑이 없으면 PixelLab 애니 폴더명을 소문자 snake_case 로 사용.
  --mirror-west : west 가 없으면 east 를 좌우반전해 채움(애니 포함).
  --north-from-south : north 애니가 없으면 south 애니를 복사(정면형 소형 졸개).
"""
import argparse
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art" / "sprites_v2"
OUT = ROOT / "game" / "assets" / "sprites"
DIRS4 = ["south", "east", "north", "west"]


def snake(s: str) -> str:
    s = re.sub(r"[^0-9a-zA-Z]+", "_", s).strip("_").lower()
    return s or "anim"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("entity_id")
    ap.add_argument("zip_path")
    ap.add_argument("--anim", action="append", default=[], help="pixellab_folder=runtime_name")
    ap.add_argument("--mirror-west", action="store_true")
    ap.add_argument("--north-from-south", action="store_true")
    ap.add_argument("--clean", action="store_true")
    a = ap.parse_args()

    amap = dict(x.split("=", 1) for x in a.anim)
    raw = ART / a.entity_id
    raw.mkdir(parents=True, exist_ok=True)
    zp = Path(a.zip_path)
    shutil.copy2(zp, raw / f"{a.entity_id}.zip")
    ext = raw / "zip"
    if ext.exists():
        shutil.rmtree(ext)
    with zipfile.ZipFile(zp) as z:
        for n in z.namelist():
            if ".." in n or n.startswith("/"):
                continue
            z.extract(n, ext)
    meta = json.loads((ext / "metadata.json").read_text(encoding="utf-8"))
    st = meta["states"][0]
    folder = ext / st.get("folder", "")
    frames = st["frames"]

    out = OUT / a.entity_id
    if a.clean and out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)
    written = {"rotations": [], "anims": {}}

    rots = frames.get("rotations", {})
    for d in DIRS4:
        src = rots.get(d)
        if src:
            shutil.copy2(ext / src, out / f"{d}.png")
            written["rotations"].append(d)
    if "west" not in rots and a.mirror_west and "east" in rots:
        ImageOps.mirror(Image.open(ext / rots["east"])).save(out / "west.png")
        written["rotations"].append("west(mirror)")

    for aname, bydir in frames.get("animations", {}).items():
        rname = amap.get(aname, snake(aname))
        if rname == "-":
            continue
        dirs = {d: bydir[d] for d in DIRS4 if d in bydir}
        if "west" not in dirs and a.mirror_west and "east" in dirs:
            dirs["west"] = ("MIRROR", dirs["east"])
        if "north" not in dirs and a.north_from_south and "south" in dirs:
            dirs["north"] = dirs["south"]
        counts = {}
        for d, lst in dirs.items():
            mirror = isinstance(lst, tuple)
            if mirror:
                lst = lst[1]
            for i, f in enumerate(lst):
                dst = out / f"{rname}_{d}_{i}.png"
                if mirror:
                    ImageOps.mirror(Image.open(ext / f)).save(dst)
                else:
                    shutil.copy2(ext / f, dst)
            counts[d + ("(mirror)" if mirror else "")] = len(lst)
        written["anims"][rname] = counts
    size = st["character"]["size"]
    written["size"] = [size["width"], size["height"]]
    written["character_id"] = st["character"]["id"]
    print(json.dumps({a.entity_id: written}, ensure_ascii=False))


if __name__ == "__main__":
    main()
