#!/usr/bin/env python3
"""art/ -> game/assets/ 런타임 스프라이트 동기화.

규약 (game/ARCHITECTURE.md §6 에셋 규약):
  game/assets/sprites/<entity_id>/{south,east,north,west}.png      정지(rotations) 4방향
  game/assets/sprites/<entity_id>/walk_<dir>_<n>.png               걷기 프레임 (n = 0..)
  game/assets/sprites/<entity_id>/<anim>_<dir>_<n>.png             기타 애니 (gut_dance 등)
  game/assets/tilesets/<name>.png (+ .metadata.json)
  game/assets/icons/<name>.png                                     아이콘 시트(슬라이스는 ui 담당)
  game/assets/vfx/<fx_id>.png + <fx_id>.json                       pixelfx/aseprite 시트
  game/assets/candidates/{bosses,deities}/*.png                    확정 전 후보(런타임 미참조)
  game/assets/sprites/manifest.json                                런타임 색인(디렉터리 나열 대신 사용)
  game/assets/sprites/<entity_id>/anims.json (spec 'art_style_v1')  새 규격 엔티티 — 이 스크립트는 건너뛴다(색인만 갱신)

런타임은 4방향(D-11). 8방향 원본 중 대각선은 복사하지 않는다(로비 8방향은 meta 담당이 별도 처리).
사용: python tools/sync_art.py [--clean | --index-only]   (--index-only: 복사 없이 manifest 색인만 갱신)
"""
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
GAME = ROOT / "game"
ASSETS = GAME / "assets"
CANON = ROOT / "data" / "canon_ids.json"
DIRS4 = ["south", "east", "north", "west"]

# 폴더명 -> 엔티티 ID 명시 매핑 (없으면 canon_ids 접두사 추측)
EXPLICIT = {
    "jeoseung_saja": "chaser_jeoseung_saja",
}
PREFIXES = ["char_", "enm_", "elite_", "mboss_", "boss_", "chaser_", "deity_", "avatar_", "npc_"]


def load_canon_ids() -> set:
    ids = set()
    try:
        d = json.loads(CANON.read_text(encoding="utf-8"))
        for v in d.get("ids", {}).values():
            if isinstance(v, list):
                ids.update(x for x in v if isinstance(x, str))
    except Exception as e:  # 데이터가 갱신 중일 수 있다
        print(f"[sync_art] warn: canon_ids 읽기 실패: {e}")
    return ids


def resolve_entity(folder: str, kind_hint: str, canon: set) -> str:
    if folder in EXPLICIT:
        return EXPLICIT[folder]
    order = PREFIXES
    if kind_hint == "char":
        order = ["char_"] + PREFIXES
    elif kind_hint == "enemy":
        order = ["enm_", "elite_", "mboss_", "boss_", "chaser_"] + PREFIXES
    for p in order:
        if p + folder in canon:
            return p + folder
    return ("char_" if kind_hint == "char" else "enm_") + folder


def copy(src: Path, dst: Path, stats: dict):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size == src.stat().st_size and dst.stat().st_mtime >= src.stat().st_mtime:
        stats["skipped"] += 1
        return
    shutil.copy2(src, dst)
    stats["copied"] += 1


def image_size(p: Path):
    try:
        from PIL import Image
        with Image.open(p) as im:
            return list(im.size)
    except Exception:
        return None


def is_spec_entity(entity_dir: Path) -> bool:
    """새 규격(ART_STYLE v1) 엔티티: game/assets/sprites/<id>/anims.json 에 spec 'art_style_v1'.
    정본은 art/rework/<그룹>/stage/<id>/ 이고 그룹 스크립트가 직접 반입한다 → sync_art 는 덮어쓰지도 지우지도 않는다."""
    f = entity_dir / "anims.json"
    if not f.exists():
        return False
    try:
        return str(json.loads(f.read_text(encoding="utf-8")).get("spec", "")).startswith("art_style_v")
    except Exception:
        return False


