#!/usr/bin/env bash
# usage: run_worldgen.sh [loop|fresh] [seeds]
#   loop           : one offline dedicated server launch that generates every seed (first seed fresh, rest looped)
#   fresh (default): one launch per seed, so every world is a genuine fresh generation
#   seeds          : comma separated seeds or ranges, default 1-10
# Needs groundtruth-worldgen copied or symlinked into the game's mods/ folder. Logs go to build/groundtruth/logs/worldgen/,
# worlds to build/groundtruth/data/worlds/ (GT_WORLDS_DIR overrides).
set -euo pipefail

here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
work="$(cd "$here/../.." && pwd)/build/groundtruth"
mode="${1:-fresh}"
seeds="${2:-1-10}"
default_dst="$HOME/.local/share/Steam/steamapps/common/Don't Starve Together"
dst="${DST_GAME:-$default_dst}"
storage="$work/storage"
cluster_dir="$storage/DoNotStarveTogether/Cluster_GTW"
server_log="$cluster_dir/Master/server_log.txt"
logs="$work/logs/worldgen"
steam_runtime="${STEAM_RUNTIME_DIR:-$HOME/.local/share/Steam/ubuntu12_32/steam-runtime}"
runtime_libs="$steam_runtime/pinned_libs_64:$steam_runtime/usr/lib/x86_64-linux-gnu:$steam_runtime/lib/x86_64-linux-gnu"

if [[ ! -f "$dst/mods/groundtruth-worldgen/modworldgenmain.lua" ]]; then
    echo "copy $here/groundtruth-worldgen into \"$dst/mods/\" first" >&2
    exit 1
fi
mkdir -p "$logs"

expand_seeds() {
    local part
    for part in ${1//,/ }; do
        if [[ "$part" == *-* ]]; then seq "${part%-*}" "${part#*-}"; else echo "$part"; fi
    done
}

run_server() {
    local spec="$1" loop="$2"
    local run_log="$logs/run_${spec//,/_}_${loop}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$cluster_dir"
    cp -r "$here/cluster_template/." "$cluster_dir/"
    rm -rf "$cluster_dir/Master/save" "$server_log"
    cat > "$cluster_dir/Master/modoverrides.lua" <<EOF
return {
    ["groundtruth-worldgen"] = {
        enabled = true,
        configuration_options = { seeds = "$spec", loop = $loop, replay_first = $loop },
    },
}
EOF
    (cd "$dst/bin64" && LD_LIBRARY_PATH="$dst/bin64/lib64:$runtime_libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        exec ./dontstarve_dedicated_server_nullrenderer_x64 \
        -persistent_storage_root "$storage" -conf_dir DoNotStarveTogether \
        -cluster Cluster_GTW -shard Master -offline -skip_update_server_mods \
        -monitor_parent_process $$) > "$run_log.stdout.txt" 2>&1 &
    local server=$!
    local deadline=$((SECONDS + ${GT_TIMEOUT:-1800}))
    until grep -q "GTWORLD done:" "$server_log" 2>/dev/null; do
        if ! kill -0 "$server" 2>/dev/null || (( SECONDS > deadline )); then
            echo "server exited or timed out before the mod finished; see $run_log.stdout.txt" >&2
            break
        fi
        sleep 2
    done
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
    [[ -f "$server_log" ]] && cp "$server_log" "$run_log.server_log.txt"
    run_logs+=("$run_log.server_log.txt")
}
run_logs=()

case "$mode" in
    loop) run_server "$seeds" true ;;
    fresh) for seed in $(expand_seeds "$seeds"); do run_server "$seed" false; done ;;
    *) echo "usage: $0 [loop|fresh] [seeds]" >&2; exit 2 ;;
esac

if [[ -n "${GT_WORLDS_DIR:-}" ]]; then
    python3 "$here/parse_worldgen.py" -o "$GT_WORLDS_DIR" "${run_logs[@]}"
else
    python3 "$here/parse_worldgen.py" "$logs"/*server_log.txt
fi
