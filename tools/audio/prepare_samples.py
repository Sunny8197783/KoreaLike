"""prepare_samples.py — 내려받은 CC0/CC-BY 원본(Freesound 미리듣기 mp3)을 빌드용 소스로 정리.

사용:  python -I tools/audio/prepare_samples.py <다운로드_디렉터리> <samples_meta.json>
출력:  art/audio/src/<key>.flac (단일 원샷/앰비언스, 모노 44.1k)
       art/audio/src/<key>_NN.flac (여러 타격이 든 파일은 온셋 검출로 잘라 원샷화, 강한 순 정렬)
       art/audio/src/SOURCES.json (키 → 원본 제목·저작자·라이선스·URL)

다운로드 파일은 신뢰하지 않는 데이터로 취급: 오디오 디코드(ffmpeg)만 하고 실행하지 않는다.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gugak_dsp as d  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "audio", "src")

# key: (mode, arg1, arg2)  slice=(최대 길이 s, 최대 개수) / whole=(최대 길이 s, 시작 s)
SPEC = {
    "drum_hits_dry": ("slice", 1.6, 7), "drum_hits_low": ("slice", 1.8, 7), "drum_sticks": ("slice", 0.35, 16),
    "bamboo_hit": ("slice", 1.2, 4), "bamboo_maraca": ("slice", 0.5, 10), "wood_blocks": ("slice", 0.4, 12),
    "wood_block_b": ("slice", 0.4, 12), "smack_body": ("slice", 0.6, 10), "smacks": ("slice", 0.6, 10),
    "paper_tear_a": ("slice", 1.0, 12), "paper_tear_b": ("slice", 1.0, 10), "paper_rustle": ("slice", 0.8, 12),
    "paper_flap": ("slice", 0.8, 12), "paper_fold": ("slice", 0.7, 12), "cloth_flap": ("slice", 1.0, 10),
    "coins": ("slice", 0.6, 16), "whoosh_sword": ("slice", 0.9, 16), "whoosh_swing": ("slice", 0.9, 12),
    "heartbeat60": ("slice", 0.9, 6), "water_drop": ("slice", 0.6, 8), "match_light": ("slice", 1.5, 8),
    "candle_light": ("slice", 1.8, 4), "sleigh_bells": ("slice", 1.0, 14), "sleigh_antique": ("slice", 2.0, 6),
    "korean_bell": ("slice", 3.5, 6), "breath_deep": ("slice", 2.5, 8), "breath_woman": ("slice", 3.0, 4),
    "fire_crackle": ("whole", 30.0, 5.0),
    # 단일 원샷
    "gong_korean_cdrk": ("whole", 6.0, 0), "gong_qubodup": ("whole", 6.0, 0), "gong_small_clear": ("whole", 2.0, 0),
    "gong_low_bash": ("whole", 14.0, 9.4), "talempong_03": ("whole", 2.0, 0.25), "talempong_05": ("whole", 2.0, 0.0),
    "rin_gong_6": ("whole", 1.0, 0), "crash_thrashed20": ("whole", 2.5, 0), "crash_mute": ("whole", 1.0, 0),
    "splash_6": ("whole", 1.0, 0), "crash_thin16": ("whole", 1.5, 0), "chime_single_02": ("whole", 4, 0),
    "chime_single_03": ("whole", 4, 0), "chime_single_04": ("whole", 4, 0), "bell_1ring": ("whole", 3, 0),
    "bell_burma": ("whole", 6, 0), "bowl_strike_a": ("whole", 7, 0), "bowl_strike_b": ("whole", 15, 0),
    "candle_wind": ("whole", 12, 0),
    # 앰비언스 베드
    "crickets_pine": ("whole", 70, 0), "crickets_forest": ("whole", 36, 0), "wind_night_a": ("whole", 22, 0),
    "wind_night_b": ("whole", 18, 0), "wind_foliage": ("whole", 70, 10), "bamboo_forest": ("whole", 45, 0),
    "whoosh_heavy": ("slice", 1.6, 8),
}


def onsets(x, min_gap=0.12, rise_db=9.0, floor_db=35.0):
    hop, win = 256, 1024
    n = (len(x) - win) // hop
    if n <= 2:
        return [0]
    fr = np.sqrt(np.array([np.mean(x[i * hop:i * hop + win] ** 2) for i in range(n)]) + 1e-12)
    lv = 20 * np.log10(fr)
    dd = np.diff(lv, prepend=lv[0])
    cand = [i for i in range(1, n) if dd[i] > rise_db and lv[i] > lv.max() - floor_db]
    out = []
    for i in cand:
        if not out or (i - out[-1]) * hop / d.SR > min_gap:
            out.append(i)
    return [max(0, i * hop - int(0.004 * d.SR)) for i in out] or [0]


def main(dl_dir, meta_path):
    meta = {m["key"]: m for m in json.load(open(meta_path, encoding="utf-8"))}
    os.makedirs(OUT, exist_ok=True)
    sources = {}
    for key, (mode, a1, a2) in SPEC.items():
        m = meta.get(key)
        if not m:
            print("skip(no meta)", key)
            continue
        x = d.load(os.path.join(dl_dir, m["file"]))
        x = d.dc_block(x)
        src = {k: m[k] for k in ("title", "creator", "license", "landing")}
        if mode == "whole":
            st = int(a2 * d.SR)
            y = x[st: st + int(a1 * d.SR)]
            y = d.fade(d.trim_silence(y, -70), 0.002, 0.05)
            y = d.normalize_peak(y, -1.0)
            d.save(os.path.join(OUT, f"{key}.flac"), y)
            sources[key] = src
        else:
            ons = onsets(x)
            segs = []
            for j, o in enumerate(ons):
                end = ons[j + 1] if j + 1 < len(ons) else len(x)
                end = min(end, o + int(a1 * d.SR))
                seg = x[o:end]
                if len(seg) < int(0.03 * d.SR):
                    continue
                segs.append((np.abs(seg).max(), seg))
            segs.sort(key=lambda s: -s[0])
            for k, (_, seg) in enumerate(segs[: int(a2)]):
                y = d.fade(d.trim_silence(seg, -60), 0.0005, 0.02)
                y = d.normalize_peak(y, -1.0)
                d.save(os.path.join(OUT, f"{key}_{k:02d}.flac"), y)
            sources[key] = dict(src, slices=min(len(segs), int(a2)))
        print("ok", key, sources[key].get("slices", "whole"))
    json.dump(sources, open(os.path.join(OUT, "SOURCES.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
