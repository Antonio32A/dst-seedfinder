import Base
import ../data/cave_catalog.bend as CaveCatalog
import ../level/cave_prefix.bend as CavePrefix
import ../level/cave_choose.bend as CaveChoose
import ../filters/cave_setpiece.bend as CaveFilter
import ../cli/args.bend as Args
import ./common.bend as SearchCommon
import ./setpiece.bend as SearchSetpiece

# `setpiece find` and `setpiece show` on the caves shard, like setpiece.bend, over AddSetPeices' outcome for the
# chosen tasks.

def json_entries(pieces: List<&2, CaveCatalog.Name>, +entries: List<&2, CaveChoose.Entry>) -> List<&2, String>:
  match pieces:
    case Nil{}:
      Nil{}
    case Con{CaveCatalog.Name{+name, +key}, rest}:
      +count = CaveChoose.count_of(entries, key)
      +tail = json_entries(rest, entries)
      Bool.pick(List<&2, String>, U32.is_zero(count), tail, ("\"" ++ name ++ "\":" ++ U32.show(count)) <> tail)

def json_line(+seed: U32) -> String:
  U32.show(seed) ++ " {" ++ String.join(json_entries(CaveCatalog.pieces(), CaveChoose.added_entries(CavePrefix.chosen(seed))), ",") ++ "}"

def print_seeds(n: Nat, +seed: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print(json_line(seed))
        print_seeds(p, (seed + 1 : U32))

def print_hits(hits: List<&2, U32>) -> IO(Unit):
  match hits:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+seed, rest}:
      do IO<Unit>:
        IO.print(json_line(seed))
        print_hits(rest)

def scan(n: Nat, +seed: U32, +bounds: List<&2, CaveFilter.Bound>, +cap: U32, +count: U32, hits: List<&2, U32>) -> U32 & List<&2, U32>:
  match n:
    case 0n:
      (count, List.reverse(&2, U32, hits))
    case 1n+p:
      +hit = CaveFilter.matches(bounds, seed)
      scan(p, (seed + 1 : U32), bounds, cap, (count + Bool.to_u32(hit) : U32), SearchCommon.keep_hit(hit, seed, count, cap, hits))

def local_bounds(bounds: List<&2, CaveFilter.Bound>) -> List<&2, CaveFilter.Bound>:
  match bounds:
    case Nil{}:
      Nil{}
    case Con{CaveFilter.Bound{+key, +low, +high}, rest}:
      CaveFilter.Bound{key, low, high} <> local_bounds(rest)

def search(+depth: Nat, +lo: U32, +n: Nat, +bounds: List<&2, CaveFilter.Bound>, +cap: U32) -> U32 & List<&2, U32>:
  match depth:
    case 0n:
      scan(n, lo, local_bounds(bounds), cap, 0, Nil{})
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = search(d, lo, half, bounds, cap) search(d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), bounds, cap)
      SearchCommon.combine(a, b)

def run_chunks(
  k: Nat, found: U32 & List<&2, U32>, +lo: U32, +left: Nat, +total: Nat, +bounds: List<&2, CaveFilter.Bound>, +started_ms: Nat, +matched: U32
) -> IO(Unit):
  match k:
    case 0n:
      (count, hits) = found
      do IO<Unit>:
        print_hits(List.take(&2, U32, hits, SearchSetpiece.room_left(matched)))
        now : Nat <- IO.now()
        IO.print_err(SearchCommon.progress_line(total, total, (matched + count : U32), Nat.sub(now, started_ms)))
    case 1n+p:
      (+count, hits) = found
      +len = Nat.min(SearchSetpiece.chunk_size(), left)
      do IO<Unit>:
        print_hits(List.take(&2, U32, hits, SearchSetpiece.room_left(matched)))
        now : Nat <- IO.now()
        IO.print_err(SearchCommon.progress_line(Nat.sub(total, left), total, (matched + count : U32), Nat.sub(now, started_ms)))
        run_chunks(p, search(SearchCommon.search_depth(), lo, len, bounds, SearchSetpiece.max_printed()), (lo + U32.from_nat(len) : U32),
          Nat.sub(left, len), total, bounds, started_ms, (matched + count : U32))

def bounds_of(+args: List<&2, String>) -> Result<&1, &1, U32 & String, List<&2, CaveFilter.Bound>>:
  CaveFilter.parse(List.drop(&2, String, args, 3n), Done{Nil{}})

def find(+args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 0)
  +to = Args.arg_u32(args, 2n, 4294967295)
  +total = Nat.add(U32.to_nat((to - from : U32)), 1n)
  do IO<Unit>:
    bounds : List<&2, CaveFilter.Bound> <- IO.pass(List<&2, CaveFilter.Bound>, bounds_of(args))
    started : Nat <- IO.now()
    run_chunks(SearchSetpiece.chunk_count(total), (0, Nil{}), from, total, total, bounds, started, 0)

def show(+args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 1)
  +to = Args.arg_u32(args, 2n, from)
  do IO<Unit>:
    unused : List<&2, CaveFilter.Bound> <- IO.pass(List<&2, CaveFilter.Bound>, bounds_of(args))
    print_seeds(Nat.add(U32.to_nat((to - from : U32)), 1n), from)
