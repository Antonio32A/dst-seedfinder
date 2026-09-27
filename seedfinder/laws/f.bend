import Base
import ../filters/json.bend as Json
import ../filters/walk.bend as Walk
import ../filters/anchor.bend as Anchor
import ../filters/straight.bend as Straight
import ../filters/world.bend as FilterWorld
import ../filters/dump.bend as FilterDump
import ../f64/repr.bend as F64Repr
import ../rng/pcg.bend as Pcg
import ../worldsim/grid.bend as Grid
import ../ocean/ents.bend as OceanEnts
import ../gen/job.bend as GenJob
import ../gen/savedata.bend as SaveData

# Lane F (filters and search) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: tiny U32 golden values, each probed alone first.
# Golden values: Python (json.loads grammar, world.py tile_coordinate, numpy distances as IEEE bits).

law json_number_grammar_accepts_exponent:
  {Json.is_number_end(Json.number_state("-0.5e+3", 0)) == True{} : Bool}

def json_number_grammar_accepts_exponent():
  {==}

law json_number_grammar_rejects_leading_zero:
  {Json.number_state("01", 0) == 9 : U32}

def json_number_grammar_rejects_leading_zero():
  {==}

# world.py tile_coordinate(-512, 425) = 85, (283.99, 425) = 283, (284, 425) = 284 (x in hundredths).
law anchor_tile_coordinate_left:
  {Anchor.tile_coordinate(4294916096, 425) == 85 : U32}

def anchor_tile_coordinate_left():
  {==}

law anchor_tile_coordinate_edge:
  {Anchor.tile_coordinate(28399, 425) == 283 : U32}

def anchor_tile_coordinate_edge():
  {==}

# One diagonal step (4*sqrt 2 = 5.65685...) is longer than 5.6568 (q1 = floor(0.6568 * 2^32)).
law walk_diagonal_above_rational:
  {Walk.compare(Walk.Length{0, 0, 0, 1}, Walk.Length{5, 2820934520, 0, 0}) == 2 : U32}

def walk_diagonal_above_rational():
  {==}

law walk_same_diagonals_compare_rational:
  {Walk.compare(Walk.Length{8, 0, 0, 3}, Walk.Length{8, 0, 1, 3}) == 0 : U32}

def walk_same_diagonals_compare_rational():
  {==}

# numpy sqrt((46 - -512)^2 + (402 - -120)^2) = 764.0994699644805 (portal to pigking on world 1).
law straight_distance_portal_pigking:
  {Straight.distance(FilterWorld.Inst{0, 0, F64Repr.F64{1078394880, 0}, F64Repr.F64{1081679872, 0}, 4600, 40200, 3}, FilterWorld.Inst{1, 0, F64Repr.F64{3229614080, 0}, F64Repr.F64{3227385856, 0}, 4294916096, 4294955296, 3}) == F64Repr.F64{1082646731, 3068699398} : F64Repr.F64}

def straight_distance_portal_pigking():
  {==}


