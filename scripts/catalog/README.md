# catalog

Generates `catalog.json`: the settings, prefab swaps, tasks, set pieces, prefabs and tiles of a default forest world
(`SURVIVAL_TOGETHER`), used by the seedfinder data generators and the website. It's built from the game scripts plus
statistics over a sample of generated worlds.

Everything here needs `scripts/setup.sh` to have been run, numpy, and the game installed through Steam (`DST_GAME`
overrides the install path; without the game the catalog silently loses its icons, tile colours and game build).

## Tiles on the map

Each of `tiles[]` carries what the website's map needs to draw it as the game's map screen does. The game draws one
layer per tile type, in `GroundTiles.minimap` order (the order of `tiledefs.lua`'s `AddTile` calls), each multiplying a
cell of the `levels/tiles/map_edge` atlas by the tile's minimap noise texture. The ocean is a separate pass, from each
ocean tile's ground colour. Colours are `[r, g, b]` (0-255).

- `color`: the tile's flat colour at full brightness, for swatches.
  - Land tiles with a minimap noise: the mean RGB of `map_edge` cell `01` times the mean RGB of the noise texture.
  - Ocean tiles: their ground def's `colors.minimap_color` (the colour `world.lua` hands to
    `MapLayerManager:SetMinimapColor`), ignoring its alpha.
  - Tiles without a minimap layer (`IMPASSABLE`, the walls, the noise tiles, ...): the mean of
    `images/minimap_paper.tex`, the minimap's background.
- `minimap_noise`: the tile's minimap noise texture (`levels/textures/<name>.tex`), for the land tiles of the sampled
  forest worlds; `null` otherwise.
- `minimap_rank`: the land tile's position in `GroundTiles.minimap` (1 is drawn first); `null` for the ocean and for
  tiles without a minimap layer.
- `ocean_minimap_color`: an ocean tile's ground `colors.minimap_color` RGB; `null` for the other tiles.

The texture names and ranks come from `inputs/static.json` (`minimap_noise`, `minimap_rank`, `ground_minimap_color`).

## Minimap icons

`icons.minimap` of each prefab is what the game itself draws for it. `minimap_icons.py` runs every game prefab's
constructor under `extract_minimap_icons.lua` (the master simulation, with stubs for what the constructors touch) and
records what each tells its `MiniMapEntity`: the last icon, priority and draw-over-fog flag. Prefabs whose last
`SetEnabled` is false, or that never set an icon, have none. The table is snapshotted in `inputs/minimap_icons.json`
(`incomplete: true` marks a constructor that crashed after setting its icon):

```sh
python3 scripts/catalog/minimap_icons.py
```

`build_catalog.py` resolves the icon name in the atlases the game loads, `minimap_data1.xml` then `minimap_data2.xml`
(`minimap_data.xml` is legacy: the game never loads it, and its rects differ). `icons.minimap.match` says where the
icon came from:

- `game`: the prefab's own constructor.
- `spawned:<prefab>`: a spawner with no icon of its own, given the icon of what it spawns (`names.SPAWNED_ICONS`). The
  icon is only what the spawner would look like: a capture of the game's map shows it draws nothing at these markers
  (`antlion_spawner`, `crabking_spawner`, `wagstaff_machinery_marker`, `seastack_spawner_rough`,
  `seastack_spawner_swell`, `waterplant_spawner_rough` and `wobster_den_spawner_shore`), only what they spawn.
- `captured`: the icon the running game showed for a prefab whose constructor sets another one (`names.CAPTURED_ICONS`:
  `shell_cluster` draws `flotsam_heavy.png`, `storage_robot` draws `storage_robot_broken.png`).

### Drawn by default

`default_shown` says whether the game's map draws the prefab's icon in a freshly generated world, which the website's
Filters start from. It is true for every prefab with an icon except those with a `hidden_by_default` reason:

- `spawned:` icons: the spawner marker itself is never drawn.
- `names.CONDITIONAL_ICONS`: prefabs whose constructor sets an icon but enables it only in some state. `rock_ice` is
  enabled by its growth stage, and a new world has none grown (the capture drew none of its 53).

