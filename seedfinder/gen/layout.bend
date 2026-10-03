import Base
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/layout/hops.bend as LayoutHops
import ../worldsim/layout/kk.bend as KK
import ../native/kk.bend as NativeKK

# The seam between the job machine (gen/job.bend) and a KK engine: a job at a KK pass hands over a Layout, and the
# engine answers the pass's positions (vertex order). Engines: `local` (kk.bend, pure, this thread) and `solve` (the
# engine switch used by `gen` and the search).

# A KamadaKawaiPass: the graph's n vertices and its arcs; vertices `first`.. are new (the constant minstd table
# places them), vertices 0..first-1 start at `prior`; `left` runs follow the first.
type Layout is Data:
  Layout{first: U32, n: U32, arcs: List<&2, LayoutHops.Arc>, left: U32, prior: List<&2, LayoutSpace.Vec>}

def placed(ps: List<&2, LayoutSpace.Vec>, +v: U32, ws: Array<U32>) -> Array<U32>:
  match ps:
    case Nil{}:
      ws
    case Con{+p, rest}:
      placed(rest, (v + 1 : U32), LayoutSpace.put_vec(ws, LayoutSpace.pos_at(v), p))

def second_of(got: Array<U32> & List<&2, LayoutSpace.Vec>) -> List<&2, LayoutSpace.Vec>:
  (_, +ps) = got
  ps

def positions_of(job: KK.Job) -> List<&2, LayoutSpace.Vec>:
  match job:
    case KK.Job{ws, +n, _, _, _, _, _}:
      second_of(KK.positions(ws, n))

# The whole pass with kk.bend on this thread (a fresh 8 MB workspace).
def local(+l: Layout) -> List<&2, LayoutSpace.Vec>:
  match l:
    case Layout{+first, +n, +arcs, +left, +prior}:
      +fuel = Nat.mul(KK.run_fuel(), U32.to_nat((left + 1 : U32)))
      positions_of(KK.advance(fuel, KK.pass_job(placed(prior, 0, LayoutSpace.new_workspace()), first, n, arcs, left)))

# A pass prepared for its engine by the thread that reached it: the native KK's input words, or the Layout for kk.bend.
type Ready is Type:
  Native{words: Array<U32>}
  Local{layout: Layout}

# A pass's answer: the native KK's output words, or kk.bend's positions.
type Answer is Type:
  Answered{words: Array<U32>}
  Positioned{ps: List<&2, LayoutSpace.Vec>}

def ready(+native: Bool, +l: Layout) -> Ready:
  match native:
    case True{}:
      match l:
        case Layout{+first, +n, +arcs, +left, +prior}:
          Native{NativeKK.words(first, n, arcs, left, prior)}
    case False{}:
      Local{l}

# The pass on its engine: native (the C KK, on the runtime's IO helper threads) or kk.bend (this thread).
def answer(r: Ready) -> IO(Answer):
  match r:
    case Native{ws}:
      do IO<Answer>:
        out : Array<U32> <- NativeKK.native_kk(ws)
        return Answered{out}
    case Local{+l}:
      IO.pure(Answer, Positioned{local(l)})

# The positions of vertices 0..n-1 after the pass.
def positions(a: Answer) -> List<&2, LayoutSpace.Vec>:
  match a:
    case Answered{ws}:
      NativeKK.vecs(ws)
    case Positioned{+ps}:
      ps

# The pass's positions from the chosen engine: native (the C KK, on the runtime's IO helper threads) or kk.bend.
def solve(+native: Bool, +l: Layout) -> IO(List<&2, LayoutSpace.Vec>):
  do IO<List<&2, LayoutSpace.Vec>>:
    a : Answer <- answer(ready(native, l))
    return positions(a)
