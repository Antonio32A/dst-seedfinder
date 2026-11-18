import Base
import ../filters/evaluate.bend as Evaluate
import ../filters/rules.bend as Rules
import ../filters/world.bend as FilterWorld
import ../filters/par.bend as Par
import ../data/builds.bend as Builds

# `world find --verbose-timings` (docs/config.md section 8): where the search spends its time, per option (`filters`
# entry). Each rule of an option is checked on all the worlds of a round at once, between two clock reads, so the
# search runs slower than without it.

# The ms of one rule of an option, labelled as its witness is (`section`, `index`).
type Rule is Data:
  Rule{section: String, index: U32, ms: Nat}

# One option: the worlds its rules were checked on, and its rules.
type Option is Data:
  Option{worlds: Nat, rules: List<&2, Rule>}

# The early check of a caves search (search/generated.bend): the early worlds it checked, how many of them were misses,
# and per option the worlds its early jobs were checked on and their ms.
type Early is Data:
  Early{worlds: Nat, misses: Nat, options: List<&2, Option>}

# The seeds the prefilter went over, the ms of the prefilter (the level table of `generation`), of the world generation
# (the CPU stages and the waits for KK passes) and of the hits' witnesses and level tables, the options in filter
# order, and the early check.
type Timings is Data:
  Timings{seeds: Nat, prefilter_ms: Nat, generation_ms: Nat, hits_ms: Nat, options: List<&2, Option>, early: Early}

def job_rule(+job: Evaluate.Job) -> Rule:
  match job:
    case Evaluate.JPlaced{+rule}:
      Rule{"setpieces", Rules.placed_index(rule), 0n}
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

def laters_jobs(laters: List<&2, Rules.Later>) -> List<&2, List<&2, Evaluate.Job>>:
  match laters:
    case Nil{}:
      Nil{}
    case Con{+later, rest}:
      Evaluate.jobs_of(later) <> laters_jobs(rest)

def started_options(jobs: List<&2, List<&2, Evaluate.Job>>) -> List<&2, Option>:
  match jobs:
    case Nil{}:
      Nil{}
    case Con{+js, rest}:
      Option{0n, job_rules(js)} <> started_options(rest)

# Nothing timed yet, for the options with parts B-E `laters`.
def started(+laters: List<&2, Rules.Later>) -> Timings:
  Timings{0n, 0n, 0n, 0n, started_options(laters_jobs(laters)), Early{0n, 0n, Nil{}}}

# Nothing timed yet, with an early check of these early jobs per option.
def with_early_jobs(+t: Timings, +jobs: List<&2, List<&2, Evaluate.Job>>) -> Timings:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options, _}:
      Timings{seeds, prefilter_ms, generation_ms, hits_ms, options, Early{0n, 0n, started_options(jobs)}}

# After the prefilter went over `len` more seeds in `ms`.
def with_prefilter(+t: Timings, +len: Nat, +ms: Nat) -> Timings:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options, +early}:
      Timings{Nat.add(seeds, len), Nat.add(prefilter_ms, ms), generation_ms, hits_ms, options, early}

def with_generation(+t: Timings, +ms: Nat) -> Timings:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options, +early}:
      Timings{seeds, prefilter_ms, Nat.add(generation_ms, ms), hits_ms, options, early}

def with_hits(+t: Timings, +ms: Nat) -> Timings:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options, +early}:
      Timings{seeds, prefilter_ms, generation_ms, Nat.add(hits_ms, ms), options, early}

# A world being decided: the world (None when there is nothing to check) and the option that matched it.
type Open is Data:
  Open{world: Maybe<&2, FilterWorld.World>, found: Maybe<&2, U32>}

