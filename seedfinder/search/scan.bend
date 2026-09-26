import Base
import ../filters/config.bend as Config
import ../cli/args.bend as Args
import ./common.bend as SearchCommon
import ./report.bend as SearchReport
import ./worlds.bend as SearchWorlds
import ./generated.bend as SearchGenerated
import ../filters/rules.bend as Rules

def world_scan(
  n: Nat, +seed: U32, +criteria: List<&2, Config.Criteria>, +cap: U32, +count: U32, hits: List<&2, U32>
) -> U32 & List<&2, U32>:
  match n:
    case 0n:
      (count, List.reverse(&2, U32, hits))
    case 1n+p:
      +hit = Config.matches(criteria, seed)
      world_scan(p, (seed + 1 : U32), criteria, cap, (count + Bool.to_u32(hit) : U32), SearchCommon.keep_hit(hit, seed, count, cap, hits))

def world_search(+depth: Nat, +lo: U32, +n: Nat, +criteria: List<&2, Config.Criteria>, +cap: U32) -> U32 & List<&2, U32>:
  match depth:
    case 0n:
      world_scan(n, lo, Config.local_criteria(criteria), cap, 0, Nil{})
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = world_search(d, lo, half, criteria, cap) world_search(d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), criteria, cap)
      SearchCommon.combine(a, b)

type Scan is Data:
  Scan{next: U32, left: Nat, size: Nat, found: U32, hits: List<&2, U32>, code: U32, len: Nat}

def min_round() -> Nat:
  65536n

def max_round() -> Nat:
  16777216n

def round_target_ms() -> Nat:
  500n

def round_fuel() -> Nat:
  65540n

def resized(+size: Nat, +round_ms: Nat) -> Nat:
  +growth = Bool.pick(Nat, Nat.is_lt(Nat.mul(round_ms, 16n), round_target_ms()), 16n,
    Bool.pick(Nat, Nat.is_lt(Nat.mul(round_ms, 4n), round_target_ms()), 4n, 2n))
  Bool.pick(Nat, Nat.is_lt(round_ms, round_target_ms()), Nat.min(Nat.mul(size, growth), max_round()),
    Bool.pick(Nat, Nat.is_gt(round_ms, Nat.mul(round_target_ms(), 2n)), Nat.max(Nat.div(size, 2n), min_round()), size))

def next_size(+size: Nat, +len: Nat, +round_ms: Nat, +remaining_ms: Nat) -> Nat:
  +fits_in_time = Nat.div(Nat.mul(len, Nat.mul(Nat.min(remaining_ms, 100000n), 3n)), Nat.mul(Nat.max(round_ms, 1n), 4n))
  Nat.max(min_round(), Nat.min(resized(size, round_ms), fits_in_time))

def stop_code(+kept: U32, +limit: U32, +left: Nat, +elapsed: Nat, +time_ms: Nat) -> U32:
  Bool.pick(U32, (kept >= limit : U32), 1,
    Bool.pick(U32, Nat.is_eq(left, 0n), 2, Bool.pick(U32, Nat.is_ge(elapsed, time_ms), 3, 0)))

def round_len(+stop: U32, +size: Nat, +left: Nat) -> Nat:
  +whole = Nat.is_le(left, Nat.add(size, Nat.div(size, 2n)))
  Bool.pick(Nat, U32.is_zero(stop), Bool.pick(Nat, whole, left, size), 0n)

def report(+q: Args.Query, +entries: List<&2, Config.Criteria>, +scan: Scan) -> IO(Unit):
  match q:
    case Args.Query{+start, +total, _, _, json, _, +platform, _, _}:
      match scan:
        case Scan{_, +left, _, +found, +hits, +code, _}:
          SearchReport.print_report(json, U32.is_ne(platform, 2), entries, hits, start, SearchReport.scanned_of(code, hits, start, total, left), found, code)

def advance(
  +scan: Scan, +count: U32, got: List<&2, U32>, +limit: U32, +time_ms: Nat, +elapsed: Nat, +round_ms: Nat
) -> Scan:
  match scan:
    case Scan{+next, +left, +size, +found, +hits, _, +len}:
      +late = Nat.is_gt(elapsed, time_ms)
      +need = (limit - found : U32)
      +kept = Bool.pick(U32, late, found, (found + Bool.pick(U32, (count < need : U32), count, need) : U32))
      +unscanned = Bool.pick(Nat, late, Nat.add(left, len), left)
      +stop = Bool.pick(U32, late, 3, stop_code(kept, limit, unscanned, elapsed, time_ms))
      +size_next = next_size(size, len, round_ms, Nat.sub(time_ms, elapsed))
      +len_next = round_len(stop, size_next, unscanned)
      Scan{Bool.pick(U32, late, next, (next + U32.from_nat(len) : U32)), Nat.sub(unscanned, len_next), size_next, kept,
        Bool.pick(List<&2, U32>, late, hits, List.append(&2, U32, hits, List.take(&2, U32, got, U32.to_nat(need)))), stop, len_next}

