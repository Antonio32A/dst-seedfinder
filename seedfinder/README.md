# DST seed finder

Searches the 2^32 seeds of a Don't Starve Together forest for worlds matching filters. The level table (what the
worldgen Lua decides before the map generator runs) is predicted directly; everything else comes from a port of the
whole forest worldgen (story, Kamada-Kawai layout, Voronoi, tiles, land and ocean population) that generates each
candidate world in memory, bit-identical to the game on Windows and Linux hosts:

- `setpiece`: the set pieces AddSetPeices rolls (boons, trap, point of interest, protected resource,
  plus the fixed task set pieces), filtered from the command line.
- `world`: the whole level table: prefab swaps, the chosen tasks, and which set pieces
  (`set_pieces` and `random_set_pieces`) `Level:ChooseSetPieces` puts in each task, plus the generated world's
  entities and tiles (counts, distances, tile distances, routes), filtered with a JSON config.

Written in Bend (module folders in this directory, see "Code layout"), validated against the real game (build 747465). Only the default world
settings are supported (forest, preset SURVIVAL_TOGETHER, every world generation option at `default`).

## Build and run

```sh
scripts/build.sh                               # bend main.bend -o .scratch/build/seedfinder; needs clang 14+
.scratch/build/seedfinder --threads 22 -- setpiece find [FROM] [TO] [filters...]
.scratch/build/seedfinder setpiece show FROM [TO]
.scratch/build/seedfinder --threads 22 -- world find [--start-seed S] [--limit N] [--time-limit T] [--json] [--config filters.json] [--platform windows|linux] [--kk native|bend]
.scratch/build/seedfinder world show FROM [TO] [--config filters.json]
.scratch/build/seedfinder --threads 16 -- world find FROM TO --config filters.json --worlds DUMPS [--json] [--limit N]
.scratch/build/seedfinder --threads 16 -- world eval --config filters.json --world DUMP.dstw [--fast]
.scratch/build/seedfinder --threads 1 gen SEED [TO] [--platform windows|linux] [--times] [--kk native|bend]
scripts/build.sh trace                         # debug binary: bend trace.bend -o .scratch/build/seedfinder_trace
.scratch/build/seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--input FILE]
```

`scripts/build.sh` runs `bend main.bend -o` with the compiler's JavaScriptCore heap sized for a 4 GB machine
(`BUN_JSC_forceRAMSize`): a plain `bend main.bend -o` on a large-memory machine lets the compiler's garbage grow
past 32 GB, while the script needs about 10 GB and emits the same C. For `main` it also passes
`-mllvm -inline-threshold=3000` to clang (`CCC_OVERRIDE_OPTIONS`): same output, ~15-20% faster worldgen, a longer
clang step (the build takes 6-8 minutes). The worldgen trace stages are only in the debug
binary (`trace.bend`, `build.sh trace`, 32 GB cap, needs 40 GB free); `seedfinder trace` exits 2 and points to it.

`.scratch/build.sh main.bend .scratch/build/seedfinder` is an optional alternative: it emits C,
widens the runtime's initial thread spread and compiles with gcc, which is ~12% faster. It passes `-ffp-contract=off`
because `-march=native` enables FMA and gcc would otherwise fuse float multiply-adds; `bend -o` builds with
`clang -std=c11 -O3` for baseline x86-64, which has no FMA, so both builds round every float operation separately.

The runtime reserves a large virtual heap per worker thread (22 threads need more than 32 GB of
address space, but resident memory stays around 330 MB), so a `ulimit -v` below ~64 GB makes
multi-threaded runs fail with `bend: reservation failed`.

### `setpiece`

- `setpiece find` scans FROM..TO inclusive (default: every seed), prints up to 1000 matching seeds as
  `seed {json}` lines on stdout and progress on stderr.
- `setpiece show` prints the set pieces of each seed in the same `seed {json}` format as the game dump.
- Filters: `Name` (at least one), `Name:min`, `Name:min:max`, e.g. `TwigsBoon:4`,
  `"Sleeping Spider"`, `Level4Boon:0:0` (none). Names are exactly the keys printed by `setpiece show`.
