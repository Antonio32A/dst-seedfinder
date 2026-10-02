import Base
import ../f64/repr.bend as F64Repr
import ../worldsim/grid.bend as Grid
import ../worldsim/tiles/groups.bend as TileGroups
import ../worldsim/tiles/topology.bend as TileTopology
import ../worldsim/tiles/convert.bend as TileConvert
import ../worldsim/tiles/disconnect.bend as TileDisconnect
import ../worldsim/noise/perlin.bend as Perlin
import ../rng/pcg.bend as Pcg
import ../populate/layout.bend as PopulateLayout
import ../populate/entities.bend as Entities
import ../populate/counts.bend as PopulateCounts
import ../ocean/pow.bend as OceanPow
import ../data/ocean_post.bend as OceanPostData
import ../ocean/ents.bend as OceanEnts
import ../populate/setpiece.bend as PopulateSetpiece
import ../ocean/monkey.bend as Monkey
import ../ocean/post.bend as OceanPost
import ../ocean/bunches.bend as Bunches
import ../f32/ops.bend as F32Ops
import ../ocean/convert.bend as OceanConvert
import ../ocean/convert_noise.bend as ConvertNoise
import ../ocean/convert_blend.bend as ConvertBlend
import ../populate/pins.bend as PopulatePins

# Lane G (grid) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: tiny U32 golden values, each probed alone first.
# Golden values: the emulator's C++ (SameTask verbatim from worldsim/src/tiles.cpp, FNV-1a as the oracle sink
# computes it) and the game Lua (tile ranges, NoiseTileFunctions via gen/out/*.json; the layout laws:
# object_layout.ConvertLayoutToEntitylist under the harness).

law grid_fnv_header_cell:
  {Grid.fnv_u16(Grid.fnv_u32(Grid.fnv_offset(), 425), 1) == Grid.Hash{2769472162, 1664137574} : Grid.Hash}

def grid_fnv_header_cell():
  {==}

law tiles_validate_ground:
  {(TileGroups.validate_ground(120) * 65536 + TileGroups.validate_ground(1) * 256 + TileGroups.validate_ground(6) : U32) == 262918 : U32}

def tiles_validate_ground():
  {==}

law tiles_noise_resolve:
  {TileConvert.resolve(TileConvert.resolver(120), F64Repr.F64{1070805811, 858993459}) == 46 : U32}

def tiles_noise_resolve():
  {==}

law tiles_same_task:
  {(Bool.to_u32(TileTopology.same_task_rest(0, 101, 100, 1, 101, 100))
    + Bool.to_u32(TileTopology.same_task_rest(0, 101, 100, 2, 102, 100)) * 2
    + Bool.to_u32(TileTopology.same_task_rest(0, 101, 100, 3, 103, 4294967295)) * 4
    + Bool.to_u32(TileTopology.same_task_rest(5, 4294967295, 4294967295, 3, 103, 4294967295)) * 8
    + Bool.to_u32(TileTopology.same_task_rest(3, 103, 4294967295, 4, 103, 4294967295)) * 16
    + Bool.to_u32(TileTopology.same_task_rest(5, 4294967295, 4294967295, 6, 4294967295, 4294967295)) * 32
    + Bool.to_u32(TileTopology.same_task_rest(0, 101, 100, 101, 100, 4294967295)) * 64
    + Bool.to_u32(TileTopology.same_task_rest(2, 102, 100, 0, 101, 100)) * 128 : U32) == 251 : U32}

def tiles_same_task():
  {==}

law layout_default_start:
  {PopulateLayout.check_code(PopulateLayout.convert(0, 25, Pcg.at_counter(1, 0)), 1) == 2583074900 : U32}

def layout_default_start():
  {==}

law layout_mushroom_ring:
  {PopulateLayout.check_code(PopulateLayout.convert(0, 62, Pcg.at_counter(1, 0)), 1) == 3519284001 : U32}

def layout_mushroom_ring():
  {==}