def job_holds_on(+build: Builds.Build, job: Evaluate.Job, m: Maybe<&2, FilterWorld.World>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{world}:
      Evaluate.job_verdict(Evaluate.BuildWorld{build, world}, job)

# A rule's job with the game build of the worlds it checks.
type BuildJob is Data:
  BuildJob{build: Builds.Build, job: Evaluate.Job}

def holds_on(on: BuildJob, m: Maybe<&2, FilterWorld.World>) -> Bool:
  match on:
    case BuildJob{+build, job}:
      job_holds_on(build, job, m)

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
def timed_rules(+build: Builds.Build, jobs: List<&2, Evaluate.Job>, rules: List<&2, Rule>, +worlds: List<&2, Maybe<&2, FilterWorld.World>>, +passed: List<&2, Bool>) -> IO(Ran):
  match jobs rules:
    case Con{+job, js} Con{Rule{+section, +index, +ms}, rs}:
      +targets = Bool.pick(List<&2, Maybe<&2, FilterWorld.World>>, Evaluate.is_route(job), masked(passed, worlds), worlds)
      do IO<Ran>:
        +t0 : Nat <- IO.now()
        +oks : List<&2, Bool> = Par.map(~Maybe<&2, FilterWorld.World>, ~Bool, ~BuildJob, ~holds_on, BuildJob{build, job}, targets)
        +t1 : Nat <- IO.now()
        +after : Ran <- timed_rules(build, js, rs, worlds, both(passed, oks))
        return rule_before(Rule{section, index, Nat.add(ms, Nat.sub(t1, t0))}, after)
    case _ _:
      IO.pure(Ran, Ran{Nil{}, passed})

def checked_world(+o: Open) -> Maybe<&2, FilterWorld.World>:
  match o:
    case Open{+world, None{}}:
      world
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

# The worlds after option `index`: matched where it was checked and held.
def stepped(opens: List<&2, Open>, +checked: List<&2, Maybe<&2, FilterWorld.World>>, +held: List<&2, Bool>, +index: U32) -> List<&2, Open>:
  match opens checked held:
    case Con{Open{+world, +found}, rest} Con{+m, ms} Con{+ok, oks}:
      Open{world, matched(found, is_some(m) && ok, index)} <> stepped(rest, ms, oks, index)
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

# The options (the jobs of each) one after the other on the worlds no earlier option matched: the timed options, and
# the worlds with the option that matched each.
def judged_options(+build: Builds.Build, jobs: List<&2, List<&2, Evaluate.Job>>, options: List<&2, Option>, +index: U32, +opens: List<&2, Open>) -> IO(Decided):
  match jobs options:
    case Con{+js, rest} Con{Option{+worlds, +rules}, os}:
      +checked = checked_worlds(opens)
      do IO<Decided>:
        +got : Ran <- timed_rules(build, js, rules, checked, all_true(List.length(&2, Maybe<&2, FilterWorld.World>, checked)))
        +after : Decided <- judged_options(build, rest, os, (index + 1 : U32), stepped(opens, checked, held_of(got), index))
        return option_before(Option{Nat.add(worlds, checks(checked)), rules_of(got)}, after)
    case _ _:
      IO.pure(Decided, Decided{Nil{}, opens})

# The timings and the worlds with the option that matched each.
type Judged is Data:
  Judged{timings: Timings, opens: List<&2, Open>}

def timed_with(+seeds: Nat, +prefilter_ms: Nat, +generation_ms: Nat, +hits_ms: Nat, +early: Early, +got: Decided) -> Judged:
  match got:
    case Decided{+options, +opens}:
      Judged{Timings{seeds, prefilter_ms, generation_ms, hits_ms, options, early}, opens}

# The worlds decided option by option, every rule timed (the worlds keep their order).
def judged(+build: Builds.Build, +t: Timings, +laters: List<&2, Rules.Later>, +opens: List<&2, Open>) -> IO(Judged):
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options, +early}:
      do IO<Judged>:
        +got : Decided <- judged_options(build, laters_jobs(laters), options, 0, opens)
        return timed_with(seeds, prefilter_ms, generation_ms, hits_ms, early, got)

