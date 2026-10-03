import Base
import ../data/constants.bend as Constants
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/layout/hops.bend as LayoutHops

# The Kamada-Kawai pass (worldsim/layout/kk.bend, bit for bit) as native C (kk.c) on an IO helper thread.

# The raw effect: an array holding n, left, the arc count, the arcs (from, to) and n positions (x hi, x lo, y hi, y lo)
# in; a new array holding n and the n positions out (the input array is consumed).
def native_kk(words: Array<U32>) -> IO(Array<U32>):
  import "./kk.c"
  import "./kk.js"

def arcs_into(arcs: List<&2, LayoutHops.Arc>, +at: U32, ws: Array<U32>) -> Array<U32>:
  match arcs:
    case Nil{}:
      ws
    case Con{LayoutHops.Arc{+a, +b}, more}:
      ws[at] <- a
      ws[(at + 1 : U32)] <- b
      arcs_into(more, (at + 2 : U32), ws)

def table_into(xy: U32 & U32, uv: U32 & U32, +at: U32, ws: Array<U32>) -> Array<U32>:
  (a, b) = xy
  (c, d) = uv
  ws[at] <- a
  ws[(at + 1 : U32)] <- b
  ws[(at + 2 : U32)] <- c
  ws[(at + 3 : U32)] <- d

def new_into(fuel: Nat, +v: U32, +at: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      new_into(f, (v + 1 : U32), (at + 4 : U32), table_into(Constants.kk_x(v), Constants.kk_y(v), at, ws))

def prior_into(fuel: Nat, prior: List<&2, LayoutSpace.Vec>, +v: U32, +n: U32, +at: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      new_into(U32.to_nat((n - v : U32)), v, at, ws)
    case 1n+f:
      match prior:
        case Nil{}:
          prior_into(f, Nil{}, (v + 1 : U32), n, (at + 4 : U32), ws)
        case Con{+p, rest}:
          prior_into(f, rest, (v + 1 : U32), n, (at + 4 : U32), LayoutSpace.put_vec(ws, at, p))

def arc_count(arcs: List<&2, LayoutHops.Arc>, +k: U32) -> U32:
  match arcs:
    case Nil{}:
      k
    case Con{_, more}:
      arc_count(more, (k + 1 : U32))

# The effect's input words for a pass (vertices 0..first-1 at prior, first.. at the table positions).
def words(+first: U32, +n: U32, +arcs: List<&2, LayoutHops.Arc>, +left: U32, +prior: List<&2, LayoutSpace.Vec>) -> Array<U32>:
  +count = arc_count(arcs, 0)
  +size = (3 + count * 2 + n * 4 : U32)
  ws = Array.new(U32, Nat.add(U32.log2((size - 1 : U32)), 1n), 0)
  ws[0] <- n
  ws[1] <- left
  ws[2] <- count
  prior_into(U32.to_nat(U32.min(first, n)), prior, 0, n, (3 + count * 2 : U32), arcs_into(arcs, 3, ws))

def vecs_from(fuel: Nat, got: Array<U32> & LayoutSpace.Vec, +at: U32) -> List<&2, LayoutSpace.Vec>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      (ws, v) = got
      v <> vecs_from(f, LayoutSpace.get_vec(ws, (at + 4 : U32)), (at + 4 : U32))

def counted_vecs(got: Array<U32> & U32) -> List<&2, LayoutSpace.Vec>:
  (ws, +n) = got
  vecs_from(U32.to_nat(n), LayoutSpace.get_vec(ws, 1), 1)

# The positions in the effect's output words.
def vecs(ws: Array<U32>) -> List<&2, LayoutSpace.Vec>:
  counted_vecs(ws[0])
