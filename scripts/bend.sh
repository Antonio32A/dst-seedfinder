#!/usr/bin/env bash
# usage: bend.sh ARGS...   (same arguments as the bend CLI)
# Runs the pinned compiler, the bend/ submodule (Bend 2.0.29 with the WebAssembly target), on the Bun runtime inside
# the installed bend CLI (BUN_BE_BUN), whatever version that CLI is. Without a caller's `ulimit -v`, it runs under
# BEND_VLIMIT KB (16 GB), so a runaway check fails instead of taking the machine down.
set -euo pipefail

root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
main="$root/bend/bend2/main.ts"

if [[ ! -f "$main" ]]; then
    echo "bend.sh: the bend/ submodule is missing; run git submodule update --init" >&2
    exit 1
fi

if [[ "$(ulimit -v)" == unlimited ]]; then
    ulimit -v "${BEND_VLIMIT:-16000000}"
fi

BUN_BE_BUN=1 BEND_NO_TELEMETRY=1 exec bend "$main" "$@"