def next_seed_of(+scan: Scan) -> U32:
  match scan:
    case Scan{+next, _, _, _, _, _, _}:
      next

def round_len_of(+scan: Scan) -> Nat:
  match scan:
    case Scan{_, _, _, _, _, _, +len}:
      len

def room_of(+scan: Scan, +limit: U32) -> U32:
  match scan:
    case Scan{_, _, _, +found, _, _, _}:
      (limit - found : U32)

def progress_of(+scan: Scan, +total: Nat, +elapsed: Nat) -> String:
  match scan:
    case Scan{_, +left, _, +found, _, _, +len}:
      SearchCommon.progress_line(Nat.sub(total, Nat.add(left, len)), total, found, elapsed)

def world_rounds(
  k: Nat, round: U32 & List<&2, U32>, +scan: Scan, +q: Args.Query, +entries: List<&2, Config.Criteria>,
  +criteria: List<&2, Config.Criteria>, +started: Nat, +ticked: Nat
) -> IO(Unit):
  match k:
    case 0n:
      report(q, entries, scan)
    case 1n+p:
      (+count, got) = round
      match scan:
        case Scan{_, _, _, _, _, +code, _}:
          match code:
            case 0:
              match q:
                case Args.Query{_, +total, +limit, +time_ms, _, _, _, _, _}:
                  do IO<Unit>:
                    +now : Nat <- IO.now()
                    +after : Scan = advance(scan, count, got, limit, time_ms, Nat.sub(now, started), Nat.sub(now, ticked))
                    +from : U32 = next_seed_of(after)
                    +len : Nat = round_len_of(after)
                    +room : U32 = room_of(after, limit)
                    IO.print_err(progress_of(after, total, Nat.sub(now, started)))
                    world_rounds(p, world_search(SearchCommon.search_depth(), from, len, criteria, room), after, q, entries, criteria, started, now)
            case _:
              report(q, entries, scan)

def level_rounds(+q: Args.Query, +config: Config.Config) -> IO(Unit):
  match q config:
    case Args.Query{+start, +total, +limit, +time_ms, +json, _, _, _, _} Config.Config{+windows, +entries, _, _, +scanned}:
      do IO<Unit>:
        +started : Nat <- IO.now()
        world_rounds(round_fuel(), (0, Nil{}), Scan{start, total, min_round(), 0, Nil{}, 0, 0n},
          Args.Query{start, total, limit, time_ms, json, None{}, Bool.pick(U32, windows, 1, 2), None{}, True{}}, entries, scanned, started, started)

def any_rules(laters: List<&2, Rules.Later>) -> Bool:
  match laters:
    case Nil{}:
      False{}
    case Con{+later, rest}:
      Rules.has_rules(later) || any_rules(rest)

def with_worlds(worlds: Maybe<&2, String>, +q: Args.Query, +config: Config.Config) -> IO(Unit):
  match worlds config:
    case None{} Config.Config{_, _, +laters, _, _}:
      Bool.pick(IO(Unit), any_rules(laters), SearchGenerated.run(q, config), level_rounds(q, config))
    case Some{+dir} Config.Config{_, _, +laters, _, _}:
      Bool.pick(IO(Unit), any_rules(laters), SearchWorlds.run(q, config, dir), level_rounds(q, config))

def with_platform(+config: Config.Config, +platform: U32) -> Config.Config:
  match config:
    case Config.Config{+windows, +criteria, +laters, +unsupported, +scanned}:
      Config.Config{Bool.pick(Bool, U32.is_zero(platform), windows, U32.is_eq(platform, 1)), criteria, laters, unsupported, scanned}

# world find: the level-table scan, or (with parts B-E) the search over worlds generated in memory, or with
# --worlds DIR over pre-generated world dumps. --platform overrides the config's platform.
def run_query(+q: Args.Query, loaded: Result<&1, &1, U32 & String, Config.Config>) -> IO(Unit):
  match q loaded:
    case Args.Query{_, _, _, _, +json, _, _, _, _} Fail{failure}:
      SearchReport.fail_job(json, failure)
    case Args.Query{_, _, _, _, _, _, +platform, +worlds, _} Done{+config}:
      with_worlds(worlds, q, with_platform(config, platform))
