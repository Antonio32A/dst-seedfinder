import Base
import ../rng/pcg.bend as Pcg
import ../cli/args.bend as Args
import ../filters/config.bend as Config
import ../filters/cave_config.bend as CaveConfig
import ../filters/cave_setpiece.bend as CaveFilter
import ../level/cave_prefix.bend as CavePrefix
import ../level/cave_summary.bend as CaveSummary
import ../data/cave_catalog.bend as CaveCatalog
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../storygen/catalog.bend as StoryCatalog
import ../gen/cave_custom.bend as CaveCustom

# Caves laws. The golden values are the real caves worlds of build 747465 (scripts/groundtruth, seed 1 of
# build/groundtruth/data/worlds_caves): the level table decodes byte for byte into the dumped tasks and set pieces,
# and the draw counts are the dump's rng_checkpoints (choose_tasks 21).

# Prefab swaps (twiggy trees, the grass gekko is excluded in the caves), the picked optional tasks as optional indices
# in chosen order, the chosen task masks and the PCG32 state after 21 draws.
law cave_seed_1_prefix:
  {CavePrefix.chosen(1) == CavePrefix.Chosen{2, [9, 1, 11, 8, 3, 16, 6, 14], CavePrefix.Masks{4294967295, 169621, 2148007682, False{}}, Pcg.at_counter(1, 21)} : CavePrefix.Chosen}

def cave_seed_1_prefix():
  {==}

# AddSetPeices (Ice Hounds, the boons, lures_and_worms), ChooseSetPieces and the pairs() order of level.set_pieces.
law cave_seed_1_level_table:
  {CaveSummary.summary_json(1) == "{\"prefab_swaps\":{\"grass\":\"regular grass\",\"twigs\":\"twiggy trees\",\"berries\":\"regular berries\"},\"tasks\":[{\"task\":\"MudWorld\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"MudCave\",\"set_pieces\":[\"WoodBoon\"],\"random_set_pieces\":[]},{\"task\":\"MudLights\",\"set_pieces\":[\"TentaclePillar\",\"ResurrectionStone\"],\"random_set_pieces\":[]},{\"task\":\"MudPit\",\"set_pieces\":[\"Level2GrassBoon\",\"Ice Hounds\"],\"random_set_pieces\":[]},{\"task\":\"BigBatCave\",\"set_pieces\":[\"TentaclePillarToAtrium\"],\"random_set_pieces\":[]},{\"task\":\"RockyLand\",\"set_pieces\":[\"TentaclePillar\",\"skeleton_notplayer\"],\"random_set_pieces\":[]},{\"task\":\"RedForest\",\"set_pieces\":[\"ResurrectionStone\"],\"random_set_pieces\":[]},{\"task\":\"GreenForest\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"BlueForest\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"SpillagmiteCaverns\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"MoonCaveForest\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"ArchiveMaze\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask1\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask2\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask3\",\"set_pieces\":[\"MiscBoon\"],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask4\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask5\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask6\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask7\",\"set_pieces\":[\"Level2WoodBoon\"],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask8\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask9\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CaveExitTask10\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"CentipedeCaveTask\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"ToadStoolTask1\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"ToadStoolTask2\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"ToadStoolTask3\",\"set_pieces\":[\"RockBoon\"],\"random_set_pieces\":[]},{\"task\":\"LichenLand\",\"set_pieces\":[\"lures_and_worms\"],\"random_set_pieces\":[]},{\"task\":\"Residential\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"Military\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"Sacred\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"TheLabyrinth\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"SacredAltar\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"AtriumMaze\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"SpiderLand\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"CaveSwamp\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"MoreAltars\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"RabbitCity\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"PleasantSinkhole\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"Residential2\",\"set_pieces\":[],\"random_set_pieces\":[]},{\"task\":\"BatCloister\",\"set_pieces\":[\"TentaclePillar\"],\"random_set_pieces\":[]},{\"task\":\"MilitaryPits\",\"set_pieces\":[],\"random_set_pieces\":[]}]}" : String}

