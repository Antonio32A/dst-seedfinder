import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../f64/hypot.bend as FH
import ../f64/random.bend as FX
import ../worldsim/layout/space.bend as KS
import ../worldsim/layout/kk.bend as KK

# Lane N (numeric) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: .scratch/port/CONVENTIONS.md "Laws" (tiny U32 golden values, each probed alone first).
# Golden values: x86-64 SSE2 and glibc (.scratch/port/exp/f64m1/golden.c).

law f64_add_one_two:
  {FA.add(FR.one(), FR.two()) == FR.F64{1074266112, 0} : FR.F64}

def f64_add_one_two():
  {==}

law f64_add_tie_even:
  {FA.add(FR.one(), FR.F64{1017118720, 0}) == FR.one() : FR.F64}

def f64_add_tie_even():
  {==}

law f64_add_three_halves_ulp:
  {FA.add(FR.one(), FR.F64{1018691584, 0}) == FR.F64{1072693248, 2} : FR.F64}

def f64_add_three_halves_ulp():
  {==}

law f64_add_close_jam:
  {FA.add(FR.one(), FR.F64{1040187392, 1073741825}) == FR.F64{1072693248, 2097153} : FR.F64}

def f64_add_close_jam():
  {==}

law f64_sub_cancel:
  {FA.sub(FR.F64{1072693248, 1}, FR.one()) == FR.epsilon() : FR.F64}

def f64_sub_cancel():
  {==}

law f64_sub_self_positive_zero:
  {FA.sub(FR.neg(FR.one()), FR.neg(FR.one())) == FR.zero() : FR.F64}

def f64_sub_self_positive_zero():
  {==}

law f64_mul_third_three:
  {FA.mul(FR.F64{1070945621, 1431655765}, FR.F64{1074266112, 0}) == FR.one() : FR.F64}

def f64_mul_third_three():
  {==}

law f64_mul_subnormal:
  {FA.mul(FR.min_normal(), FR.half()) == FR.F64{524288, 0} : FR.F64}

def f64_mul_subnormal():
  {==}

law f64_mul_overflow:
  {FA.mul(FR.max_finite(), FR.two()) == FR.inf() : FR.F64}

def f64_mul_overflow():
  {==}

law f64_div_one_three:
  {FA.div(FR.one(), FR.F64{1074266112, 0}) == FR.F64{1070945621, 1431655765} : FR.F64}

def f64_div_one_three():
  {==}

law f64_div_one_ten:
  {FA.div(FR.one(), FR.F64{1076101120, 0}) == FR.F64{1069128089, 2576980378} : FR.F64}

def f64_div_one_ten():
  {==}

law f64_div_midpoint_path:
  {FA.div(FR.F64{1073666970, 2532907559}, FR.F64{1073105216, 4129436155}) == FR.F64{1073096550, 1965773103} : FR.F64}

def f64_div_midpoint_path():
  {==}

law f64_div_zero_zero_nan:
  {FA.div(FR.zero(), FR.zero()) == FR.nan() : FR.F64}

def f64_div_zero_zero_nan():
  {==}

law f64_sqrt_two:
  {FA.sqrt(FR.two()) == FR.F64{1073127582, 1719614413} : FR.F64}

def f64_sqrt_two():
  {==}

law f64_sqrt_midpoint_path:
  {FA.sqrt(FR.F64{1072871835, 3141699480}) == FR.F64{1072779032, 3459311934} : FR.F64}

def f64_sqrt_midpoint_path():
  {==}

law f64_sqrt_subnormal:
  {FA.sqrt(FR.min_subnormal()) == FR.F64{509607936, 0} : FR.F64}

def f64_sqrt_subnormal():
  {==}

law f64_fma_single_rounding:
  {FA.fma(FR.F64{1072693248, 4194304}, FR.F64{1072693247, 4286578688}, FR.neg(FR.one())) == FR.F64{3157262336, 0} : FR.F64}

def f64_fma_single_rounding():
  {==}

law f64_floor_negative_half:
  {FR.floor(FR.F64{3221487616, 0}) == FR.F64{3221749760, 0} : FR.F64}

def f64_floor_negative_half():
  {==}

law f64_round_half_away:
  {FR.round(FR.F64{1074003968, 0}) == FR.F64{1074266112, 0} : FR.F64}

def f64_round_half_away():
  {==}

law f64_rint_half_even:
  {FR.rint(FR.F64{1074003968, 0}) == FR.two() : FR.F64}

def f64_rint_half_even():
  {==}

law f64_to_i32_truncates:
  {FR.to_i32(FR.F64{3221618688, 0}) == 4294967294 : U32}

def f64_to_i32_truncates():
  {==}

law f64_to_f32_tenth:
  {FR.to_f32_bits(FR.F64{1069128089, 2576980378}) == 1036831949 : U32}

def f64_to_f32_tenth():
  {==}

law f64_from_f32_tenth:
  {FR.from_f32_bits(1036831949) == FR.F64{1069128089, 2684354560} : FR.F64}

