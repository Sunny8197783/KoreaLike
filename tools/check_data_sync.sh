#!/usr/bin/env bash
# CI 검사: data/(원본)와 game/data/(Godot 사본)가 바이트 단위로 같은지 cmp로 확인한다.
# 다르면 exit 1. 고칠 때는 data/를 고친 뒤 bash tools/sync_data.sh 를 실행한다(game/data/ 직접 수정 금지).
# 사용: bash tools/check_data_sync.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/data"
DST="$ROOT/game/data"
fail=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/}"
  if [ ! -f "$DST/$rel" ]; then echo "[check_data_sync] MISSING game/data/$rel"; fail=1
  elif ! cmp -s "$f" "$DST/$rel"; then echo "[check_data_sync] DIFFERS $rel"; fail=1; fi
done < <(find "$SRC" -type f -name '*.json' -print0)
while IFS= read -r -d '' f; do
  rel="${f#"$DST"/}"
  [ -f "$SRC/$rel" ] || { echo "[check_data_sync] STALE game/data/$rel (원본 없음)"; fail=1; }
done < <(find "$DST" -type f -name '*.json' -print0)
[ $fail -eq 0 ] && echo "[check_data_sync] OK: data/ == game/data/"
exit $fail
