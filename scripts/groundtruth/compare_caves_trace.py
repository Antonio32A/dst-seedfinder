#!/usr/bin/env python3
"""Compares the caves stages of the trace binary with the probes of the real Linux cave worlds and names the first stage that differs.

usage: compare_caves_trace.py TRACE_BINARY [SEEDS] [--worlds DIR] [--jobs N] [--first-attempts] [--draws] [--engine-probes DIR]

Every attempt of every seed is one `TRACE_BINARY trace SEED --stage cavegen --platform linux [--draws POSITION]` run. The
first attempt starts from the seed's level table; attempt k > 1 starts at the position of the PCG32 stream at the real
attempt's `generate_begin` checkpoint (its third field, which counts the engine's draws too), so every attempt is checked
on its own. The records of the run (seedfinder/gen/cave_trace.bend) are compared with the world JSON's probes of that
attempt, stage by stage in execution order, and the first stage that differs is reported:

  begin        the attempt's start position against `generate_begin`
  commit       WorldGen_Commit's verdict against the `commit` probe
  tilemap, separate_islands, force_connectivity, before_mazes, land_done
               the FNV-1a 64 digest (width, height, then every tile as 16 bits) against the `tiles` probe of that label
  events       the sequence of engine calls (RunCA, GetPointsForSite after it, RunMaze, GetPointsForMetaMaze, ReserveSpace,
               GetPointsForSite of PopulateVoronoi) against the probes runca, points, runmaze, metamaze, reserve, points
  runca, ca_points, runmaze, metamaze, reserve, populate_points, disconnect
               the fields of each call: node id, arguments, point count and the FNV-1a 64 hash of the point list
  end          the attempt's verdict and the stream position after it against `generate_failed` / `generate_end`, and for the
               world its entity count against entity_counts (without the multiplayer_portal and spawnpoint_master the
               game adds after Generate)

What the real probes count. `draws_after` (runca, runmaze, metamaze) and `draws_before` (points) are the number of Lua-side
math.random() calls since math.randomseed: a call's own engine draws (RunCA, RunMaze, GetPointsForMetaMaze and the
shuffle inside GetPointsForSite, ReserveSpace) are not in them. The rng_checkpoints [name, lua draws, stream position] hold
both counters at the start and end of an attempt; the stream position also counts the engine's draws. The trace records
the stream position before and after every engine call, so the Lua draws between two calls are the gap between the first
call's `after` and the second's `before`.

--draws adds the draw-count checks and prints a table of them:
  gaps     for every two consecutive calls that both carry a Lua counter: (port stream gap minus the engine draws of the calls
           between them) against the difference of the real Lua counters; and for the last call of the attempt to the attempt's
           end (generate_failed / generate_end), which pins the engine draws of every call in between together with the Lua
           side's own draws
  engine   with --engine-probes DIR (the folders <seed>/engine_probe.jsonl of the engine capture: the real stream position at the
           start and stop of every RunCA, RunMaze and GetPointsForMetaMaze call of a whole world; the capture numbers the stream
           from 1, so its positions are the trace's plus one): the port's before/after of every such call against the real
           start/stop, call by call over all attempts of the seed (a capture of a world that was run several times
           is read as its first run)

SEEDS: `1-120` (default) or `1,5,9`. WORLDS: the world JSONs of scripts/groundtruth/run_worldgen.sh (default
build/groundtruth/data/worlds_caves).
"""
import argparse
import concurrent.futures
import json
import re
import statistics
import struct
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK64 = (1 << 64) - 1
STAGES = ["begin", "commit", "tilemap", "separate_islands", "force_connectivity", "events", "runca", "ca_points",
          "before_mazes", "runmaze", "metamaze", "reserve", "land_done", "disconnect", "populate_points", "end", "gaps", "engine"]
TILE_LABELS = ["tilemap", "separate_islands", "force_connectivity", "before_mazes", "land_done"]
KINDS = {"cattempt", "ccommit", "cdigest", "cca", "cpoints", "cmaze", "creserve", "cdisconnect", "cents", "creq", "cstatus", "cverdict"}
WORLD_ADDED = ("multiplayer_portal", "spawnpoint_master")
TOKEN = re.compile(r'(\w+)=("(?:\\.|[^"\\])*"|\S+)')


