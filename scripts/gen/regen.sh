#!/usr/bin/env bash
# usage: regen.sh [--check]
# Regenerates every generated module in seedfinder/data/ (the only way seedfinder/data/*.bend may change).
# The extractors first write sidecars from the real game scripts into scripts/gen/out/ (lua-dst, the host C++
# toolchain and the game binaries), then the generators write seedfinder/data/*.bend from them. Needs scripts/setup.sh.
# --check regenerates into a temp dir and fails if any seedfinder/data/*.bend (or a sidecar present in scripts/gen/out/) differs.
set -euo pipefail
root="$(cd "$(dirname "$(realpath "$0")")/../.." && pwd)"
check="${1:-}"
cd "$root"
gen=scripts/gen
build=.scratch/build/gen
lua=scripts/harness/bin/lua-dst
lua_src="${LUA_SRC:-.scratch/ref/lua-5.1.5/src}"
boost="${BOOST_DIR:-.scratch/ref/boost_1_52_0}"
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
  "catalog.bend:$gen/gen_catalog.py"
  "world_catalog.bend:$gen/gen_world_catalog.py"
  "search_vocab.bend:$gen/gen_search_vocab.py"
  "blob.bend:$gen/gen_blob.py"
  "strings.bend:$gen/gen_strings.py"
  "enums.bend:$gen/gen_enums.py"
  "closures.bend:$gen/gen_closures.py"
  "rooms.bend:$gen/gen_rooms.py"
  "tasks.bend:$gen/gen_tasks.py"
  "distribute.bend:$gen/gen_distribute.py"
  "picks.bend:$gen/gen_distribute.py picks"
  "layouts.bend:$gen/gen_layouts.py"
  "layout_props.bend:$gen/gen_layouts.py props"
  "ocean.bend:$gen/gen_ocean.py"
  "ocean_convert.bend:$gen/gen_ocean_convert.py"
  "constants.bend:$gen/gen_constants.py"
  "story.bend:$gen/gen_story.py"
  "tile_groups.bend:$gen/gen_tiles.py"
  "populate.bend:$gen/gen_populate.py"
  "ocean_post.bend:$gen/gen_ocean_post.py"
  "pow.bend:$gen/gen_pow.py"
  "gen_tags.bend:$gen/gen_gen.py"
)
for entry in "${generators[@]}"; do
  name="${entry%%:*}"; script="${entry#*:}"
  if [[ "$check" == "--check" ]]; then
    if GEN_OUT="$out" python3 $script - | cmp -s - "seedfinder/data/$name"; then echo "ok      seedfinder/data/$name"; else echo "STALE   seedfinder/data/$name ($script)"; status=1; fi
  else
    GEN_OUT="$out" python3 $script
    echo "wrote   seedfinder/data/$name ($script)"
  fi
done
exit $status
