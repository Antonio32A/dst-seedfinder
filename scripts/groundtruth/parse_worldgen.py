#!/usr/bin/env python3
"""Extract the worlds dumped by the groundtruth-worldgen mod from DST server logs.

usage: parse_worldgen.py [-o OUTDIR] LOG [LOG ...]

Every record is printed as chunks "GTWORLD <kind>:<launch>:<n> <i>/<total> <payload>|".
Chunks are joined per key and decoded as JSON, and every world keeps the "shard" the mod recorded (forest or caves).
Writes into OUTDIR (default: build/groundtruth/data/worlds):
  <seed>.json                     the reference world for that seed (a fresh launch if there is one)
  <seed>.<mode>.<launch>-<n>.json every other world generated for the same seed
  index.json                      one summary entry per world
  info.json                       the run headers (seeds, level data, tracing mode) of every launch
It prints a summary, including whether repeated generations of the same seed are identical.
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

CHUNK = re.compile(r"GTWORLD (\S+) (\d+)/(\d+) (.*)\|\s*$")
RUN_FIELDS = {"launch", "run", "mode"}


def read_chunks(paths):
    chunks = defaultdict(dict)
    totals = {}
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                match = CHUNK.search(line)
                if match:
                    key, index, total, payload = match.groups()
                    chunks[key][int(index)] = payload
                    totals[key] = int(total)
    return chunks, totals


def assemble(chunks, totals):
    records, broken = [], []
    for key, parts in chunks.items():
        missing = [i for i in range(1, totals[key] + 1) if i not in parts]
        if missing:
            broken.append(f"{key}: missing chunks {missing[:10]} of {totals[key]}")
            continue
        text = "".join(parts[i] for i in range(1, totals[key] + 1))
        try:
            record = json.loads(text)
        except json.JSONDecodeError as error:
            broken.append(f"{key}: invalid JSON ({error})")
            continue
        kind, launch, number = key.split(":")
        records.append((kind, int(launch), int(number), record))
    records.sort(key=lambda r: (r[1], r[2]))
    return records, broken


def differing_fields(a, b):
    keys = (set(a) | set(b)) - RUN_FIELDS
    return sorted(k for k in keys if without_session(k, a.get(k)) != without_session(k, b.get(k)))


def without_session(key, value):
    if key == "meta" and isinstance(value, dict):
        return {k: v for k, v in value.items() if k != "session_identifier"}
    return value


def reference_first(worlds):
    return sorted(worlds, key=lambda w: (w["mode"] != "fresh", w["launch"], w["run"]))


def write_worlds(worlds_by_seed, outdir):
    index = []
    for seed, worlds in sorted(worlds_by_seed.items()):
        ordered = reference_first(worlds)
        for position, world in enumerate(ordered):
            name = f"{seed}.json" if position == 0 else f"{seed}.{world['mode']}.{world['launch']}-{world['run']}.json"
            (outdir / name).write_text(json.dumps(world, separators=(",", ":")))
            index.append({
                "file": name, "seed": seed, "shard": world.get("shard"), "mode": world["mode"], "launch": world["launch"], "run": world["run"],
                "status": world.get("status"), "attempts": world.get("attempts"),
                "width": world.get("width"), "height": world.get("height"),
                "entities": sum((world.get("entity_counts") or {}).values()),
            })
    (outdir / "index.json").write_text(json.dumps(index, indent=1))
    return index


def report_repeats(worlds_by_seed):
    for seed, worlds in sorted(worlds_by_seed.items()):
        ordered = reference_first(worlds)
        reference = ordered[0]
        for other in ordered[1:]:
            diff = differing_fields(reference, other)
            verdict = "identical" if not diff else "DIFFERENT in " + ", ".join(diff)
            print(f"seed {seed}: {reference['mode']} run {reference['launch']}-{reference['run']} vs "
                  f"{other['mode']} run {other['launch']}-{other['run']}: {verdict}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-o", "--outdir", type=Path, default=Path(__file__).resolve().parents[2] / "build" / "groundtruth" / "data" / "worlds")
    parser.add_argument("logs", nargs="+")
    args = parser.parse_args()

    records, broken = assemble(*read_chunks(args.logs))
    if not records:
        sys.exit("no complete GTWORLD records found; was the mod enabled on the shard that ran?")

    worlds_by_seed = defaultdict(list)
    infos = []
    for kind, _, _, record in records:
        if kind == "world":
            worlds_by_seed[record["seed"]].append(record)
        elif kind == "info":
            infos.append(record)
        elif kind == "error":
            print(f"error for seed {record.get('seed')}: {record.get('message')}")
        elif kind == "done":
            print(f"launch finished: {record}")

    args.outdir.mkdir(parents=True, exist_ok=True)
    (args.outdir / "info.json").write_text(json.dumps(infos, indent=1))
    index = write_worlds(worlds_by_seed, args.outdir)
    for entry in index:
        print(f"{entry['file']}: shard={entry['shard']} status={entry['status']} attempts={entry['attempts']} "
              f"size={entry['width']}x{entry['height']} entities={entry['entities']}")
    report_repeats(worlds_by_seed)
    for problem in broken:
        print("incomplete record:", problem)


if __name__ == "__main__":
    main()
