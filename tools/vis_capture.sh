#!/usr/bin/env bash
# 가시성 기준 캡처(전/후 비교용). 한 런을 처음부터 ×SPEED 로 빨리 감다가 각 시각 LEAD 초 전부터 1배속으로 낮춰
# STEP 초 간격으로 DUR 초 동안 화면(640×360 내부 → ×3 최근접 = 1920×1080 창과 같은 픽셀)과 화면 수치를 남긴다.
# 무비 모드가 아니라 창 실행(--resolution 1280x720 = 정수 ×2, 내부 640×360 그대로) + 더미 오디오(무음) + 고정 60fps.
# 사용:
#   bash tools/vis_capture.sh before           # → game/captures/vis/before/<mmss>/shot_NN.png, vis_stats.jsonl, run.log
#   bash tools/vis_capture.sh after            # 같은 조건으로 '후'
#   PICK=random bash tools/vis_capture.sh before_crowd   # 약한 빌드(무작위 점지) — 무리에 파묻히는 경우
#   SEED=2 SPEED=10 AT=180,480,720,900,1080,1170,1220 DUR=4 STEP=0.5 LEAD=2 bash tools/vis_capture.sh <tag>
# 분석: python tools/vis_measure.py game/captures/vis/<tag>
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/c/Users/김태양/Desktop/Godot_v4.7.2-stable_win64_console.exe}"
TAG="${1:-before}"
SEED="${SEED:-2}"
SPEED="${SPEED:-10}"
AT="${AT:-180,480,720,900,1080,1170,1220}"
DUR="${DUR:-4}"
STEP="${STEP:-0.5}"
LEAD="${LEAD:-2}"
PICK="${PICK:-pair}"
EXTRA="${EXTRA:-}"   # 추가 인자(예: "--start-sec=1060")
OUT="$ROOT/game/captures/vis/$TAG"
mkdir -p "$OUT"
touch "$ROOT/game/captures/.gdignore"
LAST="${AT##*,}"
QUIT=$(python -c "print(int(float('$LAST')+float('$DUR'))+2)")
# Windows 절대 경로(Godot 에 넘길 출력 폴더)
WOUT="$(cd "$OUT" && pwd -W 2>/dev/null || pwd)"
rm -f "$OUT/vis_stats.jsonl"
echo "+ seed=$SEED speed=$SPEED pick=$PICK extra=$EXTRA at=$AT dur=$DUR step=$STEP lead=$LEAD quit=$QUIT out=$WOUT" | tee "$OUT/run.log"
"$GODOT" --path "$ROOT/game" --resolution 1280x720 --audio-driver Dummy --fixed-fps 60 --disable-vsync --quit-after 400000 -- \
  --autotest --seed="$SEED" --bot-pick="$PICK" --speed="$SPEED" --quit-at="$QUIT" \
  --vis-stats --vis-at="$AT" --vis-dur="$DUR" --vis-step="$STEP" --vis-lead="$LEAD" --vis-out="$WOUT" --vis-scale=3 $EXTRA \
  >> "$OUT/run.log" 2>&1
echo "exit=$?" | tee -a "$OUT/run.log"
grep -E "^\[vis\]|^\[autotest\] t=|^\[juice\] t=" "$OUT/run.log" | tail -n 80
grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/run.log" | sort | uniq -c | head -20
