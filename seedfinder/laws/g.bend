import Base
import ../f64/repr.bend as FR
import ../worldsim/grid.bend as GR
import ../worldsim/tiles/groups.bend as TG
import ../worldsim/tiles/topology.bend as TP
import ../worldsim/tiles/convert.bend as TC
import ../worldsim/noise/perlin.bend as NP
import ../rng/pcg.bend as R
import ../populate/layout.bend as PL
import ../populate/entities.bend as PE
import ../populate/counts.bend as PC
import ../ocean/pow.bend as OW
import ../data/ocean_post.bend as OQ
import ../ocean/ents.bend as OE
import ../ocean/monkey.bend as OM
import ../ocean/post.bend as OT
import ../ocean/bunches.bend as OB
import ../f32/ops.bend as FO
import ../ocean/convert.bend as OV
import ../ocean/convert_noise.bend as ON
import ../ocean/convert_blend.bend as OCB

# Lane G (grid) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: .scratch/port/CONVENTIONS.md "Laws" (tiny U32 golden values, each probed alone first).
# Golden values: .scratch/port/test/tiles/law_goldens.cpp (SameTask verbatim from worldsim/src/tiles.cpp, FNV-1a as
# the oracle sink computes it) and the game Lua (tile ranges, NoiseTileFunctions via gen/out/*.json; the layout laws:
# object_layout.ConvertLayoutToEntitylist under the harness, .scratch/port/test/populate/layout_ref.lua).

law grid_fnv_header_cell:
  {GR.fnv_u16(GR.fnv_u32(GR.fnv_offset(), 425), 1) == GR.Hash{2769472162, 1664137574} : GR.Hash}

def grid_fnv_header_cell():
  {==}

law tiles_validate_ground:
  {(TG.validate_ground(120) * 65536 + TG.validate_ground(1) * 256 + TG.validate_ground(6) : U32) == 262918 : U32}

def tiles_validate_ground():
  {==}

law tiles_noise_resolve:
  {TC.resolve(TC.resolver(120), FR.F64{1070805811, 858993459}) == 46 : U32}

def tiles_noise_resolve():
  {==}

law tiles_same_task:
  {(Bool.to_u32(TP.same_task_rest(0, 101, 100, 1, 101, 100))
    + Bool.to_u32(TP.same_task_rest(0, 101, 100, 2, 102, 100)) * 2
    + Bool.to_u32(TP.same_task_rest(0, 101, 100, 3, 103, 4294967295)) * 4
    + Bool.to_u32(TP.same_task_rest(5, 4294967295, 4294967295, 3, 103, 4294967295)) * 8
    + Bool.to_u32(TP.same_task_rest(3, 103, 4294967295, 4, 103, 4294967295)) * 16
    + Bool.to_u32(TP.same_task_rest(5, 4294967295, 4294967295, 6, 4294967295, 4294967295)) * 32
    + Bool.to_u32(TP.same_task_rest(0, 101, 100, 101, 100, 4294967295)) * 64
    + Bool.to_u32(TP.same_task_rest(2, 102, 100, 0, 101, 100)) * 128 : U32) == 251 : U32}

def tiles_same_task():
  {==}

law layout_default_start:
  {PL.check_code(PL.convert(0, 25, R.at_counter(1, 0)), 1) == 2583074900 : U32}

def layout_default_start():
  {==}

law layout_mushroom_ring:
  {PL.check_code(PL.convert(0, 62, R.at_counter(1, 0)), 1) == 3519284001 : U32}

def layout_mushroom_ring():
  {==}

law populate_entity_offset:
  {PE.entity(0, FR.from_u32(197), FR.from_u32(185), 425, 425, True{}, R.at_counter(1, 202333))
    == PE.Ent{0, FR.from_u32(197), FR.from_u32(185), FR.F64{3226375618, 2405181686}, FR.F64{3227234795, 2233382994}, 4294961179,
      4294956218, R.at_counter(1, 202335)} : PE.Ent}

def populate_entity_offset():
  {==}

law populate_rare_count:
  {PC.count_of(80, 0, 425, R.at_counter(1, 1002)) == (2, R.at_counter(1, 1004)) : U32 & R.Rng}

def populate_rare_count():
  {==}

