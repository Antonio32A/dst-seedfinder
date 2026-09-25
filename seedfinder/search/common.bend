import Base

def search_depth() -> Nat:
  12n

def keep_below(room: Bool, +seed: U32, hits: List<&2, U32>) -> List<&2, U32>:
  match room:
    case True{}:
      seed <> hits
    case False{}:
      hits

def keep_hit(hit: Bool, +seed: U32, +count: U32, +cap: U32, hits: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      keep_below((count < cap : U32), seed, hits)
    case False{}:
      hits

def combine(a: U32 & List<&2, U32>, b: U32 & List<&2, U32>) -> U32 & List<&2, U32>:
  (ca, la) = a
  (cb, lb) = b
  ((ca + cb : U32), List.append(&2, U32, la, lb))

def rate(done: Nat, elapsed_ms: Nat) -> Nat:
  Nat.div(Nat.mul(done, 1000n), Nat.max(elapsed_ms, 1n))

def progress_line(+scanned: Nat, +total: Nat, +matched: U32, elapsed_ms: Nat) -> String:
  "scanned " ++ Nat.show(scanned) ++ "/" ++ Nat.show(total) ++ " matches " ++ U32.show(matched)
    ++ " (" ++ Nat.show(rate(scanned, elapsed_ms)) ++ " seeds/s)"