law populate_entity_offset:
  {Entities.entity(0, F64Repr.from_u32(197), F64Repr.from_u32(185), 425, 425, True{}, Pcg.at_counter(1, 202333))
    == Entities.Ent{0, F64Repr.from_u32(197), F64Repr.from_u32(185), F64Repr.F64{3226375618, 2405181686}, F64Repr.F64{3227234795, 2233382994}, 4294961179,
      4294956218, Pcg.at_counter(1, 202335)} : Entities.Ent}

def populate_entity_offset():
  {==}

law populate_rare_count:
  {PopulateCounts.count_of(80, 0, 425, Pcg.at_counter(1, 1002)) == (2, Pcg.at_counter(1, 1004)) : U32 & Pcg.Rng}

def populate_rare_count():
  {==}

# M10 (ocean) laws. Goldens: the real functions (host glibc 2.41 pow, the MSVCR90.dll pow mapped and called), a C
# model of the Windows pow, Python doubles
# (8 - 8/3; floor(213 + 262.87/4)) and SwapOutWormholeMarkers (3 markers: one pair, the odd one dropped).

law ocean_pow_windows_exception_9218:
  {OceanPow.win_output(9218, F64Repr.F64{1056873873, 2364317489}) == F64Repr.F64{1056873873, 2364317490} : F64Repr.F64}

def ocean_pow_windows_exception_9218():
  {==}

law ocean_pow_output_of:
  {OceanPow.output_of(F64Repr.F64{1072060939, 3222690316}) == 3000000000 : U32}

def ocean_pow_output_of():
  {==}

law ocean_dock_two_thirds:
  {Monkey.two_thirds(F64Repr.from_u32(8)) == F64Repr.F64{1075139925, 1431655766} : F64Repr.F64}

def ocean_dock_two_thirds():
  {==}

law ocean_bunch_ground:
  {F64Repr.to_i32(Bunches.ground_of(F64Repr.F64{1081109995, 2233382994}, 425)) == 278 : U32}

def ocean_bunch_ground():
  {==}

law ocean_wormhole_pairs:
  {OceanEnts.count(OceanPost.swap_wormholes(OceanPostData.wormhole_prefab(), [OceanEnts.Ent{OceanPostData.wormhole_marker(), F64Repr.zero(), F64Repr.zero(), 0, 0, 0}, OceanEnts.Ent{OceanPostData.wormhole_marker(), F64Repr.one(), F64Repr.zero(), 0, 0, 0}, OceanEnts.Ent{OceanPostData.wormhole_marker(), F64Repr.two(), F64Repr.zero(), 0, 0, 0}]), OceanPostData.wormhole_prefab()) == 2 : U32}

def ocean_wormhole_pairs():
  {==}

# Five entities (oldest first 10 .. 14) and three placed layouts holding the entries 1..2, none and 4: each member
# takes its layout's number from 1, the rest 0.
law ocean_set_piece_members:
  {OceanEnts.tagged([OceanEnts.Ent{14, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}, OceanEnts.Ent{13, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}, OceanEnts.Ent{12, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}, OceanEnts.Ent{11, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}, OceanEnts.Ent{10, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}], [PopulateSetpiece.Piece{25, 0, 0, F64Repr.zero(), F64Repr.zero(), F64Repr.zero(), 1, 3}, PopulateSetpiece.Piece{25, 0, 0, F64Repr.zero(), F64Repr.zero(), F64Repr.zero(), 3, 3}, PopulateSetpiece.Piece{25, 0, 0, F64Repr.zero(), F64Repr.zero(), F64Repr.zero(), 4, 5}]) == [OceanEnts.Ent{14, F64Repr.zero(), F64Repr.zero(), 0, 0, 3}, OceanEnts.Ent{13, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}, OceanEnts.Ent{12, F64Repr.zero(), F64Repr.zero(), 0, 0, 1}, OceanEnts.Ent{11, F64Repr.zero(), F64Repr.zero(), 0, 0, 1}, OceanEnts.Ent{10, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}] : List<&2, OceanEnts.Ent>}

def ocean_set_piece_members():
  {==}

# Ocean_ConvertImpassibleToWater.

law ocean_convert_gradient_coefs:
  {ConvertNoise.coefs() == ConvertNoise.Coefs{1178993290, 404363545} : ConvertNoise.Coefs}

def ocean_convert_gradient_coefs():
  {==}

