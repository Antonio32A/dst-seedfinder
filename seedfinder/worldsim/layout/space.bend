import Base
import ../../f64/repr.bend as FR

# The Kamada-Kawai workspace: one Array<U32> of 2^21 words holding every table of a layout job, with a vertex
# stride of 512 (so at most 512 vertices). Regions: pair partials (4 words per ordered pair), pair distances
# (2 words), hop counts (1 word), positions, derivatives and pinned partials (4 words per vertex), coefficients
# per hop count (6 words), CSR adjacency (starts and arcs), a BFS queue and the positions of the moving vertex after
# each Newton move of an inner loop (4 words per move).

type Vec is Data:
  Vec{x: FR.F64, y: FR.F64}

def max_vertices() -> U32:
  512

def max_arcs() -> U32:
  16384

def new_workspace() -> Array<U32>:
  [0 : U32^21n]

def pair(+m: U32, +i: U32) -> U32:
  ((m << 9n) + i : U32)

def partial_at(+m: U32, +i: U32) -> U32:
  (pair(m, i) << 2n : U32)

def dist_at(+m: U32, +i: U32) -> U32:
  (1048576 + (pair(m, i) << 1n) : U32)

def hop_at(+m: U32, +i: U32) -> U32:
  (1572864 + pair(m, i) : U32)

def pos_at(+v: U32) -> U32:
  (1835008 + (v << 2n) : U32)

def deriv_at(+v: U32) -> U32:
  (1837056 + (v << 2n) : U32)

def pinned_at(+v: U32) -> U32:
  (1839104 + (v << 2n) : U32)

def coef_at(+d: U32) -> U32:
  (1841152 + (d << 3n) : U32)

def start_at(+v: U32) -> U32:
  (1845248 + v : U32)

def arc_at(+k: U32) -> U32:
  (1846272 + k : U32)

def queue_at(+k: U32) -> U32:
  (1862656 + k : U32)

def history_at(+m: U32) -> U32:
  (1900544 + (m << 2n) : U32)

def get_lo(got: Array<U32> & U32, +hi: U32) -> Array<U32> & FR.F64:
  (ws, lo) = got
  (ws, FR.F64{hi, lo})

def get_hi(got: Array<U32> & U32, +at: U32) -> Array<U32> & FR.F64:
  (ws, hi) = got
  get_lo(ws[(at + 1 : U32)], hi)

# The F64 stored in the two words at `at` (high word first).
def get(ws: Array<U32>, +at: U32) -> Array<U32> & FR.F64:
  get_hi(ws[at], at)

def put(ws: Array<U32>, +at: U32, x: FR.F64) -> Array<U32>:
  match x:
    case FR.F64{hi, lo}:
      ws[at] <- hi
      ws[(at + 1 : U32)] <- lo

def get_y(got: Array<U32> & FR.F64, +x: FR.F64) -> Array<U32> & Vec:
  (ws, y) = got
  (ws, Vec{x, y})

def get_x(got: Array<U32> & FR.F64, +at: U32) -> Array<U32> & Vec:
  (ws, x) = got
  get_y(get(ws, (at + 2 : U32)), x)

# The Vec stored in the four words at `at` (x then y).
def get_vec(ws: Array<U32>, +at: U32) -> Array<U32> & Vec:
  get_x(get(ws, at), at)

def put_vec(ws: Array<U32>, +at: U32, v: Vec) -> Array<U32>:
  match v:
    case Vec{x, y}:
      put(put(ws, at, x), (at + 2 : U32), y)
