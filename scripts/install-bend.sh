#!/usr/bin/env bash
# usage: install-bend.sh [PREFIX]
# Installs the bend/ submodule as the bend CLI into PREFIX (default ~/.bend, the layout of the official installer).
# Needs bun (BUN overrides it); `bend update` would put the stock release back.
set -euo pipefail

root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
src="$root/bend"
prefix="${1:-$HOME/.bend}"
bun="${BUN:-bun}"

if [[ ! -f "$src/bend2/main.ts" ]]; then
    echo "install-bend.sh: the bend/ submodule is missing; run git submodule update --init" >&2
    exit 1
fi

mkdir -p "$prefix/bin" "$prefix/bend2" "$prefix/guide"
rm -rf "$prefix/bend2/effs"
cp -r "$src/bend2/base.bend" "$src/bend2/effs" "$prefix/bend2/"
cp "$src"/guide/*.md "$prefix/guide/"

trap 'rm -f "$prefix/bin/bend.new"' EXIT
"$bun" build --compile "$src/bend2/main.ts" --outfile "$prefix/bin/bend.new"
version="$(BEND_NO_TELEMETRY=1 "$prefix/bin/bend.new" version)"
mv "$prefix/bin/bend.new" "$prefix/bin/bend"
echo "installed $version into $prefix" >&2
