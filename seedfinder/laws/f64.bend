import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../f64/hypot.bend as F64Hypot
import ../f64/random.bend as F64Random

# Golden values: x86-64 SSE2 and glibc.

law f64_add_one_two:
  {F64Arith.add(F64Repr.one(), F64Repr.two()) == F64Repr.F64{1074266112, 0} : F64Repr.F64}

def f64_add_one_two():
  {==}

law f64_add_tie_even:
  {F64Arith.add(F64Repr.one(), F64Repr.F64{1017118720, 0}) == F64Repr.one() : F64Repr.F64}

def f64_add_tie_even():
  {==}

law f64_add_three_halves_ulp:
  {F64Arith.add(F64Repr.one(), F64Repr.F64{1018691584, 0}) == F64Repr.F64{1072693248, 2} : F64Repr.F64}

def f64_add_three_halves_ulp():
  {==}

law f64_add_close_jam:
  {F64Arith.add(F64Repr.one(), F64Repr.F64{1040187392, 1073741825}) == F64Repr.F64{1072693248, 2097153} : F64Repr.F64}

def f64_add_close_jam():
  {==}

law f64_sub_cancel:
  {F64Arith.sub(F64Repr.F64{1072693248, 1}, F64Repr.one()) == F64Repr.epsilon() : F64Repr.F64}

def f64_sub_cancel():
  {==}

law f64_sub_self_positive_zero:
  {F64Arith.sub(F64Repr.neg(F64Repr.one()), F64Repr.neg(F64Repr.one())) == F64Repr.zero() : F64Repr.F64}

def f64_sub_self_positive_zero():
  {==}

law f64_mul_third_three:
  {F64Arith.mul(F64Repr.F64{1070945621, 1431655765}, F64Repr.F64{1074266112, 0}) == F64Repr.one() : F64Repr.F64}

def f64_mul_third_three():
  {==}

law f64_mul_subnormal:
  {F64Arith.mul(F64Repr.min_normal(), F64Repr.half()) == F64Repr.F64{524288, 0} : F64Repr.F64}

def f64_mul_subnormal():
  {==}

law f64_mul_overflow:
  {F64Arith.mul(F64Repr.max_finite(), F64Repr.two()) == F64Repr.inf() : F64Repr.F64}

def f64_mul_overflow():
  {==}

law f64_div_one_three:
  {F64Arith.div(F64Repr.one(), F64Repr.F64{1074266112, 0}) == F64Repr.F64{1070945621, 1431655765} : F64Repr.F64}

def f64_div_one_three():
  {==}

law f64_div_one_ten:
  {F64Arith.div(F64Repr.one(), F64Repr.F64{1076101120, 0}) == F64Repr.F64{1069128089, 2576980378} : F64Repr.F64}

def f64_div_one_ten():
  {==}

law f64_div_midpoint_path:
  {F64Arith.div(F64Repr.F64{1073666970, 2532907559}, F64Repr.F64{1073105216, 4129436155}) == F64Repr.F64{1073096550, 1965773103} : F64Repr.F64}

def f64_div_midpoint_path():
  {==}

law f64_div_zero_zero_nan:
  {F64Arith.div(F64Repr.zero(), F64Repr.zero()) == F64Repr.nan() : F64Repr.F64}

def f64_div_zero_zero_nan():
  {==}

law f64_sqrt_two:
  {F64Arith.sqrt(F64Repr.two()) == F64Repr.F64{1073127582, 1719614413} : F64Repr.F64}

def f64_sqrt_two():
  {==}

law f64_sqrt_midpoint_path:
  {F64Arith.sqrt(F64Repr.F64{1072871835, 3141699480}) == F64Repr.F64{1072779032, 3459311934} : F64Repr.F64}

def f64_sqrt_midpoint_path():
  {==}

law f64_sqrt_subnormal:
  {F64Arith.sqrt(F64Repr.min_subnormal()) == F64Repr.F64{509607936, 0} : F64Repr.F64}

def f64_sqrt_subnormal():
  {==}

law f64_fma_single_rounding:
  {F64Arith.fma(F64Repr.F64{1072693248, 4194304}, F64Repr.F64{1072693247, 4286578688}, F64Repr.neg(F64Repr.one())) == F64Repr.F64{3157262336, 0} : F64Repr.F64}

def f64_fma_single_rounding():
  {==}

law f64_floor_negative_half:
  {F64Repr.floor(F64Repr.F64{3221487616, 0}) == F64Repr.F64{3221749760, 0} : F64Repr.F64}

def f64_floor_negative_half():
  {==}

law f64_round_half_away:
  {F64Repr.round(F64Repr.F64{1074003968, 0}) == F64Repr.F64{1074266112, 0} : F64Repr.F64}

def f64_round_half_away():
  {==}

law f64_rint_half_even:
  {F64Repr.rint(F64Repr.F64{1074003968, 0}) == F64Repr.two() : F64Repr.F64}

def f64_rint_half_even():
  {==}

law f64_to_i32_truncates:
  {F64Repr.to_i32(F64Repr.F64{3221618688, 0}) == 4294967294 : U32}

def f64_to_i32_truncates():
  {==}

law f64_to_f32_tenth:
  {F64Repr.to_f32_bits(F64Repr.F64{1069128089, 2576980378}) == 1036831949 : U32}

def f64_to_f32_tenth():
  {==}

law f64_from_f32_tenth:
  {F64Repr.from_f32_bits(1036831949) == F64Repr.F64{1069128089, 2684354560} : F64Repr.F64}

def f64_from_f32_tenth():
  {==}

law f64_ldexp_min_subnormal:
  {F64Repr.ldexp(F64Repr.one(), 4294966222) == F64Repr.min_subnormal() : F64Repr.F64}

def f64_ldexp_min_subnormal():
  {==}

law f64_random_small:
  {F64Random.from_output(12345) == F64Repr.F64{1053301888, 1580160} : F64Repr.F64}

def f64_random_small():
  {==}

law f64_random_largest_is_one:
  {F64Random.from_output(4294967295) == F64Repr.one() : F64Repr.F64}

def f64_random_largest_is_one():
  {==}

law f64_hypot_three_four:
  {F64Hypot.hypot(F64Repr.F64{1074266112, 0}, F64Repr.F64{1074790400, 0}) == F64Repr.F64{1075052544, 0} : F64Repr.F64}

def f64_hypot_three_four():
  {==}

law f64_hypot_boost_order:
  {F64Hypot.hypot(F64Repr.F64{1072064102, 1717986918}, F64Repr.half()) == F64Repr.F64{1072400134, 1562693347} : F64Repr.F64}

def f64_hypot_boost_order():
  {==}

law f64_lt_nan_false:
  {F64Cmp.lt(F64Repr.nan(), F64Repr.one()) == False{} : Bool}

def f64_lt_nan_false():
  {==}

law f64_eq_signed_zeros:
  {F64Cmp.eq(F64Repr.zero(), F64Repr.neg_zero()) == True{} : Bool}

def f64_eq_signed_zeros():
  {==}

law f64_ulp_cmp_one_ulp_equal:
  {F64Cmp.ulp_cmp(F64Repr.one(), F64Repr.F64{1072693248, 1}, 1) == EQ{} : Cmp}

def f64_ulp_cmp_one_ulp_equal():
  {==}

law f64_ulp_cmp_less:
  {F64Cmp.ulp_cmp(F64Repr.one(), F64Repr.F64{1072693248, 5}, 4) == LT{} : Cmp}

def f64_ulp_cmp_less():
  {==}