def seeds_of(text):
    out = []
    for part in text.split(","):
        first, _, last = part.partition("-")
        out += range(int(first), int(last or first) + 1)
    return out


def fnv_bytes(h, data):
    for b in data:
        h = ((h ^ b) * FNV_PRIME) & MASK64
    return h


def tiles_digest(width, height, tiles):
    h = fnv_bytes(FNV_OFFSET, struct.pack("<II", width, height))
    return fnv_bytes(h, struct.pack(f"<{len(tiles)}H", *tiles))


def rle_tiles(rle):
    tiles = []
    for run in rle.split(","):
        tile, _, count = run.partition("*")
        tiles += [int(tile)] * int(count)
    return tiles


def point_hash(triples):
    h = FNV_OFFSET
    for x, y, t in triples:
        h = fnv_bytes(h, struct.pack("<III", x & 0xFFFFFFFF, y & 0xFFFFFFFF, t & 0xFFFFFFFF))
    return h


def real_triples(text):
    return [tuple(int(v) for v in item.split(",")) for item in text.split(";")] if text else []


def float32_bits(value):
    return struct.unpack("<I", struct.pack("<f", float(value)))[0]


def unquote(text):
    return json.loads(text) if text.startswith('"') else text


def parse(stdout):
    records = defaultdict(list)
    for line in stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind in KINDS:
            record = {key: unquote(value) for key, value in TOKEN.findall(rest)}
            records[kind].append(record)
            records["ordered"].append((kind, record))
    return records


def run_trace(binary, seed, position):
    cmd = [binary, "trace", str(seed), "--stage", "cavegen", "--platform", "linux"]
    if position:
        cmd += ["--draws", str(position)]
    done = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
    return parse(done.stdout), done.stderr.strip()


def attempt_ends(world):
    return [c for c in world["rng_checkpoints"] if c[0] in ("generate_failed", "generate_end")]


def attempt_begins(world):
    return [c for c in world["rng_checkpoints"] if c[0] == "generate_begin"]


class Real:
    """The probes of one real attempt, in execution order."""

    def __init__(self, world, attempt):
        self.world = world
        self.attempt = attempt
        self.probes = [p for p in world["probes"] if p["attempt"] == attempt]
        self.tiles = {p["label"]: p for p in self.probes if p["kind"] == "tiles"}
        self.commit = next((p["ok"] for p in self.probes if p["kind"] == "commit"), None)
        self.disconnect = next((p["count"] for p in self.probes if p["kind"] == "disconnect"), None)
        self.calls = []
        before_mazes_seen = False
        for p in self.probes:
            if p["kind"] == "tiles" and p["label"] == "before_mazes":
                before_mazes_seen = True
            if p["kind"] == "runca":
                self.calls.append(("ca", p))
            elif p["kind"] == "points":
                self.calls.append(("populate_points" if before_mazes_seen else "ca_points", p))
            elif p["kind"] in ("runmaze", "metamaze", "reserve"):
                self.calls.append((p["kind"], p))

    def begin(self):
        return attempt_begins(self.world)[self.attempt - 1]

    def end(self):
        ends = attempt_ends(self.world)
        return ends[self.attempt - 1] if self.attempt <= len(ends) else None


def lua_counter(kind, probe):
    if kind in ("ca", "runmaze", "metamaze"):
        return probe["draws_after"]
    if kind in ("ca_points", "populate_points"):
        return probe["draws_before"]
    return None


def port_calls(records):
    """The engine calls of the run in execution order as (kind, record)."""
    kinds = {"cca": lambda r: "ca", "cmaze": lambda r: r["kind"], "creserve": lambda r: "reserve",
             "cpoints": lambda r: "ca_points" if r["kind"] == "ca" else "populate_points"}
    return [(kinds[name](record), record) for name, record in records["ordered"] if name in kinds]


