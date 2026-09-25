#!/usr/bin/env python3
"""Level-table statistics (tasks, prefab swaps, random set pieces) from the harness `world` mode.

Runs ../harness/harness.lua world FROM TO in parallel chunks (each under ulimit -v / timeout), caches the raw
lines in build/harness_world/, and prints the aggregate JSON on stdout.
usage: python3 level_world_stats.py [FROM] [TO] [JOBS] > build/level_world_stats.json
"""
import collections
import concurrent.futures
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
SCRATCH = os.path.join(os.path.dirname(os.path.dirname(HERE)), ".scratch")
HARNESS = os.path.join(SCRATCH, "harness")
CACHE = os.path.join(SCRATCH, "catalog/build/harness_world")


def run_chunk(lo, hi):
    out = os.path.join(CACHE, "%d_%d.txt" % (lo, hi))
    if os.path.exists(out) and sum(1 for _ in open(out)) == hi - lo + 1:
        return out
    cmd = "ulimit -v 16000000; exec timeout 900 ./bin/lua-dst harness.lua world %d %d" % (lo, hi)
    with open(out + ".tmp", "w") as f:
        subprocess.run(["bash", "-c", cmd], cwd=HARNESS, stdout=f, check=True)
    os.replace(out + ".tmp", out)
    return out


def aggregate(paths):
    worlds = 0
    tasks = collections.Counter()
    swaps = collections.defaultdict(collections.Counter)
    random_pieces = collections.defaultdict(collections.Counter)
    task_pieces = collections.defaultdict(collections.Counter)
    for path in paths:
        for line in open(path):
            _, _, payload = line.partition(" ")
            w = json.loads(payload)
            worlds += 1
            for cat, option in w["prefab_swaps"].items():
                swaps[cat][option] += 1
            per_world = collections.Counter()
            for t in w["tasks"]:
                tasks[t["task"]] += 1
                for piece in t["set_pieces"] + t["random_set_pieces"]:
                    task_pieces[piece][t["task"]] += 1
                per_world.update(t["random_set_pieces"])
            for piece, n in per_world.items():
                random_pieces[piece][n] += 1
    return {
        "worlds": worlds,
        "tasks": {t: round(n / worlds, 6) for t, n in sorted(tasks.items())},
        "prefab_swaps": {c: {o: round(n / worlds, 6) for o, n in sorted(v.items())} for c, v in sorted(swaps.items())},
        "random_set_pieces": {p: {"share": round(sum(h.values()) / worlds, 6), "max": max(h),
                                  "count_histogram": {str(k): v for k, v in sorted(h.items())}}
                              for p, h in sorted(random_pieces.items())},
        "set_piece_tasks": {p: {t: n for t, n in sorted(v.items())} for p, v in sorted(task_pieces.items())},
    }


def main():
    lo = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    hi = int(sys.argv[2]) if len(sys.argv) > 2 else 100000
    jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    os.makedirs(CACHE, exist_ok=True)
    step = (hi - lo + jobs) // jobs
    chunks = [(a, min(a + step - 1, hi)) for a in range(lo, hi + 1, step)]
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        paths = list(pool.map(lambda c: run_chunk(*c), chunks))
    result = aggregate(paths)
    result["seeds"] = [lo, hi]
    json.dump(result, sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
