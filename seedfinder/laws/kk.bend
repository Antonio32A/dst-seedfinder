import Base
import ../f64/repr.bend as F64Repr
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/layout/kk.bend as KK
import ../native/kk.bend as NativeKK
import ../worldsim/layout/hops.bend as LayoutHops
import ../data/constants.bend as Constants

# Kamada-Kawai pieces: golden values from the Boost 1.52 formulas in IEEE double. The three-vertex example is the
# path 0-1-2 at (10, 20), (13, 24.5), (30, 21), moving vertex 1.

law kk_coef_three_hops:
  {KK.coef_of(3) == KK.Coef{F64Repr.F64{1077805056, 0}, F64Repr.F64{1069314503, 477218588}, F64Repr.F64{1074440874, 2863311530}} : KK.Coef}

def kk_coef_three_hops():
  {==}

law kk_norm_three_four:
  {KK.norm(F64Repr.F64{1074266112, 0}, F64Repr.F64{3222274048, 0}) == F64Repr.F64{1075052544, 0} : F64Repr.F64}

def kk_norm_three_four():
  {==}

law kk_partial_three_vertices:
  {KK.partial(LayoutSpace.Vec{F64Repr.F64{1076494336, 0}, F64Repr.F64{1077444608, 0}}, LayoutSpace.Vec{F64Repr.F64{1077805056, 0}, F64Repr.F64{1077215232, 0}},
    KK.coef_of(1)) == KK.Partial{F64Repr.F64{3223114332, 552011888}, F64Repr.F64{1073200203, 3738984782},
    F64Repr.F64{1076976455, 797611798}} : KK.Partial}

def kk_partial_three_vertices():
  {==}

law kk_hessian_three_second:
  {KK.hess_add(LayoutSpace.Vec{F64Repr.F64{1076494336, 0}, F64Repr.F64{1077444608, 0}}, LayoutSpace.Vec{F64Repr.F64{1077805056, 0}, F64Repr.F64{1077215232, 0}},
    KK.coef_of(1), [0 : U32*1n], F64Repr.F64{1076976455, 797611798}, F64Repr.F64{3218205897, 2826368612},
    F64Repr.F64{1072385773, 3805434401}, F64Repr.F64{1072385773, 3805434401}, F64Repr.F64{1071355586, 3516022054})
    == KK.Hess{[0 : U32*1n], F64Repr.F64{1072056749, 3993396824}, F64Repr.F64{1072147126, 3069034035}, F64Repr.F64{1072147126, 3069034035},
    F64Repr.F64{1072438138, 21909520}} : KK.Hess}

def kk_hessian_three_second():
  {==}

law kk_newton_three:
  {KK.solved(LayoutSpace.Vec{F64Repr.F64{3223552318, 3029923221}, F64Repr.F64{3221402173, 3916593033}},
    LayoutSpace.Vec{F64Repr.F64{1076494336, 0}, F64Repr.F64{1077444608, 0}}, F64Repr.F64{1072056749, 3993396824}, F64Repr.F64{1072147126, 3069034035},
    F64Repr.F64{1072147126, 3069034035}, F64Repr.F64{1072438138, 21909520})
    == LayoutSpace.Vec{F64Repr.F64{1079878576, 2371297139}, F64Repr.F64{3226393662, 198426450}} : LayoutSpace.Vec}

def kk_newton_three():
  {==}

law kk_global_close:
  {KK.global_done(F64Repr.half(), 3, F64Repr.F64{1071645720, 2473901162}) == KK.Global{True{}, 4, F64Repr.half()} : KK.Global}

def kk_global_close():
  {==}

law kk_global_capped:
  {KK.global_done(F64Repr.half(), 100, F64Repr.one()) == KK.Global{True{}, 0, F64Repr.one()} : KK.Global}

def kk_global_capped():
  {==}

def kk_vec(+a: U32, +b: U32, +c: U32, +d: U32) -> LayoutSpace.Vec:
  LayoutSpace.Vec{F64Repr.F64{a, b}, F64Repr.F64{c, d}}

def kk_table_words(xy: U32 & U32, uv: U32 & U32) -> List<&2, U32>:
  (+a, +b) = xy
  (+c, +d) = uv
  [a, b, c, d]

def kk_listed(xs: List<&1, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      x <> kk_listed(rest)

# A KK pass's input words for the native KK: n, left, the arc count, the arcs, then the positions (the prior ones, zero
# past the end of the prior list, the constant table's from `first` on), in an array padded with zeros to a power of two.
law native_kk_words_prior:
  {kk_listed(Array.to_list(~U32, NativeKK.words(2, 3, [LayoutHops.Arc{0, 1}, LayoutHops.Arc{1, 2}], 4, [kk_vec(1, 2, 3, 4)])))
    == List.concat(&2, U32, [[3, 4, 2, 0, 1, 1, 2, 1, 2, 3, 4, 0, 0, 0, 0], kk_table_words(Constants.kk_x(2), Constants.kk_y(2)), List.replicate(U32, 13n, 0)]) : List<&2, U32>}

def native_kk_words_prior():
  {==}

def kk_answer() -> Array<U32>:
  ws = Array.new(U32, 4n, 7)
  ws[0] <- 2
  ws = LayoutSpace.put_vec(ws, 1, kk_vec(1, 2, 3, 4))
  LayoutSpace.put_vec(ws, 5, kk_vec(5, 6, 7, 8))

# The native KK's output words: n, then the n positions (the rest of the array is ignored).
law native_kk_vecs:
  {NativeKK.vecs(kk_answer()) == [kk_vec(1, 2, 3, 4), kk_vec(5, 6, 7, 8)] : List<&2, LayoutSpace.Vec>}

def native_kk_vecs():
  {==}