def sync_entity(src_root: Path, entity_id: str, manifest: dict, stats: dict):
    """src_root = .../<name>  (PixelLab 내보내기: <state>/rotations, <state>/animations/<anim>/<dir>/frame_*.png)"""
    out = ASSETS / "sprites" / entity_id
    if is_spec_entity(out):
        stats["spec_kept"] = stats.get("spec_kept", 0) + 1
        return  # rescan_sprites 가 색인만 다시 만든다
    entry = {"dirs": [], "anims": {}, "size": None, "source": str(src_root.relative_to(ROOT)).replace("\\", "/")}
    states = [p for p in src_root.iterdir() if p.is_dir()]
    # Idle 상태 폴더 우선
    states.sort(key=lambda p: (p.name != "Idle", p.name))
    for st in states:
        rot = st / "rotations"
        if rot.is_dir():
            for d in DIRS4:
                f = rot / f"{d}.png"
                if f.exists() and d not in entry["dirs"]:
                    copy(f, out / f"{d}.png", stats)
                    entry["dirs"].append(d)
                    if entry["size"] is None:
                        entry["size"] = image_size(f)
        anims = st / "animations"
        if anims.is_dir():
            for a in sorted(p for p in anims.iterdir() if p.is_dir()):
                anim_name = re.sub(r"[^a-z0-9_]", "_", a.name.lower())
                for d in DIRS4:
                    ddir = a / d
                    if not ddir.is_dir():
                        continue
                    frames = sorted(ddir.glob("frame_*.png"))
                    if not frames:
                        continue
                    for i, f in enumerate(frames):
                        copy(f, out / f"{anim_name}_{d}_{i}.png", stats)
                    entry["anims"].setdefault(anim_name, {})[d] = len(frames)
    if entry["dirs"] or entry["anims"]:
        manifest["entities"][entity_id] = entry


FRAME_RE = re.compile(r"^(?P<anim>[a-z0-9_]+?)_(?P<dir>south|east|north|west)_(?P<n>\d+)\.png$")


def rescan_sprites(manifest: dict):
    root = ASSETS / "sprites"
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        entry = manifest["entities"].get(d.name, {"dirs": [], "anims": {}, "size": None, "source": "game/assets (direct)"})
        dirs, anims = [], {}
        for f in d.glob("*.png"):
            if f.stem in DIRS4:
                dirs.append(f.stem)
                if entry.get("size") is None:
                    entry["size"] = image_size(f)
                continue
            m = FRAME_RE.match(f.name)
            if m:
                a, dd, n = m.group("anim"), m.group("dir"), int(m.group("n"))
                anims.setdefault(a, {})
                anims[a][dd] = max(anims[a].get(dd, 0), n + 1)
        entry["dirs"] = [x for x in DIRS4 if x in dirs]
        entry["anims"] = anims
        if is_spec_entity(d):
            sp = json.loads((d / "anims.json").read_text(encoding="utf-8"))
            entry["spec"] = sp.get("spec", "")
            entry["size"] = sp.get("canvas", sp.get("size", entry.get("size")))
            entry["source"] = sp.get("source", entry.get("source"))
        if entry["dirs"] or entry["anims"]:
            manifest["entities"][d.name] = entry


def index_only():
    """--index-only: 파일 복사 없이 기존 manifest.json 을 실제 game/assets/sprites 폴더로 다시 색인한다.
    (각 아트 그룹이 런타임에 직접 반입한 뒤 리드가 색인만 맞출 때. 폴더가 사라진 항목은 지운다.)"""
    mf = ASSETS / "sprites" / "manifest.json"
    manifest = json.loads(mf.read_text(encoding="utf-8")) if mf.exists() else {"entities": {}, "tilesets": [], "icons": [], "vfx": [], "candidates": []}
    manifest["_note"] = "tools/sync_art.py 가 생성. 손으로 고치지 말 것."
    gone = [k for k in manifest["entities"] if not (ASSETS / "sprites" / k).is_dir()]
    for k in gone:
        del manifest["entities"][k]
    for k in list(manifest["entities"].keys()):
        manifest["entities"][k]["size"] = None   # 캔버스가 바뀐 엔티티(재생성)를 다시 잰다
    rescan_sprites(manifest)
    mf.write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[sync_art] index-only entities={len(manifest['entities'])} removed={gone}")


