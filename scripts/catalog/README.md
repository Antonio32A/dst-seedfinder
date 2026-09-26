# catalog

Generates `catalog.json`: the settings, prefab swaps, tasks, set pieces, prefabs and tiles of a default forest world
(`SURVIVAL_TOGETHER`), used by the seedfinder data generators and the website. It's built from the game scripts plus
statistics over a sample of generated worlds.

Everything here needs `scripts/setup.sh` to have been run, and the game installed through Steam (`DST_GAME` overrides
the install path; without the game the catalog silently loses its icons and game build).

## Rebuilding from the committed inputs

The world samples and statistics are snapshotted in `inputs/`, so tweaks like names or groups (`names.py`) only need:

```sh
python3 scripts/catalog/build_catalog.py
```

## Regenerating after a game update

Needs tools that aren't in the repo, given by environment variables:

- `WORLDSIM_DIR`: the worldsim emulator (`run.sh SEED OUT` writes `OUT/world.json`)
- `HARNESS_DIR`: the level-table harness (`harness.lua`, `bin/lua-dst` and the seeds 1..1000000 batch
  `out/out_1M.txt`)
- `REALGEN_DIR` (optional): real-game world summaries (`out/*/summary.json`)

1. Delete `build/deps/game-scripts/` and rerun `scripts/setup.sh` to pull the new scripts.
2. If worldgen changed, re-validate the emulator and rebuild `$HARNESS_DIR/out/out_1M.txt`.
3. Run `scripts/catalog/regen.sh --fresh-worlds` (without the flag, the cached worlds in `build/catalog/worlds/` are
   reused). It refreshes `inputs/` and writes `catalog.json`.
4. Seeds the emulator couldn't generate are listed as `no-world` in `build/catalog/build/run_worlds.log`. Generate them
   with the real game, one at a time (`$REALGEN_DIR/run.sh <seed> build/catalog/build/realgen/<seed>`), then run
   `build_catalog.py --collect` and `build_catalog.py` again.
5. Check the output: `cross_check.empirical_not_static` must be empty, and any prefab with `name_source: "fallback"`
   needs a name in `names.py`.
6. Regenerate what depends on it: `scripts/gen/regen.sh` and `node scripts/gen/gen_website_catalog.mjs`.