# M10 (ocean) laws. Goldens: the real functions (.scratch/port/test/ocean/pow_ref.c: host glibc 2.41 pow, the
# MSVCR90.dll pow mapped and called), the model of .scratch/port/test/ocean/pow_win_model.h, Python doubles
# (8 - 8/3; floor(213 + 262.87/4)) and SwapOutWormholeMarkers (3 markers: one pair, the odd one dropped).

law ocean_pow_windows_exception_9218:
  {OW.win_output(9218, FR.F64{1056873873, 2364317489}) == FR.F64{1056873873, 2364317490} : FR.F64}

def ocean_pow_windows_exception_9218():
  {==}

law ocean_pow_output_of:
  {OW.output_of(FR.F64{1072060939, 3222690316}) == 3000000000 : U32}

def ocean_pow_output_of():
  {==}

law ocean_dock_two_thirds:
  {OM.two_thirds(FR.from_u32(8)) == FR.F64{1075139925, 1431655766} : FR.F64}

def ocean_dock_two_thirds():
  {==}

law ocean_bunch_ground:
  {FR.to_i32(OB.ground_of(FR.F64{1081109995, 2233382994}, 425)) == 278 : U32}

def ocean_bunch_ground():
  {==}

law ocean_wormhole_pairs:
  {OE.count(OT.swap_wormholes([OE.Ent{OQ.wormhole_marker(), FR.zero(), FR.zero(), 0, 0}, OE.Ent{OQ.wormhole_marker(), FR.one(), FR.zero(), 0, 0}, OE.Ent{OQ.wormhole_marker(), FR.two(), FR.zero(), 0, 0}]), OQ.wormhole_prefab()) == 2 : U32}

def ocean_wormhole_pairs():
  {==}

# Ocean_ConvertImpassibleToWater (goldens: .scratch/port/test/ocean/convert_law_goldens.py).

law ocean_convert_gradient_coefs:
  {ON.coefs() == ON.Coefs{1178993290, 404363545} : ON.Coefs}

def ocean_convert_gradient_coefs():
  {==}

law ocean_convert_level_threshold:
  {OCB.smallest_above(FR.F64{1071434956, 3435973837}) == FO.from_bits(1055286887) : F32}

def ocean_convert_level_threshold():
  {==}

law ocean_convert_el_levels:
  {OCB.el_levels() == OCB.Levels{[OCB.Level{205, 1065353216}, OCB.Level{201, 1063675494}, OCB.Level{203, 1053609165}, OCB.Level{204, 0}, OCB.Level{207, 0}, OCB.Level{1, 0}], 1065353216} : OCB.Levels}

def ocean_convert_el_levels():
  {==}

law ocean_convert_edge_falloff:
  {OCB.falloff(16, 200, 425, 425) == FR.F64{1070596096, 0} : FR.F64}

def ocean_convert_edge_falloff():
  {==}

law ocean_convert_void_step:
  {OV.calc_next(FR.F64{1072483532, 3435973837}, OV.Walk{10, 10, 9}, OV.middle()) == OV.Next{10, OV.Walk{10, 10, 10}} : OV.Next}

def ocean_convert_void_step():
  {==}

# M12 (lanes G/S performance) laws. Goldens: the oracle's pent record of populate_entity_offset (PE.tile_entity, the
# integer-centred path, must give the same entity) and the C ImprovedNoise of worldsim/src/tiles.cpp at (x / 8, y / 8,
# 0) (.scratch/port/test/tiles/perlin_ref.c; (1092, 516) is a noise value of exactly 1, where the integer sum wraps).

law populate_tile_entity_offset:
  {PE.tile_entity(0, 197, 185, 425, 425, True{}, R.at_counter(1, 202333))
    == PE.Ent{0, FR.from_u32(197), FR.from_u32(185), FR.F64{3226375618, 2405181686}, FR.F64{3227234795, 2233382994}, 4294961179,
      4294956218, R.at_counter(1, 202335)} : PE.Ent}

def populate_tile_entity_offset():
  {==}

law tiles_noise_eighths_one:
  {NP.eighths_value(1092, 516) == FR.F64{1072693248, 0} : FR.F64}

def tiles_noise_eighths_one():
  {==}

law tiles_noise_eighths_mid:
  {NP.eighths_value(3, 5) == FR.F64{1071283952, 0} : FR.F64}

def tiles_noise_eighths_mid():
  {==}
