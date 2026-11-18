#!/usr/bin/env python3
"""Checks the caves search's early check on a seed range: every seed's early world against its world.

usage: compare_caves_early.py BINARY [FROM-TO] [--platform linux|windows] [--build BUILD] [--threads N]

Runs `BINARY world dump FROM TO --shard caves` twice, plainly and with `--early` (an attempt whose early world, the
attempt as it stands once its layouts and mazes are placed, passes the required prefab check is dumped as that early
world). Per seed both dumps must have the same outcome, and when they differ (the early check decided the world) the
early world must be the world's attempt: the same tiles and pillar links, and every prefab outside the build's late
set (scripts/gen/gen_gen.py cave_late, the generator of data/gen_tags.bend's cave_late_prefabs) with the same
instances. A world whose dumps are equal had its early check fail, which costs speed, not exactness.

FROM-TO: the seeds (default 1-400). BUILD: the game build (default the latest of builds.json). Exits 1 on any
mismatch.
"""
import argparse
import os
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare_common import ROOT, latest_build  # noqa: E402
from dstw import World  # noqa: E402


def late_prefabs(build):
    os.environ["GEN_BUILD"] = str(build)
    sys.path.insert(0, str(ROOT / "scripts/gen"))
    sys.path.insert(0, str(ROOT / "scripts/gen/lib"))
    import gen_gen  # noqa: E402
    return gen_gen.cave_late()


def dump_range(binary, first, last, args, folder, early):
    command = [binary, "+RTS", "--threads", str(args.threads), "-RTS", "world", "dump", str(first), str(last),
               "--shard", "caves", "--platform", args.platform, "--build", str(args.build), "-o", str(folder)]
    subprocess.run(command + (["--early"] if early else []), check=False, stdout=subprocess.DEVNULL)


def compare_world(full, early, late, report):
    if (full.width, full.height, full.tiles) != (early.width, early.height, early.tiles):
        report["errors"].append(f"seed {full.seed}: the early world is another attempt (tiles differ)")
        return
    if sorted(full.pillar_links) != sorted(early.pillar_links):
        report["errors"].append(f"seed {full.seed}: pillar links differ")
    for prefab in set(full.hundredths) | set(early.hundredths):
        if full.hundredths.get(prefab, []) == early.hundredths.get(prefab, []):
            continue
        report["differ"][prefab] += 1
        if prefab not in late:
            report["errors"].append(f"seed {full.seed}: {prefab} is not late but its instances differ")


def compare(full_dir, early_dir, seeds, late):
    report = {"errors": [], "differ": Counter(), "worlds": 0, "decided": 0, "no_world": 0}
    for seed in seeds:
        full_path, early_path = full_dir / f"{seed}.dstw", early_dir / f"{seed}.dstw"
        if not full_path.exists() or not early_path.exists():
            if full_path.exists() != early_path.exists():
                report["errors"].append(f"seed {seed}: only one binary run wrote a dump")
            continue
        full, early = World(full_path), World(early_path)
        if not full.status or not early.status:
            report["no_world"] += 1
            if full.status != early.status:
                report["errors"].append(f"seed {seed}: outcome differs (world {full.status}, early {early.status})")
            continue
        report["worlds"] += 1
        if full_path.read_bytes() == early_path.read_bytes():
            continue
        report["decided"] += 1
        compare_world(full, early, late, report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("binary")
    parser.add_argument("seeds", nargs="?", default="1-400")
    parser.add_argument("--platform", choices=("linux", "windows"), default="windows")
    parser.add_argument("--build", type=int, default=latest_build())
    parser.add_argument("--threads", type=int, default=4)
    args = parser.parse_args()
    first, _, last = args.seeds.partition("-")
    first, last = int(first), int(last or first)
    late = late_prefabs(args.build)
    with tempfile.TemporaryDirectory() as temp:
        full_dir, early_dir = Path(temp) / "full", Path(temp) / "early"
        full_dir.mkdir()
        early_dir.mkdir()
        dump_range(args.binary, first, last, args, full_dir, False)
        dump_range(args.binary, first, last, args, early_dir, True)
        report = compare(full_dir, early_dir, range(first, last + 1), late)
    print(f"build {args.build} {args.platform} seeds {first}-{last}: {report['worlds']} worlds, {report['no_world']} "
          f"without a world, {report['decided']} decided by the early check, "
          f"{report['worlds'] - report['decided']} whose early check failed")
    differ = report["differ"]
    print(f"prefabs that differ ({len(differ)}, all late): "
          + " ".join(f"{prefab}:{differ[prefab]}" for prefab in sorted(differ)))
    for error in report["errors"][:20]:
        print(f"MISMATCH {error}")
    print("early check: " + ("MISMATCH" if report["errors"] else "exact"))
    sys.exit(1 if report["errors"] else 0)


if __name__ == "__main__":
    main()
