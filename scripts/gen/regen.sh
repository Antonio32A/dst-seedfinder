#!/usr/bin/env bash
# usage: regen.sh [--check]
# Regenerates every generated module in seedfinder/data/ and config.schema.json (the only way they may change).
# The extractors first write sidecars from the real game scripts into scripts/gen/out/ (lua-dst, the host C++
# toolchain and the game binaries), then the generators write seedfinder/data/*.bend from them. Needs scripts/setup.sh.
# --check regenerates into a temp dir and fails if any of them (or a sidecar present in scripts/gen/out/) differs.
set -euo pipefail
root="$(cd "$(dirname "$(realpath "$0")")/../.." && pwd)"
check="${1:-}"
cd "$root"
gen=scripts/gen
build=build/gen
lua=scripts/harness/bin/lua-dst
lua_src="${LUA_SRC:-build/deps/lua-5.1.5/src}"
boost="${BOOST_DIR:-build/deps/boost_1_52_0}"
[[ -x "$lua" ]] || scripts/harness/build.sh
mkdir -p "$build" "$gen/out"
status=0

out="$gen/out"
if [[ "$check" == "--check" ]]; then
  out="$(mktemp -d)"
  trap 'rm -rf "$out"' EXIT
fi

gcc -O2 -shared -fPIC -I"$lua_src" -o "$build/tablelayout.so" "$gen/lib/tablelayout.c"
g++ -O0 -std=c++17 -ffp-contract=off -w -isystem "$boost" -o "$build/gen_constants" "$gen/gen_constants.cpp"

sidecars=(
  "story.json:$lua $gen/extract_story.lua"
  "distribute.json:$lua $gen/extract_distribute.lua"
  "layouts.json:$lua $gen/extract_layouts.lua"
  "ocean.json:$lua $gen/extract_ocean.lua"
  "constants.json:$lua $gen/extract_constants.lua"
  "constants_c.json:$build/gen_constants"
  "storygen.json:$lua $gen/extract_storygen.lua"
  "tiles.json:$lua $gen/extract_tiles.lua"
  "ocean_post.json:$lua $gen/extract_ocean_post.lua"
)
for entry in "${sidecars[@]}"; do
  name="${entry%%:*}"; cmd="${entry#*:}"
  (ulimit -v 16000000; timeout 900 $cmd > "$out/$name")
  if [[ "$check" == "--check" ]]; then
    if [[ ! -f "$gen/out/$name" ]]; then echo "new     $gen/out/$name"
    elif cmp -s "$out/$name" "$gen/out/$name"; then echo "ok      $gen/out/$name"
    else echo "STALE   $gen/out/$name ($cmd)"; status=1; fi
  else
    echo "wrote   $gen/out/$name"
  fi
done

generators=(
  "seedfinder/data/catalog.bend:$gen/gen_catalog.py"
  "seedfinder/data/world_catalog.bend:$gen/gen_world_catalog.py"
  "seedfinder/data/search_vocab.bend:$gen/gen_search_vocab.py"
  "seedfinder/data/blob.bend:$gen/gen_blob.py"
  "seedfinder/data/strings.bend:$gen/gen_strings.py"
  "seedfinder/data/enums.bend:$gen/gen_enums.py"
  "seedfinder/data/closures.bend:$gen/gen_closures.py"
  "seedfinder/data/rooms.bend:$gen/gen_rooms.py"
  "seedfinder/data/tasks.bend:$gen/gen_tasks.py"
  "seedfinder/data/distribute.bend:$gen/gen_distribute.py"
  "seedfinder/data/picks.bend:$gen/gen_distribute.py picks"
  "seedfinder/data/layouts.bend:$gen/gen_layouts.py"
  "seedfinder/data/layout_props.bend:$gen/gen_layouts.py props"
  "seedfinder/data/ocean.bend:$gen/gen_ocean.py"
  "seedfinder/data/ocean_convert.bend:$gen/gen_ocean_convert.py"
  "seedfinder/data/constants.bend:$gen/gen_constants.py"
  "seedfinder/data/story.bend:$gen/gen_story.py"
  "seedfinder/data/tile_groups.bend:$gen/gen_tiles.py"
  "seedfinder/data/populate.bend:$gen/gen_populate.py"
  "seedfinder/data/ocean_post.bend:$gen/gen_ocean_post.py"
  "seedfinder/data/pow.bend:$gen/gen_pow.py"
  "seedfinder/data/gen_tags.bend:$gen/gen_gen.py"
  "config.schema.json:$gen/gen_schema.py"
)
for entry in "${generators[@]}"; do
  name="${entry%%:*}"; script="${entry#*:}"
  if [[ "$check" == "--check" ]]; then
    if GEN_OUT="$out" python3 $script - | cmp -s - "$name"; then echo "ok      $name"; else echo "STALE   $name ($script)"; status=1; fi
  else
    GEN_OUT="$out" python3 $script
    echo "wrote   $name ($script)"
  fi
done
exit $status