- Default settings: every seed gets one trap, point of interest and protected resource pick and
  `math.random(3, 8)` boons. There are no settings flags.
- Example: `seedfinder --threads 22 -- setpiece find 0 4294967295 MiscBoon:7` (the 90 seeds with the
  most MiscBoons on default settings; none has 8)

### `world`

- `world show FROM [TO]` prints one line per seed: `seed {"prefab_swaps":{...},"tasks":[{"task":..,
  "set_pieces":[..],"random_set_pieces":[..]}, ...]}`. Tasks are in `level.chosen_tasks` order and set
  pieces in the order the game assigns them. This is byte-identical to the reference harness' world
  line. A seed whose worldgen would raise a Lua error (`math.random(n)` returning n + 1; one seed among
  the first 2^27) prints `{"error":"worldgen raises a Lua error for this seed"}` and never matches a filter.
- `world find` implements the search command of the v1 spec (`.scratch/spec/search-v1.md` § 8), parts A-E:

  | Flag | Values | Default | Meaning |
  |---|---|---|---|
  | `--start-seed S` | uint32 | 0 | Scan `S, S+1, ..., 4294967295, 0, ..., S-1`: every seed at most once. |
  | `--limit N` | 1..100 | 100 | Stop at the N-th hit. |
  | `--time-limit T` | seconds > 0, fractional (ms precision, e.g. `0.25`) | none | Stop once T seconds have passed. |
  | `--json` | | off | Print only the job object instead of lines. |
  | `--config F` (or `--config=F`) | file | every seed matches | The search config. |
  | `--platform P` | `windows` \| `linux` | the config's `platform` | The OS whose worlds parts B-E are decided on. |

  Hit lines are `seed {"entry":E,"level":{...},"results":[...]}` in scan order: `entry` is the index of the first
  matching criteria entry (`null` without criteria), `level` is exactly the `world show` object, and `results`
  holds one witness per counts/tiles/distances/routes rule of that entry (`[]` for a level-table entry). The last line is
  `done {"scanned":C,"last_scanned":L,"next_seed":X,"hits":H,"stopped":"limit"|"time"|"end"}`: the first C seeds
  of the scan order were decided, L is the C-th (`null` if C = 0; the last hit when stopped by the limit) and X the
  one after it (`null` when stopped at the end). `--start-seed X` continues without gaps or repeats. `--json` prints
  `{"version":1,"platform":"windows","hits":[{"seed":..,"entry":..,"level":{..},"results":[]}],"scanned":..,
  "last_scanned":..,"next_seed":..,"stopped":..}` instead.
- Exit status: 0 with at least one hit, 1 with none, 2 on a config or usage error. The message goes to stderr
  (`config: ...` or `search: ...`); with `--json` stdout gets `{"error":"<message>"}`.
- The hits depend only on (config, start seed, limit), never on `--threads` or timing; a time limit only decides
  how far the scan got. A level-table-only config runs in parallel rounds that start at 2^16 seeds and grow while a
  round takes under 500 ms (at most 2^24 seeds). The clock is checked between rounds, a round still running at the
  deadline is dropped (not scanned), and the last rounds before the deadline are sized to fit it, so a 0.5 s limit
  returns after ~0.52 s. Progress lines go to stderr; stdout is buffered until exit.
