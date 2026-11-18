import Base
import ../f64/repr.bend as F64Repr
import ../worldsim/voronoi/ctypes.bend as VoronoiTypes
import ../worldsim/voronoi/predicates.bend as VoronoiPredicates
import ../worldsim/voronoi/exact.bend as VoronoiExact
import ../worldsim/voronoi/lazy.bend as VoronoiLazy
import ../worldsim/voronoi/polygon.bend as VoronoiPolygon
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/tiles/world.bend as TileWorld
import ../stl/heap.bend as Heap
import ../native/voronoi.bend as NativeVoronoi

# Golden values: Boost 1.52.

# robust_cross_product(3, 4, 5, 7) = 3 * 7 - 4 * 5.
law voronoi_cross_small:
  {VoronoiPredicates.cross(VoronoiTypes.widen(3), VoronoiTypes.widen(4), VoronoiTypes.widen(5), VoronoiTypes.widen(7)) == F64Repr.F64{1072693248, 0} : F64Repr.F64}

def voronoi_cross_small():
  {==}

# robust_cross_product(-1, 0, 0, 0) is -0.0 (the -(l + r) branch).
law voronoi_cross_negative_zero:
  {VoronoiPredicates.cross(VoronoiTypes.widen(4294967295), VoronoiTypes.widen(0), VoronoiTypes.widen(0), VoronoiTypes.widen(0)) == F64Repr.F64{2147483648, 0} : F64Repr.F64}

def voronoi_cross_negative_zero():
  {==}

# extended_int: 2^64 - (2^64 - 1) keeps a leading zero chunk (count 2, chunks 1, 0).
law voronoi_big_dif_leading_zero:
  {VoronoiTypes.big_sub(VoronoiTypes.Big{3, [0, 0, 1]}, VoronoiTypes.Big{2, [4294967295, 4294967295]}) == VoronoiTypes.Big{2, [1, 0]} : VoronoiTypes.Big}

def voronoi_big_dif_leading_zero():
  {==}

# extended_int::d() of a 3-chunk value (two roundings in Boost's order).
law voronoi_big_to_double:
  {VoronoiTypes.big_to_f64(VoronoiTypes.Big{3, [2147483649, 2049, 1048576]}) == F64Repr.F64{1160773632, 2050} : F64Repr.F64}

def voronoi_big_to_double():
  {==}

# extended_exponent_fpt(8).sqrt(): the odd exponent path.
law voronoi_efpt_sqrt_odd:
  {VoronoiTypes.efpt_to_f64(VoronoiTypes.efpt_sqrt(VoronoiTypes.efpt_of(F64Repr.F64{1075838976, 0}))) == F64Repr.F64{1074176158, 1719614413} : F64Repr.F64}

def voronoi_efpt_sqrt_odd():
  {==}

# event_comparison_predicate on sites: a point before a vertical segment starting at it, not vice versa.
law voronoi_site_order:
  {(VoronoiPredicates.site_less(VoronoiPredicates.Site{1, 5, 1, 9, 0, 0, 0}, VoronoiPredicates.Site{1, 5, 1, 5, 0, 0, 0}), VoronoiPredicates.site_less(VoronoiPredicates.Site{1, 5, 1, 5, 0, 0, 0}, VoronoiPredicates.Site{1, 7, 1, 7, 0, 0, 0})) == (False{}, True{}) : Bool & Bool}

def voronoi_site_order():
  {==}

# The exact circle of (0,0), (0,3), (4,0): centre (2, 1.5), lower x 4.5.
law voronoi_ppp_exact:
  {VoronoiExact.ppp(VoronoiPredicates.Site{0, 0, 0, 0, 0, 0, 0}, VoronoiPredicates.Site{0, 3, 0, 3, 0, 0, 0}, VoronoiPredicates.Site{4, 0, 4, 0, 0, 0, 0}, VoronoiPredicates.Circle{F64Repr.zero(), F64Repr.zero(), F64Repr.zero()}, True{}, True{}, True{})
    == VoronoiPredicates.Circle{F64Repr.F64{1073741824, 0}, F64Repr.F64{1073217536, 0}, F64Repr.F64{1074921472, 0}} : VoronoiPredicates.Circle}

def voronoi_ppp_exact():
  {==}

# circle_formation_predicate on the same three points (the lazy robust_fpt path).
law voronoi_ppp_lazy:
  {VoronoiLazy.circle_formation(VoronoiPredicates.Site{0, 0, 0, 0, 0, 0, 0}, VoronoiPredicates.Site{0, 3, 0, 3, 0, 0, 0}, VoronoiPredicates.Site{4, 0, 4, 0, 0, 0, 0})
    == Some{VoronoiPredicates.Circle{F64Repr.F64{1073741824, 0}, F64Repr.F64{1073217536, 0}, F64Repr.F64{1074921472, 0}}} : Maybe<&2, VoronoiPredicates.Circle>}

def voronoi_ppp_lazy():
  {==}

def array_words(a: Array<U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match a:
    case ALeaf{+x}:
      x <> acc
    case ANode{xs, ys}:
      array_words(xs, array_words(ys, acc))

# The native Voronoi's plan words: windows, the world size, the last-pass flag, then each site's kind and centroid
# (positions come from the KK pass), padded with zeros to a power of two.
law native_voronoi_plan:
  {array_words(NativeVoronoi.plan(True{}, 425, False{}, [VoronoiPolygon.SiteIn{1, 2, 3, 4, 5}, VoronoiPolygon.SiteIn{6, 7, 8, 9, 10}]), Nil{})
    == [1, 425, 0, 3, 4, 5, 8, 9, 10, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def native_voronoi_plan():
  {==}

def one() -> F64Repr.F64:
  F64Repr.F64{1072693248, 0}

def two() -> F64Repr.F64:
  F64Repr.F64{1073741824, 0}

# A last pass's answer of one site: the word count (43), the KK words, the last-pass flag, the pass's polygon, Commit's
# polygon, then ConvertToTileMap's polygon and its one cell with one half-edge (vertex 0 only, one drawn point). The
# words past the count are ignored.
def native_answer_words() -> Array<U32>:
  Heap.from_list(6n, [43, 1, 1072693248, 0, 1073741824, 0, 1, 0, 11, 12, 0, 5, 1, 13, 14, 15, 16, 1, 4294967295, 4, 0,
    21, 22, 0, 1, 1, 0, 1, 7, 1, 1072693248, 0, 1073741824, 0, 0, 0, 0, 0, 1, 1072693248, 0, 1072693248, 0, 9, 9])

law native_voronoi_answer:
  {NativeVoronoi.answer(native_answer_words()) == NativeVoronoi.Answer{[LayoutSpace.Vec{one(), two()}], [VoronoiPolygon.Poly{[], 11, 12, [], 5}],
    Some{NativeVoronoi.Ahead{[VoronoiPolygon.Poly{[VoronoiPolygon.P32{13, 14}], 15, 16, [4294967295], 4}], [VoronoiPolygon.Poly{[], 21, 22, [], 1}],
      [TileWorld.Cell{0, [TileWorld.VEdge{7, Some{TileWorld.DPoint{one(), two()}}, None{}, [TileWorld.DPoint{one(), one()}]}]}]}}} : NativeVoronoi.Answer}

def native_voronoi_answer():
  {==}
