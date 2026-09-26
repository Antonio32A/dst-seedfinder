#!/usr/bin/env bash
# usage: run_worlds.sh [seeds-file] [jobs]
# Runs the worldsim emulator for every seed in seeds-file (default seeds.txt) that has no summary yet,
# reduces each world.json to worlds/<seed>.json and deletes the raw output.
set -uo pipefail

here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
work="$(cd "$here/../.." && pwd)/build/catalog"
worldsim="${WORLDSIM_DIR:?set WORLDSIM_DIR to the worldsim emulator}"
seeds="${1:-$here/seeds.txt}"
jobs="${2:-8}"
mkdir -p "$work/worlds" "$work/tmp"

one() {
    local here="$1" work="$2" worldsim="$3" seed="$4"
    local out="$work/tmp/$seed"
    if [[ -s "$work/worlds/$seed.json" ]]; then
        return 0
    fi

    (
        ulimit -v 16000000
        timeout 900 "$worldsim/run.sh" "$seed" "$out"
    ) > /dev/null 2>&1
    local status=$?

    if [[ -s "$out/world.json" ]]; then
        python3 "$here/summarize_world.py" "$out/world.json" "$work/worlds/$seed.json" emulator
        echo "seed $seed exit $status ok"
    else
        echo "seed $seed exit $status no-world"
        tail -5 "$out/log.txt" 2>/dev/null | sed "s/^/  $seed: /"
    fi
    rm -rf "$out"
}
export -f one

grep -E '^[0-9]+$' "$seeds" | xargs -P "$jobs" -I{} bash -c 'one "$0" "$1" "$2" "$3"' "$here" "$work" "$worldsim" {}
rmdir "$work/tmp" 2>/dev/null || true