- A config with parts B-E (counts, distances, tiles, routes) is searched on worlds generated in memory
  (`search/generated.bend`), on the config's platform (or `--platform`). Part A still rejects seeds first, at the
  level-table speed; only its candidates are generated, two per worker thread at once (`--threads`; the default
  is the CPU count capped by the cgroup CPU quota). The layout (Kamada-Kawai, most of a world's time) is native C
  (`native/`, `--kk bend` for the Bend port): each KK pass runs as its own computation on the runtime's IO helper
  threads, while rounds of the rest of worldgen (storygen, Voronoi, tiles, land, ocean) and the filters run on the
  worker threads for the other seeds; a round takes the passes finished by then and never waits for one, so a slow
  pass (the layout's heavy tail) holds only its own seed. A finished world is decided at once (the first entry whose
  parts A-E hold; a seed whose worldgen gives up after 5 attempts never matches), and decided seeds are released in
  scan order, so every hit line is printed once it and all earlier seeds are decided, and the hits never depend on
  threads, engine or timing. Each round runs one CPU stage per seed, split across the threads by the stages'
  estimated cost; the oldest seeds (one per thread) run on to their next KK pass, since they hold back the release of
  later hits. Slots: 8 per thread, a quarter of them in the first 8 s. With `--time-limit` the clock is checked
  between rounds (a round takes ~0.1-1 s): every candidate not yet finished is dropped, and `scanned` / `next_seed`
  stop before the first undecided seed, so `--start-seed next_seed` continues without gaps.
  Speed (14 threads, 13.6-core VM, output identical to the pre-native build): `counts.json` Windows seeds 1..256
  8.9 seeds/s (was 0.45); a config with 1.4% hits (Windows, beefalo >= 40, chess pieces >= 10), seeds 1..1024
  10.8 seeds/s, first hit (seed 132) 20 s (was 250 s). Peak RSS ~1.6 GB. A KK pass is ~50 ms native (~2.5 s in
  kk.bend); the rest of a world is ~0.3-0.5 s of one thread.
- `world find FROM [TO]` is a range mode for tests: FROM..TO inclusive (TO < FROM wraps; no TO means the whole
  space), with the same limit, time limit and output. FROM can't be combined with `--start-seed`.
- `world show` only validates the config. With no `--config`, everything matches.
- Parts B–E can also run on pre-generated worlds: world dumps written by `.scratch/port/tools/world_dump.py` (or
  `snapshot_worlds.py`) from a `world.json` of the game's dump mod or the emulator. `world find ... --worlds DIR`
  decides each part-A candidate on `DIR/<seed>.dstw` (a missing dump is no match, counted on stderr) and prints the
  hits with their witnesses as `.scratch/search/search.py` does; on the same seeds it prints exactly what the
  in-memory search prints.
  `world eval` prints `.scratch/search/evaluate.py --json --level` for one dump (`--fast` stops at the first
  failing rule). Both are byte-identical to the Python reference on the spec and search examples and on random
  configs, on Windows and Linux worlds (`.scratch/port/status/M4.md`). Speed (16 threads, load ~11): 19 worlds with
  `full.json`'s rules in 1.5 s (6.1 s on 1 thread); `route6.json` on one world 4.5 s (25 s on 1 thread;
  `evaluate.py` ~110 s).
