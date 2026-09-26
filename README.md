# dst-seedfinder

[![forthebadge](https://forthebadge.com/badges/contains-technical-debt.svg)]()

A seed finder for Don't Starve Together. Supports forest worlds on version `747465` on Windows and Linux.

This is mostly a toy project, the majority of the code is very sloppy and not production ready. 

## Structure

### seedfinder 

The real deal. This does all the heavy lifting. It's the majority of the game's world geneneration code ported to Bend and
optimized to generate worlds as fast as possible. 

It uses [Bend](https://github.com/bendlang/bend) as it's a pretty fast language, and I honestly just wanted to fuck 
around with it. It does not support CUDA/GPU world generation, as when I was testing it, it was unfortunately just
too slow and not the right job for the GPU. It is still, very fast and will take advantage of your entire CPU. 

A tiny amount of the code is also in C, because Bend currently does not support F64 and the majority of the world
generation time is spent computing KK layouts, which are very slow with the boxed F64 this project reimplements.

To use it, you define a JSON config which says what you want to search for (e.g., a world with five walking canes 
and five `MiscBoon` set pieces). You can see the spec for it in [docs/config.md](docs/config.md).

### website

This is a Next.js app that lets users sign in and submit seed searches. Users currently sign in with Discord (it was
the simplest solution) and are given a set number of credits. Credits are purely used for rate limiting.

All seed searches are run on a different server, currently this comes from Vast.ai. When you press "Find seeds",
it literally spins up a new server which downloads the runner image, passes the config to it, and then
starts finding seeds on there. 

This runs on Cloudflare Workers, as I was lazy to properly deploy it anywhere else.

### runner

This is the Docker image that Vast.ai pulls and runs on boot. It runs Alpine Linux with a small script which runs the 
seedfinder. The script pulls the JSON config from the backend, runs the seedfinder, and pipes all outputs to the backend.

### bend

We use a custom version of Bend which has WebAssembly support. This is used so users can find seeds in their browser.

### scripts

This contains a bunch of scripts for building, setting up the build environment and generating other files:
- `catalog` - Generates the prefab catalog for the website using the game scripts.
- `gen` - Generates a lot of data for the seedfinder. A lot of the Bend code is auto generated using these scripts, so
when the game updates this code should still work (unless Klei changes a lot of stuff in the engine). 
- `groundtruth` - Spins up a dedicated DST server with a custom mod to dump world generation data. This was originally used to
validate to ensure we haven't broken any world generation code, but now it's mostly used to port the tool to newer versions.
- `harness` - Contains the Lua harness that lets us run some game scripts without actually running the game.

# TODO CONTINUE

# Requirements

To build and run:
- Linux x86-64.
- Bend 2.0.29, pinned: the compiler is the `bend/` submodule, a Bend 2.0.29 fork with a WebAssembly target and the
  fix for [bendlang/bend#1093](https://github.com/bendlang/bend/issues/1093)
  ([Antonio32A/bend-wasm](https://github.com/Antonio32A/bend-wasm), branch `wasm-2.0.29`). Fetch it with
  `git submodule update --init`. `scripts/bend.sh` runs it on the Bun runtime inside an installed
  [Bend](https://bend-lang.com) CLI (`curl -fsSL https://bend-lang.com/install.sh | sh`). A stock Bend 2.0.29 builds
  a wrong seedfinder (#1093: every double reads as NaN).
- clang 14 or newer.
- Only for the WebAssembly build: [Emscripten](https://emscripten.org) 3.1.35 or newer (`emcc` on `PATH`, or `EMCC`).
- About 12 GB of free RAM to build the production binary, 40 GB for the debug (trace) binary.

Only to regenerate the generated data in `seedfinder/data/` (it is committed, so a normal build does not need this):
- Don't Starve Together installed through Steam. The generators read `data/databundles/scripts.zip` and the Linux
  dedicated server binary (`bin64/dontstarve_dedicated_server_nullrenderer_x64`). `DST_GAME` overrides the install path.
- python3, gcc, g++, curl, unzip.

# Building

```sh
scripts/build.sh                                   # seedfinder/main.bend -> build/seedfinder (5-8 min)
scripts/proof.sh -j 3                              # the laws (seedfinder/LAWS.bend, seedfinder/laws/); run before committing
scripts/bend.sh seedfinder/main.bend --check-only  # type-check only
scripts/build.sh trace                             # debug binary with the worldgen trace stages -> build/seedfinder_trace
scripts/build.sh wasm                              # browser build -> build/wasm/seedfinder.{wasm,mjs}
```

Use `scripts/build.sh` rather than a plain `scripts/bend.sh seedfinder/main.bend -o ...`. It caps the compiler's heap
(`BUN_JSC_forceRAMSize`), otherwise the build can grow past 32 GB. It also passes an inline threshold to clang, which
makes worldgen about 15-20% faster with identical output. Under load the build sometimes fails with "machine stack
overflowed"; a retry passes.

## Another machine

A binary built on a new distribution needs a recent glibc (2.38 on Fedora 42). The portable route is to emit the C
source and compile it on the target:

```sh
scripts/build.sh seedfinder/main.bend build/seedfinder.c
# on the target, with clang 14+:
CCC_OVERRIDE_OPTIONS='# +-mllvm +-inline-threshold=3000' clang -std=c11 -O3 seedfinder.c -lpthread -lm -o seedfinder
```

The seed finder runs on the CPU only. The worldgen layout (Kamada-Kawai, most of a world's time) is native C
(`seedfinder/native/`), a foreign IO effect that bend compiles into the same binary; `--kk bend` switches `world find`
and `gen` to the Bend reference port (`seedfinder/worldsim/layout/kk.bend`, same output, several times slower).

## WebAssembly

`scripts/build.sh wasm` builds the same seedfinder for browsers with Emscripten: `build/wasm/seedfinder.wasm` and
`seedfinder.mjs`, an ES module whose default export is the Emscripten module factory. The .mjs is also the script of
the runtime's worker threads, so serve both files side by side, with the .wasm as `application/wasm`. The page that
loads them must be cross-origin isolated (`Cross-Origin-Opener-Policy: same-origin`,
`Cross-Origin-Embedder-Policy: require-corp`), because the threads share memory.

The module takes the same arguments as the binary (`arguments`), and the config file goes into its in-memory
filesystem (`FS.writeFile` in `preRun`). The seedfinder reads `--threads` from `/proc/self/cmdline` to size its
parallel rounds, so write the NUL-separated argument list there as well. Stdout and stderr arrive through `print`
and `printErr`. Each instance reserves 2 GiB of memory. Per core it runs at about 90% of the native speed, and
several `--threads 1` instances on separate seed ranges are faster than one instance with several threads.

The website's local search runs this build, so run `scripts/build.sh wasm` before building the website: its
`npm run build` copies `build/wasm/` into `website/public/wasm/`.

# Running

```sh
build/seedfinder --threads 16 -- world find --limit 5 --time-limit 120 --config config.json
build/seedfinder --threads 16 -- world find --start-seed 123456 --limit 1 --json --config config.json
build/seedfinder world show 123456 --config config.json
build/seedfinder --threads 16 -- setpiece find 0 4294967295 MiscBoon:7
build/seedfinder --threads 1 gen 123456 --platform windows
```

- **Config format:** `seedfinder/README.md` describes it and has examples.
- **Search speed:** the level table is scanned at millions of seeds per second. Every seed that passes it and has
  count, distance, tile, or route filters costs one full worldgen, about 0.5 s of one thread (about 11 worlds/s
  on 14 threads).
- **Continuing a search:** `--time-limit` stops the search, and `--start-seed` with the printed `next_seed`
  continues it.
- **Memory:** a multi-threaded run reserves about 3 GB of virtual memory per thread, so don't run it under a low
  `ulimit -v`. Pass `--threads` in a container: the runtime's default is the host's CPU count, not the CPU quota.

# Regenerating the data

```sh
scripts/setup.sh              # once: game scripts from the local install, Lua 5.1.5 and Boost 1.52 into build/deps/, builds lua-dst
scripts/gen/regen.sh          # rewrites seedfinder/data/*.bend and config.schema.json
scripts/gen/regen.sh --check  # fails if any generated file is stale
```

Regenerate after a game update, then rebuild and re-run the proofs. `scripts/gen/out/pow_windows_exceptions.txt` is
committed because it comes from an exhaustive run against the Windows server's MSVCR90 `pow` and can't be regenerated
from the Linux install. `DST_WINDOWS_EXE` optionally points at the Windows server exe, which adds a cross-check of the
Perlin table. The config spec is [`docs/config.md`](docs/config.md); `scripts/gen/gen_schema.py` generates
`config.schema.json` from its caps and the catalog.

`scripts/catalog/catalog.json` is the prefab catalog behind `seedfinder/data/catalog.bend`, `world_catalog.bend` and
the website's prefab lists. `python3 scripts/catalog/build_catalog.py` rebuilds it from the game install plus the
snapshot in `scripts/catalog/inputs/`: the static extraction of the game scripts, level-table statistics and per-world
prefab summaries. Refreshing that snapshot (`scripts/catalog/regen.sh`) needs the validation emulator and the
level-table harness (`WORLDSIM_DIR`, `HARNESS_DIR`), which are not part of this repository.

# Dumping real worlds

`scripts/groundtruth/` generates worlds on the real dedicated server and dumps them, to validate the port after a game
update or to feed `seedfinder world find --worlds` / `world eval`:

```sh
ln -s "$PWD/scripts/groundtruth/groundtruth-worldgen" "<DST install>/mods/"   # once
scripts/groundtruth/run_worldgen.sh fresh 1-10          # one server launch per seed -> build/groundtruth/data/worlds/<seed>.json
python3 scripts/groundtruth/world_dump.py --platform linux build/groundtruth/data/worlds/1.json 1.dstw
```