def f64_from_f32_tenth():
  {==}

law f64_ldexp_min_subnormal:
  {FR.ldexp(FR.one(), 4294966222) == FR.min_subnormal() : FR.F64}

def f64_ldexp_min_subnormal():
  {==}

law f64_random_small:
  {FX.from_output(12345) == FR.F64{1053301888, 1580160} : FR.F64}

def f64_random_small():
  {==}

law f64_random_largest_is_one:
  {FX.from_output(4294967295) == FR.one() : FR.F64}

def f64_random_largest_is_one():
  {==}

law f64_hypot_three_four:
  {FH.hypot(FR.F64{1074266112, 0}, FR.F64{1074790400, 0}) == FR.F64{1075052544, 0} : FR.F64}

def f64_hypot_three_four():
  {==}

law f64_hypot_boost_order:
  {FH.hypot(FR.F64{1072064102, 1717986918}, FR.half()) == FR.F64{1072400134, 1562693347} : FR.F64}

def f64_hypot_boost_order():
  {==}

law f64_lt_nan_false:
  {FC.lt(FR.nan(), FR.one()) == False{} : Bool}

def f64_lt_nan_false():
  {==}

law f64_eq_signed_zeros:
  {FC.eq(FR.zero(), FR.neg_zero()) == True{} : Bool}

def f64_eq_signed_zeros():
  {==}

law f64_ulp_cmp_one_ulp_equal:
  {FC.ulp_cmp(FR.one(), FR.F64{1072693248, 1}, 1) == EQ{} : Cmp}

def f64_ulp_cmp_one_ulp_equal():
  {==}

law f64_ulp_cmp_less:
  {FC.ulp_cmp(FR.one(), FR.F64{1072693248, 5}, 4) == LT{} : Cmp}

def f64_ulp_cmp_less():
  {==}

# Kamada-Kawai pieces (M5): golden values from .scratch/port/test/kk/kk_golden.py (Boost 1.52 formulas in IEEE
# double). The three-vertex example is the path 0-1-2 at (10, 20), (13, 24.5), (30, 21), moving vertex 1.

law kk_coef_three_hops:
  {KK.coef_of(3) == KK.Coef{FR.F64{1077805056, 0}, FR.F64{1069314503, 477218588}, FR.F64{1074440874, 2863311530}} : KK.Coef}

def kk_coef_three_hops():
  {==}

law kk_norm_three_four:
  {KK.norm(FR.F64{1074266112, 0}, FR.F64{3222274048, 0}) == FR.F64{1075052544, 0} : FR.F64}

def kk_norm_three_four():
  {==}

law kk_partial_three_vertices:
  {KK.partial(KS.Vec{FR.F64{1076494336, 0}, FR.F64{1077444608, 0}}, KS.Vec{FR.F64{1077805056, 0}, FR.F64{1077215232, 0}},
    KK.coef_of(1)) == KK.Partial{FR.F64{3223114332, 552011888}, FR.F64{1073200203, 3738984782},
    FR.F64{1076976455, 797611798}} : KK.Partial}

def kk_partial_three_vertices():
  {==}

law kk_hessian_three_second:
  {KK.hess_add(KS.Vec{FR.F64{1076494336, 0}, FR.F64{1077444608, 0}}, KS.Vec{FR.F64{1077805056, 0}, FR.F64{1077215232, 0}},
    KK.coef_of(1), [0 : U32*1n], FR.F64{1076976455, 797611798}, FR.F64{3218205897, 2826368612},
    FR.F64{1072385773, 3805434401}, FR.F64{1072385773, 3805434401}, FR.F64{1071355586, 3516022054})
    == KK.Hess{[0 : U32*1n], FR.F64{1072056749, 3993396824}, FR.F64{1072147126, 3069034035}, FR.F64{1072147126, 3069034035},
    FR.F64{1072438138, 21909520}} : KK.Hess}

def kk_hessian_three_second():
  {==}

law kk_newton_three:
  {KK.solved(KS.Vec{FR.F64{3223552318, 3029923221}, FR.F64{3221402173, 3916593033}},
    KS.Vec{FR.F64{1076494336, 0}, FR.F64{1077444608, 0}}, FR.F64{1072056749, 3993396824}, FR.F64{1072147126, 3069034035},
    FR.F64{1072147126, 3069034035}, FR.F64{1072438138, 21909520})
    == KS.Vec{FR.F64{1079878576, 2371297139}, FR.F64{3226393662, 198426450}} : KS.Vec}

def kk_newton_three():
  {==}

law kk_global_close:
  {KK.global_done(FR.half(), 3, FR.F64{1071645720, 2473901162}) == KK.Global{True{}, 4, FR.half()} : KK.Global}

def kk_global_close():
  {==}

law kk_global_capped:
  {KK.global_done(FR.half(), 100, FR.one()) == KK.Global{True{}, 0, FR.one()} : KK.Global}

def kk_global_capped():
  {==}
