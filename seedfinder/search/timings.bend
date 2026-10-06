import Base
import ../filters/shard_search.bend as ShardSearch
import ../filters/evaluate.bend as Evaluate
import ../filters/rules.bend as Rules
import ../filters/world.bend as FilterWorld
import ../filters/par.bend as Par
import ./common.bend as SearchCommon

# `world find --verbose-timings` (docs/config.md section 8): where the search spends its time, per option (criteria
# entry). Each option's level table is checked on its own over every prefiltered seed, and each rule of an option is
# checked on all the worlds of a round at once, between two clock reads, so the search runs slower than without it.

# The ms of one rule of an option, labelled as its witness is (`section`, `index`).
type Rule is Data:
  Rule{section: String, index: U32, ms: Nat}

# One option: the ms its level table took over the prefiltered seeds and how many passed it, the worlds its rules were
# checked on, and its rules.
type Option is Data:
  Option{prefilter_ms: Nat, passed: Nat, worlds: Nat, rules: List<&2, Rule>}

# The seeds the options' level tables went over, the ms of the search's own prefilter (the level tables of the options
# that pick the candidates), of the world generation (the CPU stages and the waits for KK passes) and of the hits'
# witnesses and level tables, and the options in entry order.
type Timings is Data:
  Timings{seeds: Nat, prefilter_ms: Nat, generation_ms: Nat, hits_ms: Nat, options: List<&2, Option>}

def job_rule(+job: Evaluate.Job) -> Rule:
  match job:
    case Evaluate.JCount{+i, _}:
      Rule{"counts", i, 0n}
    case Evaluate.JTiles{+i, _}:
      Rule{"tiles", i, 0n}
    case Evaluate.JDistance{+i, _}:
      Rule{"distances", i, 0n}
    case Evaluate.JBridge{+i, _}:
      Rule{"bridges", i, 0n}
    case Evaluate.JRoute{+i, _}:
      Rule{"routes", i, 0n}

def job_rules(jobs: List<&2, Evaluate.Job>) -> List<&2, Rule>:
  match jobs:
    case Nil{}:
      Nil{}
    case Con{+job, rest}:
      job_rule(job) <> job_rules(rest)

def started_options(laters: List<&2, Rules.Later>) -> List<&2, Option>:
  match laters:
    case Nil{}:
      Nil{}
    case Con{+later, rest}:
      Option{0n, 0n, 0n, job_rules(Evaluate.jobs_of(later))} <> started_options(rest)

# Nothing timed yet, for the options with parts B-E `laters`.
def started(+laters: List<&2, Rules.Later>) -> Timings:
  Timings{0n, 0n, 0n, 0n, started_options(laters)}

def counted(+depth: Nat, +lo: U32, +n: Nat, +levels: ShardSearch.Levels) -> Nat:
  match depth:
    case 0n:
      ShardSearch.count_leaf(levels, lo, n)
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = counted(d, lo, half, levels) counted(d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), levels)
      Nat.add(a, b)

def prefiltered_options(entries: List<&2, ShardSearch.Levels>, options: List<&2, Option>, +lo: U32, +len: Nat) -> IO(List<&2, Option>):
  match entries options:
    case Con{+levels, rest} Con{Option{+ms, +passed, +worlds, +rules}, more}:
      do IO<List<&2, Option>>:
        +t0 : Nat <- IO.now()
        +n : Nat = counted(SearchCommon.search_depth(), lo, len, levels)
        +t1 : Nat <- IO.now()
        after : List<&2, Option> <- prefiltered_options(rest, more, lo, len)
        return Option{Nat.add(ms, Nat.sub(t1, t0)), Nat.add(passed, n), worlds, rules} <> after
    case _ _:
      IO.pure(List<&2, Option>, Nil{})

# Each option's level table over the seeds lo..lo+len-1 on its own (`entries`: ShardSearch.each_entry), timed.
def prefiltered(+t: Timings, +entries: List<&2, ShardSearch.Levels>, +lo: U32, +len: Nat) -> IO(Timings):
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options}:
      do IO<Timings>:
        after : List<&2, Option> <- prefiltered_options(entries, options, lo, len)
        return Timings{Nat.add(seeds, len), prefilter_ms, generation_ms, hits_ms, after}

def with_prefilter(+t: Timings, +ms: Nat) -> Timings:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options}:
      Timings{seeds, Nat.add(prefilter_ms, ms), generation_ms, hits_ms, options}

def with_generation(+t: Timings, +ms: Nat) -> Timings:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options}:
      Timings{seeds, prefilter_ms, Nat.add(generation_ms, ms), hits_ms, options}

