#!/usr/bin/env bash
# usage: regen.sh [--check]
# Regenerates seedfinder/data/, website/lib/config/game-builds.ts, config.schema.json and website/lib/catalog/cave-vocab.ts
# (the only way they may change) for every game build of builds.json. For each build B the extractors write sidecars
# from B's game files (build/deps/builds/B/, filled by scripts/setup.sh) into scripts/gen/out/B/ (lua-dst, the host C++
# toolchain and the game binaries), and the generators stage B's modules in build/gen/data/B/. gen_builds.py then
# writes seedfinder/data/ from the staged modules: the ones every build shares, the per-build copies in b<build>/ with
# their dispatch modules, and builds.bend. The schema and cave-vocab.ts come from the latest build.
# --check regenerates into a temp dir and fails if anything differs: a sidecar present in scripts/gen/out/B/, any file
# of seedfinder/data/ (stray or missing ones too), game-builds.ts, the schema or cave-vocab.ts.
set -euo pipefail

root="$(cd "$(dirname "$(realpath "$0")")/../.." && pwd)"
check="${1:-}"
cd "$root"

gen=scripts/gen
lua=scripts/harness/bin/lua-dst
lua_src="${LUA_SRC:-build/deps/lua-5.1.5/src}"
boost="${BOOST_DIR:-build/deps/boost_1_52_0}"
[[ -x "$lua" ]] || scripts/harness/build.sh
mkdir -p build/gen "$gen/out"
status=0

out="$gen/out"
staging=build/gen/data
target=.
if [[ "$check" == "--check" ]]; then
    temp="$(mktemp -d)"
    trap 'rm -rf "$temp"' EXIT
    out="$temp/out"
    staging="$temp/data"
    target="$temp/root"
fi

clang -O2 -shared -fPIC -I"$lua_src" -o build/gen/tablelayout.so "$gen/lib/tablelayout.c"
clang++ -O0 -std=c++17 -ffp-contract=off -w -isystem "$boost" -o build/gen/gen_constants "$gen/gen_constants.cpp"

read -r latest builds < <(python3 -c 'import json, sys; r = json.load(open(sys.argv[1]))
print(r["latest"], *(b["number"] for b in r["builds"]))' builds.json)

sidecars=(
    "story.json:$lua $gen/extract_story.lua"
    "distribute.json:$lua $gen/extract_distribute.lua"
    "layouts.json:$lua $gen/extract_layouts.lua"
    "ocean.json:$lua $gen/extract_ocean.lua"
    "constants.json:$lua $gen/extract_constants.lua"
    "constants_c.json:build/gen/gen_constants"
    "storygen.json:$lua $gen/extract_storygen.lua"
    "tiles.json:$lua $gen/extract_tiles.lua"
    "ocean_post.json:$lua $gen/extract_ocean_post.lua"
    "caves.json:$lua $gen/extract_caves.lua"
    "story_caves.json:env GEN_SHARD=caves $lua $gen/extract_story.lua"
    "distribute_caves.json:env GEN_SHARD=caves $lua $gen/extract_distribute.lua"
    "layouts_caves.json:env GEN_SHARD=caves $lua $gen/extract_layouts.lua"
)

generators=(
    gen_catalog.py gen_world_catalog.py gen_cave_catalog.py gen_cave_story.py gen_search_vocab.py gen_blob.py
    gen_strings.py gen_enums.py gen_closures.py gen_rooms.py gen_tasks.py gen_distribute.py "gen_distribute.py picks"
    gen_layouts.py "gen_layouts.py props" gen_ocean.py gen_ocean_convert.py gen_constants.py gen_story.py gen_tiles.py
    gen_populate.py gen_ocean_post.py gen_pow.py gen_powf.py gen_gen.py
)

use_build() {
    export GEN_BUILD="$1" GEN_GAME="build/deps/builds/$1" GEN_SCRIPTS="build/deps/builds/$1/scripts"
    export GEN_OUT="$out/$1" GEN_DATA="$staging/$1"
}

for build in $builds; do
    if [[ ! -f "build/deps/builds/$build/version.txt" ]]; then
        echo "regen.sh: build/deps/builds/$build is missing: run DST_GAME=<that build's install> scripts/setup.sh" >&2
        exit 1
    fi
    use_build "$build"
    rm -rf "$GEN_DATA"
    mkdir -p "$GEN_OUT" "$GEN_DATA"

    for entry in "${sidecars[@]}"; do
        (
            ulimit -v 16000000
            timeout 900 ${entry#*:} > "$GEN_OUT/${entry%%:*}"
        )
    done

    for script in "${generators[@]}"; do
        python3 $gen/$script
    done

    for file in "$GEN_OUT"/*; do
        name="$gen/out/$build/$(basename "$file")"
        if [[ "$check" != "--check" ]]; then
            echo "wrote   $name"
        elif [[ ! -f "$name" ]]; then
            echo "new     $name"
        elif cmp -s "$file" "$name"; then
            echo "ok      $name"
        else
            echo "STALE   $name"
            status=1
        fi
    done
done

python3 $gen/gen_builds.py --staging "$staging" --root "$target"
use_build "$latest"
outputs=(seedfinder/data website/lib/config/game-builds.ts config.schema.json website/lib/catalog/cave-vocab.ts)

if [[ "$check" != "--check" ]]; then
    python3 $gen/gen_schema.py
    python3 $gen/gen_cave_vocab.py
    printf 'wrote   %s\n' "${outputs[@]}"
    exit $status
fi

mkdir -p "$target/website/lib/catalog"
python3 $gen/gen_schema.py - > "$target/config.schema.json"
python3 $gen/gen_cave_vocab.py - > "$target/website/lib/catalog/cave-vocab.ts"
for name in "${outputs[@]}"; do
    if diff -r "$target/$name" "$name" > "$temp/diff"; then
        echo "ok      $name"
    else
        echo "STALE   $name"
        grep -E '^(Only in|diff )' "$temp/diff" | sed 's/^/          /' || true
        status=1
    fi
done

exit $status
