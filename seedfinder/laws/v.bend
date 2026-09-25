import Base
import ../f64/word.bend as FW
import ../f64/repr.bend as FR
import ../worldsim/voronoi/ctypes.bend as VT
import ../worldsim/voronoi/predicates.bend as VP
import ../worldsim/voronoi/exact.bend as VE
import ../worldsim/voronoi/lazy.bend as VL

# Lane N (Voronoi, M6) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: .scratch/port/CONVENTIONS.md "Laws" (tiny U32 golden values, each probed alone first).
# Golden values: Boost 1.52 (.scratch/port/test/voronoi/law_goldens.cpp).

# robust_cross_product(3, 4, 5, 7) = 3 * 7 - 4 * 5.
law voronoi_cross_small:
  {VP.cross(VT.widen(3), VT.widen(4), VT.widen(5), VT.widen(7)) == FR.F64{1072693248, 0} : FR.F64}

def voronoi_cross_small():
  {==}

# robust_cross_product(-1, 0, 0, 0) is -0.0 (the -(l + r) branch).
law voronoi_cross_negative_zero:
  {VP.cross(VT.widen(4294967295), VT.widen(0), VT.widen(0), VT.widen(0)) == FR.F64{2147483648, 0} : FR.F64}

def voronoi_cross_negative_zero():
  {==}

# extended_int: 2^64 - (2^64 - 1) keeps a leading zero chunk (count 2, chunks 1, 0).
law voronoi_big_dif_leading_zero:
  {VT.big_sub(VT.Big{3, [0, 0, 1]}, VT.Big{2, [4294967295, 4294967295]}) == VT.Big{2, [1, 0]} : VT.Big}

def voronoi_big_dif_leading_zero():
  {==}

# extended_int::d() of a 3-chunk value (two roundings in Boost's order).
law voronoi_big_to_double:
  {VT.big_to_f64(VT.Big{3, [2147483649, 2049, 1048576]}) == FR.F64{1160773632, 2050} : FR.F64}

def voronoi_big_to_double():
  {==}

# extended_exponent_fpt(8).sqrt(): the odd exponent path.
law voronoi_efpt_sqrt_odd:
  {VT.efpt_to_f64(VT.efpt_sqrt(VT.efpt_of(FR.F64{1075838976, 0}))) == FR.F64{1074176158, 1719614413} : FR.F64}

def voronoi_efpt_sqrt_odd():
  {==}

# event_comparison_predicate on sites: a point before a vertical segment starting at it, not vice versa.
law voronoi_site_order:
  {(VP.site_less(VP.Site{1, 5, 1, 9, 0, 0, 0}, VP.Site{1, 5, 1, 5, 0, 0, 0}), VP.site_less(VP.Site{1, 5, 1, 5, 0, 0, 0}, VP.Site{1, 7, 1, 7, 0, 0, 0})) == (False{}, True{}) : Bool & Bool}

def voronoi_site_order():
  {==}

# The exact circle of (0,0), (0,3), (4,0): centre (2, 1.5), lower x 4.5.
law voronoi_ppp_exact:
  {VE.ppp(VP.Site{0, 0, 0, 0, 0, 0, 0}, VP.Site{0, 3, 0, 3, 0, 0, 0}, VP.Site{4, 0, 4, 0, 0, 0, 0}, VP.Circle{FR.zero(), FR.zero(), FR.zero()}, True{}, True{}, True{})
    == VP.Circle{FR.F64{1073741824, 0}, FR.F64{1073217536, 0}, FR.F64{1074921472, 0}} : VP.Circle}

def voronoi_ppp_exact():
  {==}

# circle_formation_predicate on the same three points (the lazy robust_fpt path).
law voronoi_ppp_lazy:
  {VL.circle_formation(VP.Site{0, 0, 0, 0, 0, 0, 0}, VP.Site{0, 3, 0, 3, 0, 0, 0}, VP.Site{4, 0, 4, 0, 0, 0, 0})
    == Some{VP.Circle{FR.F64{1073741824, 0}, FR.F64{1073217536, 0}, FR.F64{1074921472, 0}}} : Maybe<&2, VP.Circle>}

def voronoi_ppp_lazy():
  {==}
