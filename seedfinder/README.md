# seedfinder

The real deal. 
Searches all 2^32 seeds of a DST forest world for worlds matching a filter (see [docs/config.md](../docs/config.md)),
and cave worlds by their level table (`--shard caves`).

## Requirements

- Linux x86-64.
- Bend: the fork in the `bend/` submodule (`git submodule update --init`), installed with `scripts/install-bend.sh`
  (needs [Bun](https://bun.sh)).
- clang 14 or newer.
- 16 GB of RAM for the build (40 GB free for the trace build).
- Only for the WebAssembly build: [Emscripten](https://emscripten.org) 3.1.35 or newer (`emcc` on `PATH`, or `EMCC`).

Only to regenerate `seedfinder/data/` (it's committed, since it only changes every DST update):
- Don't Starve Together installed through Steam (`DST_GAME` overrides the install path).
- python3, clang, curl, tar, unzip.

## Building

```sh
scripts/build.sh                                   # -> build/seedfinder
scripts/build.sh wasm                              # -> build/wasm/seedfinder.{wasm,mjs}
scripts/build.sh trace                             # debug binary with the trace stages -> build/seedfinder_trace
scripts/bend.sh seedfinder/main.bend --check-only  # type-check only
scripts/proof.sh -j 3                              # the laws (LAWS.bend, laws/), run before committing
```

- Use `scripts/build.sh`, not a plain `scripts/bend.sh seedfinder/main.bend -o ...`, or the compiler eats all your RAM (yum!).
- If the build fails with "machine stack overflowed", retry it. Yes, this is shitty. No, I don't know what causes it.
- The website's build copies `build/wasm/`, so build wasm first.

A binary built on a new distro needs a recent glibc. To run it somewhere else, emit the C and compile it there:

```sh
scripts/build.sh seedfinder/main.bend build/seedfinder.c
clang -std=c11 -O3 -mllvm -inline-threshold=3000 seedfinder.c -lpthread -lm -o seedfinder
```

## Running

Runtime options (`--threads`, see `--bend-help`) go before `--`, the seedfinder's arguments after it.

```sh
build/seedfinder --threads 16 -- world find --limit 5 --time-limit 120 --config config.json
build/seedfinder --threads 16 -- world find --start-seed 123456 --limit 1 --json --config config.json
build/seedfinder -- world show 123456 --config config.json
build/seedfinder --threads 16 -- setpiece find 0 4294967295 MiscBoon:7
build/seedfinder -- setpiece show 123456
build/seedfinder --threads 16 -- world find --shard caves --limit 5 --config caves.json  # cave seeds by level table
build/seedfinder -- world show 123456 --shard caves                                     # the caves level table
build/seedfinder --threads 1 -- gen 123456 --platform windows
build/seedfinder --threads 1 -- gen 123456 --platform linux --shard caves --dump 3  # the caves up to the mazes
build/seedfinder --threads 1 -- gen 123456 --platform linux --shard caves            # the whole caves worldgen
build/seedfinder -- world dump 123456 --platform linux -o 123456.dstw
build/seedfinder -- world dump 123456 --platform linux --shard caves -o 123456.dstw
build/seedfinder --threads 16 -- world dump 0 999 --platform linux -o worlds  # worlds/<seed>.dstw, worlds must exist
```

`world find` flags on top of the ones in [docs/config.md](../docs/config.md):
- `--config F`: the search config (without one every seed matches).
- `--platform windows|linux`: overrides the config's `platform`.
- `--shard forest|caves`: overrides the config's `shard` (default forest); also on `world show`, `world dump`, `gen` and
  `setpiece`. The caves shard has the level table (`world find`, `world show`, `setpiece find|show`) and its whole
  worldgen (`gen`, `world dump`, see below). A caves config's world sections (`counts`, `distances`, `tiles`, `routes`)
  are decided on caves worlds generated in memory, or with `--worlds` on caves dumps, and `world eval` reads a caves dump.
- `FROM [TO]`: scan a seed range instead of the whole space (can't be combined with `--start-seed`).
- `--worlds DIR`: decide seeds on world dumps (`DIR/<seed>.dstw`) instead of generating them.
- `--kk native|bend`: the layout engine, `bend` is the slow reference port (also on `gen`).

`gen --shard caves` runs the whole caves worldgen (up to 5 attempts, retried like the forest's: CheckForValidCells, the
site areas, DetectDisconnect and the required prefabs fail an attempt) and prints the forest's line with `shard=caves`.
An attempt whose custom tile pass runs RunCA on a site without a polygon crashes the real server (a segfault, e.g. seed
3026), so that seed has no world: `outcome=crashed`.
With `--dump BITS` it stops after the first attempt's custom tile pass (stage `tiled`: story, layout, Commit, tiles,
SeparateIslands, ForceConnectivity and the RunCA rooms) and prints `gen seed=S ... a=A outcome=tiled ctr=C nodes=N w=W
tiles=H`; `BITS` adds the attempt's tile map (bit 1, a `tiles` record, `tile*count` runs) and story graph (bit 2, one
JSON line), bit 4 the entities of the Labyrinth and Maze passes with the stream counters around every maze engine call
(one JSON line) and bit 8 the tile map after them (a `tiles` record); `--draws N` starts the attempt N draws into the seed's
stream (the position of a real attempt's `generate_begin`) to check the attempts after the first.

`world eval --config F --world DUMP.dstw [--json] [--fast]` checks one config against one world dump. Both read the
format of [docs/world-dump.md](../docs/world-dump.md) (version 3, older dumps have to be regenerated; only forest dumps can be read).

`world dump SEED [TO] [--platform windows|linux] [--shard forest|caves] [--kk native|bend] -o PATH` generates worlds and writes their dumps:
`PATH` is the dump of `SEED`, or with `TO` an existing folder that gets `PATH/<seed>.dstw` for every seed, ready for
`world find --worlds PATH`. It prints one line per seed (`dump seed=S platform=P outcome=world|gaveup|crashed ents=N
ms=T`). A seed whose world generation gave up gets the 24-byte gave-up dump, and a crashed one gets none (the exit
status is then 1). The platform defaults to windows, like `gen`.

- `--time-limit` stops the search, `--start-seed` with the printed `next_seed` continues it.
- Pass `--threads` in a container, the runtime's default is the host's CPU count, not the quota.
- Don't run it under a low `ulimit -v`, each thread reserves a lot of virtual memory.

## Throughput

Measured with the production binary, `--threads 8`, on a 24-core machine that was shared with other jobs (load average
about 6), so read them as ratios. Seeds 1 to 200, `--platform linux`:

| | forest | caves |
|---|---|---|
| `world dump 1 200`, wall time | 48.4 s (4.1 worlds/s) | 31.0 s (6.5 worlds/s) |
| ms per seed in the dump lines (median / mean) | 3389 / 3650 | 2425 / 2333 |
| outcomes | 199 worlds, 1 gave up | 196 worlds, 4 gave up |
| `world find` with a filter that never matches | 83 M seeds/s (level search) | 21 M seeds/s (level table search) |

The caves' ms include the retried attempts (331 attempts for the 240 seeds of the real dumps, 1.4 per world).
A `gen --times` stage line names the stage it leaves. `gen 1 30 --shard caves --times` on one thread (230 ms per seed,
1.27 attempts) spends per attempt 53 ms in `kk1` (the caves' one KK pass and the Voronoi build after it), 37 ms in
`mazed` (the land population), 27 ms in `post` (the post steps up to the required prefab check), 20 ms in `tiles`
(ConvertToTileMap and the site tiles), 16 ms in `land` (the custom tile pass), 12 ms in `tiled` (the mazes) and 8 ms
each in `start` (the story) and `commit`.

`world find` on the caves presets of the website (the Ancient Guardian within 75 walked tiles, the Atrium Gateway at
spawn) decides about 11 seeds/s at `--threads 8` and 3.4 to 3.9 seeds/s at `--threads 1`; the website's wasm build, one
thread per worker, about 2.3 to 2.7 seeds/s.

## Regenerating the data

After a game update:

```sh
scripts/setup.sh              # once: game scripts, Lua 5.1.5 and Boost 1.52 into build/deps/, builds lua-dst
scripts/gen/regen.sh          # rewrites seedfinder/data/*.bend and config.schema.json
scripts/gen/regen.sh --check  # fails if any generated file is stale
```

Then rebuild and run the proofs. `DST_WINDOWS_EXE` can point at the Windows server exe for an extra check. The
prefab catalog (`scripts/catalog/catalog.json`) has its own regen, see
[scripts/catalog/README.md](../scripts/catalog/README.md).

## Dumping real worlds

`scripts/groundtruth/` generates worlds on the real dedicated server, to validate the port after a game update or to
feed `world find --worlds` / `world eval`:

```sh
ln -s "$PWD/scripts/groundtruth/groundtruth-worldgen" "<DST install>/mods/"  # once
scripts/groundtruth/run_worldgen.sh fresh 1-10  # one launch per seed -> build/groundtruth/data/worlds/<seed>.json
python3 scripts/groundtruth/world_dump.py --platform linux build/groundtruth/data/worlds/1.json 1.dstw
python3 scripts/groundtruth/world_dump.py --platform linux --worlds build/groundtruth/data/worlds build/groundtruth/dstw
```

The third argument picks the shard: `scripts/groundtruth/run_worldgen.sh fresh 1-10 caves` generates the caves shard
(preset `DST_CAVE`) into `build/groundtruth/data/worlds_caves/`. The dump script reads the shard from the world JSON
and writes it into the `.dstw` header. Besides the tiles, entities and topology, a caves world JSON holds probes of
the caves-only engine calls (`runca` with the tiles around the site, `runmaze`, `metamaze` and `disconnect` records, and
the tiles right before the
mazes as the `before_mazes` tiles record).

`world_dump.py` writes every entity of the world, also those of prefabs outside the catalog. For worlds generated by
the seedfinder, `world dump` writes the same bytes.

The `generate_begin`, `generate_failed` and `generate_end` checkpoints of a world JSON carry the position of the PCG32
stream after the Lua draw counter, engine draws included. `scripts/groundtruth/compare_caves_land.py build/seedfinder`
checks the seedfinder's caves worldgen against the caves worlds: every attempt's tile map right before the mazes (each
attempt starting at its real stream position), the story graph of the final attempt and the global tags of every
attempt. `scripts/groundtruth/compare_caves_trace.py build/seedfinder_trace` runs the trace binary's `cavegen` stage
(`build/seedfinder_trace trace SEED --stage cavegen --platform linux [--draws POSITION]`, one attempt: the story, Voronoi
and tile stages, every RunCA, RunMaze, GetPointsForMetaMaze, ReserveSpace and GetPointsForSite, DetectDisconnect, the
entity counts of the post steps and the required prefab table) for every attempt and names the first stage that differs
from the real probes; with `--draws` it also checks the random-draw counts of every engine call. `scripts/groundtruth/compare_caves_world.py build/seedfinder` compares whole cave world dumps byte for byte with
the converted real ones and reports the attempts each needed.
`--platform windows --worlds DIR` compares against Windows server dumps instead: the Windows caves differ from the Linux ones only
by the VC9 `random_shuffle` over `rand()` with RAND_MAX 0x7fff and MSVCR90's `powf` in the growing-tree maze.
