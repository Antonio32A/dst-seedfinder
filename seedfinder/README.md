# seedfinder

The real deal. 
Searches all 2^32 seeds of a DST forest world for worlds matching a filter (see [docs/config.md](../docs/config.md)),
and cave worlds by their level table (`--shard caves`).

## Requirements

- Linux x86-64.
- Bend: the fork in the `bend/` submodule (`git submodule update --init`), installed with `scripts/install-bend.sh`
  (needs [Bun](https://bun.sh)).
- clang 18 or newer.
- 16 GB of RAM for the build (40 GB free for the trace build).
- Only for the WebAssembly build: [Emscripten](https://emscripten.org) 3.1.45 or newer (`emcc` on `PATH`, or `EMCC`)

Only to regenerate `seedfinder/data/` (it's committed, since it only changes every DST update):
- Don't Starve Together installed through Steam (`DST_GAME` overrides the install path), once per game build of
  `builds.json`.
- python3, clang, curl, tar, unzip.

## Building

```sh
scripts/build.sh                                   # -> build/seedfinder
scripts/build.sh wasm                              # -> build/wasm/seedfinder.{wasm,mjs}
scripts/build.sh wasm-single                       # single-threaded, for a Cloudflare Worker -> build/wasm-single/
scripts/build.sh trace                             # debug binary with the trace stages -> build/seedfinder_trace
scripts/bend.sh seedfinder/main.bend --check-only  # type-check only
scripts/proof.sh -j 3                              # the laws (LAWS.bend, laws/), run before committing
```

- Use `scripts/build.sh`, not a plain `scripts/bend.sh seedfinder/main.bend -o ...`, or the compiler eats all your RAM (yum!).
- If the build fails with "machine stack overflowed", retry it. Yes, this is shitty. No, I don't know what causes it.
- The website's build copies `build/wasm/`, so build wasm first.
- `wasm-single` runs on the caller's thread (no Web Workers, no SharedArrayBuffer) in growable memory: 102 to 105 MB a
  world with its 80 MB corpus (`BUILD_CORPUS_MB`; 76 is the least that dumps every tested world, though only the
  windows forest of seed 59233 needs over 36). Give it its precompiled `WebAssembly.Module` through the factory's `instantiateWasm`, and a fresh instance per run.

Keep in mind that these binaries may not be portable, so you may have to rebuild it on the system.

```sh
scripts/build.sh seedfinder/main.bend build/seedfinder.c
clang -std=c11 -O3 -mllvm -inline-threshold=3000 seedfinder.c -lpthread -lm -o seedfinder
```

## Running

Runtime options (`--threads`, see `+RTS --help -RTS`) go between `+RTS` and `-RTS` before the command.

```sh
build/seedfinder +RTS --threads 16 -RTS world find --limit 5 --time-limit 120 --config config.json
build/seedfinder +RTS --threads 16 -RTS world find --start-seed 123456 --limit 1 --json --config config.json
build/seedfinder world show 123456 --config config.json
build/seedfinder +RTS --threads 16 -RTS setpiece find 0 4294967295 MiscBoon:7
build/seedfinder setpiece show 123456
build/seedfinder +RTS --threads 16 -RTS world find --shard caves --limit 5 --config caves.json  # cave seeds by level table
build/seedfinder world show 123456 --shard caves                                                # the caves level table
build/seedfinder +RTS --threads 16 -RTS world odds 0 9999999 --config config.json               # how common each task and set piece is
build/seedfinder +RTS --threads 1 -RTS gen 123456 --platform windows
build/seedfinder +RTS --threads 1 -RTS gen 123456 --platform linux --shard caves --dump 3  # the caves up to the mazes
build/seedfinder +RTS --threads 1 -RTS gen 123456 --platform linux --shard caves           # the whole caves worldgen
build/seedfinder world dump 123456 --platform linux -o 123456.dstw
build/seedfinder world dump 123456 --platform linux --shard caves -o 123456.dstw
build/seedfinder +RTS --threads 16 -RTS world dump 0 999 --platform linux -o worlds  # worlds/<seed>.dstw, worlds must exist
build/seedfinder world dump 123456 --platform linux --build 757748 -o 123456.dstw  # another game build
```

`world find` flags on top of the ones in [docs/config.md](../docs/config.md):
- `--config F`: the search config (without one every seed matches).
- `--platform windows|linux`: overrides the config's `platform`.
- `--build NUMBER`: the game build the worlds are generated for, one of `builds.json`; overrides the config's `build`.
  Without a config it defaults to the latest build. Also on `world show`, `world odds`, `world eval`, `world dump`,
  `gen`, `setpiece` and the trace binary. Every registered build has both shards; a build without the caves shard
  would reject `--shard caves` (`build <n> does not support the caves shard yet`).
- `--shard forest|caves`: overrides the config's `shard` (default forest); also on `world show`, `world dump`, `gen` and
  `setpiece`. The caves shard has the level table (`world find`, `world show`, `setpiece find|show`) and its whole
  worldgen (`gen`, `world dump`, see below). A caves config's world sections (`counts`, `distances`, `tiles`, `bridges`, `routes`)
  are decided on caves worlds generated in memory, or with `--worlds` on caves dumps, and `world eval` reads a caves dump.
- `FROM [TO]`: scan a seed range instead of the whole space (can't be combined with `--start-seed`).
- `--worlds DIR`: decide seeds on world dumps (`DIR/<seed>.dstw`) instead of generating them. A `bridges` rule needs
  the dumps' topology (their `GRPH` section) and a `setpieces` rule or group with `placed` names their level plan (their
  `PLAN` section); a dump without the one it needs counts as missing.
- `--kk native|bend`: the layout engine and the Voronoi builds that follow each pass (native C in `native/`), `bend`
  is the slow reference port of both (also on `gen`).
- `--verbose-timings`: adds a `timings {json}` line to stderr with the time each option (world filter) takes
  ([docs/config.md](../docs/config.md) section 8). It slows the search down: only for finding out what makes one slow.

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

`world odds FROM [TO] [--config F] [--shard forest|caves] [--build NUMBER]` generates the level tables of the seeds `FROM..TO` and prints one
line, `odds {"seeds":N,"candidates":C,"tasks":{...},"setpieces":{...}}`: `seeds` is how many have a level table, `candidates` how
many of them are candidates of the config (all without one), and the two objects count the seeds that choose each task or
place each set piece at least once (names that no seed has are left out). The website sums the lines of its workers.

`world eval --config F --world DUMP.dstw [--build NUMBER] [--json] [--fast]` checks one config against one world dump.
Both read the format of [docs/world-dump.md](../docs/world-dump.md) (version 3, older dumps have to be regenerated), and
both reject a dump of another game build than the config's (`world dump is build X, the config is build Y`; a dump
whose build word is 0 is accepted).

`world dump SEED [TO] [--platform windows|linux] [--shard forest|caves] [--build NUMBER] [--kk native|bend] [--early] -o PATH`
generates worlds and writes their dumps, with the build in the header:
`PATH` is the dump of `SEED`, or with `TO` an existing folder that gets `PATH/<seed>.dstw` for every seed, ready for
`world find --worlds PATH`. It prints one line per seed (`dump seed=S platform=P outcome=world|gaveup|crashed ents=N
ms=T`). A seed whose world generation gave up gets the 24-byte gave-up dump, and a crashed one gets none (the exit
status is then 1). The platform defaults to windows, like `gen`. `--early` (caves, native KK) is for checking the caves
search's early check: an attempt whose early world passes the required prefab check is dumped as that early world (the
attempt once ConvertGround and DetectDisconnect are done, with the post steps but without PopulateVoronoi and the bunch
spawner); `scripts/groundtruth/compare_caves_early.py` compares those with the worlds.

- `--time-limit` stops the search, `--start-seed` with the printed `next_seed` continues it.
- Pass `+RTS --threads N -RTS` in a container, the runtime's default is the host's CPU count, not the quota.
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
A `gen --times` stage line names the stage it leaves. `gen 1 30 --shard caves --times` on one thread (245 ms per seed,
1.57 attempts) spends per attempt 48 ms in `kk1` (the caves' one KK pass and the Voronoi build after it), 26 ms in
`ground` (PopulateVoronoi), 22 ms in `post` (the post steps up to the required prefab check), 16 ms in `land` (the
custom tile pass), 13 ms in `tiles` (ConvertToTileMap and the site tiles), 12 ms in `mazed` (ConvertGround to
DetectDisconnect), 10 ms in `tiled` (the mazes), 8 ms in `start` (the story) and 1 ms in `commit`. A caves search
with an early check (docs/config.md section 8) decides most candidates after `mazed`, before `ground` and `post`.

`world find` on the caves presets of the website (the Ancient Guardian within 75 walked tiles, the Atrium Gateway at
spawn) decides about 15 to 17 seeds/s at `--threads 8` (about 20.5 at `--threads 16`) and 3.4 to 3.9 seeds/s at
`--threads 1`; the website's wasm build, one thread per worker, about 2.3 to 2.7 seeds/s.

## Regenerating the data

After a game update:

```sh
scripts/setup.sh              # per install: its game build into build/deps/builds/<build>/, Lua 5.1.5, Boost 1.52, lua-dst
scripts/gen/regen.sh          # rewrites seedfinder/data/, config.schema.json and the website's generated tables
scripts/gen/regen.sh --check  # fails if any generated file is stale
```

`builds.json` lists the game builds the finder supports; `regen.sh` generates every module once per build (sidecars
in `scripts/gen/out/<build>/`), keeps one copy per distinct content in `seedfinder/data/b<build>/` and writes a
dispatch module `seedfinder/data/<module>.bend` that picks the copy by the game build. Modules every build must share
(the blob codec, pow tables, enums, tile groups, ocean, constants and the `*_types.bend` modules) stay single, and
regen fails naming one that differs. Then rebuild and run the proofs. `DST_WINDOWS_EXE` can point at the Windows
server exe for an extra check. The prefab catalogs (`scripts/catalog/<build>/`) have their own regen, see
[scripts/catalog/README.md](../scripts/catalog/README.md).

## Dumping real worlds

`scripts/groundtruth/` generates worlds on the real dedicated server, to validate the port after a game update or to
feed `world find --worlds` / `world eval`:

```sh
ln -s "$PWD/scripts/groundtruth/groundtruth-worldgen" "<DST install>/mods/"  # once
scripts/groundtruth/run_worldgen.sh fresh 1-10  # one launch per seed -> build/groundtruth/<build>/data/worlds/<seed>.json
python3 scripts/groundtruth/world_dump.py --platform linux build/groundtruth/756039/data/worlds/1.json 1.dstw
python3 scripts/groundtruth/world_dump.py --platform linux --worlds build/groundtruth/756039/data/worlds build/groundtruth/756039/dstw
```

Every world is generated with events disabled, as the finder models them: the cluster template's
`worldgenoverride.lua` files set `specialevent` to `"none"` (the server log then prints `Overriding World Event to:
none`). The game build is the install's `version.txt` (`DST_GAME` picks the install), and every build has its own folder
`build/groundtruth/<build>/` (`data/worlds`, `data/worlds_caves`, `dstw`, `dstw_caves`, `windows_caves`, `logs`). The
scripts use the main checkout's `build/groundtruth`, also from a git worktree; `GT_ROOT` overrides it. The compare
scripts and `parse_worldgen.py` take `--build B` (default the latest of `builds.json`): it picks the build's folder and
is passed to the binary.

The third argument picks the shard: `scripts/groundtruth/run_worldgen.sh fresh 1-10 caves` generates the caves shard
(preset `DST_CAVE`) into `build/groundtruth/<build>/data/worlds_caves/`. The dump script reads the shard from the world JSON
and writes it into the `.dstw` header. Besides the tiles, entities and topology, a caves world JSON holds probes of
the caves-only engine calls (`runca` with the tiles around the site, `runmaze`, `metamaze` and `disconnect` records, and
the tiles right before the
mazes as the `before_mazes` tiles record).

`world_dump.py` writes every entity of the world, also those of prefabs outside the catalog, and the topology (the
`GRPH` section: the savedata topology's nodes and the links ApplyPoisonTag keeps, which the `bridges` rules measure).
For worlds generated by the seedfinder, `world dump` writes the same bytes.

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

## Adding a game build

1. `DST_GAME=<install> scripts/setup.sh`: extracts the install's scripts into `build/deps/builds/<build>/`.
2. Add the build to `builds.json` with `"website": false` (and the shards it supports).
3. `scripts/gen/regen.sh`: identical module copies are shared. When a module that must stay single differs, regen
   names it: split it into a per-build module and thread `+build: Builds.Build` to its callers. Closure ids are the
   first registered build's in every build (a variant that replaces one at the same source sites keeps its id, a new
   closure variant takes the next free id), so the hand ports of `populate/` keep their ids; a new or changed room
   count or layout area closure fails the pins law until it is ported and pinned (`populate/pins.bend` lists one row
   per variant). The finder models every build with events disabled, whatever its default event (constants.lua
   `WORLD_SPECIAL_EVENT`): the extractors apply specialevent `"none"` where `forest_map.Generate` does
   (`scripts/gen/lib/boot.lua`), so the event branches of the closures and layouts never run, and regen fails if a
   closure was evaluated with an event on. regen also fails when the build's caves level table differs from the latest
   build's, which the website uses for every build.
4. `scripts/groundtruth/run_worldgen.sh` with `DST_GAME` on the new install, into `build/groundtruth/<build>/`; then
   the compare scripts with `--build <build>`, and `world dump --build <build>` against its dumps.
   `scripts/groundtruth/compare_caves_early.py build/seedfinder 1-1500 --build <build>` (and `--platform linux`) checks
   the caves search's early check: every early world must be its seed's world with the same tiles, pillar links and
   instances of every prefab outside the generated late set (data/gen_tags.bend `cave_late_prefabs`, from the rooms'
   contents, map tags, bunches and post-populate proxies). A prefab it reports as not late but different is placed
   after ConvertGround by something the generator (`scripts/gen/gen_gen.py` `cave_late`) does not know yet.
5. `scripts/proof.sh -j 3`. When its worlds differ from the previous build's, add a golden law pinned to the build.
6. When the catalog changed, regenerate it with the catalog scripts' `--build <build>` (`scripts/catalog/README.md`)
   and point the registry's `catalog` at it.
7. Set `"website": true` once the website offers it, and move `latest` when the build goes public.

Code changes are needed only when the world generation logic changed: a data-driven feature or a generated flag.