Prefabs without an icon are not `default_shown`; the website still lets them be toggled, as dots. Exploration fog is
not modelled: the game draws icons only over explored ground. Other prefabs disable their icon at runtime
(`beequeenhive` off its base, `oceanvine_cocoon` when burnt, `beemine` when deactivated, `cave_entrance` on a
client-hosted server without shards); none of that applies to a new world's default state, so they stay default-on.

Bunch spawners (`bunch:` sources) have no icon of their own: the game scatters several copies around each, so the
marker's single icon only approximates them.

## Map textures

`map_textures.py` writes the textures the website's map draws with to `website/public/world-map/`, as lossless PNGs of
the full-size mip, rows in stored order (the first row is v = 0, as the game uploads it):

- `noise/<name>.<hash>.png`: every `minimap_noise` of `catalog.json`, RGB.
- `map_edge.<hash>.png`: `levels/tiles/map_edge.tex`, RGBA, with its straight alpha exactly as stored
  (`levels/tiles/map_edge.xml` places its 48 cells).
- `minimap_paper.<hash>.png`: `images/minimap_paper.tex`, RGB.
- `minimap_icons.<hash>.png` and `minimap_icon_rects.<hash>.json`: the sprite sheet of the catalog's minimap icons, and
  where each sits on it.

Every file's name carries the first 10 hex digits of the SHA-256 of its bytes, so the deployed files are served with
`Cache-Control: public, max-age=31536000, immutable` (one `/world-map/*` rule in the generated `_headers`, next to the
security headers). Files the run didn't write are deleted, and `map_textures.json` lists which file each texture went
to: `gen_website_catalog.mjs` reads it for the texture URLs of `website/lib/catalog/world.ts`.

The sprite sheet is 2048 wide at its full size, and its RGBA is the atlas' as stored, with each icon's rows flipped to
read top first: premultiplied alpha, which the game blends as if it were straight alpha. Each icon has a cell of the
atlas around its rect (the rect plus at least 32 texels, aligned to 32 texels), copied as the game sees it, neighbouring
art included, and edge texels repeated past the atlas' edge. The game samples its atlas trilinearly from a mip chain
that isn't a box filter of level 0, so the sheet carries the chain too: each of its 6 levels holds every icon's cell
cut from the atlas' own mip of that level (the cell at `x >> level`, `y >> level`), and the website uploads each level
as it is instead of generating mipmaps. The PNG stacks the levels: level 0 on the left, levels 1 to 5 in a column to its
right; `iconSheet.levels` of the manifest (and `world.ts`) gives each one's region in the PNG, and `iconSheet.width` and
`height` are level 0's. The rects are each element's rect in level 0 sheet texels, top row first
(`u = x / width`, `v = y / height`). Atlas elements have their edges on half texels: a 63 wide icon is a rect
`w = 63` starting half a texel into 64 texels, and is drawn 63 px (9.84375 world units) wide. Priorities are per prefab
(`world.ts` `icon.priority`), not per icon.

It needs the game install (`DST_GAME` overrides the path) and reads `catalog.json`, so rerun it after
`build_catalog.py`, then regenerate `world.ts`:

```sh
python3 scripts/catalog/map_textures.py && node scripts/gen/gen_website_catalog.mjs
```

The output is deterministic, and committed because the site build has no game install. `ktex.py` decodes the textures
the way Mesa's OpenGL driver does, pixel for pixel (DXT interpolants round down). Run the tests with
`python3 -m unittest discover -s scripts/catalog`.

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
6. Regenerate what depends on it: `scripts/gen/regen.sh`, `python3 scripts/catalog/map_textures.py` and
   `node scripts/gen/gen_website_catalog.mjs`. `regen.sh` (step 3) already reruns `minimap_icons.py`; check that
   `SPAWNED_ICONS` and `CAPTURED_ICONS` in `names.py` still hold.