- `gen SEED [TO]` runs the ported forest worldgen (story, KK, Voronoi, tiles, land and ocean population, every
  attempt as worldgen_main retries it) of each seed and prints
  `gen seed=S platform=P a=A outcome=world|gaveup|crashed ctr=C ents=N tiles=H ms=T` (the RNG counter at the end
  of Generate, the savedata.ents count and the encoded tile map's FNV-1a digest); `--times` adds one
  `stage seed=S a=A name=NAME ms=T` line per stage of every attempt. About 0.3-0.6 s per seed on one thread with the
  native KK (5-8 s with `--kk bend`, KK ~95% of it).
- Example: `seedfinder --threads 22 -- world find --start-seed 123 --limit 10 --time-limit 30 --json --config .scratch/world/configs/example.json`

### JSON config

The format is the v1 search spec, `.scratch/spec/search-v1.md` (JSON Schema: `.scratch/spec/config.schema.json`).
The binary implements all of it: part A (the level table) below, and the world sections `counts`, `distances`,
`tiles` and `routes` (parts B–E, spec § 4-5) on both platforms.

```json
{
  "version": 1,
  "platform": "windows",
  "settings": {},
  "criteria": [
    {
      "tasks": {"required": ["Killer bees!", "Magic meadow"], "excluded": ["Mole Colony Rocks"]},
      "prefab_swaps": {"twigs": "twiggy trees"},
      "setpieces": [
        {"tasks": ["Magic meadow"], "required": {"MooseNest": 1}},
        {"required": {"MiscBoon": [2, 8], "Chessy_1": 1}}
      ]
    },
    {"setpieces": [{"required": {"Level4Boon": 2}}]}
  ]
}
```

| Key | Meaning |
|---|---|
| `version` | Optional schema version. Missing means 1; anything else exits 2 with `config: unsupported version 2`. |
| `platform` | Optional, `"windows"` (the default) or `"linux"`: the OS of the host that generates the world. The level table is the same on both, so part A ignores it; `--json` echoes it. Anything else exits 2 with `config: unknown platform "mac" (windows or linux)`. |
| `settings` | Optional and reserved for later. Only the default settings are supported, so it must be absent, `{}`, or map every key to `"default"`; anything else exits 2 with `config: only default settings are supported (boons)`. |
| `criteria` | Optional list of at most 8 alternatives. A seed matches when **any** entry holds. A missing or empty list matches every seed. |
| `criteria[].passive` | Optional `true`/`false` (default `false`). A seed is only decided when the part A of an entry that isn't passive holds (its world is generated when the config has parts B-E); it then matches the first entry, passive or not, that holds. A passive entry rides along on the other entries' candidates without making every seed one. At least one entry must not be passive (`config: every criteria entry is passive (at least one must not be)`). |
| `criteria[].tasks.required` | Every listed task is among the chosen tasks. Task lists are always lists (never a bare string) of at most 25 tasks. |
| `criteria[].tasks.excluded` | No listed task is among the chosen tasks. |
| `criteria[].prefab_swaps` | `grass`: `regular grass` or `grass gekko`; `twigs`: `regular twigs` or `twiggy trees`; `berries`: `regular berries` or `juicy berries`. |
| `criteria[].setpieces[]` | At most 16 rules. `required` maps at most 16 set piece names to `min` (at least min) or `[min, max]` (inclusive), integers in 0..4294967295. The count is how many times the piece is placed, summed over `set_pieces` and `random_set_pieces` of the entry's `tasks`. A missing or empty `tasks` means every task. |

All conditions of one criteria entry must hold. Task names are the game's task ids as printed by
`world show` (e.g. `"Killer bees!"`, `"MoonIsland_Beach"`). Set piece names are the `level.set_pieces` keys
(boons, traps, points of interest, protected resources, and the fixed ones such as `MooseNest` or
`CaveEntrance`) and the random set pieces (`Sculptures_1`..`5`, `Maxwell1`..`7`, `Chessy_1`..`6`,
`Warzone_1`..`3`). The JSON is strict: unknown or repeated keys, `null` values, fractions or integers above
4294967295 where an integer is expected, and anything over a cap exit with status 2 and the spec's message
(§ 7), e.g. `config: unknown task "Killer Bees" in criteria[0].tasks.required`,
`config: duplicate key "tasks" in criteria[0]` or `config: criteria[0].setpieces has 17 rules (at most 16)`.

### Speed (clang build, 22 threads)

| Command | seeds/s | whole 2^32 space |
|---|---|---|
| `setpiece find MiscBoon:6` | ~40M (1 thread ~4.2M) | ~2 min |
| `world find`, prefab swap + trap filter (`t_traps.json`) | ~55M | ~1.5 min |
| `world find`, boon filters (`t_boons.json`, `example.json`, `t_scoped.json`) | ~18–21M (1 thread ~2.1M) | ~4 min |
| `world find`, filters that need ChooseSetPieces for most seeds (`t_fixed.json`, `t_specials.json`) | ~6.7–7.2M | ~10 min |
| `world find`, every seed matches (full level table for every seed) | ~8.2M (1 thread ~720k) | ~9 min |
| `world find`, no hits: rejected at the tasks (`nohit_fast`) / boon counts (`misc7`) / ChooseSetPieces (`nohit_deep`) | ~85–90M / ~26M / ~8.6M | ~50 s / ~3 min / ~8 min |
| `world show` (sequential, JSON output) | ~5k | |

`world find` works in stages and stops at the first one that can't match. First the tasks and prefab swaps.
Then AddSetPeices: a count bound fails early when too few copies of a piece exist. The last stage is the
full ChooseSetPieces.

## How it works

Everything filtered on is decided in Lua before `forest_map.Generate` (`worldgen_main.lua`
`GenerateNew`: `SelectPrefabSwaps`, `ChooseTasks`, `AddSetPeices`, `Level:ChooseSetPieces`). The only inputs
are the RNG stream and stock Lua 5.1 table orders, so the finder replays the RNG draws:

- RNG: Klei replaced libc rand with PCG32; `math.random` = output / (2^32 - 1). See
  `.scratch/research/rng.md` (verified against the game binary).
- The 13 draws before set piece selection are constant, so seeding plus skipping them is one
  affine map `state = seed * K + L (mod 2^64)` (`rng/pcg.bend`).
- Prefab swaps are the first 3 draws after the discarded one. ChooseTasks shuffles the 10 optional tasks
  (9 draws), and the first 5 are chosen (`level/prefix.bend`).
- Traps / POI / protected / boons picks follow `GetRandomFromLayouts` + `GetRandomKey`
  (`level/setpieces.bend`), with area/item orders baked into `data/catalog.bend`
  (generated by `scripts/gen/gen_catalog.py`; orders from `.scratch/research/worldgen-trace.md`).
- ChooseSetPieces (`level/choose.bend`) walks `level.set_pieces` in `pairs()` order. That order depends on the
  insertion history, so `level/choose.bend` emulates Lua 5.1's `ltable.c` hash part (main positions, `lastfree`,
  rehash) with the string hashes baked into `data/world_catalog.bend` (generated by
  `scripts/gen/gen_world_catalog.py`; the Python spec is `.scratch/world/model.py`). Required and random
  set pieces go to random placeable tasks. Each entry's copies go to distinct random tasks among
  its choices.
