import Base
import ../data/catalog.bend as Catalog
import ../level/setpieces.bend as LevelSetpieces
import ../filters/setpiece.bend as FilterSetpiece
import ../cli/args.bend as Args
import ./common.bend as SearchCommon
import ../data/catalog_types.bend as CatalogTypes
import ../data/builds.bend as Builds

def chunk_size() -> Nat:
  16777216n

def max_printed() -> U32:
  1000

def json_entries(+build: Builds.Build, entries: List<&2, CatalogTypes.Entry>, +p: LevelSetpieces.Pieces) -> List<&2, String>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{CatalogTypes.Entry{+name, +kind, +index}, rest}:
      +count = LevelSetpieces.count_of(build, p, kind, index)
      +tail = json_entries(build, rest, p)
      Bool.pick(List<&2, String>, U32.is_zero(count), tail, ("\"" ++ name ++ "\":" ++ U32.show(count)) <> tail)

def json_line(+build: Builds.Build, +seed: U32) -> String:
  U32.show(seed) ++ " {" ++ String.join(json_entries(build, Catalog.catalog(build), LevelSetpieces.generate(build, seed)), ",") ++ "}"

def print_seeds(+build: Builds.Build, n: Nat, +seed: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print(json_line(build, seed))
        print_seeds(build, p, (seed + 1 : U32))

def print_hits(+build: Builds.Build, hits: List<&2, U32>) -> IO(Unit):
  match hits:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+seed, rest}:
      do IO<Unit>:
        IO.print(json_line(build, seed))
        print_hits(build, rest)

def scan(+build: Builds.Build, n: Nat, +seed: U32, +f: FilterSetpiece.Filter, +cap: U32, +count: U32, hits: List<&2, U32>) -> U32 & List<&2, U32>:
  match n:
    case 0n:
      (count, List.reverse(&2, U32, hits))
    case 1n+p:
      +hit = FilterSetpiece.matches(f, LevelSetpieces.generate(build, seed))
      scan(build, p, (seed + 1 : U32), f, cap, (count + Bool.to_u32(hit) : U32), SearchCommon.keep_hit(hit, seed, count, cap, hits))

def local_filter(+f: FilterSetpiece.Filter) -> FilterSetpiece.Filter:
  match f:
    case FilterSetpiece.Filter{+a, +b, +c, +d, +e, +g, +h, +i, +j, +k, +l}:
      FilterSetpiece.Filter{a, b, c, d, e, g, h, i, j, k, l}

def search(+build: Builds.Build, +depth: Nat, +lo: U32, +n: Nat, +f: FilterSetpiece.Filter, +cap: U32) -> U32 & List<&2, U32>:
  match depth:
    case 0n:
      scan(build, n, lo, local_filter(f), cap, 0, Nil{})
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = search(build, d, lo, half, f, cap) search(build, d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), f, cap)
      SearchCommon.combine(a, b)

def room_left(+matched: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, (matched < max_printed() : U32), (max_printed() - matched : U32), 0))

def run_chunks(
  +build: Builds.Build, k: Nat, found: U32 & List<&2, U32>, +lo: U32, +left: Nat, +total: Nat, +f: FilterSetpiece.Filter, +started_ms: Nat, +matched: U32
) -> IO(Unit):
  match k:
    case 0n:
      (count, hits) = found
      do IO<Unit>:
        print_hits(build, List.take(&2, U32, hits, room_left(matched)))
        now : Nat <- IO.now()
        IO.print_err(SearchCommon.progress_line(total, total, (matched + count : U32), Nat.sub(now, started_ms)))
    case 1n+p:
      (+count, hits) = found
      +len = Nat.min(chunk_size(), left)
      do IO<Unit>:
        print_hits(build, List.take(&2, U32, hits, room_left(matched)))
        now : Nat <- IO.now()
        IO.print_err(SearchCommon.progress_line(Nat.sub(total, left), total, (matched + count : U32), Nat.sub(now, started_ms)))
        run_chunks(build, p, search(build, SearchCommon.search_depth(), lo, len, f, max_printed()), (lo + U32.from_nat(len) : U32),
          Nat.sub(left, len), total, f, started_ms, (matched + count : U32))

def chunk_count(+n: Nat) -> Nat:
  Nat.div(Nat.add(n, Nat.sub(chunk_size(), 1n)), chunk_size())

def filter_of(+build: Builds.Build, +args: List<&2, String>) -> Result<&1, &1, U32 & String, FilterSetpiece.Filter>:
  FilterSetpiece.parse(build, List.drop(&2, String, args, 3n), Done{FilterSetpiece.unfiltered()})

def find(+build: Builds.Build, +args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 0)
  +to = Args.arg_u32(args, 2n, 4294967295)
  +total = Nat.add(U32.to_nat((to - from : U32)), 1n)
  do IO<Unit>:
    f : FilterSetpiece.Filter <- IO.pass(FilterSetpiece.Filter, filter_of(build, args))
    started : Nat <- IO.now()
    run_chunks(build, chunk_count(total), (0, Nil{}), from, total, total, f, started, 0)

def show(+build: Builds.Build, +args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 1)
  +to = Args.arg_u32(args, 2n, from)
  do IO<Unit>:
    unused : FilterSetpiece.Filter <- IO.pass(FilterSetpiece.Filter, filter_of(build, args))
    print_seeds(build, Nat.add(U32.to_nat((to - from : U32)), 1n), from)
