"""write_audio_credits.py — 오디오 에셋 크레딧·매니페스트 조각 생성.

  python -I tools/audio/write_audio_credits.py

- game/assets/CREDITS.md 의 <!-- audio:begin --> ~ <!-- audio:end --> 블록만 교체(다른 에이전트 섹션은 건드리지 않음)
- game/assets/manifest_parts/audio.json 작성 ({id, path, kind, source, license, status})
"""
import glob
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
A = os.path.join(ROOT, "game", "assets")
SRC = os.path.join(ROOT, "art", "audio", "src", "SOURCES.json")

# 장단 스템에 들어가는 샘플(build_jangdan → gugak_inst)
MUSIC_SAMPLES = {
    "janggu": ["drum_hits_low", "drum_sticks"], "buk": ["drum_hits_low"], "jing": ["gong_qubodup"],
    "kkwaenggwari": ["gong_korean_cdrk"], "jegeum": ["crash_thrashed20", "crash_thin16", "splash_6", "crash_mute"],
    "melody": [], "bed": [],
}
MUSIC_SAMPLES["mix"] = sorted({s for v in MUSIC_SAMPLES.values() for s in v})
# gugak_inst 내부에서 암묵적으로 쓰는 샘플(SFX 레시피가 해당 악기를 부르면 포함)
IMPLICIT = {"bangul": ["sleigh_bells"], "soribuk": ["drum_hits_dry", "wood_blocks"], "kkwaenggwari": ["gong_korean_cdrk"],
            "jing": ["gong_qubodup"], "jegeum": ["crash_thrashed20", "crash_thin16", "splash_6", "crash_mute"],
            "pungyeong": ["chime_single_02", "bell_1ring", "chime_single_04"], "nokgeureut": ["korean_bell"],
            "janggu": ["drum_hits_low", "drum_sticks"], "daebuk": ["drum_hits_low"]}
BY_KEYS = {"gong_korean_cdrk"}


def lic_of(samples, sources):
    by = [s for s in samples if sources.get(s, {}).get("license", "").startswith("by")]
    if by:
        return "CC-BY 4.0 구성요소 포함(" + ", ".join(sources[s]["creator"] for s in by) + ") + CC0 + 프로젝트 원작 합성"
    if samples:
        return "CC0 구성요소 + 프로젝트 원작 합성"
    return "프로젝트 원작(코드 합성)"