def opens_of(worlds: List<&2, Maybe<&2, FilterWorld.World>>) -> List<&2, Open>:
  match worlds:
    case Nil{}:
      Nil{}
    case Con{+world, rest}:
      Open{world, None{}} <> opens_of(rest)

def found_some(+found: Maybe<&2, U32>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{_}:
      True{}

# Whether an early world goes on: none was built, or some option's early jobs held on it.
def goes_on(+o: Open) -> Bool:
  match o:
    case Open{+world, +found}:
      Bool.not(is_some(world)) || found_some(found)

def goes_on_each(opens: List<&2, Open>) -> List<&2, Bool>:
  match opens:
    case Nil{}:
      Nil{}
    case Con{+o, rest}:
      goes_on(o) <> goes_on_each(rest)

def stopped_count(gone: List<&2, Bool>) -> Nat:
  match gone:
    case Nil{}:
      0n
    case Con{+on, rest}:
      Nat.add(Bool.pick(Nat, on, 0n, 1n), stopped_count(rest))

# The timings after an early check, and per early world whether it goes on.
type Checked is Data:
  Checked{timings: Timings, on: List<&2, Bool>}

def checked_with(+t: Timings, +worlds: Nat, +got: Decided) -> Checked:
  match t got:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options, Early{+checked, +missed, _}} Decided{+early_options, +opens}:
      +on = goes_on_each(opens)
      Checked{Timings{seeds, prefilter_ms, generation_ms, hits_ms, options, Early{Nat.add(checked, worlds), Nat.add(missed, stopped_count(on)), early_options}}, on}

# The early worlds of a round (None for an attempt that failed the early required prefab check) checked as `judged`
# checks worlds, with each filter's early jobs, every job timed.
def early_options(+t: Timings) -> List<&2, Option>:
  match t:
    case Timings{_, _, _, _, _, Early{_, _, +options}}:
      options

def early_judged(+build: Builds.Build, +t: Timings, +jobs: List<&2, List<&2, Evaluate.Job>>, +worlds: List<&2, Maybe<&2, FilterWorld.World>>) -> IO(Checked):
  do IO<Checked>:
    +got : Decided <- judged_options(build, jobs, early_options(t), 0, opens_of(worlds))
    return checked_with(t, checks(worlds), got)

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
    case Option{+worlds, +rules}:
      "{\"worlds\":" ++ Nat.show(worlds) ++ ",\"rules\":[" ++ String.join(rules_json(rules), ",") ++ "]}"

def options_json(options: List<&2, Option>) -> List<&2, String>:
  match options:
    case Nil{}:
      Nil{}
    case Con{+o, rest}:
      option_json(o) <> options_json(rest)

def early_json(+e: Early) -> String:
  match e:
    case Early{+worlds, +misses, +options}:
      "{\"worlds\":" ++ Nat.show(worlds) ++ ",\"misses\":" ++ Nat.show(misses) ++ ",\"options\":[" ++ String.join(options_json(options), ",") ++ "]}"

# `timings {...}`, `elapsed_ms` into the run.
def line(+t: Timings, +elapsed_ms: Nat) -> String:
  match t:
    case Timings{+seeds, +prefilter_ms, +generation_ms, +hits_ms, +options, +early}:
      "timings {\"elapsed_ms\":" ++ Nat.show(elapsed_ms) ++ ",\"seeds\":" ++ Nat.show(seeds) ++ ",\"prefilter_ms\":" ++ Nat.show(prefilter_ms) ++ ",\"generation_ms\":" ++ Nat.show(generation_ms) ++ ",\"hits_ms\":" ++ Nat.show(hits_ms)
        ++ ",\"options\":[" ++ String.join(options_json(options), ",") ++ "],\"early\":" ++ early_json(early) ++ "}"

def print_if(on: Bool, +t: Timings, +elapsed_ms: Nat) -> IO(Unit):
  match on:
    case True{}:
      IO.print_err(line(t, elapsed_ms))
    case False{}:
      IO.pure(Unit, Unit{})