def with_hits(+t: Timings, +ms: Nat) -> Timings:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options}:
      Timings{seeds, prefilter_ms, generation_ms, Nat.add(hits_ms, ms), options}

# A world being decided: the world (None when there is nothing to check), whether the level table of its seed
# satisfies each option not checked yet, and the option that matched it.
type Open is Data:
  Open{world: Maybe<&2, FilterWorld.World>, flags: List<&2, Bool>, found: Maybe<&2, U32>}

def holds_on(job: Evaluate.Job, m: Maybe<&2, FilterWorld.World>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{world}:
      Evaluate.job_verdict(world, job)

def masked(+passed: List<&2, Bool>, +worlds: List<&2, Maybe<&2, FilterWorld.World>>) -> List<&2, Maybe<&2, FilterWorld.World>>:
  match passed worlds:
    case Con{+ok, ps} Con{+m, ms}:
      Bool.pick(Maybe<&2, FilterWorld.World>, ok, m, None{}) <> masked(ps, ms)
    case _ _:
      Nil{}

def both(+a: List<&2, Bool>, +b: List<&2, Bool>) -> List<&2, Bool>:
  match a b:
    case Con{+x, xs} Con{+y, ys}:
      (x && y) <> both(xs, ys)
    case _ _:
      Nil{}

# Rules after their checks, and whether each world passed them all.
type Ran is Data:
  Ran{rules: List<&2, Rule>, held: List<&2, Bool>}

def rule_before(+r: Rule, +got: Ran) -> Ran:
  match got:
    case Ran{+rules, +held}:
      Ran{r <> rules, held}

# The rules over the worlds, each timed (the routes only on the worlds whose earlier rules held, as
# Evaluate.parallel_holds checks them): the rules with their ms added, and whether each world passed them all.
def timed_rules(jobs: List<&2, Evaluate.Job>, rules: List<&2, Rule>, +worlds: List<&2, Maybe<&2, FilterWorld.World>>, +passed: List<&2, Bool>) -> IO(Ran):
  match jobs rules:
    case Con{+job, js} Con{Rule{+section, +index, +ms}, rs}:
      +targets = Bool.pick(List<&2, Maybe<&2, FilterWorld.World>>, Evaluate.is_route(job), masked(passed, worlds), worlds)
      do IO<Ran>:
        +t0 : Nat <- IO.now()
        +oks : List<&2, Bool> = Par.map(~Maybe<&2, FilterWorld.World>, ~Bool, ~Evaluate.Job, ~holds_on, job, targets)
        +t1 : Nat <- IO.now()
        +after : Ran <- timed_rules(js, rs, worlds, both(passed, oks))
        return rule_before(Rule{section, index, Nat.add(ms, Nat.sub(t1, t0))}, after)
    case _ _:
      IO.pure(Ran, Ran{Nil{}, passed})

def first_flag(+flags: List<&2, Bool>) -> Bool:
  Maybe.default(&2, Bool, List.head(&2, Bool, flags), False{})

def checked_world(+o: Open) -> Maybe<&2, FilterWorld.World>:
  match o:
    case Open{+world, +flags, None{}}:
      Bool.pick(Maybe<&2, FilterWorld.World>, first_flag(flags), world, None{})
    case _:
      None{}

def checked_worlds(opens: List<&2, Open>) -> List<&2, Maybe<&2, FilterWorld.World>>:
  match opens:
    case Nil{}:
      Nil{}
    case Con{+o, rest}:
      checked_world(o) <> checked_worlds(rest)

def is_some(+m: Maybe<&2, FilterWorld.World>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{_}:
      True{}

def checks(worlds: List<&2, Maybe<&2, FilterWorld.World>>) -> Nat:
  match worlds:
    case Nil{}:
      0n
    case Con{+m, rest}:
      Nat.add(Bool.pick(Nat, is_some(m), 1n, 0n), checks(rest))

def all_true(+n: Nat) -> List<&2, Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      True{} <> all_true(p)

def matched(+found: Maybe<&2, U32>, +hit: Bool, +index: U32) -> Maybe<&2, U32>:
  match found:
    case None{}:
      Bool.pick(Maybe<&2, U32>, hit, Some{index}, None{})
    case Some{+i}:
      Some{i}

# The worlds after option `index`: matched where it was checked and held, its flag dropped.
def stepped(opens: List<&2, Open>, +checked: List<&2, Maybe<&2, FilterWorld.World>>, +held: List<&2, Bool>, +index: U32) -> List<&2, Open>:
  match opens checked held:
    case Con{Open{+world, +flags, +found}, rest} Con{+m, ms} Con{+ok, oks}:
      Open{world, List.drop(&2, Bool, flags, 1n), matched(found, is_some(m) && ok, index)} <> stepped(rest, ms, oks, index)
    case _ _ _:
      Nil{}

def held_of(+got: Ran) -> List<&2, Bool>:
  match got:
    case Ran{_, +held}:
      held

def rules_of(+got: Ran) -> List<&2, Rule>:
  match got:
    case Ran{+rules, _}:
      rules

# Options after their checks, and the worlds with the option that matched each.
type Decided is Data:
  Decided{options: List<&2, Option>, opens: List<&2, Open>}

def option_before(+o: Option, +got: Decided) -> Decided:
  match got:
    case Decided{+options, +opens}:
      Decided{o <> options, opens}

# The options one after the other on the worlds no earlier option matched and whose level table they pass: the timed
# options, and the worlds with the option that matched each.
def judged_options(laters: List<&2, Rules.Later>, options: List<&2, Option>, +index: U32, +opens: List<&2, Open>) -> IO(Decided):
  match laters options:
    case Con{+later, ls} Con{Option{+prefilter_ms, +passed, +worlds, +rules}, os}:
      +checked = checked_worlds(opens)
      do IO<Decided>:
        +got : Ran <- timed_rules(Evaluate.jobs_of(later), rules, checked, all_true(List.length(&2, Maybe<&2, FilterWorld.World>, checked)))
        +after : Decided <- judged_options(ls, os, (index + 1 : U32), stepped(opens, checked, held_of(got), index))
        return option_before(Option{prefilter_ms, passed, Nat.add(worlds, checks(checked)), rules_of(got)}, after)
    case _ _:
      IO.pure(Decided, Decided{Nil{}, opens})

# The timings and the worlds with the option that matched each.
type Judged is Data:
  Judged{timings: Timings, opens: List<&2, Open>}

def timed_with(+seeds: Nat, +prefilter_ms: Nat, +generation_ms: Nat, +hits_ms: Nat, +got: Decided) -> Judged:
  match got:
    case Decided{+options, +opens}:
      Judged{Timings{seeds, prefilter_ms, generation_ms, hits_ms, options}, opens}

# The worlds decided option by option, every rule timed (the worlds keep their order).
def judged(+t: Timings, +laters: List<&2, Rules.Later>, +opens: List<&2, Open>) -> IO(Judged):
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options}:
      do IO<Judged>:
        +got : Decided <- judged_options(laters, options, 0, opens)
        return timed_with(seeds, prefilter_ms, generation_ms, hits_ms, got)

def rule_json(+r: Rule) -> String:
  match r:
    case Rule{+section, +index, +ms}:
      "{\"section\":\"" ++ section ++ "\",\"index\":" ++ U32.show(index) ++ ",\"ms\":" ++ Nat.show(ms) ++ "}"

def rules_json(rules: List<&2, Rule>) -> List<&2, String>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{+r, rest}:
      rule_json(r) <> rules_json(rest)

def option_json(+o: Option) -> String:
  match o:
    case Option{+prefilter_ms, +passed, +worlds, +rules}:
      "{\"prefilter_ms\":" ++ Nat.show(prefilter_ms) ++ ",\"passed\":" ++ Nat.show(passed) ++ ",\"worlds\":" ++ Nat.show(worlds)
        ++ ",\"rules\":[" ++ String.join(rules_json(rules), ",") ++ "]}"

def options_json(options: List<&2, Option>) -> List<&2, String>:
  match options:
    case Nil{}:
      Nil{}
    case Con{+o, rest}:
      option_json(o) <> options_json(rest)

# `timings {...}`, `elapsed_ms` into the run.
def line(+t: Timings, +elapsed_ms: Nat) -> String:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options}:
      "timings {\"elapsed_ms\":" ++ Nat.show(elapsed_ms) ++ ",\"seeds\":" ++ Nat.show(seeds) ++ ",\"prefilter_ms\":" ++ Nat.show(prefilter_ms) ++ ",\"generation_ms\":" ++ Nat.show(generation_ms) ++ ",\"hits_ms\":" ++ Nat.show(hits_ms)
        ++ ",\"options\":[" ++ String.join(options_json(options), ",") ++ "]}"

def print_if(on: Bool, +t: Timings, +elapsed_ms: Nat) -> IO(Unit):
  match on:
    case True{}:
      IO.print_err(line(t, elapsed_ms))
    case False{}:
      IO.pure(Unit, Unit{})
