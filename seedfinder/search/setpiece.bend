import Base
import ../data/catalog.bend as Catalog
import ../level/setpieces.bend as LevelSetpieces
import ../filters/setpiece.bend as FilterSetpiece
import ../cli/args.bend as Args
import ./common.bend as SearchCommon

def chunk_size() -> Nat:
  16777216n

def max_printed() -> U32:
  1000

def json_entries(entries: List<&2, Catalog.Entry>, +p: LevelSetpieces.Pieces) -> List<&2, String>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Catalog.Entry{+name, +kind, +index}, rest}:
      +count = LevelSetpieces.count_of(p, kind, index)
      +tail = json_entries(rest, p)
      Bool.pick(List<&2, String>, U32.is_zero(count), tail, ("\"" ++ name ++ "\":" ++ U32.show(count)) <> tail)

def json_line(+seed: U32) -> String:
  U32.show(seed) ++ " {" ++ String.join(json_entries(Catalog.catalog(), LevelSetpieces.generate(seed)), ",") ++ "}"

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

def scan(n: Nat, +seed: U32, +f: FilterSetpiece.Filter, +cap: U32, +count: U32, hits: List<&2, U32>) -> U32 & List<&2, U32>:
  match n:
    case 0n:
      (count, List.reverse(&2, U32, hits))
    case 1n+p:
      +hit = FilterSetpiece.matches(f, LevelSetpieces.generate(seed))
      scan(p, (seed + 1 : U32), f, cap, (count + Bool.to_u32(hit) : U32), SearchCommon.keep_hit(hit, seed, count, cap, hits))

def local_filter(+f: FilterSetpiece.Filter) -> FilterSetpiece.Filter:
  match f:
    case FilterSetpiece.Filter{+a, +b, +c, +d, +e, +g, +h, +i, +j, +k, +l}:
      FilterSetpiece.Filter{a, b, c, d, e, g, h, i, j, k, l}

def search(+depth: Nat, +lo: U32, +n: Nat, +f: FilterSetpiece.Filter, +cap: U32) -> U32 & List<&2, U32>:
  match depth:
    case 0n:
      scan(n, lo, local_filter(f), cap, 0, Nil{})
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = search(d, lo, half, f, cap) search(d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), f, cap)
      SearchCommon.combine(a, b)

def room_left(+matched: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, (matched < max_printed() : U32), (max_printed() - matched : U32), 0))

def run_chunks(
  k: Nat, found: U32 & List<&2, U32>, +lo: U32, +left: Nat, +total: Nat, +f: FilterSetpiece.Filter, +started_ms: Nat, +matched: U32
) -> IO(Unit):
  match k:
    case 0n:
      (count, hits) = found
      do IO<Unit>:
        print_hits(List.take(&2, U32, hits, room_left(matched)))
        now : Nat <- IO.now()
        IO.print_err(SearchCommon.progress_line(total, total, (matched + count : U32), Nat.sub(now, started_ms)))
    case 1n+p:
      (+count, hits) = found
      +len = Nat.min(chunk_size(), left)
      do IO<Unit>:
        print_hits(List.take(&2, U32, hits, room_left(matched)))
        now : Nat <- IO.now()
        IO.print_err(SearchCommon.progress_line(Nat.sub(total, left), total, (matched + count : U32), Nat.sub(now, started_ms)))
        run_chunks(p, search(SearchCommon.search_depth(), lo, len, f, max_printed()), (lo + U32.from_nat(len) : U32),
          Nat.sub(left, len), total, f, started_ms, (matched + count : U32))

def chunk_count(+n: Nat) -> Nat:
  Nat.div(Nat.add(n, Nat.sub(chunk_size(), 1n)), chunk_size())

def filter_of(+args: List<&2, String>) -> Result<&1, &1, U32 & String, FilterSetpiece.Filter>:
  FilterSetpiece.parse(List.drop(&2, String, args, 3n), Done{FilterSetpiece.unfiltered()})

def find(+args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 0)
  +to = Args.arg_u32(args, 2n, 4294967295)
  +total = Nat.add(U32.to_nat((to - from : U32)), 1n)
  do IO<Unit>:
    f : FilterSetpiece.Filter <- IO.pass(FilterSetpiece.Filter, filter_of(args))
    started : Nat <- IO.now()
    run_chunks(chunk_count(total), (0, Nil{}), from, total, total, f, started, 0)

def show(+args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 1)
  +to = Args.arg_u32(args, 2n, from)
  do IO<Unit>:
    unused : FilterSetpiece.Filter <- IO.pass(FilterSetpiece.Filter, filter_of(args))
    print_seeds(Nat.add(U32.to_nat((to - from : U32)), 1n), from)
