#!/usr/bin/env bash
# usage: build.sh [main | trace | ENTRY.bend [OUT]]   (OUT ending in .c emits C only)
#   (none), main  seedfinder/main.bend  -> .scratch/build/seedfinder        production binary, 16 GB cap, clang with
#                 -mllvm -inline-threshold=3000 (CCC_OVERRIDE_OPTIONS; same output, ~15-20% faster worldgen)
#   trace         seedfinder/trace.bend -> .scratch/build/seedfinder_trace  debug binary with every lane's trace stages, 32 GB
#                 cap; refuses to start unless `free -g` shows at least BUILD_MIN_FREE_GB (default 40) available
#   ENTRY [OUT]   any program (lane test binaries), 16 GB cap
#
# Builds a Bend program with the compiler's JavaScriptCore heap sized for a 4 GB machine. The bend CLI is a Bun
# executable; JSC sizes its GC heap from physical RAM, so on this 94 GB box codegen keeps several times its live set
# as garbage and exceeds `ulimit -v`. The emitted C is byte-identical at every setting.
# Env: BUILD_RAM (bytes, default 4000000000), BUILD_VLIMIT (KB, default 16000000, trace 32000000), BUILD_TIMEOUT (s,
# default 1800), BUILD_MIN_FREE_GB (trace only, default 40).
set -euo pipefail
root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
vlimit="${BUILD_VLIMIT:-16000000}"
clang_override="${CCC_OVERRIDE_OPTIONS:-}"
case "${1:-main}" in
  main)
    entry="$root/seedfinder/main.bend"
    out="$root/.scratch/build/seedfinder"
    clang_override="${CCC_OVERRIDE_OPTIONS:-# +-mllvm +-inline-threshold=3000}"
    ;;
  trace)
    entry="$root/seedfinder/trace.bend"
    out="$root/.scratch/build/seedfinder_trace"
    vlimit="${BUILD_VLIMIT:-32000000}"
    available=$(free -g | awk '/^Mem:/ {print $7}')
    if (( available < ${BUILD_MIN_FREE_GB:-40} )); then
      echo "build.sh: only ${available} GB available (free -g), the trace build needs ${BUILD_MIN_FREE_GB:-40} GB" >&2
      exit 1
    fi
    ;;
  *)
    entry="$1"
    out="${2:-$root/.scratch/build/seedfinder}"
    ;;
esac
mkdir -p "$(dirname "$out")"
start=$(date +%s)
(
  ulimit -v "$vlimit"
  [[ -n "$clang_override" ]] && export CCC_OVERRIDE_OPTIONS="$clang_override"
  BUN_JSC_forceRAMSize="${BUILD_RAM:-4000000000}" BEND_NO_TELEMETRY=1 \
    timeout "${BUILD_TIMEOUT:-1800}" bend "$entry" -o "$out"
)
echo "build.sh: $entry -> $out in $(( $(date +%s) - start )) s"
