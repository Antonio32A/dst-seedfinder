#!/usr/bin/env bash
# Regenerates a game build's catalogs (<build>/catalog.json and <build>/cave_catalog.json) from scratch. See README.md.
# usage: ./regen.sh [--build NUMBER] [--fresh-worlds]   (the build defaults to the latest of builds.json;
# --fresh-worlds deletes the cached emulator worlds so they are re-run)
set -euo pipefail

here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
root="$(cd "$here/../.." && pwd)"
: "${WORLDSIM_DIR:?set WORLDSIM_DIR to the worldsim emulator (see README.md)}"
: "${HARNESS_DIR:?set HARNESS_DIR to the level-table harness (see README.md)}"

build="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["latest"])' "$root/builds.json")"
fresh=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    --build) build="$2"; shift 2 ;;
    --fresh-worlds) fresh=1; shift ;;
    *) echo "usage: regen.sh [--build NUMBER] [--fresh-worlds]" >&2; exit 2 ;;
    esac
done

mkdir -p "$root/build/catalog/$build" "$here/$build"
cd "$root/build/catalog/$build"
mkdir -p build worlds

if [[ -n "$fresh" ]]; then
    rm -f worlds/*.json
    rm -rf build/harness_world
fi

(
    ulimit -v 16000000
    timeout 900 "$root/scripts/harness/bin/lua-dst" "$here/extract_static.lua" --build "$build" > build/static.json
)
(
    ulimit -v 16000000
    CATALOG_SHARD=caves timeout 900 "$root/scripts/harness/bin/lua-dst" "$here/extract_static.lua" --build "$build" \
        > build/static_caves.json
)
python3 "$here/minimap_icons.py" --build "$build"
"$here/run_worlds.sh" "$here/seeds.txt" 8 "$root/build/catalog/$build" | tee build/run_worlds.log
python3 "$here/level_table_stats.py" "$HARNESS_DIR/out/out_1M.txt" > build/level_table_stats.json
python3 "$here/level_world_stats.py" 1 100000 8 > build/level_world_stats.json
python3 "$here/build_catalog.py" --build "$build" --collect
python3 "$here/build_catalog.py" --build "$build" --shard caves --collect
python3 "$here/build_catalog.py" --build "$build"
python3 "$here/build_catalog.py" --build "$build" --shard caves