def main():
    if "--index-only" in sys.argv:
        index_only()
        return
    clean = "--clean" in sys.argv
    if clean and ASSETS.exists():
        for sub in ["sprites", "tilesets", "icons", "candidates"]:
            if sub == "sprites" and (ASSETS / sub).is_dir():
                # 새 규격 엔티티 폴더는 남긴다(원본 art/ 에서 다시 만들 수 없다)
                for p in (ASSETS / sub).iterdir():
                    if p.is_dir() and not is_spec_entity(p):
                        shutil.rmtree(p, ignore_errors=True)
                    elif p.is_file():
                        p.unlink()
                continue
            shutil.rmtree(ASSETS / sub, ignore_errors=True)
    for sub in ["sprites", "tilesets", "icons", "vfx", "sfx", "music", "fonts", "candidates"]:
        (ASSETS / sub).mkdir(parents=True, exist_ok=True)
    canon = load_canon_ids()
    stats = {"copied": 0, "skipped": 0}
    manifest = {"_note": "tools/sync_art.py 가 생성. 손으로 고치지 말 것.", "entities": {}, "tilesets": [], "icons": [], "vfx": [], "candidates": []}

    chars = ART / "characters"
    for p in sorted(chars.iterdir()) if chars.is_dir() else []:
        if p.is_dir() and (p / "metadata.json").exists():
            sync_entity(p, resolve_entity(p.name, "char", canon), manifest, stats)
    enemies = ART / "enemies" / "sprites"
    for p in sorted(enemies.iterdir()) if enemies.is_dir() else []:
        if p.is_dir() and (p / "metadata.json").exists():
            sync_entity(p, resolve_entity(p.name, "enemy", canon), manifest, stats)

    for f in sorted((ART / "tilesets").glob("*.png")):
        copy(f, ASSETS / "tilesets" / f.name, stats)
        meta = f.with_name(f.stem + ".metadata.json")
        if meta.exists():
            copy(meta, ASSETS / "tilesets" / meta.name, stats)
        manifest["tilesets"].append({"id": f.stem, "size": image_size(f), "meta": meta.exists()})

    for f in sorted((ART / "items").glob("icons_sheet_*.png")):
        copy(f, ASSETS / "icons" / f.name, stats)
        manifest["icons"].append({"id": f.stem, "size": image_size(f)})

    # 이펙트 시트: art/vfx/ (pixelfx --sheet 결과를 vfx 담당이 여기에 둔다)
    vfx_src = ART / "vfx"
    if vfx_src.is_dir():
        for j in sorted(vfx_src.rglob("*.json")):
            png = j.with_suffix(".png")
            if png.exists():
                copy(png, ASSETS / "vfx" / png.name, stats)
                copy(j, ASSETS / "vfx" / j.name, stats)
                manifest["vfx"].append(j.stem)

    for sub in ["bosses", "deities"]:
        for f in sorted((ART / sub).glob("*.png")):
            copy(f, ASSETS / "candidates" / sub / f.name, stats)
            manifest["candidates"].append(f"{sub}/{f.name}")

    # 다른 담당이 game/assets/sprites/ 에 직접 넣은 엔티티까지 포함하도록 실제 폴더를 스캔해 색인을 다시 만든다.
    rescan_sprites(manifest)
    (ASSETS / "sprites" / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[sync_art] entities={len(manifest['entities'])} tilesets={len(manifest['tilesets'])} "
          f"icons={len(manifest['icons'])} vfx={len(manifest['vfx'])} copied={stats['copied']} skipped={stats['skipped']}")
    for k, v in manifest["entities"].items():
        print(f"  {k}: dirs={v['dirs']} anims={ {a: d for a, d in v['anims'].items()} } size={v['size']}")


if __name__ == "__main__":
    main()
