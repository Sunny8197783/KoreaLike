#!/usr/bin/env bash
# 헤드리스 검증: 임포트 → 파싱/런타임 오류 0 확인 → (선택) 화면 캡처.
# 사용:
#   bash tools/godot_check.sh                 # 기본: 임포트 + 메인 씬 600프레임 + 봇 60초(고정 60fps)
#   bash tools/godot_check.sh --movie         # + non-headless --write-movie 캡처(captures/frame*.png)
#   bash tools/godot_check.sh --full          # + 봇 완주(보스·정산·결과 화면까지, ×10 배속, 점지 정책 pair)
#   bash tools/godot_check.sh --geodum        # + 보스 해결 뒤 정산 중 사망 → '굿판 거둠'(클리어 유지) 경로
#   bash tools/godot_check.sh --builds        # + 빌드 다양성 행렬(시드 3 × 무당 2, 병렬) — [autotest] build 한 줄 요약
#   (기본 단계에 사망 경로 포함: --autotest-die=20 → 정산(R_DEATH) → 신당)
#   (기본 단계에 튜토리얼 포함: 인트로 카드 6 · 굿 안내서 8쪽 · 연습 굿판 10단계 · 새 프로필 첫 실전 직행 · 첫 실행 흐름(인트로→권유→연습→타이틀, 두 번째 실행=메뉴) — design/17)
#   GODOT=/path/to/godot bash tools/godot_check.sh
#   LOG_TAG=combat bash tools/godot_check.sh   # 동시 실행용: 로그 captures/godot_check_<tag>.log, 캡처 captures/<tag>/frame*.png
#   OUT_DIR=/abs/dir bash tools/godot_check.sh # 로그·캡처 출력 폴더 직접 지정(LOG_TAG 보다 우선)
#   MOVIE_AT=74 MOVIE_ARGS="--start-sec=600" bash tools/godot_check.sh --movie  # 캡처 종료 게임 시각·추가 인자
# 종료 코드: 0 = 오류 없음, 1 = 오류 발견(로그: captures/godot_check[_<tag>].log)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/c/Users/김태양/Desktop/Godot_v4.7.2-stable_win64_console.exe}"
PROJ="$ROOT/game"
CAP="$ROOT/game/captures"
mkdir -p "$CAP"
touch "$CAP/.gdignore"   # 캡처 PNG 가 리소스로 임포트되지 않게
TAG="${LOG_TAG:-}"
if [ -n "${OUT_DIR:-}" ]; then OUT="$OUT_DIR"; LOG="$OUT/godot_check.log"
elif [ -n "$TAG" ]; then OUT="$CAP/$TAG"; LOG="$CAP/godot_check_$TAG.log"
else OUT="$CAP"; LOG="$CAP/godot_check.log"; fi
mkdir -p "$OUT"
MOVIE_AT="${MOVIE_AT:-74}"
MOVIE_ARGS="${MOVIE_ARGS:-}"
: > "$LOG"

run() { echo "+ $*" | tee -a "$LOG"; "$@" 2>&1 | tee -a "$LOG" | tail -n 25; }

