#!/usr/bin/env python3
"""Set-piece frequencies over the harness level-table batch (default: ../harness/out/out_1M.txt, seeds 1..1000000).

Each line is `seed {"piece": count, ...}` (level.set_pieces after AddSetPeices; random_set_pieces are not in it).
usage: python3 level_table_stats.py [batch.txt] > build/level_table_stats.json
"""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
SCRATCH = os.path.join(os.path.dirname(os.path.dirname(HERE)), ".scratch")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SCRATCH, "harness/out/out_1M.txt")
    worlds = 0
    hist = collections.defaultdict(collections.Counter)
    for line in open(path):
        _, _, payload = line.partition(" ")
        worlds += 1
        for name, n in json.loads(payload).items():
            hist[name][n] += 1
    out = {"source": os.path.relpath(path, SCRATCH), "worlds": worlds, "pieces": {}}
    for name, counts in sorted(hist.items()):
        present = sum(counts.values())
        out["pieces"][name] = {
            "worlds": present,
            "share": round(present / worlds, 6),
            "max": max(counts),
            "count_histogram": {str(k): v for k, v in sorted(counts.items())},
        }
    json.dump(out, sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