law ocean_convert_level_threshold:
  {ConvertBlend.smallest_above(F64Repr.F64{1071434956, 3435973837}) == F32Ops.from_bits(1055286887) : F32}

def ocean_convert_level_threshold():
  {==}

law ocean_convert_el_levels:
  {ConvertBlend.el_levels() == ConvertBlend.Levels{[ConvertBlend.Level{205, 1065353216}, ConvertBlend.Level{201, 1063675494}, ConvertBlend.Level{203, 1053609165}, ConvertBlend.Level{204, 0}, ConvertBlend.Level{207, 0}, ConvertBlend.Level{1, 0}], 1065353216} : ConvertBlend.Levels}

def ocean_convert_el_levels():
  {==}

law ocean_convert_edge_falloff:
  {ConvertBlend.falloff(16, 200, 425, 425) == F64Repr.F64{1070596096, 0} : F64Repr.F64}

def ocean_convert_edge_falloff():
  {==}

law ocean_convert_void_step:
  {OceanConvert.calc_next(F64Repr.F64{1072483532, 3435973837}, OceanConvert.Walk{10, 10, 9}, OceanConvert.middle()) == OceanConvert.Next{10, OceanConvert.Walk{10, 10, 10}} : OceanConvert.Next}

def ocean_convert_void_step():
  {==}

# M12 (lanes G/S performance) laws. Goldens: the oracle's pent record of populate_entity_offset (Entities.tile_entity, the
# integer-centred path, must give the same entity) and the C ImprovedNoise of worldsim/src/tiles.cpp at (x / 8, y / 8,
# 0) ((1092, 516) is a noise value of exactly 1, where the integer sum wraps).

law populate_tile_entity_offset:
  {Entities.tile_entity(0, 197, 185, 425, 425, True{}, Pcg.at_counter(1, 202333))
    == Entities.Ent{0, F64Repr.from_u32(197), F64Repr.from_u32(185), F64Repr.F64{3226375618, 2405181686}, F64Repr.F64{3227234795, 2233382994}, 4294961179,
      4294956218, Pcg.at_counter(1, 202335)} : Entities.Ent}

def populate_tile_entity_offset():
  {==}

law tiles_noise_eighths_one:
  {Perlin.eighths_value(1092, 516) == F64Repr.F64{1072693248, 0} : F64Repr.F64}

def tiles_noise_eighths_one():
  {==}

law tiles_noise_eighths_mid:
  {Perlin.eighths_value(3, 5) == F64Repr.F64{1071283952, 0} : F64Repr.F64}

def tiles_noise_eighths_mid():
  {==}

# The closures that counts.bend and layout.bend port by hand are found by id, and an unknown id counts 0: each port is
# pinned to the fingerprint of the game code it ports, so a regeneration that renumbers or edits a closure fails here.
law ported_closures_line_up:
  {PopulatePins.line_up(PopulatePins.ported()) == True{} : Bool}

def ported_closures_line_up():
  {==}

law ported_closures_are_all_pinned:
  {PopulatePins.every_ported_closure_is_pinned() == True{} : Bool}

def ported_closures_are_all_pinned():
  {==}

# DetectDisconnect goldens: the count of the real caves shard's attempts matches for seeds 1..120 (the game's engine call
# under the groundtruth harness); here a 4x4 map of grass with a column of impassable at x = 2 cuts x = 3 off from (0, 0).
def walled_column() -> Grid.Grid:
  Grid.put(Grid.put(Grid.put(Grid.put(Grid.new(4, 4, 6), 2, 1), 6, 1), 10, 1), 14, 1)

law disconnect_counts_the_cut_off_column:
  {Pair.snd(Grid.Grid, U32, TileDisconnect.detect(walled_column(), 0, 0)) == 4 : U32}

def disconnect_counts_the_cut_off_column():
  {==}

law disconnect_fails_past_five_percent:
  {TileDisconnect.exceeds(9032, 425, 425) == True{} : Bool}

def disconnect_fails_past_five_percent():
  {==}

law disconnect_passes_at_five_percent:
  {TileDisconnect.exceeds(9031, 425, 425) == False{} : Bool}

def disconnect_passes_at_five_percent():
  {==}
