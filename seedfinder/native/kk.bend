import Base
import ../f64/repr.bend as F64Repr
import ../data/constants.bend as Constants
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/layout/hops.bend as LayoutHops

# The Kamada-Kawai pass (worldsim/layout/kk.bend, bit for bit) as native C (kk.c) on an IO helper thread.

# The raw effect: words n, left, arc count, arcs (from, to), n positions (x hi, x lo, y hi, y lo) in; n positions out.
def native_kk(words: List<&2, U32>) -> IO(List<&2, U32>):
  import "./kk.c"
  import "./kk.js"

def vec_words(+v: LayoutSpace.Vec, rest: List<&2, U32>) -> List<&2, U32>:
  match v:
    case LayoutSpace.Vec{F64Repr.F64{+a, +b}, F64Repr.F64{+c, +d}}:
      a <> b <> c <> d <> rest

def table_words(xy: U32 & U32, uv: U32 & U32, rest: List<&2, U32>) -> List<&2, U32>:
  (a, b) = xy
  (c, d) = uv
  a <> b <> c <> d <> rest

def new_words(fuel: Nat, +v: U32) -> List<&2, U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      table_words(Constants.kk_x(v), Constants.kk_y(v), new_words(f, (v + 1 : U32)))

def prior_words(fuel: Nat, prior: List<&2, LayoutSpace.Vec>, +v: U32, +n: U32) -> List<&2, U32>:
  match fuel:
    case 0n:
      new_words(U32.to_nat((n - v : U32)), v)
    case 1n+f:
      match prior:
        case Nil{}:
          0 <> 0 <> 0 <> 0 <> prior_words(f, Nil{}, (v + 1 : U32), n)
        case Con{+p, rest}:
          vec_words(p, prior_words(f, rest, (v + 1 : U32), n))

def arc_words(arcs: List<&2, LayoutHops.Arc>, rest: List<&2, U32>) -> List<&2, U32>:
  match arcs:
    case Nil{}:
      rest
    case Con{LayoutHops.Arc{+a, +b}, more}:
      a <> b <> arc_words(more, rest)

def arc_count(arcs: List<&2, LayoutHops.Arc>, +k: U32) -> U32:
  match arcs:
    case Nil{}:
      k
    case Con{_, more}:
      arc_count(more, (k + 1 : U32))

# The effect's input words for a pass (vertices 0..first-1 at prior, first.. at the table positions).
def words(+first: U32, +n: U32, +arcs: List<&2, LayoutHops.Arc>, +left: U32, +prior: List<&2, LayoutSpace.Vec>) -> List<&2, U32>:
  n <> left <> arc_count(arcs, 0) <> arc_words(arcs, prior_words(U32.to_nat(U32.min(first, n)), prior, 0, n))

# The positions in the effect's output words.
def vecs(ws: List<&2, U32>) -> List<&2, LayoutSpace.Vec>:
  match ws:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      LayoutSpace.Vec{F64Repr.F64{a, b}, F64Repr.F64{c, d}} <> vecs(rest)
    case _:
      Nil{}

# A KamadaKawaiPass (gen/layout.bend's Layout fields): the positions of vertices 0..n-1 after it, as GenLayout.local gives.
def pass(+first: U32, +n: U32, +arcs: List<&2, LayoutHops.Arc>, +left: U32, +prior: List<&2, LayoutSpace.Vec>) -> IO(List<&2, LayoutSpace.Vec>):
  do IO<List<&2, LayoutSpace.Vec>>:
    out : List<&2, U32> <- native_kk(words(first, n, arcs, left, prior))
    return vecs(out)
