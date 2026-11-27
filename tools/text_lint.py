#!/usr/bin/env python3
"""화면 글 검사(design/19 §4.1·§8.1 ③). 경고만 내고 늘 0 으로 끝난다(godot_check.sh 끝에서 부른다).

검사
  1) 8px 한글: 한글 문자열과 Galmuri7(_f_tiny / UiKit.tiny() / SZ_TINY / 크기 8)이 같은 줄에 있다.
  2) 격자 밖 크기: draw_string / UiKit.text / text_outline 에 숫자 크기가 (8, 10, 12, 15, 붓 ≥32) 밖이다.
  3) 한자 노출: 판 안 화면 코드(HUD·길잡이·거리 카드·예고 띠)의 문자열과 waves_stage1 *_ko 에 한자가 있다.
  4) 금지어: 화면 문자열에 '손님'(적을 손님이라 부르지 않는다, 캐논 D-03) 등.
  5) 해라체 명령: waves_stage1 *_ko(판 안 안내 띠·목표)가 '~라'로 끝난다(행동을 시키는 글은 '~세요', 검토 11-26). 대사 파일은 제외.
사용: python tools/text_lint.py [게임 폴더(기본: 이 파일 기준 ../game)]
출력: '[text_lint] 경고 <종류> <파일>:<줄> <내용>' 줄들 + 요약 한 줄.
"""
import io
import json
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")
ROOT = os.path.normpath(ROOT)

HANGUL = re.compile(r"[가-힣]")
HANJA = re.compile(r"[一-鿿]")
STR = re.compile(r'"(?:[^"\\\n]|\\.)*"')
TINY = re.compile(r"_f_tiny|UiKit\.tiny\(\)|SZ_TINY|F_TINY")
SIZE_CALL = re.compile(r"(draw_string\s*\(|UiKit\.text\s*\(|UiKit\.text_outline\s*\(|draw_string_outline\s*\()")
OK_SIZES = {8, 10, 12, 15}
BANNED = ["손님"]
HAERA = re.compile(r"[가-힣]라\s*(?:$|—|[.!,])")
# 판 안에서 플레이 중 보이는 화면 코드(한자 노출 검사 대상)
IN_RUN = {"ui/hud.gd", "ui/guide.gd", "waves/wave_presenter.gd"}
SKIP_DIRS = {"captures", ".godot", "addons", "tests"}

warns = []


def warn(kind, path, line, text):
    warns.append((kind, path, line, text.strip()[:110]))


def code_part(line):
    """주석(# …)을 뗀 코드 부분. 문자열 안의 #은 남긴다."""
    out = []
    q = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            q = not q
        if c == "#" and not q:
            break
        out.append(c)
        i += 1
    return "".join(out)


def call_sizes(code):
    """크기 인자 후보: 호출 괄호 안의 정수 리터럴 중 글자 크기 자리(draw_string 6번째, UiKit.text 2번째)."""
    sizes = []
    for m in SIZE_CALL.finditer(code):
        start = m.end()
        depth = 1
        j = start
        while j < len(code) and depth > 0:
            if code[j] in "([{":
                depth += 1
            elif code[j] in ")]}":
                depth -= 1
            j += 1
        inner = code[start:j - 1]
        args = []
        depth = 0
        cur = ""
        qq = False
        for ch in inner:
            if ch == '"':
                qq = not qq
            if not qq and ch in "([{":
                depth += 1
            if not qq and ch in ")]}":
                depth -= 1
            if ch == "," and depth == 0 and not qq:
                args.append(cur.strip())
                cur = ""
            else:
                cur += ch
        args.append(cur.strip())
        name = m.group(1)
        idx = None
        if name.startswith("draw_string"):
            idx = 5
        elif name.startswith("UiKit.text"):
            idx = 1
        if idx is not None and len(args) > idx and re.fullmatch(r"\d+", args[idx] or ""):
            sizes.append(int(args[idx]))
    return sizes


def lint_gd(path, rel):
    try:
        lines = io.open(path, encoding="utf-8").read().split("\n")
    except (OSError, UnicodeDecodeError):
        return
    for n, raw in enumerate(lines, 1):
        code = code_part(raw)
        if not code.strip():
            continue
        strs = STR.findall(code)
        has_kr = any(HANGUL.search(s) for s in strs)
        if has_kr and (TINY.search(code) or re.search(r",\s*8\s*,", code) and SIZE_CALL.search(code)):
            warn("8px한글", rel, n, code)
        for sz in call_sizes(code):
            if sz not in OK_SIZES and sz < 32:
                warn("격자밖크기", rel, n, "%d: %s" % (sz, code))
        if rel in IN_RUN:
            for s in strs:
                if HANJA.search(s):
                    warn("한자노출", rel, n, s)
        for s in strs:
            for b in BANNED:
                if b in s:
                    warn("금지어", rel, n, s)


def walk_json(v, key, rel, path, in_run_ko):
    if isinstance(v, dict):
        for k, x in v.items():
            if str(k).startswith("_") or k in ("doc", "note", "canon_v1_2_log", "review_log"):
                continue
            walk_json(x, str(k), rel, path + "." + str(k), in_run_ko)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            walk_json(x, key, rel, "%s[%d]" % (path, i), in_run_ko)
    elif isinstance(v, str):
        if not (key.endswith("_ko") or key == "ko"):
            return
        for b in BANNED:
            if b in v:
                warn("금지어", rel, path, v)
        if in_run_ko and HANJA.search(v):
            warn("한자노출", rel, path, v)
        if in_run_ko and HAERA.search(v):
            warn("해라체", rel, path, v)


def main():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in fns:
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            if fn.endswith(".gd"):
                lint_gd(full, rel)
    for rel, in_run in (("data/waves_stage1.json", True), ("data/narrative/gongsu_lines.json", False),
                        ("data/onboarding_hints.json", False)):
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            continue
        try:
            d = json.load(io.open(p, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        walk_json(d, "", rel, "", in_run)
    kinds = {}
    for k, p, ln, t in warns:
        kinds[k] = kinds.get(k, 0) + 1
        print("[text_lint] 경고 %s %s:%s %s" % (k, p, ln, t))
    summ = " ".join("%s=%d" % (k, kinds[k]) for k in sorted(kinds)) or "없음"
    print("[text_lint] 요약 %d건 (%s)" % (len(warns), summ))
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass
    sys.exit(main())
