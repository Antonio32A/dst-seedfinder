#!/usr/bin/env bash
# Regenerates catalog.json from scratch. See README.md.
# usage: ./regen.sh [--fresh-worlds]   (--fresh-worlds deletes worlds/*.json so the emulator worlds are re-run)
set -euo pipefail
here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cd "$root/.scratch/catalog"
mkdir -p build worlds

if [[ "${1:-}" == "--fresh-worlds" ]]; then
    rm -f worlds/*.json
    rm -rf build/harness_world
fi

(ulimit -v 16000000; timeout 900 "$root/scripts/harness/bin/lua-dst" "$here/extract_static.lua" > build/static.json)
"$here/run_worlds.sh" "$here/seeds.txt" 8 | tee build/run_worlds.log
python3 "$here/level_table_stats.py" > build/level_table_stats.json
python3 "$here/level_world_stats.py" 1 100000 8 > build/level_world_stats.json
python3 "$here/build_catalog.py" --collect
python3 "$here/build_catalog.py" --out "$here/catalog.json"