# World dumps (docs/world-dump.md): tiny hand-built files.
law dump_gave_up:
  {FilterDump.of_bytes([68, 83, 84, 87, 2, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0]) == Done{FilterDump.GaveUp{7, 2}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_gave_up():
  {==}

law dump_format_1_rejected:
  {FilterDump.of_bytes([68, 83, 84, 87, 1, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0]) == Fail{(2, "world dump format 1, regenerate it (this finder reads format 2)")} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_format_1_rejected():
  {==}

# Seed 7 on Linux, build 747465, 3 x 1 tiles GRASS GRASS IMPASSABLE.
law dump_tiles:
  {FilterDump.of_bytes([68, 83, 84, 87, 2, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0]) == Done{FilterDump.Generated{7, 2, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [], []}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_tiles():
  {==}

# The same world with a moonbase at (602, 106) and a wormhole pair at (284, -116) and (-484, -140.5).
law dump_entities_and_links:
  {FilterDump.of_bytes([68, 83, 84, 87, 2, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]) == Done{FilterDump.Generated{7, 2, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}]}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_entities_and_links():
  {==}

# The same world with an unknown ROAD section before and after the others.
law dump_skips_unknown_sections:
  {FilterDump.of_bytes([68, 83, 84, 87, 2, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 82, 79, 65, 68, 8, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 82, 79, 65, 68, 8, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0]) == Done{FilterDump.Generated{7, 2, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}]}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_skips_unknown_sections():
  {==}

# A prefab's instances are found by name, others (in the vocabulary or not) are skipped, and the indices stay those of
# the dump. Positions are k / 100 (IEEE bits), and the flags say which of x, z is whole.
law world_group_by_name:
  {FilterWorld.group_of([FilterDump.Prefab{"not_a_prefab", [FilterDump.Position{0, 0}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], "wormhole", 338) == [FilterWorld.Inst{338, 0, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 28400, 4294955696, 3}, FilterWorld.Inst{338, 1, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 4294918896, 4294953246, 1}] : List<&2, FilterWorld.Inst>}

def world_group_by_name():
  {==}

# The world dump writer, section by section, on the same world as the reader laws above.
law dump_writes_tile_names:
  {FilterDump.tile_names_section([FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}]) == [84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0] : List<&2, U32>}

def dump_writes_tile_names():
  {==}

law dump_writes_tiles:
  {FilterDump.tiles_section([393222, 1]) == [84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0] : List<&2, U32>}

def dump_writes_tiles():
  {==}

law dump_writes_entities:
  {FilterDump.entities_section([FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}]) == [69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255] : List<&2, U32>}

def dump_writes_entities():
  {==}

law dump_writes_links:
  {FilterDump.links_section([FilterDump.Link{0, 1}, FilterDump.Link{1, 0}]) == [87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def dump_writes_links():
  {==}

law dump_writes_gave_up:
  {FilterDump.bytes(FilterDump.GaveUp{7, 2}) == [68, 83, 84, 87, 2, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0] : List<&2, U32>}

def dump_writes_gave_up():
  {==}

law dump_writes_generated:
  {FilterDump.bytes(FilterDump.Generated{7, 2, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}]}) == [68, 83, 84, 87, 2, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def dump_writes_generated():
  {==}

# A 3 x 3 world on Linux (IMPASSABLE in the middle of GRASS) with, oldest first, a wormhole, a wormhole_MARKER (outside
# the catalog), an armorgrass at (0.125, -0.125) (a rounding tie) and the other wormhole: the dump of its savedata reads
# back as the filters' world of it.
law dump_round_trip:
  {FilterWorld.of_bytes(FilterDump.bytes(SaveData.dump(7, False{}, GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0}, [OceanEnts.Ent{611, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10}, OceanEnts.Ent{547, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0}, OceanEnts.Ent{546, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 0, 0}, OceanEnts.Ent{611, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 10, 11}], 3}))) == Done{FilterWorld.Generated{SaveData.world(7, False{}, GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0}, [OceanEnts.Ent{611, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10}, OceanEnts.Ent{547, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0}, OceanEnts.Ent{546, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 0, 0}, OceanEnts.Ent{611, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 10, 11}], 3}), 2}} : Result<&1, &1, U32 & String, FilterWorld.Loaded>}

def dump_round_trip():
  {==}

# The same world on Windows: every prefab in name order (the catalog's or not, and the pocket dimension containers at
# (0, 0)), instances in savedata order, and the tie rounded away from zero.
law dump_prefabs_in_name_order:
  {FilterDump.prefabs(SaveData.dump(7, True{}, GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0}, [OceanEnts.Ent{611, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10}, OceanEnts.Ent{547, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0}, OceanEnts.Ent{546, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 0, 0}, OceanEnts.Ent{611, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 10, 11}], 3})) == [FilterDump.Prefab{"armorgrass", [FilterDump.Position{13, 4294967283}]}, FilterDump.Prefab{"rabbitkinghorn_container", [FilterDump.Position{0, 0}]}, FilterDump.Prefab{"shadow_container", [FilterDump.Position{0, 0}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}, FilterDump.Prefab{"wormhole_MARKER", [FilterDump.Position{60200, 10600}]}] : List<&2, FilterDump.Prefab>}

def dump_prefabs_in_name_order():
  {==}
