# catalog

Generates `catalog.json`: the settings, prefab swaps, tasks, set pieces, prefabs and tiles of a default forest world
(`SURVIVAL_TOGETHER`), used by the seedfinder data generators and the website. It's built from the game scripts plus
statistics over a sample of generated worlds.

Everything here needs `scripts/setup.sh` to have been run, numpy, and the game installed through Steam (`DST_GAME`
overrides the install path; without the game the catalog silently loses its icons, tile colours and game build).

## Tiles on the map

Each of `tiles[]` carries what the website's map needs to draw it the way the game's map screen does. The game draws
one layer per tile type, in `GroundTiles.minimap` order (the order of `tiledefs.lua`'s `AddTile` calls): each layer
multiplies a cell of the `levels/tiles/map_edge` atlas by the tile's minimap noise texture. The ocean is drawn in a
separate pass, from each ocean tile's ground colour. Colours are `[r, g, b]` (0-255).

- `color`: the tile's flat colour on the map at full brightness, for swatches and anything that isn't drawn per pixel.
  - Land tiles with a minimap noise: the mean RGB of `map_edge` cell `01` times the mean RGB of the noise texture.
  - Ocean tiles: their ground def's `colors.minimap_color` (the colour `world.lua` hands to
    `MapLayerManager:SetMinimapColor`), ignoring its alpha.
  - Tiles without a minimap layer (`IMPASSABLE`, the walls, the noise tiles, ...): the mean of
    `images/minimap_paper.tex`, the minimap's background.
- `minimap_noise`: the name of the tile's minimap noise texture (`levels/textures/<name>.tex`), for the land tiles of
  the sampled forest worlds; `null` otherwise. `map_textures.py` writes each one to the website.
- `minimap_rank`: the land tile's position in `GroundTiles.minimap` (1 is drawn first); `null` for the ocean, which
  has its own pass, and for tiles without a minimap layer.
- `ocean_minimap_color`: an ocean tile's ground `colors.minimap_color` RGB; `null` for the other tiles.

The texture names and ranks come from `inputs/static.json` (`minimap_noise`, `minimap_rank`, `ground_minimap_color`).
Only the numbers are committed.

## Map textures

`map_textures.py` writes the textures the website's map draws with to `website/public/world-map/`, as lossless PNGs of
the full-size mip, rows in stored order (the first row is texture coordinate v = 0, as the game uploads it):

- `noise/<name>.png`: every `minimap_noise` of `catalog.json`, RGB.
- `map_edge.png`: `levels/tiles/map_edge.tex`, RGBA, with its straight alpha exactly as stored
  (`levels/tiles/map_edge.xml` places its 48 cells).
- `minimap_paper.png`: `images/minimap_paper.tex`, RGB.

It needs the game install (`DST_GAME` overrides the path) and reads `catalog.json`, so rerun it after
`build_catalog.py`:

```sh
python3 scripts/catalog/map_textures.py
```

The output is deterministic, and committed because the site build has no game install. `ktex.py` decodes the textures
the way Mesa's OpenGL driver does, pixel for pixel (DXT interpolants round down). `python3 -m unittest discover -s
scripts/catalog` tests the decoder and the writer.

The art is © Klei Entertainment and used under Klei's Player Creation Guidelines, which allow it as long as the site
stays free and credits the art to Klei with a notice that the site isn't affiliated with Klei.

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
6. Regenerate what depends on it: `scripts/gen/regen.sh`, `node scripts/gen/gen_website_catalog.mjs` and
   `python3 scripts/catalog/map_textures.py`.