echo "== 1) import" | tee -a "$LOG"
run "$GODOT" --headless --path "$PROJ" --import
echo "== 2) main scene, 600 frames (title)" | tee -a "$LOG"
run "$GODOT" --headless --path "$PROJ" --quit-after 600
echo "== 3) autotest bot, 60s game time at fixed 60fps" | tee -a "$LOG"
run "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 4000 -- --autotest --seed=1 --quit-at=60
echo "== 3d) death path: die at 20s -> result (R_DEATH) -> lobby" | tee -a "$LOG"
run "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 3000 -- --autotest --seed=3 --autotest-die=20 --quit-at=60 --result-hold=1.0 --autotest-lobby
grep -q "^\[autotest\] run_finished victory=false" "$LOG" || echo "ERROR: death path did not reach run_finished" | tee -a "$LOG"
# 튜토리얼(design/17 §7.6·§9): 각 단계는 자기 로그($SL)에서 판정한다. 판정 실패는 "ERROR:" 줄로 남겨 아래 오류 집계에 잡힌다.
SL="$OUT/godot_check_stage.log"
runs() { : > "$SL"; echo "+ $*" | tee -a "$LOG"; "$@" 2>&1 | tee -a "$LOG" "$SL" | grep -E "^\[(intro|guidebook|tutorial|title)\] (card|page|done|end|offer|choice|open|title_back|step=.* done|finished|save_same|route|real_run|quit_mid)" ; }
need() { local n; n=$(grep -cE "$1" "$SL"); [ "$n" -ge "$2" ] || echo "ERROR: $3 (pattern '$1' x$n < $2)" | tee -a "$LOG"; }
echo "== 3t) intro cards (--intro-test)" | tee -a "$LOG"
runs "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 900 -- --intro-test
need "^\[intro\] card=[1-6]/6 " 6 "intro did not show 6 cards"
need "^\[intro\] done " 1 "intro did not finish"
echo "== 3g) guidebook pages (--guidebook-test=all)" | tee -a "$LOG"
runs "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 900 -- --guidebook-test=all
need "^\[guidebook\] page=[1-8]/8 " 8 "guidebook did not show 8 pages"
need "^\[guidebook\] done" 1 "guidebook did not finish"
echo "== 3p) practice gutpan autotest (10 steps, x4)" | tee -a "$LOG"
runs "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 12000 -- --autotest --tutorial-autotest --seed=1 --speed=4
need "^\[tutorial\] step=[a-z]+ done " 10 "practice gutpan did not complete 10 steps"
need "^\[tutorial\] finished .* done=10/10" 1 "practice gutpan did not finish 10/10"
need "^\[tutorial\] save_same=true" 1 "practice gutpan changed real-run records"
# 새 프로필: 연습 중간에 그만두기 → 다시 연습 → 완주 → '굿판 열기(실전)' = 만신 직행 + 첫 굿판 완화(§9-3·4)
echo "== 3q) practice on fresh profile: quit mid -> again -> real run (first-run assist kept)" | tee -a "$LOG"
UD="${APPDATA:-$HOME/AppData/Roaming}/Godot/app_userdata/넋길- 해원굿"
# 동시 실행 시 서로 프로필을 지우지 않게 LOG_TAG 를 프로필 이름에 붙인다(예: tutcheck_vis).
PT="${TAG:+_$TAG}"; PT="${PT//[^A-Za-z0-9_]/_}"
rm -f "$UD/save_profile_tutcheck$PT.json" "$UD/save_profile_tutcheck$PT.json.bak"
runs "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 20000 -- --autotest --profile=tutcheck$PT --tutorial-autotest --tutorial-exit-at=white --tutorial-exit=real --seed=2 --speed=4
need "^\[tutorial\] quit_mid step=white" 1 "mid-practice quit did not happen"
need "^\[tutorial\] finished .* done=10/10" 1 "practice after restart did not finish 10/10"
need "^\[tutorial\] save_same=true" 1 "practice changed real-run records (fresh profile)"
need "^\[tutorial\] route=real first_run_pending=true runs_done=0" 1 "first real run is not first_run_pending after practice"
need "^\[tutorial\] real_run char=char_mansin assist=true" 1 "first real run lost mansin direct start / first-run assist"
# 첫 실행 흐름(§3.1·§9-1): 새 프로필 ftcheck → 타이틀 인트로 6장 → 권유 창 '연습하기' → 연습 굿판 완주 → '타이틀로'
# → 두 번째 실행은 인트로·권유 없이 타이틀 메뉴(첫 실전 직행·완화는 그대로 남아 있어야 한다)
echo "== 3f) first launch flow on fresh profile: intro -> offer(practice) -> practice -> title; second launch -> menu" | tee -a "$LOG"
rm -f "$UD/save_profile_ftcheck$PT.json" "$UD/save_profile_ftcheck$PT.json.bak"
runs "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 20000 -- --autotest --profile=ftcheck$PT --intro-test --intro-choice=practice --ui-save=1 --tutorial-autotest --tutorial-exit=title --seed=1 --speed=4
need "^\[title\] open intro_seen=false offered=false" 1 "fresh profile did not start at intro"
need "^\[intro\] card=[1-6]/6 " 6 "first launch did not show 6 intro cards"
need "^\[intro\] choice=practice" 1 "offer did not lead to practice"
need "^\[tutorial\] finished .* done=10/10" 1 "practice from offer did not finish 10/10"
need "^\[tutorial\] save_same=true" 1 "practice from offer changed real-run records"
need "^\[tutorial\] title_back" 1 "practice end did not return to title"
runs "$GODOT" --headless --path "$PROJ" --quit-after 300 -- --profile=ftcheck$PT
need "^\[title\] open intro_seen=true offered=true practice_done=true first_run_pending=true" 1 "second launch did not open title menu directly (or first run assist lost)"
if [ "${1:-}" = "--geodum" ]; then
  # 보스 강제 해원 → 사자 정산 단계에서 정기 0 → '굿판 거둠'(victory=true, ending=gutpan_geodum)
  echo "== 3e) settle death -> gutpan_geodum" | tee -a "$LOG"
  run "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 20000 -- --autotest --seed=4 --start-sec=1190 --speed=10 --waves-boss-resolve=haewon --waves-boss-resolve-after=3 --autotest-die=settle --quit-at=1700 --result-hold=1.0
  grep -q "ending=gutpan_geodum" "$LOG" || echo "ERROR: settle death did not end as gutpan_geodum" | tee -a "$LOG"
