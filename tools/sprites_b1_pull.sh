#!/bin/sh
# usage: sprites_b1_pull.sh <entity_id> <pixellab_char_id> [converter flags...]
set -e
cd "$(dirname "$0")/.."
E=$1; ID=$2; shift 2
mkdir -p art/sprites_v2/$E
curl -sfL -o art/sprites_v2/$E/$E.zip "https://api.pixellab.ai/mcp/characters/$ID/download"
python tools/sprites_b1_convert.py art/sprites_v2/$E/$E.zip $E --clean "$@"
