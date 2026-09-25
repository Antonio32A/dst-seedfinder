#!/usr/bin/env bash
# usage: build.sh
# Builds bin/lua-dst: stock Lua 5.1.5 with DST's math library (lmathlib_dst.c: math.random on PCG32), the interpreter
# the data extractors in scripts/gen run under. LUA_SRC defaults to the tarball unpacked by scripts/setup.sh.
set -euo pipefail
here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
root="$(cd "$here/../.." && pwd)"
src="${LUA_SRC:-$root/.scratch/ref/lua-5.1.5/src}"
out="$here/bin"
mkdir -p "$out"
core=()
for f in "$src"/*.c; do
  case "$(basename "$f")" in
    lua.c|luac.c|print.c|lmathlib.c) ;;
    *) core+=("$f") ;;
  esac
done
gcc -O2 -DLUA_USE_POSIX -DLUA_USE_DLOPEN -I"$src" -o "$out/lua-dst" "$src/lua.c" "${core[@]}" "$here/lmathlib_dst.c" -lm -ldl -Wl,-E
echo "built $out/lua-dst" >&2