def cave_seed_1_level_table():
  {==}

law cave_grass_gekko_is_excluded:
  {CaveCatalog.swaps_possible() == 6 : U32}

def cave_grass_gekko_is_excluded():
  {==}

law shard_flag_values:
  {(Args.shard_flag(None{}), (Args.shard_flag(Some{"forest"}), (Args.shard_flag(Some{"caves"}), Args.shard_flag(Some{"nether"})))) == (Done{0}, (Done{1}, (Done{2}, Fail{(2, "--shard must be forest or caves, got \"nether\"")}))) : (Result<&1, &1, U32 & String, U32> & (Result<&1, &1, U32 & String, U32> & (Result<&1, &1, U32 & String, U32> & Result<&1, &1, U32 & String, U32>)))}

def shard_flag_values():
  {==}

law forest_config_accepts_the_shard_key:
  {Config.config_of("{\"shard\": \"forest\"}") == Done{Config.Config{True{}, [], [], None{}, [Config.anything()]}} : Result<&1, &1, U32 & String, Config.Config>}

def forest_config_accepts_the_shard_key():
  {==}

law config_rejects_an_unknown_shard:
  {Config.config_of("{\"shard\": \"nether\"}") == Fail{(2, "config: unknown shard \"nether\" (forest or caves)")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_an_unknown_shard():
  {==}

law config_names_its_shard:
  {(Config.shard_named("{\"shard\": \"caves\"}"), (Config.shard_named("{\"shard\": \"forest\"}"), (Config.shard_named("{}"), Config.shard_named("[")))) == (2, (1, (0, 0))) : (U32 & (U32 & (U32 & U32)))}

def config_names_its_shard():
  {==}

law cave_config_tasks:
  {CaveConfig.config_of("{\"shard\": \"caves\", \"criteria\": [{\"tasks\": {\"required\": [\"MoreAltars\"], \"excluded\": [\"MudWorld\"]}}]}") == Done{CaveConfig.Config{True{}, [CaveConfig.Criteria{CaveConfig.TaskSet{0, 4096}, CaveConfig.TaskSet{1, 0}, 0, 0, []}], [CaveConfig.Criteria{CaveConfig.TaskSet{0, 4096}, CaveConfig.TaskSet{1, 0}, 0, 0, []}]}} : Result<&1, &1, U32 & String, CaveConfig.Config>}

def cave_config_tasks():
  {==}

law cave_config_rejects_forest_tasks:
  {CaveConfig.config_of("{\"criteria\": [{\"tasks\": {\"required\": [\"Great Plains\"]}}]}") == Fail{(2, "config: unknown task \"Great Plains\" in criteria[0].tasks.required")} : Result<&1, &1, U32 & String, CaveConfig.Config>}

def cave_config_rejects_forest_tasks():
  {==}

law cave_config_rejects_the_gekko:
  {CaveConfig.config_of("{\"criteria\": [{\"prefab_swaps\": {\"grass\": \"grass gekko\"}}]}") == Fail{(2, "config: unknown prefab swap \"grass\": \"grass gekko\" in criteria[0].prefab_swaps")} : Result<&1, &1, U32 & String, CaveConfig.Config>}

def cave_config_rejects_the_gekko():
  {==}

law cave_config_rejects_world_sections:
  {CaveConfig.config_of("{\"criteria\": [{\"counts\": [{\"prefab\": \"rook\"}]}]}") == Fail{(2, "config: criteria[0].counts is not supported for the caves shard yet (only tasks, prefab_swaps and setpieces are)")} : Result<&1, &1, U32 & String, CaveConfig.Config>}

def cave_config_rejects_world_sections():
  {==}

law cave_config_rejects_forest_set_pieces:
  {CaveConfig.config_of("{\"criteria\": [{\"setpieces\": [{\"required\": {\"CaveEntrance\": 1}}]}]}") == Fail{(2, "config: unknown set piece \"CaveEntrance\" in criteria[0].setpieces[0].required")} : Result<&1, &1, U32 & String, CaveConfig.Config>}

def cave_config_rejects_forest_set_pieces():
  {==}

law cave_config_set_pieces:
  {CaveConfig.config_of("{\"criteria\": [{\"setpieces\": [{\"tasks\": [\"MudWorld\"], \"required\": {\"MiscBoon\": [1, 2]}}]}]}") == Done{CaveConfig.Config{True{}, [CaveConfig.Criteria{CaveConfig.TaskSet{0, 0}, CaveConfig.TaskSet{0, 0}, 0, 0, [CaveConfig.Rule{32, CaveConfig.TaskSet{1, 0}, 1, 2}]}], [CaveConfig.Criteria{CaveConfig.TaskSet{0, 0}, CaveConfig.TaskSet{0, 0}, 0, 0, [CaveConfig.Rule{32, CaveConfig.TaskSet{1, 0}, 1, 2}]}]}} : Result<&1, &1, U32 & String, CaveConfig.Config>}

def cave_config_set_pieces():
  {==}

# Seed 1 has MoreAltars (id 44, bit 12 of the second word) and seed 3 has not.
law cave_config_matches_by_task:
  {(CaveConfig.matches([CaveConfig.Criteria{CaveConfig.TaskSet{0, 4096}, CaveConfig.TaskSet{0, 0}, 0, 0, []}], 1), CaveConfig.matches([CaveConfig.Criteria{CaveConfig.TaskSet{0, 4096}, CaveConfig.TaskSet{0, 0}, 0, 0, []}], 3)) == (True{}, False{}) : (Bool & Bool)}

def cave_config_matches_by_task():
  {==}

# Seed 1 has twiggy trees (bit 1 of the swaps) and no grass gekko (bit 0, which the caves never take).
law cave_config_matches_by_swap:
  {(CaveConfig.matches([CaveConfig.Criteria{CaveConfig.TaskSet{0, 0}, CaveConfig.TaskSet{0, 0}, 2, 2, []}], 1), CaveConfig.matches([CaveConfig.Criteria{CaveConfig.TaskSet{0, 0}, CaveConfig.TaskSet{0, 0}, 1, 1, []}], 1)) == (True{}, False{}) : (Bool & Bool)}

def cave_config_matches_by_swap():
  {==}

law cave_setpiece_filter:
  {CaveFilter.parse(["MiscBoon:2", "TentaclePillar:1:10"], Done{Nil{}}) == Done{[CaveFilter.Bound{2, 1, 10}, CaveFilter.Bound{32, 2, 255}]} : Result<&1, &1, U32 & String, List<&2, CaveFilter.Bound>>}

def cave_setpiece_filter():
  {==}

law cave_setpiece_filter_rejects_forest_pieces:
  {CaveFilter.parse(["MooseNest"], Done{Nil{}}) == Fail{(2, "unknown set piece: MooseNest")} : Result<&1, &1, U32 & String, List<&2, CaveFilter.Bound>>}

def cave_setpiece_filter_rejects_forest_pieces():
  {==}

# Caves room and task ids sit above the forest's rows, so one id says which table it belongs to.
law cave_ids_sit_above_the_forest_rows:
  {((Rooms.rooms_count() <= StoryCatalog.cave_room_base() : U32), (Tasks.task_count() <= StoryCatalog.cave_task_base() : U32)) == (True{}, True{}) : (Bool & Bool)}

def cave_ids_sit_above_the_forest_rows():
  {==}

law story_catalog_names_both_shards:
  {(StoryCatalog.task_name(0), (StoryCatalog.task_name(StoryCatalog.caves_task_id(0)), StoryCatalog.task_name(StoryCatalog.caves_task_id(8)))) == ("Make a pick", ("MudWorld", "BlueForest")) : (String & (String & String))}

def story_catalog_names_both_shards():
  {==}

law cave_custom_layer_counts_run_down:
  {CaveCustom.decremented([5, 10, 3], 1) == [5, 9, 3] : List<&2, U32>}

def cave_custom_layer_counts_run_down():
  {==}
