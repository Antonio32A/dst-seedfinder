#!/usr/bin/env bash
# usage: build.sh [main | trace | wasm | ENTRY.bend [OUT]]   (OUT ending in .c emits C only, .wasm WebAssembly)
#   (none), main  seedfinder/main.bend  -> build/seedfinder
#   trace         seedfinder/trace.bend -> build/seedfinder_trace, the debug binary with the trace stages (needs
#                 BUILD_MIN_FREE_GB of free RAM)
#   wasm          seedfinder/main.bend  -> build/wasm/seedfinder.{wasm,mjs} (emcc on PATH, or EMCC)
#   ENTRY [OUT]   any program
# The compiler's JavaScriptCore heap is capped (BUILD_RAM) because JSC sizes it from physical RAM, and on a big machine
# the build then outgrows its `ulimit -v` (BUILD_VLIMIT). BUILD_TIMEOUT bounds the build.
set -euo pipefail

root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
vlimit="${BUILD_VLIMIT:-16000000}"
clang_override="${CCC_OVERRIDE_OPTIONS:-}"

case "${1:-main}" in
main)
    entry="$root/seedfinder/main.bend"
    out="$root/build/seedfinder"
    clang_override="${CCC_OVERRIDE_OPTIONS:-# +-mllvm +-inline-threshold=3000}"
    ;;
trace)
    entry="$root/seedfinder/trace.bend"
    out="$root/build/seedfinder_trace"
    vlimit="${BUILD_VLIMIT:-32000000}"
    available=$(free -g | awk '/^Mem:/ {print $7}')
    if (( available < ${BUILD_MIN_FREE_GB:-40} )); then
        echo "build.sh: only ${available} GB available (free -g), the trace build needs ${BUILD_MIN_FREE_GB:-40} GB" >&2
        exit 1
    fi
    ;;
wasm)
    entry="$root/seedfinder/main.bend"
    out="$root/build/wasm/seedfinder.wasm"
    ;;
*)
    entry="$1"
    out="${2:-$root/build/seedfinder}"
    ;;
esac

mkdir -p "$(dirname "$out")"
start=$(date +%s)
(
    ulimit -v "$vlimit"
    if [[ -n "$clang_override" ]]; then
        export CCC_OVERRIDE_OPTIONS="$clang_override"
    fi
    BUN_JSC_forceRAMSize="${BUILD_RAM:-4000000000}" \
        timeout "${BUILD_TIMEOUT:-1800}" "$root/scripts/bend.sh" "$entry" -o "$out"
)
echo "build.sh: $entry -> $out in $(( $(date +%s) - start )) s"
