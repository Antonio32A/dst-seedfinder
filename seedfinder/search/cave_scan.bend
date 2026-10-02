import Base
import ../filters/cave_config.bend as CaveConfig
import ../filters/shard_search.bend as ShardSearch
import ../cli/args.bend as Args
import ../level/cave_summary.bend as CaveSummary
import ./common.bend as SearchCommon
import ./report.bend as SearchReport
import ./scan.bend as SearchScan
import ./generated.bend as SearchGenerated
import ./worlds.bend as SearchWorlds

# `world find` and `world show` on the caves shard: the level table scan of scan.bend over CaveConfig criteria.

def world_line(+seed: U32) -> String:
  U32.show(seed) ++ " " ++ CaveSummary.summary_json(seed)

def world_print_seeds(n: Nat, +seed: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print(world_line(seed))
        world_print_seeds(p, (seed + 1 : U32))

def world_scan(
  n: Nat, +seed: U32, +criteria: List<&2, CaveConfig.Criteria>, +cap: U32, +count: U32, hits: List<&2, U32>
) -> U32 & List<&2, U32>:
  match n:
    case 0n:
      (count, List.reverse(&2, U32, hits))
    case 1n+p:
      +hit = CaveConfig.matches(criteria, seed)
      world_scan(p, (seed + 1 : U32), criteria, cap, (count + Bool.to_u32(hit) : U32), SearchCommon.keep_hit(hit, seed, count, cap, hits))

def world_search(+depth: Nat, +lo: U32, +n: Nat, +criteria: List<&2, CaveConfig.Criteria>, +cap: U32) -> U32 & List<&2, U32>:
  match depth:
    case 0n:
      world_scan(n, lo, CaveConfig.local_criteria(criteria), cap, 0, Nil{})
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = world_search(d, lo, half, criteria, cap) world_search(d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), criteria, cap)
      SearchCommon.combine(a, b)

def hit_fields(+entries: List<&2, CaveConfig.Criteria>, +seed: U32) -> String:
  "\"entry\":" ++ U32.show(CaveConfig.first_match(entries, seed)) ++ ",\"level\":" ++ CaveSummary.summary_json(seed) ++ ",\"results\":[]"

def hits_of(+entries: List<&2, CaveConfig.Criteria>, hits: List<&2, U32>) -> List<&2, SearchReport.Hit>:
  match hits:
    case Nil{}:
      Nil{}
    case Con{+seed, rest}:
      SearchReport.Hit{seed, hit_fields(entries, seed)} <> hits_of(entries, rest)

def report(+q: Args.Query, +entries: List<&2, CaveConfig.Criteria>, +scan: SearchScan.Scan) -> IO(Unit):
  match q:
    case Args.Query{+start, +total, _, _, json, _, +platform, _, _}:
      match scan:
        case SearchScan.Scan{_, +left, _, +found, +hits, +code, _}:
          SearchReport.print_hits_report(json, U32.is_ne(platform, 2), hits_of(entries, hits), start, SearchReport.scanned_of(code, hits, start, total, left), found, code)

def world_rounds(
  k: Nat, round: U32 & List<&2, U32>, +scan: SearchScan.Scan, +q: Args.Query, +entries: List<&2, CaveConfig.Criteria>,
  +criteria: List<&2, CaveConfig.Criteria>, +started: Nat, +ticked: Nat
) -> IO(Unit):
  match k:
    case 0n:
      report(q, entries, scan)
    case 1n+p:
      (+count, got) = round
      match scan:
        case SearchScan.Scan{_, _, _, _, _, +code, _}:
          match code:
            case 0:
              match q:
                case Args.Query{_, +total, +limit, +time_ms, _, _, _, _, _}:
                  do IO<Unit>:
                    +now : Nat <- IO.now()
                    +after : SearchScan.Scan = SearchScan.advance(scan, count, got, limit, time_ms, Nat.sub(now, started), Nat.sub(now, ticked))
                    +from : U32 = SearchScan.next_seed_of(after)
                    +len : Nat = SearchScan.round_len_of(after)
                    +room : U32 = SearchScan.room_of(after, limit)
                    IO.print_err(SearchScan.progress_of(after, total, Nat.sub(now, started)))
                    world_rounds(p, world_search(SearchCommon.search_depth(), from, len, criteria, room), after, q, entries, criteria, started, now)
            case _:
              report(q, entries, scan)

def level_rounds(+q: Args.Query, +config: CaveConfig.Config) -> IO(Unit):
  match q config:
    case Args.Query{+start, +total, +limit, +time_ms, +json, _, _, _, _} CaveConfig.Config{+windows, +entries, _, +scanned}:
      do IO<Unit>:
        +started : Nat <- IO.now()
        world_rounds(SearchScan.round_fuel(), (0, Nil{}), SearchScan.Scan{start, total, SearchScan.min_round(), 0, Nil{}, 0, 0n},
          Args.Query{start, total, limit, time_ms, json, None{}, Bool.pick(U32, windows, 1, 2), None{}, True{}}, entries, scanned, started, started)

# world find on the caves shard: the level table scan, or (with parts B-E) the search over caves worlds generated in
# memory, or with --worlds DIR over pre-generated caves world dumps.
def run_query(+q: Args.Query, +config: CaveConfig.Config) -> IO(Unit):
  match q config:
    case Args.Query{_, _, _, _, _, _, _, None{}, _} CaveConfig.Config{_, _, +laters, _}:
      Bool.pick(IO(Unit), SearchScan.any_rules(laters), SearchGenerated.run(q, ShardSearch.of_caves(config)), level_rounds(q, config))
    case Args.Query{_, _, _, _, _, _, _, Some{+dir}, _} CaveConfig.Config{_, _, +laters, _}:
      Bool.pick(IO(Unit), SearchScan.any_rules(laters), SearchWorlds.run(q, ShardSearch.of_caves(config), dir), level_rounds(q, config))
