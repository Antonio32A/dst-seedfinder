#!/usr/bin/env python3
"""Compares the seedfinder's caves world dumps with the real Linux cave worlds, section by section (the SETP section is
the seedfinder's own: the game's savedata does not record where layouts and mazes went).

usage: compare_caves_world.py BINARY [SEEDS] [--worlds DIR] [--jobs N] [--no-attempts]

Every seed is one `BINARY -- world dump SEED --shard caves --platform linux -o TMP.dstw`, compared with the world JSON
of scripts/groundtruth/run_worldgen.sh converted by world_dump.py (the same code path the forest's dumps use). A seed
that differs reports its first differing section and, inside it, the first differing tile, prefab or pillar link; and
every seed reports the attempts the seedfinder needed (`gen SEED --shard caves`) next to the real world's.

SEEDS: `1-120` (default) or `1,5,9`. WORLDS: the world JSONs (default build/groundtruth/data/worlds_caves).
"""
import argparse
import concurrent.futures
import json
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from world_dump import dump_of  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
HEADER_BYTES = 36


def seeds_of(text):
    out = []
    for part in text.split(","):
        first, _, last = part.partition("-")
        out += range(int(first), int(last or first) + 1)
    return out


def sections_of(raw):
    found = {}
    offset = HEADER_BYTES
    while offset + 8 <= len(raw):
        tag = raw[offset:offset + 4].decode("ascii")
        length = struct.unpack_from("<I", raw, offset + 4)[0]
        found[tag] = raw[offset + 8:offset + 8 + length]
        offset += 8 + length
    return found


def words(payload):
    return struct.unpack(f"<{len(payload) // 4}I", payload)


def first_difference(tag, ours, real):
    if tag == "TILE":
        a, b = struct.unpack(f"<{len(ours) // 2}H", ours), struct.unpack(f"<{len(real) // 2}H", real)
        index = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
        return f"first differing tile {index} (ours {a[index] if index < len(a) else None}, real {b[index] if index < len(b) else None})"
    if tag == "PILL":
        return f"pillar links ours {words(ours)} real {words(real)}"
    a, b = words(ours), words(real)
    index = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    return f"first differing word {index} of {len(a)} (ours) vs {len(b)} (real)"


def compare_sections(ours, real):
    if ours[:HEADER_BYTES] != real[:HEADER_BYTES]:
        return [f"header differs: ours {words(ours[:HEADER_BYTES])} real {words(real[:HEADER_BYTES])}"]
    a, b = sections_of(ours), sections_of(real)
    a.pop("SETP", None)
    problems = []
    for tag in sorted(set(a) | set(b)):
        if a.get(tag) != b.get(tag):
            problems.append(f"{tag}: " + ("missing in ours" if tag not in a else "missing in real" if tag not in b
                                          else first_difference(tag, a[tag], b[tag])))
    return problems


def prefab_counts(raw):
    payload = sections_of(raw).get("ENTS", b"")
    counts, offset = {}, 4
    for _ in range(struct.unpack_from("<I", payload, 0)[0] if payload else 0):
        length = struct.unpack_from("<I", payload, offset)[0]
        name = payload[offset + 4:offset + 4 + length].decode()
        offset += 4 + length + (-length % 4)
        count = struct.unpack_from("<I", payload, offset)[0]
        counts[name] = count
        offset += 4 + 8 * count
    return counts


def entity_problems(ours, real):
    a, b = prefab_counts(ours), prefab_counts(real)
    return [f"{name}: ours {a.get(name, 0)} real {b.get(name, 0)}" for name in sorted(set(a) | set(b)) if a.get(name) != b.get(name)][:8]


def attempts_of(binary, seed):
    out = subprocess.run([binary, "--threads", "2", "--", "gen", str(seed), "--shard", "caves", "--platform", "linux"],
                         capture_output=True, text=True, timeout=3600).stdout
    found = re.search(r"\ba=(\d+)", out)
    return int(found.group(1)) if found else None


def check(binary, world_path, with_attempts):
    world = json.loads(Path(world_path).read_text())
    seed = world["seed"]
    real = dump_of(world, "linux")
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / f"{seed}.dstw"
        run = subprocess.run([binary, "--threads", "2", "--", "world", "dump", str(seed), "--shard", "caves", "--platform", "linux",
                              "-o", str(target)], capture_output=True, text=True, timeout=3600)
        if not target.exists():
            return seed, [f"no dump ({run.stdout.strip() or run.stderr.strip()[:200]})"], None
        ours = target.read_bytes()
    problems = compare_sections(ours, real)
    if problems and "ENTS" in "".join(problems):
        problems += entity_problems(ours, real)
    attempts = f"attempts ours {attempts_of(binary, seed)} real {world.get('attempts')}" if with_attempts else None
    return seed, problems, attempts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary")
    ap.add_argument("seeds", nargs="?", default="1-120")
    ap.add_argument("--worlds", default=str(ROOT / "build/groundtruth/data/worlds_caves"))
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--no-attempts", action="store_true", help="skip the `gen` run that counts the attempts")
    args = ap.parse_args()
    paths = [Path(args.worlds) / f"{seed}.json" for seed in seeds_of(args.seeds)]
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(check, args.binary, path, not args.no_attempts) for path in paths]
        for future in concurrent.futures.as_completed(futures):
            seed, problems, attempts = future.result()
            failed += bool(problems)
            suffix = f" ({attempts})" if attempts else ""
            print(f"seed {seed}: {'; '.join(problems) if problems else 'ok'}{suffix}", flush=True)
    print(f"{len(paths) - failed}/{len(paths)} worlds match")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
