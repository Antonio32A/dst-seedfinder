# dst-seedfinder

A seed finder for Don't Starve Together forest worlds. It predicts the level table (tasks, set pieces, prefab swaps)
of every seed directly, and generates candidate worlds in memory with a port of the whole forest worldgen that is
bit-identical to the game (build 747465) on Windows and Linux servers. Only the default world settings are supported.

| Folder | Contents |
|---|---|
| `seedfinder/` | The Bend sources. `seedfinder/README.md` documents the CLI, the search config and the code layout. |
| `scripts/` | Build and proof scripts, the data generators (`gen/`), the prefab catalog (`catalog/`), the Lua harness the generators run under (`harness/`). |
| `website/` | The web UI (`website/README.md`). |

# Requirements

To build and run:
- Linux x86-64.
- [Bend](https://bend-lang.com) 2.0.27 or newer: `curl -fsSL https://bend-lang.com/install.sh | sh`.
- clang 14 or newer (19 or newer plus the CUDA toolkit for GPU builds).
- About 12 GB of free RAM to build the production binary, 40 GB for the debug (trace) binary.

Only to regenerate the generated data in `seedfinder/data/` (it is committed, so a normal build does not need this):
- Don't Starve Together installed through Steam. The generators read `data/databundles/scripts.zip` and the Linux
  dedicated server binary (`bin64/dontstarve_dedicated_server_nullrenderer_x64`). `DST_GAME` overrides the install path.
- python3, gcc, g++, curl, unzip.

# Building

```sh
scripts/build.sh                                   # seedfinder/main.bend -> .scratch/build/seedfinder (5-8 min)
scripts/proof.sh -j 3                              # the laws (seedfinder/LAWS.bend, seedfinder/laws/); run before committing
bend seedfinder/main.bend --check-only             # type-check only
scripts/build.sh trace                             # debug binary with the worldgen trace stages -> .scratch/build/seedfinder_trace
```

Use `scripts/build.sh` rather than a plain `bend seedfinder/main.bend -o ...`. It caps the compiler's heap
(`BUN_JSC_forceRAMSize`), otherwise the build can grow past 32 GB. It also passes an inline threshold to clang, which
makes worldgen about 15-20% faster with identical output. Under load the build sometimes fails with "machine stack
overflowed"; a retry passes.

## Another machine (e.g. a GPU server)

A binary built on a new distribution needs a recent glibc (2.38 on Fedora 42). The portable route is to emit the C
source and compile it on the target:

```sh
scripts/build.sh seedfinder/main.bend .scratch/build/seedfinder.c
# on the target, with clang 14+:
CCC_OVERRIDE_OPTIONS='# +-mllvm +-inline-threshold=3000' clang -std=c11 -O3 seedfinder.c -lpthread -lm -o seedfinder
```

The code has no GPU (`!`) calls yet, so the result runs on the CPU. Once it has them, build on the target with
`bend seedfinder/main.bend -o seedfinder`. Bend detects the CUDA toolkit (`CUDA_HOME`, default `/usr/local/cuda`) and
links `-lcuda -lnvrtc`; this needs clang 19 or newer.

# Running

```sh
.scratch/build/seedfinder --threads 16 -- world find --limit 5 --time-limit 120 --config config.json
.scratch/build/seedfinder --threads 16 -- world find --start-seed 123456 --limit 1 --json --config config.json
.scratch/build/seedfinder world show 123456 --config config.json
.scratch/build/seedfinder --threads 16 -- setpiece find 0 4294967295 MiscBoon:7
.scratch/build/seedfinder --threads 1 gen 123456 --platform windows
```

- **Config format:** `seedfinder/README.md` describes it and has examples.
- **Search speed:** the level table is scanned at millions of seeds per second. Every seed that passes it and has
  count, distance, tile or route filters costs one full worldgen, about 3-6 s of one thread.
- **Continuing a search:** `--time-limit` stops the search, and `--start-seed` with the printed `next_seed`
  continues it.
- **Memory:** a multi-threaded run reserves about 3 GB of virtual memory per thread, so don't run it under a low
  `ulimit -v`.

# Regenerating the data

```sh
scripts/setup.sh              # once: game scripts from the local install, Lua 5.1.5 and Boost 1.52 into .scratch/, builds lua-dst
scripts/gen/regen.sh          # rewrites seedfinder/data/*.bend from the game scripts
scripts/gen/regen.sh --check  # fails if any generated file is stale
```

Regenerate after a game update, then rebuild and re-run the proofs. `scripts/gen/out/pow_windows_exceptions.txt` is
committed because it comes from an exhaustive run against the Windows server's MSVCR90 `pow` and can't be regenerated
from the Linux install. `DST_WINDOWS_EXE` optionally points at the Windows server exe, which adds a cross-check of the
Perlin table.

`scripts/catalog/catalog.json` is the prefab catalog behind `seedfinder/data/catalog.bend`, `world_catalog.bend` and
the website's prefab lists. `scripts/catalog/build_catalog.py` rebuilds it from a static extraction of the game scripts
plus prefab statistics from generated worlds. Those statistics come from the validation emulator, which is not part of
this repository, so a full `scripts/catalog/regen.sh` only works where that emulator is set up.
