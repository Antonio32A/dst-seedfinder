#!/usr/bin/env python3
"""Set-piece frequencies over the harness level-table batch ($HARNESS_DIR/out/out_1M.txt, seeds 1..1000000).

Each line is `seed {"piece": count, ...}` (level.set_pieces after AddSetPeices; random_set_pieces are not in it).
usage: python3 level_table_stats.py BATCH.txt > build/level_table_stats.json
"""
import collections
import json
import os
import sys



def main():
    path = sys.argv[1]
    worlds = 0
    hist = collections.defaultdict(collections.Counter)
    for line in open(path):
        _, _, payload = line.partition(" ")
        worlds += 1
        for name, n in json.loads(payload).items():
            hist[name][n] += 1
    out = {"source": os.path.basename(path), "worlds": worlds, "pieces": {}}
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