def check_tiles(real, records, problems):
    digests = {r["at"]: r for r in records.get("cdigest", [])}
    for label in TILE_LABELS:
        probe = real.tiles.get(label)
        got = digests.get(label)
        if probe is None or got is None:
            if (probe is None) != (got is None):
                problems[label] = f"{'port has no' if got is None else 'real has no'} {label} map"
            continue
        want = tiles_digest(probe["w"], probe["h"], rle_tiles(probe["rle"]))
        if int(got["w"]) != probe["w"] or got["tiles"] != f"{want:016x}":
            problems[label] = f"tile digest {got['tiles']} vs real {want:016x}"


def check_call(kind, record, probe):
    if kind == "ca":
        pairs = [("id", record["id"], probe["id"]), ("iterations", int(record["iterations"]), probe["iterations"]),
                 ("seed_mode", int(record["mode"]), probe["seed_mode"]), ("num_random_points", int(record["points"]), probe["num_random_points"])]
    elif kind in ("ca_points", "populate_points"):
        want = real_triples(probe["pts"])
        pairs = [("id", record["id"], probe["id"]), ("area", int(record["area"]), probe["area"]), ("count", int(record["count"]), probe["count"]),
                 ("hash", record["hash"], f"{point_hash(want):016x}")]
    elif kind in ("runmaze", "metamaze"):
        want = real_triples(probe["pts"])
        pairs = [("nodes", record["nodes"], ";".join(probe["nodes"])), ("count", int(record["count"]), probe["count"]),
                 ("hash", record["hash"], f"{point_hash([(x, y, t) for x, y, t in want]):016x}")]
    else:
        ok = record["ok"] == "1"
        pairs = [("node", record["node"], probe["id"]), ("size", record["size"], f"{float32_bits(probe['size']):08x}"),
                 ("start", int(record["start"]), probe["start_mask"]), ("fill", int(record["fill"]), probe["fill_mask"]),
                 ("pos", int(record["pos"]), probe["position"]), ("area", int(record["n"]), probe["area"]),
                 ("ok", ok, probe["x"] is not None)]
        if ok and probe["x"] is not None:
            pairs += [("x", int(record["x"]), probe["x"]), ("y", int(record["y"]), probe["y"])]
    return [f"{name} {got} vs real {want}" for name, got, want in pairs if got != want]


STAGE_OF_KIND = {"ca": "runca", "ca_points": "ca_points", "runmaze": "runmaze", "metamaze": "metamaze", "reserve": "reserve",
                 "populate_points": "populate_points"}


def check_calls(real, records, problems):
    port = port_calls(records)
    if [k for k, _ in port] != [k for k, _ in real.calls]:
        for i in range(max(len(port), len(real.calls))):
            got = port[i][0] if i < len(port) else "-"
            want = real.calls[i][0] if i < len(real.calls) else "-"
            if got != want:
                problems["events"] = f"call {i}: port {got}, real {want} ({len(port)} vs {len(real.calls)} calls)"
                break
        return port
    for i, ((kind, record), (_, probe)) in enumerate(zip(port, real.calls)):
        mismatches = check_call(kind, record, probe)
        stage = STAGE_OF_KIND[kind]
        if mismatches and stage not in problems:
            problems[stage] = f"call {i}: " + "; ".join(mismatches)
    return port


def check_disconnect(real, records, problems):
    got = records.get("cdisconnect", [])
    if real.disconnect is None:
        if got:
            problems["disconnect"] = "port ran DetectDisconnect, real did not"
    elif not got:
        problems["disconnect"] = "port has no DetectDisconnect"
    elif int(got[0]["count"]) != real.disconnect:
        problems["disconnect"] = f"count {got[0]['count']} vs real {real.disconnect}"


def failure_consistent(real, result):
    if result == "commit":
        return real.commit is False
    if result == "areas":
        return "tilemap" in real.tiles and "separate_islands" not in real.tiles
    if result == "disconnect":
        return real.disconnect is not None and not any(k == "populate_points" for k, _ in real.calls)
    if result == "required":
        return any(k == "populate_points" for k, _ in real.calls)
    return True


