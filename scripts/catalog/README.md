# Worldgen catalog (`catalog.json`)

Generated enumerations for the website UI and the `seedfinder` binary: settings, prefab swaps, tasks, set pieces,
prefabs placeable by forest worldgen (with names, groups, icons and empirical counts) and tiles. Scope: forest shard,
preset `SURVIVAL_TOGETHER`, default settings. The file is tagged with the game build (`game_build`, from the
install's `version.txt`).

## Regenerating after a game update

The regen needs two tools that aren't in the repository, given by environment variables: `WORLDSIM_DIR`, the
worldsim emulator (its `run.sh SEED OUT` writes `OUT/world.json`; `gt/*/world.json` are real-game dumps), and
`HARNESS_DIR`, the level-table harness (`harness.lua`, `bin/lua-dst`, and the batch `out/out_1M.txt`).
`REALGEN_DIR` optionally adds real-game summaries (`out/*/summary.json`). Work files go to `build/catalog/`.

1. Refresh `build/deps/game-scripts/` from the new install (`scripts/setup.sh` after deleting it).
2. If worldgen changed, re-validate the emulator and rebuild the harness level-table batch
   `$HARNESS_DIR/out/out_1M.txt` (seeds 1..1000000).
3. Run `./regen.sh --fresh-worlds` (without the flag, the cached emulator world summaries in
   `build/catalog/worlds/` are reused). It runs (outputs relative to `build/catalog/`):

| Step | Script | Output |
|---|---|---|
| Static extraction (game Lua, harness stubs) | `extract_static.lua` (run with `../harness/bin/lua-dst`) | `build/static.json` |
| Emulator worlds (fixed seeds in `seeds.txt`, 8 in parallel, `ulimit -v 16000000`, `timeout 900`) | `run_worlds.sh` → `summarize_world.py` | `worlds/<seed>.json` |
| Level-table set-piece frequencies over seeds 1..1M | `level_table_stats.py` | `build/level_table_stats.json` |
| Tasks, swaps, random set pieces over seeds 1..100k (harness `world` mode) | `level_world_stats.py` | `build/level_world_stats.json`, cache `build/harness_world/` |
| Merge, names, groups, icons, cross-check | `build_catalog.py` (+ hand data in `names.py`) | `catalog.json` |

Takes about 10 minutes (the emulator step dominates: ~8-14 s per world). Then check the summary line and
`cross_check` in the output: `empirical_not_static` must be empty. Any new unnamed prefab shows `name_source:
"fallback"`; add it to `names.py` (`PREFAB_NAMES`, `GROUPS`, `ICON_OVERRIDES`).

### How the static extraction works

`extract_static.lua` runs the unmodified `worldgen_main.lua` for seed 1 under `../harness/stubs.lua` and stops at
`forest_map.Generate` (like the harness). All worldgen modules are then loaded, and the script walks the game's own
tables instead of regex-parsing:

- task set `default` (`map/tasksets/forest.lua`): tasks, optional tasks, `set_pieces`, `ocean_prefill_setpieces`,
  required prefabs; level `SURVIVAL_TOGETHER`: required / random set pieces, `ocean_population`; start location
  `default` (`DefaultStart`, start node `Clearing`);
- every task via `tasks.GetTaskByName`: room choices (function counts are evaluated 200 times for a min/max),
  background room, entrance/cove rooms, room tags, `room_bg`;
- every room used by those (plus start node, blank, ocean rooms, `MoonIsland_Meadows` region link) via
  `rooms.GetRoomByName`: `countprefabs`, `distributeprefabs` (swappable entries expanded), `countstaticlayouts`,
  and room/task tags evaluated through `map/maptags.lua` (items such as `chester_eyebone`, static layouts such as
  `junk_yard`, `Terrarium_*`, `Charlie1/2`, `Balatro`);
- every layout via `object_layout.LayoutForDefinition` + `ConvertLayoutToEntitylist`, sampled 400 times when it
  has `areas`/`defs` (boon loot is random), plus the raw Tiled `layers[].objects[].type` of the static layout file;
- sandboxes from `map/boons.lua`, `traps.lua`, `pointsofinterest.lua`, `protected_resources.lua`;
- `map/bunches.lua` (bunch spawners → seastack/saltstack/waterplant/wobster dens), the Monkey Island dock data
  (upvalue of `MonkeyIsland_GenerateDocks`), `worldentities.lua` (pocket dimension containers), prefab proxies,
  customization proxies (`lunar_island_rock1` → `rock1`), randomization proxies (`worldgen_chesspieces`),
  `wormhole_MARKER` → `wormhole`;
- prefab swaps (`prefabswaps.lua`), `map/customize.lua` settings, tiles (`GetWorldTileMap`, `TileGroupManager`,
  `worldtiledefs` turf names), `STRINGS.NAMES`.

Empirical worlds are unioned from the real-game dumps (`build/groundtruth/data/worlds/`, `$WORLDSIM_DIR/gt/*/world.json`,
`$REALGEN_DIR/out/*/summary.json`) and the emulator worlds (`build/catalog/worlds/`). One entry per seed; real-game sources win, and
overlapping sources are compared (`worlds.seed_disagreements`).

## Top-level fields

| Field | Meaning |
|---|---|
| `schema_version` | Catalog format version (1). |
| `game_build` | Build number from the install's `version.txt`. |
| `shard`, `preset` | `forest`, `SURVIVAL_TOGETHER`. |
| `worlds` | Empirical sample: `total` distinct seeds, `by_source`, `with_tiles`, `failed` (gave up / crashed), `seed_disagreements`. |
| `settings.supported` | **Default only (decided 2026-09-24).** The finder and the config accept only `"default"` for every setting, so the UI offers none. This field still lists `boons` (game label/image/atlas, `levels`, `count_range[level]`) and `traps`/`poi`/`protected` from before that decision; treat it as reference data (the default boon range is 3..8), not as options. |
| `settings.unsupported_must_be_default` | Every other forest worldgen option in `customize.lua` (label, image, options). Like everything under `settings`, it must stay `default`. |
| `prefab_swaps[]` | `category`, `label`, `options[]` (`name` as used in the config, `prefabs`, `weight`, `probability`, `primary`, `empirical_share`). |
| `tasks[]` | `id` (exact game id), `kind` (`required`/`optional`/`moon`), `required`, `optional`, `moon`, `background_terrain` (`room_bg`, decides which terrain-specific boons/traps/POIs/protected pieces can go there), `background_room`, `display_name` (suggested), `rooms`, `region`, `set_piece_blocker` (moon tasks get no level set pieces), `share` (fraction of seeds 1..100k that have it). |
| `setpieces[]` | See below. |
| `prefabs[]` | See below. |
| `tiles[]` | `name`, `id`, `class` (`land`/`ocean`/`impassable`/`invalid`), `land`, `ocean`, `noise`, `legacy` (only in the world tile map), `display_name` (turf name, else hand/ground name), `turf_prefab`, `in_forest_worlds` (`worlds`, `share`, min/median/max tile counts over worlds with tile data). |
| `cross_check` | `empirical_not_static` (must be empty) and `static_not_empirical` with a reason each. |

### `setpieces[]`

| Field | Meaning |
|---|---|
| `name` | Layout name, exactly as in the config / output. |
| `kind` | `boon`, `trap`, `poi`, `protected`, `fixed` (task-set pieces with a constant count), `random` (`random_set_pieces`/`required_setpieces`), or a non-filterable placement: `room` (room `countstaticlayouts`), `ocean`, `maptag`, `start`. |
| `filterable` | True for level-table pieces (what `world find` can filter). |
| `display_name` | Suggested UI name. |
| `forest` | False if the piece can never be placed in the forest (cave-only terrain such as `skeleton_mushjack`, `lures_and_worms`, or an event-only layout). |
| `candidate_tasks` | Tasks the piece can be assigned to. Sandbox pieces: tasks whose `background_terrain` matches the area (all non-moon tasks for `Any`/`Rare`). |
| `fixed_count` | Count for `fixed` pieces and the always-placed random ones (`Sculptures_1`, `Maxwell5`). |
| `areas`, `p_per_draw`, `p_placed_per_draw`, `draws_per_world` | Sandbox pieces: terrain areas, the exact probability that one `AddSingleSetPeice` draw picks it (`GetRandomFromLayouts`, including the 98 % Rare re-roll and empty areas), and the same restricted to forest terrains. Boons get `boon count` draws, the others one draw. Random pieces: `1/19` per draw, 4 draws. |
| `contents[]` | What the layout places: `prefab`, `as` (raw name when a proxy), and for sampled layouts `min`/`max` count and `p` (share of samples with it). Items without counts come only from the raw Tiled types or `defs` choices. |
| `scenarios`, `data_hints` | Scenario scripts on its objects (chest fills, traps) and string data (e.g. blueprint recipes). |
| `level_stats` | Frequency over many seeds: `share`, `max`, `count_histogram` (1M seeds for level-table pieces; 100k for random pieces). Use `max` to clamp count inputs. |
| `task_distribution` | Share of placements per task (seeds 1..100k), e.g. where `MooseNest` lands. |
| `empirical` | Same statistics as prefabs, over the world sample. |

### `prefabs[]`

| Field | Meaning |
|---|---|
| `id` | Prefab id in `savedata.ents`. |
| `display_name` | `STRINGS.NAMES` (with a qualifier for ambiguous names, e.g. `rock1` → "Boulder (flint)"), or a hand-written name for spawners and markers (`names.py`). `name_source`: `strings`, `strings_variant`, `hand`, `fallback`. `game_name`: raw `STRINGS.NAMES` value or null. |
| `group` | Suggested UI group: `spawn & travel`, `bosses & spawners`, `landmarks`, `clockwork`, `sculptures`, `statues`, `trees`, `rocks`, `plants`, `mobs & dens`, `structures`, `items`, `set-piece loot`, `ocean`, `moon island`, `markers`, `other`. |
| `tags` | Derived from sources: `biome`, `set piece`, `ocean`, `moon island`, `hermit island`, `monkey island`. |
| `variant_of` | Grouping key for variants (`evergreen_tall` → `evergreen`, `rock1` → `rock`). |
| `sources[]` | `kind` (`room`, `layout`, `ocean` = ocean population room, `special` = bunch / Monkey Island docks / map tag / world entities), `name`, `default` (false = only reachable with non-default settings or events, or via cave-only pieces), `note`. |
| `default_reachable` | Any source is reachable in a default forest. |
| `placed_as` | Raw names that resolve to it (proxies, `wormhole_MARKER`, `worldgen_chesspieces`). |
| `swap` | Swap-dependent prefab: `category`, `option`, `primary`. Non-primary ones only appear with that swap. |
| `empirical` | Over `worlds.total` worlds: `worlds`, `share`, `min`/`median`/`max`/`mean` (zeros included), `min_when_present`, `always` (in every world), `unique` (never more than 1). |
| `static_only_reason` | Set when it was never seen: rare set piece, cave-only, or setting/event dependent. |
| `icons` | Atlas references (paths relative to the install's `data/`): `inventory` (`images/inventoryimages*.xml` inside `databundles/images.zip`, element `<id>.tex`) and `minimap` (`minimap/minimap_data*.xml`, element name). `match`: `name` (element named after the prefab), `prefab_file` (a literal `SetIcon` in its prefab file), `hand` (`names.py`), `variant:<id>` (borrowed from a variant). `minimap_candidates` when it was ambiguous. |

## Caveats

- **Only worldgen.** Counts are `savedata.ents` at world creation. Anything spawned later by game systems is not
  there: hounds, Deerclops, Bearger, Klaus and its sack, Antlion sinkholes, Bee Queen, Crab King, Dragonfly itself,
  Moose/Goose, pengulls, tumbleweeds, Wagstaff/moonstorm, sea hounds, etc. Their spawners/markers are, and have
  creature display names (`dragonfly_spawner` → Dragonfly).
- **Container contents are runtime.** Chests, skeletons and boats get their loot from `scenario` scripts after load
  (`chest_abandonedboat`, `sunkenchest_oceanmonument`, `chest_terrarium*`), so contents listed for a set piece are
  only the objects the layout places, plus scenario names.
- **Default settings only.** Anything behind a non-default option or a special event (Hallowed Nights pumpkins,
  `HalloweenPumpkinCarving`, pig-village `pumpkin_lantern`) is listed with `default: false`. World size, branching,
  touch stones, starting variety and the resource sliders change counts and the RNG stream.
- **Emulator worlds.** Most of the empirical sample comes from the worldsim emulator (it matches the real game on all
  validated seeds). In the 300-seed run, two seeds crashed the emulator (`114021`, `955923`: `bad_alloc` right after
  `poly.size() == 0` on a `COVE_0:Blank` node, during a retry attempt). The real game generates both (2 and 3
  attempts), so this is an emulator bug; they were run with realgen instead (`build/catalog/build/realgen/<seed>/`, traces kept for
  debugging, picked up by `build_catalog.py`). Four seeds (`324837`, `700523`, `728448`, `898441`) give up after 5
  attempts in the emulator and also in the real game (logs in `build/catalog/build/realgen/`), like seed 11; they are excluded
  (`worlds.failed`). `regen.sh` doesn't rerun realgen: after a regen, check `build/catalog/build/run_worlds.log` for `no-world`
  seeds and run `REALGEN_PORT=11001 $REALGEN_DIR/run.sh <seed> build/catalog/build/realgen/<seed>` for them (one at a time or with
  different ports in 10998..11018; LAN servers fall back to 10999 and clash).
- **Rare prefabs.** Items only in rare POIs (`skeleton_dapper`, `skeleton_researchlab*`: ~0.03 % of worlds) are
  statically placeable but usually absent from the sample. Their empirical fields are zero.
- **Icons are references only.** `.tex` files are Klei KTEX textures and need a converter such as `ktools`
  (`ktech`), which isn't available here. Only atlas files and element names are recorded; many mobs, plants and
  markers have no minimap icon in the game at all. Check the game's terms of use before serving extracted art.
- **Names.** Several prefabs share a game name (four boulders, three berry bushes). Keep ids for precision; the
  display names add a qualifier. Task display names are suggestions (the game only has internal ids).
