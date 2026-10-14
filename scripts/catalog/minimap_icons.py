#!/usr/bin/env python3
"""Runs every game prefab's constructor and writes the minimap icon table to <build>/inputs/minimap_icons.json
(README.md), for the game build given (the latest of builds.json by default).

usage: python3 minimap_icons.py [--build NUMBER] [--out FILE]
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

sys.path.insert(0, os.path.join(ROOT, "scripts/gen/lib"))
import registry  # noqa: E402


def scripts_dir(build):
    return os.path.join(ROOT, "build/deps/builds", str(build), "scripts")


def parse_icons(text):
    """The extractor's JSON as a prefab -> row table, refusing icon names that aren't file names."""
    table = json.loads(text)
    odd = sorted(prefab for prefab, row in table.items() if not ICON_NAME.match(row["icon"]))
    if odd:
        raise ValueError("odd icon names for %s" % ", ".join(odd))
    return table


def run_extractor(build):
    result = subprocess.run(
        ["bash", "-c", "ulimit -v %d; exec timeout 900 \"$0\" \"$@\"" % MEMORY_LIMIT_KB, LUA, EXTRACTOR,
         "--build", str(build)],
        capture_output=True, text=True, check=True)
    return parse_icons(result.stdout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", type=int, default=registry.latest(), help="the game build (default: the latest)")
    ap.add_argument("--out")
    args = ap.parse_args()
    args.out = args.out or os.path.join(HERE, str(args.build), "inputs/minimap_icons.json")
    if not os.path.isdir(scripts_dir(args.build)):
        sys.exit("no game scripts for build %d: run scripts/setup.sh with its install" % args.build)
    table = run_extractor(args.build)
    with open(args.out, "w") as f:
        json.dump(table, f, indent=1, sort_keys=True)
        f.write("\n")
    print("%s: %d prefabs with a minimap icon" % (args.out, len(table)))


if __name__ == "__main__":
    main()
