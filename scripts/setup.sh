#!/usr/bin/env bash
# usage: setup.sh
# Fetches what the generators need but the repo does not ship, into .scratch/ (gitignored): the game's Lua scripts
# (from the local install's data/databundles/scripts.zip; DST_GAME overrides the install path), Lua 5.1.5 and
# Boost 1.52 headers. Then builds scripts/harness/bin/lua-dst.
set -euo pipefail
root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
default_game="$HOME/.local/share/Steam/steamapps/common/Don't Starve Together"
game="${DST_GAME:-$default_game}"
ref="$root/.scratch/ref"
mkdir -p "$ref"
if [[ ! -f "$root/.scratch/game-scripts/worldgen_main.lua" ]]; then
  unzip -q -o "$game/data/databundles/scripts.zip" -d "$root/.scratch"
  rm -rf "$root/.scratch/game-scripts"
  mv "$root/.scratch/scripts" "$root/.scratch/game-scripts"
fi
if [[ ! -d "$ref/lua-5.1.5" ]]; then
  curl -fsSL https://www.lua.org/ftp/lua-5.1.5.tar.gz | tar -xz -C "$ref"
fi
if [[ ! -d "$ref/boost_1_52_0" ]]; then
  curl -fsSL https://archives.boost.io/release/1.52.0/source/boost_1_52_0.tar.gz | tar -xz -C "$ref"
fi
"$root/scripts/harness/build.sh"
