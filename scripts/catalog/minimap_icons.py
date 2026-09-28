#!/usr/bin/env python3
"""Runs every game prefab's constructor and writes the minimap icon table to inputs/minimap_icons.json (README.md).

usage: python3 minimap_icons.py [--out FILE]
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LUA = os.path.join(ROOT, "scripts/harness/bin/lua-dst")
EXTRACTOR = os.path.join(HERE, "extract_minimap_icons.lua")
ICON_NAME = re.compile(r"^[\w.]+$")
MEMORY_LIMIT_KB = 16000000


def parse_icons(text):
    """prefab -> {"icon", "priority"?, "over_fog"?, "incomplete"?} from the extractor's JSON object."""
    table = json.loads(text)
    odd = sorted(prefab for prefab, row in table.items() if not ICON_NAME.match(row["icon"]))
    if odd:
        raise ValueError("odd icon names for %s" % ", ".join(odd))
    return table


def run_extractor():
    result = subprocess.run(
        ["bash", "-c", "ulimit -v %d; exec timeout 900 \"$0\" \"$1\"" % MEMORY_LIMIT_KB, LUA, EXTRACTOR],
        capture_output=True, text=True, check=True)
    return parse_icons(result.stdout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(HERE, "inputs/minimap_icons.json"))
    args = ap.parse_args()
    if not os.path.isdir(os.path.join(ROOT, "build/deps/game-scripts")):
        sys.exit("no game scripts: run scripts/setup.sh")
    table = run_extractor()
    with open(args.out, "w") as f:
        json.dump(table, f, indent=1, sort_keys=True)
        f.write("\n")
    print("%s: %d prefabs with a minimap icon" % (args.out, len(table)))


if __name__ == "__main__":
    main()