def main():
    sources = json.load(open(SRC, encoding="utf-8"))
    items = []
    # ---- music
    midx = json.load(open(os.path.join(A, "music", "music_index.json"), encoding="utf-8"))
    for key, info in sorted(midx["tiers"].items()):
        for layer, rel in info["files"].items():
            samples = MUSIC_SAMPLES[layer]
            fid = os.path.splitext(os.path.basename(rel))[0]
            items.append({"id": fid, "path": "game/" + rel, "kind": "music_mix" if layer == "mix" else "music_stem",
                          "source": "synth(tools/audio/build_jangdan.py)" + ("+freesound" if samples else ""),
                          "license": lic_of(samples, sources),
                          "status": "proto",
                          "note": f"{info['name_ko']} {info['bpm']}BPM loop {info['loop_s']}s x{info['cycles']}장단; 패턴 proto_placeholder(국악 자문 전사본 대기)"
                                  + ("; 선율은 합성 관악(연희자 녹음 대체 예정)" if layer == "melody" else "")})
    # ---- sfx
    sidx = json.load(open(os.path.join(A, "sfx", "sfx_index.json"), encoding="utf-8"))
    src_text = open(os.path.join(ROOT, "tools", "audio", "build_sfx.py"), encoding="utf-8").read()
    for sid, info in sorted(sidx.items()):
        samples = set(info["samples"])
        # 레시피 본문에서 악기 함수 호출을 찾아 암묵 샘플 추가
        start = src_text.find(f'@sfx("{sid}"')
        body = src_text[start: src_text.find("@sfx(", start + 5) if src_text.find("@sfx(", start + 5) > 0 else len(src_text)]
        for inst, ss in IMPLICIT.items():
            if f"gi.{inst}" in body or f"gi.janggu" in body and inst == "janggu" or (inst == "bangul" and "bell_tone" in body):
                samples.update(ss)
        if "_gildakkeum(" in body or "_hanpa_one(" in body:
            samples.update(IMPLICIT["janggu"] + IMPLICIT["bangul"] + ["smack_body", "paper_tear_a", "paper_flap"])
        if "_sinkal_hit(" in body:
            samples.update(["paper_tear_b", "smack_body", "paper_tear_a"])
        if "_bangul_hit(" in body:
            samples.update(IMPLICIT["bangul"])
        samples = sorted(samples)
        info["samples"] = samples
        for name, f in info["files"].items():
            kind = "ambience" if sid.startswith("amb_") else ("stinger" if sid.startswith("stg_") or info["class"] == "STG" else "sfx")
            if "__" in name:
                kind += "_variant"
            items.append({"id": name, "path": "game/" + f["path"], "kind": kind,
                          "source": "synth+freesound(tools/audio/build_sfx.py)" if samples else "synth(tools/audio/build_sfx.py)",
                          "license": lic_of(samples, sources), "status": "done",
                          "note": info["note"] + f" | {info['class']} {f['lufs_s']} LUFS-S, peak {f['peak_db']} dBFS"
                                  + (", loop" if f["loop"] else "")})
    json.dump(sidx, open(os.path.join(A, "sfx", "sfx_index.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    os.makedirs(os.path.join(A, "manifest_parts"), exist_ok=True)
    part = {"agent": "audio", "scope": "국악 장단 루프 스템(music/) + v1 SFX·스팅어·앰비언스(sfx/)",
            "tools": ["tools/audio/gugak_dsp.py", "tools/audio/gugak_inst.py", "tools/audio/prepare_samples.py",
                      "tools/audio/build_jangdan.py", "tools/audio/build_sfx.py", "tools/audio/write_audio_credits.py"],
            "source_archive": "art/audio/src (CC0/CC-BY 원본 정리본 + SOURCES.json)",
            "known_issues": [
                "장구·꽹과리 CC0/CC-BY 원샷 녹음이 공개 라이브러리에 사실상 없어 막·금속 모달 합성 + 일반 북/스틱/소형 징 샘플로 만듦 — 연희자 녹음으로 교체 권장",
                "장단 패턴은 data/audio_jangdan.json proto_patterns(verified=false) 그대로. 살풀이·엇모리·휘모리는 build_jangdan.py EXTRA_PATTERNS 보충(프로토)",
                "선율(태평소·피리·대금·아쟁)은 합성 근사 — 실제 녹음 전 임시",
                "추임새 '얼쑤'·무가·공수 등 보이스(VO)는 미포함(sfx_sys_sinmyeong_full, sfx_boss_knot_untie 는 VO 없이 제작)",
                "Freesound 미리듣기(128kbps mp3) 기반 — 마스터 품질이 필요하면 원본 WAV 를 각 landing URL 에서 받아 prepare_samples.py 재실행",
            ],
            "items": items}
    json.dump(part, open(os.path.join(A, "manifest_parts", "audio.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # ---- CREDITS.md 블록
    used_by = {}
    for sid, info in sidx.items():
        for s in info["samples"]:
            used_by.setdefault(s, set()).add(sid)
    for layer, ss in MUSIC_SAMPLES.items():
        if layer == "mix":
            continue
        for s in ss:
            used_by.setdefault(s, set()).add(f"music/*_{layer}")
    lines = ["<!-- audio:begin -->", "## Audio (audio agent)", "",
             "game/assets/music/*.ogg, game/assets/sfx/*.ogg 는 tools/audio/ 의 합성 코드(프로젝트 원작)와 아래 외부 샘플을 "
             "가공(잘라내기·피치·필터·엔벨로프·레이어·잔향)해 만든 2차 저작물이다. 외부 샘플은 전부 CC0 또는 CC-BY 4.0 이며 "
             "NC/ND/BY-SA 는 쓰지 않았다. 원본 정리본: art/audio/src/ (SOURCES.json).", "",
             "### CC-BY 4.0 — 저작자 표시 필수", "",
             "| 샘플 | 제목 | 저작자 | 라이선스 | 출처 | 변경 | 사용처 |", "|---|---|---|---|---|---|---|"]
    for k, v in sorted(sources.items()):
        if v["license"].startswith("by"):
            lines.append(f"| {k} | {v['title']} | {v['creator']} | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | "
                         f"{v['landing']} | 피치 변경·감쇠 엔벨로프·필터·합성음과 레이어 | {', '.join(sorted(used_by.get(k, [])))} |")
    lines += ["", "표기 예(게임 내 크레딧 화면): \"gong_0001_[korean]_1_shot_mono.flac\" by cdrk (freesound.org/people/cdrk/sounds/18660), "
              "CC BY 4.0, modified.", "",
              "### CC0 1.0 — 의무 없음(감사 표기)", "",
              "| 샘플 | 제목 | 저작자 | 출처 | 사용처 |", "|---|---|---|---|---|"]
    for k, v in sorted(sources.items()):
        if v["license"].startswith("cc0"):
            use = ", ".join(sorted(used_by.get(k, []))) or "(보관만, 미사용)"
            if len(use) > 160:
                use = use[:157] + "..."
            title = v["title"].replace("|", "/")
            lines.append(f"| {k} | {title} | {v['creator']} | {v['landing']} | {use} |")
    lines += ["", "- 프로젝트 원작(외부 샘플 없음): 장단 선율·베드 스템(*_melody, *_bed), 순수 합성 SFX(sfx_trl_circle_enter, "
              "sfx_enm_proj_generic, sfx_enm_dalgyal_gwisin, sfx_pick_wonhon, sfx_sys_gilbe_close_ready 등).",
              "- 검색 경로: Openverse API(Freesound·Wikimedia 색인). Wikimedia 의 장구 녹음(CC BY-SA 4.0)은 BY-SA 라 제외.",
              "<!-- audio:end -->"]
    block = "\n".join(lines) + "\n"
    cpath = os.path.join(A, "CREDITS.md")
    text = open(cpath, encoding="utf-8").read() if os.path.exists(cpath) else "# CREDITS\n\n"
    if "<!-- audio:begin -->" in text:
        a = text.index("<!-- audio:begin -->")
        b = text.index("<!-- audio:end -->") + len("<!-- audio:end -->")
        text = text[:a] + block.rstrip("\n") + text[b:]
    else:
        text = text.rstrip("\n") + "\n\n" + block
    open(cpath, "w", encoding="utf-8").write(text)
    print("manifest items:", len(items))


if __name__ == "__main__":
    main()
