#!/usr/bin/env python3
"""Prints the `Pin{id, fingerprint}` rows of seedfinder/populate/pins.bend for the closure ids given as arguments
(a single id or FIRST-LAST), from the current sidecars. After a regeneration that renumbers closures, re-check each
hand port against its closure body in scripts/gen/out/closures.json, then paste the printed rows.

usage: python3 scripts/gen/closure_pins.py 68-77 79-81 83
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import ids  # noqa: E402
from gen_closures import fingerprint  # noqa: E402


def wanted(args):
    for arg in args:
        first, _, last = arg.partition("-")
        yield from range(int(first), int(last or first) + 1)


def main():
    by_id = {c["id"]: c for c in ids.closures()}
    for i in wanted(sys.argv[1:]):
        print(f"    Pin{{{i}, {fingerprint(by_id[i]['key'])}}},")


if __name__ == "__main__":
    main()
