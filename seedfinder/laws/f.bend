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
import ../populate/setpiece.bend as PopulateSetpiece
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
  {FilterDump.of_bytes([68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]) == Done{FilterDump.GaveUp{7, 2, 0}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_gave_up():
  {==}

law dump_format_1_rejected:
  {FilterDump.of_bytes([68, 83, 84, 87, 1, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0]) == Fail{(2, "world dump format 1, regenerate it (this finder reads format 3)")} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_format_1_rejected():
  {==}

law dump_format_2_rejected:
  {FilterDump.of_bytes([68, 83, 84, 87, 2, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0]) == Fail{(2, "world dump format 2, regenerate it (this finder reads format 3)")} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_format_2_rejected():
  {==}

law dump_caves_gave_up:
  {FilterDump.of_bytes(FilterDump.bytes(FilterDump.GaveUp{7, 2, 1})) == Done{FilterDump.GaveUp{7, 2, 1}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_caves_gave_up():
  {==}

# A caves world reads back with its shard and its tentacle pillar links (the PILL section).
law dump_round_trip_caves:
  {FilterDump.of_bytes(FilterDump.bytes(FilterDump.Generated{7, 2, 1, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [FilterDump.Prefab{"tentacle_pillar", [FilterDump.Position{1, 2}, FilterDump.Position{3, 4}]}, FilterDump.Prefab{"tentacle_pillar_atrium", [FilterDump.Position{5, 6}]}], [], [FilterDump.Pillar{0, 0, 0, 1}, FilterDump.Pillar{0, 1, 1, 0}], None{}, None{}})) == Done{FilterDump.Generated{7, 2, 1, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [FilterDump.Prefab{"tentacle_pillar", [FilterDump.Position{1, 2}, FilterDump.Position{3, 4}]}, FilterDump.Prefab{"tentacle_pillar_atrium", [FilterDump.Position{5, 6}]}], [], [FilterDump.Pillar{0, 0, 0, 1}, FilterDump.Pillar{0, 1, 1, 0}], None{}, None{}}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_round_trip_caves():
  {==}

# The forest finder refuses a caves dump, generated or not.
law world_refuses_caves:
  {FilterWorld.of_bytes(FilterDump.bytes(FilterDump.Generated{7, 2, 1, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [FilterDump.Prefab{"tentacle_pillar", [FilterDump.Position{1, 2}, FilterDump.Position{3, 4}]}, FilterDump.Prefab{"tentacle_pillar_atrium", [FilterDump.Position{5, 6}]}], [], [FilterDump.Pillar{0, 0, 0, 1}, FilterDump.Pillar{0, 1, 1, 0}], None{}, None{}})) == Fail{(2, "world dump of the caves shard, this finder searches the forest shard")} : Result<&1, &1, U32 & String, FilterWorld.Loaded>}

def world_refuses_caves():
  {==}

law world_refuses_caves_gave_up:
  {FilterWorld.of_bytes(FilterDump.bytes(FilterDump.GaveUp{7, 2, 1})) == Fail{(2, "world dump of the caves shard, this finder searches the forest shard")} : Result<&1, &1, U32 & String, FilterWorld.Loaded>}

def world_refuses_caves_gave_up():
  {==}

# Seed 7 on Linux, build 747465, 3 x 1 tiles GRASS GRASS IMPASSABLE.
law dump_tiles:
  {FilterDump.of_bytes([68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0]) == Done{FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [], [], [], None{}, None{}}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_tiles():
  {==}

# The same world with a moonbase at (602, 106) and a wormhole pair at (284, -116) and (-484, -140.5).
law dump_entities_and_links:
  {FilterDump.of_bytes([68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]) == Done{FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}], [], None{}, None{}}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_entities_and_links():
  {==}

# The same world with the set piece of dump_writes_set_pieces.
law dump_set_pieces:
  {FilterDump.of_bytes([68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 83, 69, 84, 80, 64, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 72, 117, 116, 0, 1, 0, 0, 0, 5, 0, 0, 0, 32, 3, 0, 0, 112, 254, 255, 255, 0, 0, 0, 0, 80, 251, 255, 255, 64, 6, 0, 0, 144, 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]) == Done{FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}], [], Some{[FilterDump.Piece{"Hut", 1, 5, 800, 4294966896, 0, 4294966096, 1600, 400, [FilterDump.Member{0, 1}, FilterDump.Member{1, 0}]}]}, None{}}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_set_pieces():
  {==}

# The same world with an unknown XXXX section before and after the others.
law dump_skips_unknown_sections:
  {FilterDump.of_bytes([68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 88, 88, 88, 88, 8, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 88, 88, 88, 88, 8, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0]) == Done{FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}], [], None{}, None{}}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_skips_unknown_sections():
  {==}

# A prefab's instances are found by name, others (in the vocabulary or not) are skipped, and the indices stay those of
# the dump. Positions are k / 100 (IEEE bits), and the flags say which of x, z is whole.
law world_group_by_name:
  {FilterWorld.group_of([FilterDump.Prefab{"not_a_prefab", [FilterDump.Position{0, 0}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], "wormhole", 338) == [FilterWorld.Inst{338, 0, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 28400, 4294955696, 3}, FilterWorld.Inst{338, 1, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 4294918896, 4294953246, 1}] : List<&2, FilterWorld.Inst>}

def world_group_by_name():
  {==}

# The ROAD section of two roads: weight 3 with three points and weight 1 with one, positions in hundredths (int32 bits).
law dump_writes_roads:
  {FilterDump.roads_section([FilterDump.Road{3, [FilterDump.Position{1, 2}, FilterDump.Position{3, 4}, FilterDump.Position{4294967295, 6}]}, FilterDump.Road{1, [FilterDump.Position{10, 20}]}]) == [82, 79, 65, 68, 52, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 255, 255, 255, 255, 6, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 20, 0, 0, 0] : List<&2, U32>}

def dump_writes_roads():
  {==}

# A dump with roads reads back with them; one without a ROAD section has none.
law dump_round_trip_roads:
  {FilterDump.of_bytes(FilterDump.bytes(FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [], [], [], None{}, Some{[FilterDump.Road{3, [FilterDump.Position{1, 2}, FilterDump.Position{3, 4}, FilterDump.Position{4294967295, 6}]}, FilterDump.Road{1, [FilterDump.Position{10, 20}]}]}})) == Done{FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [], [], [], None{}, Some{[FilterDump.Road{3, [FilterDump.Position{1, 2}, FilterDump.Position{3, 4}, FilterDump.Position{4294967295, 6}]}, FilterDump.Road{1, [FilterDump.Position{10, 20}]}]}}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_round_trip_roads():
  {==}

law dump_without_roads_has_none:
  {FilterDump.of_bytes(FilterDump.bytes(FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [], [], [], None{}, None{}})) == Done{FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [], [], [], None{}, None{}}} : Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_without_roads_has_none():
  {==}

# A road coordinate on a 10 tile map (centre 5): 10 * floor((p - 5) * 40) in doubles, so a float just under an integer
# floors down and a negative one goes away from zero. The values are float32 widened: 5.1, 4.95, 6.45, 5.35, 5.05, 3.3.
law dump_road_units_0:
  {SaveData.road_units(F64Repr.F64{1075078758, 1610612736}, F64Repr.F64{1075052544, 0}) == 30 : U32}

def dump_road_units_0():
  {==}

law dump_road_units_1:
  {SaveData.road_units(F64Repr.F64{1075039436, 3221225472}, F64Repr.F64{1075052544, 0}) == 4294967266 : U32}

def dump_road_units_1():
  {==}

law dump_road_units_2:
  {SaveData.road_units(F64Repr.F64{1075432652, 3221225472}, F64Repr.F64{1075052544, 0}) == 570 : U32}

def dump_road_units_2():
  {==}

law dump_road_units_3:
  {SaveData.road_units(F64Repr.F64{1075144294, 1610612736}, F64Repr.F64{1075052544, 0}) == 130 : U32}

def dump_road_units_3():
  {==}

law dump_road_units_4:
  {SaveData.road_units(F64Repr.F64{1075065651, 1073741824}, F64Repr.F64{1075052544, 0}) == 20 : U32}

def dump_road_units_4():
  {==}

law dump_road_units_5:
  {SaveData.road_units(F64Repr.F64{1074423398, 1610612736}, F64Repr.F64{1075052544, 0}) == 4294966606 : U32}

def dump_road_units_5():
  {==}

# A road with fewer points than the length draw is dropped, a kept first road weighs 3 and the others 1.
law dump_roads_saved:
  {SaveData.roads_of([[], [], []], 0, 10) == [FilterDump.Road{3, []}, FilterDump.Road{1, []}, FilterDump.Road{1, []}] : List<&2, FilterDump.Road>}

def dump_roads_saved():
  {==}

law dump_roads_dropped_when_short:
  {SaveData.roads_of([[], []], 1, 10) == [] : List<&2, FilterDump.Road>}

def dump_roads_dropped_when_short():
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

# A set piece "Hut" (source 1, transform 5) centred at (8, -4), bounds (0, -12) to (16, 4), with instance 1 of the
# first ENTS prefab and instance 0 of the second.
law dump_writes_set_pieces:
  {FilterDump.set_pieces_section([FilterDump.Piece{"Hut", 1, 5, 800, 4294966896, 0, 4294966096, 1600, 400, [FilterDump.Member{0, 1}, FilterDump.Member{1, 0}]}]) == [83, 69, 84, 80, 64, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 72, 117, 116, 0, 1, 0, 0, 0, 5, 0, 0, 0, 32, 3, 0, 0, 112, 254, 255, 255, 0, 0, 0, 0, 80, 251, 255, 255, 64, 6, 0, 0, 144, 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def dump_writes_set_pieces():
  {==}

law dump_writes_gave_up:
  {FilterDump.bytes(FilterDump.GaveUp{7, 2, 0}) == [68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def dump_writes_gave_up():
  {==}

law dump_writes_generated:
  {FilterDump.bytes(FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}], [], None{}, None{}}) == [68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def dump_writes_generated():
  {==}

law dump_writes_generated_set_pieces:
  {FilterDump.bytes(FilterDump.Generated{7, 2, 0, 747465, 3, 1, [FilterDump.TileName{6, "GRASS"}, FilterDump.TileName{1, "IMPASSABLE"}], [393222, 1], [FilterDump.Prefab{"moonbase", [FilterDump.Position{60200, 10600}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}], [FilterDump.Link{0, 1}, FilterDump.Link{1, 0}], [], Some{[FilterDump.Piece{"Hut", 1, 5, 800, 4294966896, 0, 4294966096, 1600, 400, [FilterDump.Member{0, 1}, FilterDump.Member{1, 0}]}]}, None{}}) == [68, 83, 84, 87, 3, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 201, 103, 11, 0, 3, 0, 0, 0, 1, 0, 0, 0, 84, 78, 65, 77, 40, 0, 0, 0, 2, 0, 0, 0, 6, 0, 0, 0, 5, 0, 0, 0, 71, 82, 65, 83, 83, 0, 0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 73, 77, 80, 65, 83, 83, 65, 66, 76, 69, 0, 0, 84, 73, 76, 69, 8, 0, 0, 0, 6, 0, 6, 0, 1, 0, 0, 0, 69, 78, 84, 83, 60, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 109, 111, 111, 110, 98, 97, 115, 101, 1, 0, 0, 0, 40, 235, 0, 0, 104, 41, 0, 0, 8, 0, 0, 0, 119, 111, 114, 109, 104, 111, 108, 101, 2, 0, 0, 0, 240, 110, 0, 0, 176, 210, 255, 255, 240, 66, 255, 255, 30, 201, 255, 255, 87, 79, 82, 77, 20, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 83, 69, 84, 80, 64, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 72, 117, 116, 0, 1, 0, 0, 0, 5, 0, 0, 0, 32, 3, 0, 0, 112, 254, 255, 255, 0, 0, 0, 0, 80, 251, 255, 255, 64, 6, 0, 0, 144, 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def dump_writes_generated_set_pieces():
  {==}

# A 3 x 3 world on Linux (IMPASSABLE in the middle of GRASS) with, oldest first, a wormhole, a wormhole_MARKER (outside
# the catalog), an armorgrass at (0.125, -0.125) (a rounding tie) and the other wormhole: the dump of its savedata reads
# back as the filters' world of it.
law dump_round_trip:
  {FilterWorld.of_bytes(FilterDump.bytes(SaveData.dump(7, False{}, GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0}, [OceanEnts.Ent{611, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10, 0}, OceanEnts.Ent{547, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0, 0}, OceanEnts.Ent{546, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 0, 0, 0}, OceanEnts.Ent{611, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 10, 11, 0}], 3, [], [], 3}))) == Done{FilterWorld.Generated{SaveData.world(7, False{}, GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0}, [OceanEnts.Ent{611, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10, 0}, OceanEnts.Ent{547, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0, 0}, OceanEnts.Ent{546, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 0, 0, 0}, OceanEnts.Ent{611, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 10, 11, 0}], 3, [], [], 3}), 2}} : Result<&1, &1, U32 & String, FilterWorld.Loaded>}

def dump_round_trip():
  {==}

# The same world on Windows: every prefab in name order (the catalog's or not, and the pocket dimension containers at
# (0, 0)), instances in savedata order, and the tie rounded away from zero.
law dump_prefabs_in_name_order:
  {FilterDump.prefabs(SaveData.dump(7, True{}, GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0}, [OceanEnts.Ent{611, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10, 0}, OceanEnts.Ent{547, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0, 0}, OceanEnts.Ent{546, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 0, 0, 0}, OceanEnts.Ent{611, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 10, 11, 0}], 3, [], [], 3})) == [FilterDump.Prefab{"armorgrass", [FilterDump.Position{13, 4294967283}]}, FilterDump.Prefab{"rabbitkinghorn_container", [FilterDump.Position{0, 0}]}, FilterDump.Prefab{"shadow_container", [FilterDump.Position{0, 0}]}, FilterDump.Prefab{"wormhole", [FilterDump.Position{28400, 4294955696}, FilterDump.Position{4294918896, 4294953246}]}, FilterDump.Prefab{"wormhole_MARKER", [FilterDump.Position{60200, 10600}]}] : List<&2, FilterDump.Prefab>}

def dump_prefabs_in_name_order():
  {==}

# The same world where the armorgrass and the wormhole_MARKER are the members of a first placed AbandonedBoat1 (source
# 4) centred on tile (1.5, 1) with half-size 0.5, and the newer wormhole the member of a second one (source 5, turned
# 3) at tile (0.5, 0.5) of half-size 0: members by ENTS name order and savedata index, centres and bounds in world
# hundredths.
law dump_set_piece_members:
  {FilterDump.set_pieces(SaveData.dump(7, False{}, GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0}, [OceanEnts.Ent{611, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10, 2}, OceanEnts.Ent{547, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0, 1}, OceanEnts.Ent{546, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 0, 0, 1}, OceanEnts.Ent{611, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 10, 11, 0}], 3, [PopulateSetpiece.Piece{25, 4, 0, F64Repr.F64{1073217536, 0}, F64Repr.F64{1072693248, 0}, F64Repr.F64{1071644672, 0}, 1, 3}, PopulateSetpiece.Piece{25, 5, 3, F64Repr.F64{1071644672, 0}, F64Repr.F64{1071644672, 0}, F64Repr.F64{0, 0}, 3, 4}], [], 3})) == Some{[FilterDump.Piece{"AbandonedBoat1", 4, 0, 0, 4294967096, 4294967096, 4294966896, 200, 0, [FilterDump.Member{0, 0}, FilterDump.Member{4, 0}]}, FilterDump.Piece{"AbandonedBoat1", 5, 3, 4294966896, 4294966896, 4294966896, 4294966896, 4294966896, 4294966896, [FilterDump.Member{3, 1}]}]} : Maybe<&2, List<&2, FilterDump.Piece>>}

def dump_set_piece_members():
  {==}