def check_end(real, records, problems):
    world = real.world
    begin = real.begin()
    attempt_start = records.get("cattempt", [{}])
    if attempt_start and int(attempt_start[0].get("ctr", -1)) != begin[2] and real.attempt == 1:
        problems["begin"] = f"start {attempt_start[0].get('ctr')} vs real {begin[2]}"
    if real.commit is not None and (real.commit is False) != (not records.get("ccommit")):
        problems["commit"] = f"commit ok={real.commit} in the real game, port {'passed' if records.get('ccommit') else 'failed'}"
    verdicts = records.get("cverdict", [])
    if not verdicts:
        problems["end"] = "no verdict"
        return
    verdict = verdicts[-1]
    end = real.end()
    final = real.attempt == world["attempts"] and world["status"] == "ok"
    if final != (verdict["result"] == "world"):
        problems["end"] = f"port verdict {verdict['result']}, real {'world' if final else 'failed'}"
    elif not final and not failure_consistent(real, verdict["result"]):
        problems["end"] = f"port fails at {verdict['result']}, the real probes disagree"
    elif end is not None and int(verdict["ctr"]) != end[2]:
        problems["end"] = f"end position {verdict['ctr']} vs real {end[2]}"
    elif final:
        want = sum(count for prefab, count in world["entity_counts"].items() if prefab not in WORLD_ADDED)
        final_ents = next((r for r in records.get("cents", []) if r["at"] == "final"), None)
        if final_ents is None or int(final_ents["n"]) != want:
            problems["end"] = f"final entities {final_ents and final_ents['n']} vs real {want}"


class Draws:
    def __init__(self):
        self.per_kind = defaultdict(list)
        self.gaps = 0
        self.gap_mismatches = 0
        self.engine_checked = defaultdict(int)
        self.engine_mismatches = 0
        self.total_mismatches = []

    def merge(self, other):
        for kind, values in other.per_kind.items():
            self.per_kind[kind] += values
        self.gaps += other.gaps
        self.gap_mismatches += other.gap_mismatches
        for kind, count in other.engine_checked.items():
            self.engine_checked[kind] += count
        self.engine_mismatches += other.engine_mismatches
        self.total_mismatches += other.total_mismatches


def check_gaps(real, records, port, problems, draws):
    ends = real.end()
    known = [(i, lua_counter(kind, probe)) for i, (kind, probe) in enumerate(real.calls) if lua_counter(kind, probe) is not None]
    for kind, record in port:
        draws.per_kind[kind].append(int(record["after"]) - int(record["before"]))
    if len(port) != len(real.calls):
        return
    spans = [(int(record["before"]), int(record["after"])) for _, record in port]
    for (i, lua_i), (j, lua_j) in zip(known, known[1:]):
        between = sum(after - before for before, after in spans[i + 1:j])
        got = spans[j][0] - spans[i][1] - between
        draws.gaps += 1
        if got != lua_j - lua_i:
            draws.gap_mismatches += 1
            problems.setdefault("gaps", f"Lua draws between call {i} and {j}: {got} vs real {lua_j - lua_i}")
    if known and ends is not None and records.get("cverdict"):
        i, lua_i = known[-1]
        tail = sum(after - before for before, after in spans[i + 1:])
        got = int(records["cverdict"][-1]["ctr"]) - spans[i][1] - tail
        draws.gaps += 1
        if got != ends[1] - lua_i:
            draws.gap_mismatches += 1
            problems.setdefault("gaps", f"Lua draws from call {i} to the end: {got} vs real {ends[1] - lua_i}")


def engine_calls(port):
    return [(kind, record) for kind, record in port if kind in ("ca", "runmaze", "metamaze")]