- `math.random(n)` is computed exactly with U32 math (`LuaRandom.scale`), bit-exact with the game's
  double arithmetic for every n the worldgen uses.
- The config is parsed in Bend (`filters/json.bend`, `filters/config.bend`). The search is a chunked parallel
  fork-join (`search/`).

## Code layout

| Path | What |
|---|---|
| `main.bend` | CLI dispatch |
| `rng/` | PCG32 (`pcg.bend`: seeding, affine skip, jump-ahead, draw counters), `math.random` (`lua_random.bend`), Klei's C++ `rand()` and `std::random_shuffle` for Windows and Linux hosts (`crand.bend`) |
| `level/` | the level table: `prefix.bend` (prefab swaps, ChooseTasks), `setpieces.bend` (AddSetPeices), `choose.bend` (ChooseSetPieces), `summary.bend` (the `world show` JSON) |
| `filters/` | `json.bend` (reader), `config.bend` (search config), `setpiece.bend` (`setpiece find` filters), `world.bend` (the world the filters read) and the part B-E evaluators (`evaluate.bend`, `metric.bend`, `walk.bend`, `routes.bend`, ...) |
| `storygen/`, `worldsim/`, `populate/`, `ocean/`, `f64/`, `f32/`, `xint/`, `lua/`, `stl/` | the worldgen port: storygen, KK layout, Voronoi, tiles, land and ocean population, soft float, Lua and libstdc++ emulation |
| `search/`, `cli/` | `setpiece`/`world` scans, rounds and output (`generated.bend`: the search on generated worlds, `order.bend`: scan order, `threads.bend`: the runtime's thread count (capped by the cgroup CPU quota); `worlds.bend`: on world dumps); argument parsing and file reading |
| `native/` | the KK layout in C (the one part not in Bend), a foreign IO effect reached through `gen/layout.bend`'s `solve`; `worldsim/layout/kk.bend` is its reference |
| `data/` | generated tables (`catalog.bend`, `world_catalog.bend`), never edited by hand: `scripts/gen/regen.sh` rewrites them |
| `gen/` | the end-to-end generator: `generate.bend` (stage functions of forest_map.Generate), `job.bend` (the resumable per-seed job state machine: `step`, `layout`/`laid` at the KK passes; the ocean stage and its retries), `layout.bend` (a KK pass and its engines: `solve`, native C or kk.bend), `graph.bend`/`tags.bend`/`world.bend` (the Boost graph, ApplyPoisonTag, the tile world), `savedata.bend`/`centi.bend` (the filters' world of a generated world, positions rounded as the savedata dump prints them), `run.bend` (`seedfinder gen`), `trace.bend` (trace stage `gen`) |
| `trace/`, `trace.bend` | `seedfinder_trace trace` (the debug binary), the canonical dumps the worldgen port is checked with |
| `LAWS.bend`, `PROOF.bend`, `laws/` | golden-value laws with their proofs (`LAWS.bend`: root, `laws/*.bend`: each port lane); `PROOF.bend` imports them all |

`seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--input FILE]` prints one worldgen stage in the
canonical record format of the reference oracle (`.scratch/port/oracle/`), for the full-worldgen port
(`.scratch/port/PLAN.md`, rules in `.scratch/port/CONVENTIONS.md`). Stages: `crand` (M0), `kk`/`hops`, `voronoi`,
`polygons` (lane N), `storygen` (lane S), `sitetiles`/`tiles`/`populate`/`pvoronoi` (lane G), `gen` (end to end from
the seed alone, every attempt, M11); each is checked by its
`.scratch/port/diff/<stage>.py` against the oracle.

## Validation

- `bend PROOF.bend` (~50-65 s, 2.2 GB; `scripts/proof.sh` checks the same law files one by one with
  their times): golden values from the Lua reference harness and the port lanes' references. The root laws cover set pieces
  (edge seeds 0 / 1 / 2^31 / 2^32-1), the seed-1 prefix (prefab swaps, the task shuffle and the PCG state), the
  whole level table of seed 1, and config parsing (including the default-only settings and `version` checks)
  and matching. `.scratch/world/golden.py` checks a level-table golden value against the harness.
  `.scratch/lawprobe/probe.sh LAW` checks one law alone with a memory cap. Keep each law cheap: the
  checker evaluates slowly, and a `LevelSummary.summary` of a seed with many boons can need more than 8 GB.
- `.scratch/harness/`: runs the real worldgen Lua under Lua 5.1.5 with DST's RNG.
  - `setpiece`: Bend == harness for seeds 1..1,000,000 (`harness/compare.py` against `harness/out/out_1M.txt`).
  - `world show` (`.scratch/world/validate_all.sh`, `compare_bend.sh`) is byte-identical to the harness for
    1..1,000,000 plus 2^31-50,000..2^31+49,999 and 2^32-100,000..2^32-1. That is 1.2M seeds in total.
  - `world find` (`.scratch/world/run_find_checks.sh`): the hit lines (seed, entry, level) and the `done` line agree
    with an independent Python evaluation of 9 configs over the harness summaries of seeds 1..20,000.
  - `world find` flags (`.scratch/findflags/validate.py`): `--limit` hits equal the first lines of the old range mode
    (8 configs × 3 start seeds × 3 limits, and `world find 2147483000 4294967295`), wrap-around at 2^32, a whole-space
    scan, `--threads 1` == `--threads 22`, the `--json` job object against `world show` and the entries, time limits
    and their continuation, platform and flag errors. `config_errors.py` compares 48 config errors with the
    reference parser `.scratch/search/config.py`, and `spec_examples.py` checks `.scratch/spec/examples/`.
- `.scratch/groundtruth/`: a mod that dumps worldgen data from the real game.
  - The log for seeds 1..1000 matches the harness and the Bend finder exactly. That covers the set pieces and
    the per-task `PLACE` lines of ChooseSetPieces.
  - Full world dumps for seeds 1..10 (`data/worlds/`: tasks, per-task set pieces and prefab swaps) also match
    (`.scratch/world/compare_groundtruth.py`).
  - The mod's output lands in the dedicated server log
    (`~/.klei/DoNotStarveTogether/<id>/Cluster_1/Master/server_log.txt`).

## Limits

- Default forest preset (SURVIVAL_TOGETHER) with default settings only. Other presets, settings and mods
  are not modelled (they may change the RNG stream or the task set), and the config rejects them.
- Worlds are generated as a dedicated server on Windows or Linux generates them (build 747465); other hosts
  (macOS, consoles) are not modelled. Part B-E searches cost a full worldgen per part-A candidate.
