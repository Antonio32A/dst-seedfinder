#!/usr/bin/env bash
# usage: setup.sh
# Fetches what the generators need but the repo does not ship, into build/deps/ (gitignored): the game build of the
# local install (DST_GAME overrides the install path) as build/deps/builds/<number>/ (its version.txt, its Lua scripts
# from data/databundles/scripts.zip and its Linux dedicated server binary), Lua 5.1.5 and Boost 1.52 headers. Then builds
# scripts/harness/bin/lua-dst. Run it once per install: each game build gets its own folder, and an existing one is kept.
# build/deps/game-scripts is the latest build's scripts (builds.json) when it is missing.
set -euo pipefail

root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
default_game="$HOME/.local/share/Steam/steamapps/common/Don't Starve Together"
game="${DST_GAME:-$default_game}"
deps="$root/build/deps"
server="bin64/dontstarve_dedicated_server_nullrenderer_x64"
mkdir -p "$deps/builds"

number="$(tr -d '[:space:]' < "$game/version.txt")"
[[ "$number" =~ ^[0-9]+$ ]] || { echo "setup.sh: $game/version.txt is not a build number: $number" >&2; exit 1; }
build="$deps/builds/$number"

if [[ ! -d "$build" ]]; then
    staging="$(mktemp -d "$deps/builds/.$number.XXXXXX")"
    chmod 755 "$staging"
    trap 'rm -rf "$staging"' EXIT
    unzip -q "$game/data/databundles/scripts.zip" -d "$staging"
    cp "$game/version.txt" "$staging/version.txt"
    mkdir -p "$staging/bin64"
    cp "$game/$server" "$staging/$server"
    mv -T "$staging" "$build"
    trap - EXIT
    echo "added $build"
fi

latest="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["latest"])' "$root/builds.json")"
if [[ ! -e "$deps/game-scripts" && -d "$deps/builds/$latest/scripts" ]]; then
    ln -s "builds/$latest/scripts" "$deps/game-scripts"
fi

if [[ ! -d "$deps/lua-5.1.5" ]]; then
    curl -fsSL https://www.lua.org/ftp/lua-5.1.5.tar.gz | tar -xz -C "$deps"
fi

if [[ ! -d "$deps/boost_1_52_0" ]]; then
    curl -fsSL https://archives.boost.io/release/1.52.0/source/boost_1_52_0.tar.gz | tar -xz -C "$deps"
fi

"$root/scripts/harness/build.sh"
