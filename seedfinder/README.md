# seedfinder

The real deal. 
Searches all 2^32 seeds of a DST forest world for worlds matching a filter (see [docs/config.md](../docs/config.md)).

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
build/seedfinder --threads 1 -- gen 123456 --platform windows
```

`world find` flags on top of the ones in [docs/config.md](../docs/config.md):
- `--config F`: the search config (without one every seed matches).
- `--platform windows|linux`: overrides the config's `platform`.
- `FROM [TO]`: scan a seed range instead of the whole space (can't be combined with `--start-seed`).
- `--worlds DIR`: decide seeds on world dumps (`DIR/<seed>.dstw`) instead of generating them.
- `--kk native|bend`: the layout engine, `bend` is the slow reference port (also on `gen`).

`world eval --config F --world DUMP.dstw [--json] [--fast]` checks one config against one world dump. Both read the
format of [docs/world-dump.md](../docs/world-dump.md) (version 2, older dumps have to be regenerated).

- `--time-limit` stops the search, `--start-seed` with the printed `next_seed` continues it.
- Pass `--threads` in a container, the runtime's default is the host's CPU count, not the quota.
- Don't run it under a low `ulimit -v`, each thread reserves a lot of virtual memory.

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
```

`world_dump.py` writes every entity of the world, also those of prefabs outside the catalog.
