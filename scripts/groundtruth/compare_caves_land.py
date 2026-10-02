#!/usr/bin/env python3
"""Compares the seedfinder's caves worldgen up to the tile map right before the mazes with the real Linux cave worlds.

usage: compare_caves_land.py BINARY [SEEDS] [--worlds DIR] [--jobs N] [--first-attempts] [--label LABEL]

Every attempt of every seed is one `BINARY -- gen SEED --shard caves --platform linux --dump 3` run. The first attempt
starts from the seed's level table; attempt k > 1 starts at the position of the PCG32 stream at the real attempt's
generate_begin (the third field of the `generate_begin` rng_checkpoints entry, which counts the engine's draws too), so
every attempt is checked on its own. The tile map of the run must equal the world JSON's tiles probe of that attempt
(`before_mazes` by default), and for the final attempt of a world its story graph must equal the topology: node ids,
node types, links and tags. The Labyrinth and Maze global tags of every attempt must equal the node lists of its
RunMaze and GetPointsForMetaMaze calls.

SEEDS: `1-120` (default) or `1,5,9`. WORLDS: the world JSONs of scripts/groundtruth/run_worldgen.sh (default
build/groundtruth/data/worlds_caves).
"""
import argparse
import concurrent.futures
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare_common import CAVE_WORLDS, attempts_of_seeds  # noqa: E402

POISON_BITS = {"ForceConnected": 2, "RoadPoison": 4, "ForceDisconnected": 8}


def start_positions(world):
    return [c[2] if len(c) > 2 else c[1] for c in world["rng_checkpoints"] if c[0] == "generate_begin"]


def run(binary, seed, position):
    cmd = [binary, "--threads", "2", "--", "gen", str(seed), "--shard", "caves", "--platform", "linux", "--dump", "3"]
    if position:
        cmd += ["--draws", str(position)]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=1800).stdout


def parse(stdout):
    found = {}
    for line in stdout.splitlines():
        if line.startswith("tiles "):
            found["tiles"] = dict(re.findall(r"(\w+)=(\S+)", line))
        elif line.startswith("{"):
            found["story"] = json.loads(line)
    return found


def tiles_probe(world, attempt, label):
    for probe in world["probes"]:
        if probe["kind"] == "tiles" and probe["attempt"] == attempt and probe["label"] == label:
            return probe
    return None


def story_problems(world, story):
    topology = world["topology"]
    ids = topology["ids"]
    names = [node[0] for node in story["nodes"]]
    if sorted(names) != sorted(ids):
        return [f"node ids differ ({len(names)} vs {len(ids)})"]
    real_links = sorted(tuple(sorted((ids[e["n1"] - 1], ids[e["n2"] - 1]))) for e in topology["edges"])
    links = sorted(tuple(sorted((names[a], names[b]))) for a, b in story["edges"])
    problems = [] if real_links == links else [f"links differ ({len(links)} vs {len(real_links)})"]
    by_name = {node[0]: node for node in story["nodes"]}
    for name, real in zip(ids, topology["nodes"]):
        node = by_name[name]
        bits = sum(bit for tag, bit in POISON_BITS.items() if tag in real.get("tags", []))
        if node[1] != real["type"] or (node[2] & 14) != bits or node[3] != real.get("tags", []):
            problems.append(f"node {name}: type {node[1]} tags {node[3]} vs {real['type']} {real.get('tags', [])}")
            break
    return problems


def globals_problems(world, attempt, story):
    groups = {}
    for tag, task, node in story["globals"]:
        groups.setdefault((tag, task), []).append(node)
    problems = []
    for tag, kind in (("Labyrinth", "runmaze"), ("Maze", "metamaze")):
        got = sorted(nodes for (name, _), nodes in groups.items() if name == tag)
        want = sorted(p["nodes"] for p in world["probes"] if p["kind"] == kind and p["attempt"] == attempt)
        if got != want:
            problems.append(f"{tag} global tags differ ({len(got)} tasks vs {len(want)} {kind} calls)")
    return problems


def check(binary, world, attempt, label):
    seed = world["seed"]
    position = start_positions(world)[attempt - 1] if attempt > 1 else 0
    found = parse(run(binary, seed, position))
    want = tiles_probe(world, attempt, label)
    if "tiles" not in found or want is None:
        return seed, attempt, ["no tiles record"]
    problems = [] if found["tiles"]["rle"] == want["rle"] else ["tiles differ"]
    if "story" in found:
        problems += globals_problems(world, attempt, found["story"])
        if attempt == world["attempts"] and world.get("topology"):
            problems += story_problems(world, found["story"])
    return seed, attempt, problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary")
    ap.add_argument("seeds", nargs="?", default="1-120")
    ap.add_argument("--worlds", default=str(CAVE_WORLDS))
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--first-attempts", action="store_true", help="only the first attempt of every seed")
    ap.add_argument("--label", default="before_mazes")
    args = ap.parse_args()
    work = attempts_of_seeds(args.seeds, args.worlds, args.first_attempts)
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(check, args.binary, world, attempt, args.label) for world, attempt in work]
        for future in concurrent.futures.as_completed(futures):
            seed, attempt, problems = future.result()
            failed += bool(problems)
            print(f"seed {seed} attempt {attempt}: {'; '.join(problems) if problems else 'ok'}", flush=True)
    print(f"{len(work) - failed}/{len(work)} attempts match")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
