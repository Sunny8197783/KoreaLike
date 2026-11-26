#!/usr/bin/env bash
# data/ -> game/data/ 복사 (디렉터리 구조 유지). 원본은 data/ 이고 game/data/ 는 사본이다 — game/data/ 를 직접 고치지 말 것.
# 사용: bash tools/sync_data.sh [--art]   (--art 면 tools/sync_art.py 도 실행)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/data"
DST="$ROOT/game/data"

mkdir -p "$DST"
# 원본에 없는 사본 파일 제거(이름이 바뀐 테이블이 남아 이중 로드되는 것 방지)
( cd "$DST" && find . -type f -name '*.json' ) | while read -r f; do
  [ -f "$SRC/$f" ] || { rm -f "$DST/$f"; echo "[sync_data] removed stale $f"; }
done
count=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/}"
  mkdir -p "$DST/$(dirname "$rel")"
  cp -p "$f" "$DST/$rel"
  count=$((count+1))
done < <(find "$SRC" -type f -name '*.json' -print0)
# 빈 디렉터리 정리
find "$DST" -mindepth 1 -type d -empty -delete 2>/dev/null || true
echo "[sync_data] copied $count json files -> game/data/"

if [ "${1:-}" = "--art" ]; then
  python "$ROOT/tools/sync_art.py"
fi
