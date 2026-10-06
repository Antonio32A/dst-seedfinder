import Base

# The speed line of `world find` on stderr (docs/config.md section 8): seeds prefiltered by their level table, worlds
# generated and seeds decided, per second over the last 30 s and over the whole run.

# The counts `at` ms into the run.
type Point is Data:
  Point{at: Nat, prefiltered: Nat, generated: Nat, decided: Nat}

def window_ms() -> Nat:
  30000n

# The points of a run before its first tick.
def started() -> List<&2, Point>:
  [Point{0n, 0n, 0n, 0n}]

def superseded(+rest: List<&2, Point>, +since: Nat) -> Bool:
  match rest:
    case Con{Point{+at, _, _, _}, _}:
      Nat.is_le(at, since)
    case Nil{}:
      False{}

# The points from the last one at or before `since` on.
def dropped(points: List<&2, Point>, +since: Nat) -> List<&2, Point>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+p, +rest}:
      Bool.pick(List<&2, Point>, superseded(rest, since), dropped(rest, since), p <> rest)

# The points after a tick at `p`: the window's points, oldest first, and the newest one before the window.
def ticked(+points: List<&2, Point>, +p: Point) -> List<&2, Point>:
  match p:
    case Point{+at, _, _, _}:
      dropped(List.append(&2, Point, points, [p]), Nat.sub(at, window_ms()))

# Per second, with one decimal below 100.
def rate(+count: Nat, +ms: Nat) -> String:
  +tenths = Nat.div(Nat.mul(count, 10000n), Nat.max(ms, 1n))
  +whole = Nat.show(Nat.div(tenths, 10n))
  Bool.pick(String, Nat.is_lt(tenths, 1000n), whole ++ "." ++ Nat.show(Nat.mod(tenths, 10n)), whole)

def rates(+from: Point, +to: Point) -> String:
  match from to:
    case Point{+t0, +p0, +g0, +d0} Point{+t1, +p1, +g1, +d1}:
      +ms = Nat.sub(t1, t0)
      rate(Nat.sub(p1, p0), ms) ++ "/" ++ rate(Nat.sub(g1, g0), ms) ++ "/" ++ rate(Nat.sub(d1, d0), ms)

# `speed 30s: P/G/T full: P/G/T`: prefiltered, generated and decided per second.
def line(+points: List<&2, Point>) -> String:
  +first = {Point{0n, 0n, 0n, 0n} : Point}
  +last = Maybe.default(&2, Point, List.last(&2, Point, points), first)
  "speed 30s: " ++ rates(Maybe.default(&2, Point, List.head(&2, Point, points), first), last) ++ " full: " ++ rates(first, last)