def check_engine(seed, ported, engine_dir, draws):
    path = Path(engine_dir) / str(seed) / "engine_probe.jsonl"
    if not path.exists():
        return []
    real = [json.loads(line) for line in path.read_text().splitlines()]
    kinds = {"ca": "ca", "maze": "runmaze", "meta": "metamaze"}
    if len(ported) and len(real) > len(ported) and len(real) % len(ported) == 0:
        real = real[:len(ported)]
    problems = []
    if len(real) != len(ported):
        problems.append(f"engine capture has {len(real)} calls, the port made {len(ported)}")
    for index, (probe, (kind, record)) in enumerate(zip(real, ported)):
        draws.engine_checked[kind] += 1
        if kinds[probe["op"]] != kind or int(record["before"]) + 1 != probe["start"] or int(record["after"]) + 1 != probe["stop"]:
            draws.engine_mismatches += 1
            problems.append(f"call {index + 1} ({probe['op']}): port {int(record['before']) + 1}..{int(record['after']) + 1}, real {probe['start']}..{probe['stop']}")
    return problems


def check(binary, world, attempt, want_draws):
    real = Real(world, attempt)
    begin = real.begin()
    records, error = run_trace(binary, world["seed"], begin[2] if attempt > 1 else 0)
    problems = {}
    draws = Draws()
    if not records.get("cverdict"):
        return world["seed"], attempt, {"begin": f"the trace made no verdict {error[:200]}"}, draws, []
    check_end(real, records, problems)
    check_tiles(real, records, problems)
    port = check_calls(real, records, problems)
    check_disconnect(real, records, problems)
    if want_draws:
        check_gaps(real, records, port, problems, draws)
    return world["seed"], attempt, problems, draws, engine_calls(port)


def first_problem(problems):
    for stage in STAGES:
        if stage in problems:
            return stage, problems[stage]
    return None


def print_table(total, seeds_checked):
    print(f"\ndraw counts over {seeds_checked} seeds")
    print(f"{'call':18} {'calls':>7} {'engine draws min/median/max':>32}")
    for kind in ("ca", "ca_points", "runmaze", "metamaze", "reserve", "populate_points"):
        values = total.per_kind.get(kind, [])
        if values:
            print(f"{kind:18} {len(values):7} {min(values):>12}/{statistics.median(values):>8.0f}/{max(values):>8}")
    print(f"Lua-gap checks: {total.gaps}, mismatches {total.gap_mismatches}")
    engine = sum(total.engine_checked.values())
    breakdown = ", ".join(f"{k} {v}" for k, v in sorted(total.engine_checked.items()))
    print(f"engine-capture calls checked: {engine} ({breakdown}), mismatches {total.engine_mismatches}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary")
    ap.add_argument("seeds", nargs="?", default="1-120")
    ap.add_argument("--worlds", default=str(ROOT / "build/groundtruth/data/worlds_caves"))
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--first-attempts", action="store_true", help="only the first attempt of every seed")
    ap.add_argument("--draws", action="store_true", help="check and tabulate the random-draw counts")
    ap.add_argument("--engine-probes", help="folder of <seed>/engine_probe.jsonl captures (with --draws)")
    args = ap.parse_args()
    worlds = {}
    work = []
    for seed in seeds_of(args.seeds):
        worlds[seed] = json.loads((Path(args.worlds) / f"{seed}.json").read_text())
        for attempt in [1] if args.first_attempts else range(1, worlds[seed]["attempts"] + 1):
            work.append((worlds[seed], attempt))
    failed = 0
    total = Draws()
    ported = defaultdict(dict)
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(check, args.binary, world, attempt, args.draws) for world, attempt in work]
        for future in concurrent.futures.as_completed(futures):
            seed, attempt, problems, draws, calls = future.result()
            total.merge(draws)
            ported[seed][attempt] = calls
            found = first_problem(problems)
            failed += bool(found)
            print(f"seed {seed} attempt {attempt}: {f'first mismatch at {found[0]}: {found[1]}' if found else 'ok'}", flush=True)
    if args.draws and args.engine_probes:
        for seed, attempts in sorted(ported.items()):
            if len(attempts) != worlds[seed]["attempts"]:
                continue
            calls = [call for attempt in sorted(attempts) for call in attempts[attempt]]
            for message in check_engine(seed, calls, args.engine_probes, total):
                failed += 1
                print(f"seed {seed} engine capture: {message}")
    if args.draws:
        print_table(total, len(ported))
        failed += total.gap_mismatches > 0
    print(f"{len(work) - failed}/{len(work)} attempts match")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