fi
if [ "${1:-}" = "--builds" ]; then
  # 빌드 다양성: 시드 3 × 무당 2, 점지 정책 pair, 병렬 실행 → 한 줄 요약([autotest] build ...)
  echo "== 3c) build matrix (pair policy, seeds 2/7/11 x mansin/second char, parallel)" | tee -a "$LOG"
  C2="${BUILD_CHAR2:-char_myeongdu}"
  pids=()
  for ch in char_mansin "$C2"; do for sd in 2 7 11; do
    "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 30000 -- --autotest --seed=$sd --char=$ch --bot-pick=pair --quit-at=1560 --speed=10 > "$OUT/build_${ch}_${sd}.log" 2>&1 &
    pids+=($!)
  done; done
  for p in "${pids[@]}"; do wait "$p"; done
  for f in "$OUT"/build_*.log; do cat "$f" >> "$LOG"; grep -E "^\[autotest\] build " "$f"; done
fi
if [ "${1:-}" = "--full" ]; then
  # 20:00 보스 → 저승사자 정산 → Events.stage_finished → 정산 화면까지(강제 사자 23:00 + 살 거둠). quit-at 은 안전망.
  echo "== 3b) autotest bot, full run to stage_finished at x10" | tee -a "$LOG"
  run "$GODOT" --headless --path "$PROJ" --fixed-fps 60 --quit-after 30000 -- --autotest --seed=2 --bot-pick=pair --quit-at=1560 --speed=10
  grep -E "^\[autotest\] build " "$LOG" | tail -1
fi
if [ "${1:-}" = "--movie" ]; then
  echo "== 4) movie capture (non-headless)" | tee -a "$LOG"
  rm -f "$OUT"/frame*.png
  # 1280x720(×2), 시뮬레이션 ×10, 게임 74초에 quit_game 으로 종료(--quit-after 로 끊으면 오디오 누수 오류). 50프레임마다 1장만 남긴다.
  # shellcheck disable=SC2086
  run "$GODOT" --path "$PROJ" --resolution 1280x720 --write-movie "$OUT/frame.png" --fixed-fps 60 --quit-after 100000 -- --autotest --seed=1 --speed=10 --quit-at="$MOVIE_AT" $MOVIE_ARGS
  for f in "$OUT"/frame*.png; do n=$(basename "$f" .png); n=${n#frame}; n=$((10#$n)); [ $((n % 50)) -eq 0 ] || rm -f "$f"; done
  ls "$OUT"/frame*.png 2>/dev/null | tee -a "$LOG"
fi

ERRS=$(grep -E "SCRIPT ERROR|Parse Error|ERROR:|Failed to load|Invalid call|Cannot call|Attempt to call|Nonexistent function|Identifier .* not declared" "$LOG" | grep -v "^+ " | sort | uniq -c | sort -rn)
if [ -n "$ERRS" ]; then
  echo "== FAIL: errors found"
  echo "$ERRS" | head -40
  exit 1
fi
echo "== OK: no errors"
grep -E "^\[autotest\]" "$LOG" | tail -3
exit 0
