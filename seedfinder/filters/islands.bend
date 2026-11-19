import Base
import ./world.bend as FilterWorld
import ./anchor.bend as Anchor
import ./walking.bend as Walking
import ./landmass.bend as Landmass
import ./rules.bend as Rules
import ./checks.bend as Checks
import ./witness.bend as Witness
import ../data/builds.bend as Builds

# The islands rules (docs/config.md section 4 G). An instance's reach is the landmass of its walk anchor (section 5)
# and, with the links, every landmass a link exits to from the reach (chained, in link order); its area is the tiles
# of those landmasses, and A the smallest area over the anchored instances of `at`.

# A link between landmasses: the landmass of its entry's anchor, that of its exit's anchor, and the exit's anchor tile.
type Hop is Data:
  Hop{from: U32, to: U32, tile: U32}

# A landmass of a reach and the tile it was reached at.
type Reached is Data:
  Reached{mass: U32, tile: U32}

# The reach of an instance: its landmasses (its anchor's first) and their tile count.
type Reach is Data:
  Reach{inst: FilterWorld.Inst, masses: List<&2, Reached>, area: U32}

type Bounds is Data:
  Bounds{tx0: U32, ty0: U32, tx1: U32, ty1: U32}

def hop_of(+masses: Landmass.Masses, a: Maybe<&2, Anchor.Anchor>, b: Maybe<&2, Anchor.Anchor>) -> List<&2, Hop>:
  match a b:
    case Some{Anchor.Anchor{+entry, _, _}} Some{Anchor.Anchor{+exit, _, _}}:
      [Hop{Landmass.mass_at(masses, entry), Landmass.mass_at(masses, exit), exit}]
    case _ _:
      Nil{}

def hops_of(points: List<&2, Anchor.Point>, +masses: Landmass.Masses) -> List<&2, Hop>:
  match points:
    case Con{Anchor.Point{_, a}, Con{Anchor.Point{_, b}, rest}}:
      List.append(&2, Hop, hop_of(masses, a, b), hops_of(rest, masses))
    case _:
      Nil{}

def has_mass(found: List<&2, Reached>, +m: U32) -> Bool:
  match found:
    case Nil{}:
      False{}
    case Con{Reached{+x, _}, rest}:
      U32.is_eq(x, m) || has_mass(rest, m)

def added(on: Bool, +found: List<&2, Reached>, +m: U32, +tile: U32) -> List<&2, Reached>:
  match on:
    case True{}:
      List.append(&2, Reached, found, [Reached{m, tile}])
    case False{}:
      found

def sweep(hops: List<&2, Hop>, +found: List<&2, Reached>) -> List<&2, Reached>:
  match hops:
    case Nil{}:
      found
    case Con{Hop{+from, +to, +tile}, rest}:
      sweep(rest, added(has_mass(found, from) && Bool.not(has_mass(found, to)), found, to, tile))

# Every pass that adds nothing changes nothing, and each of the others adds one of at most n exits.
def closure(n: Nat, +hops: List<&2, Hop>, +found: List<&2, Reached>) -> List<&2, Reached>:
  match n:
    case 0n:
      found
    case 1n+p:
      closure(p, hops, sweep(hops, found))

def area_of(+mass: Landmass.Mass) -> U32:
  match mass:
    case Landmass.Mass{+area, _, _, _, _}:
      area

def mass_area(+masses: Landmass.Masses, +m: U32) -> U32:
  area_of(Landmass.mass(masses, m))

def area_sum(found: List<&2, Reached>, +masses: Landmass.Masses, +sum: U32) -> U32:
  match found:
    case Nil{}:
      sum
    case Con{Reached{+m, _}, rest}:
      area_sum(rest, masses, (sum + mass_area(masses, m) : U32))

def reach_of(+masses: Landmass.Masses, +hops: List<&2, Hop>, +inst: FilterWorld.Inst, +m: U32, +tile: U32) -> Reach:
  +found = closure(List.length(&2, Hop, hops), hops, [Reached{m, tile}])
  Reach{inst, found, area_sum(found, masses, 0)}

def seen_mass(reaches: List<&2, Reach>, +m: U32) -> Bool:
  match reaches:
    case Con{Reach{_, Con{Reached{+x, _}, _}, _}, rest}:
      U32.is_eq(x, m) || seen_mass(rest, m)
    case Con{_, rest}:
      seen_mass(rest, m)
    case Nil{}:
      False{}

def with_reach(fresh: Bool, +masses: Landmass.Masses, +hops: List<&2, Hop>, +inst: FilterWorld.Inst, +m: U32, +tile: U32, +acc: List<&2, Reach>) -> List<&2, Reach>:
  match fresh:
    case True{}:
      reach_of(masses, hops, inst, m, tile) <> acc
    case False{}:
      acc

# Instances anchored in one landmass have the same reach, so only the first one's is kept.
def reaches(points: List<&2, Anchor.Point>, +masses: Landmass.Masses, +hops: List<&2, Hop>, +acc: List<&2, Reach>) -> List<&2, Reach>:
  match points:
    case Nil{}:
      List.reverse(&2, Reach, acc)
    case Con{Anchor.Point{+inst, Some{Anchor.Anchor{+tile, _, _}}}, rest}:
      +m = Landmass.mass_at(masses, tile)
      reaches(rest, masses, hops, with_reach(U32.is_ne(m, Landmass.none()) && Bool.not(seen_mass(acc, m)), masses, hops, inst, m, tile, acc))
    case Con{_, rest}:
      reaches(rest, masses, hops, acc)

def smaller(+r: Reach, +best: Maybe<&2, Reach>) -> Bool:
  match r best:
    case _ None{}:
      True{}
    case Reach{_, _, +a} Some{Reach{_, _, +b}}:
      (a < b : U32)

def smallest(reaches: List<&2, Reach>, +best: Maybe<&2, Reach>) -> Maybe<&2, Reach>:
  match reaches:
    case Nil{}:
      best
    case Con{+r, rest}:
      smallest(rest, Bool.pick(Maybe<&2, Reach>, smaller(r, best), Some{r}, best))

def world_links(+world: FilterWorld.World, +links: Bool) -> List<&2, FilterWorld.Link>:
  Bool.pick(List<&2, FilterWorld.Link>, links, Walking.world_links(world), Nil{})

# A of the rule's instances in the world, as the instance that gives it with its reach (none without an anchored one).
def smallest_reach(+world: FilterWorld.World, +at: List<&2, U32>, +links: Bool) -> Maybe<&2, Reach>:
  +masses = FilterWorld.landmasses(world)
  +insts = FilterWorld.instances(world, at)
  +n = List.length(&2, FilterWorld.Inst, insts)
  +points = Walking.anchored(world, List.append(&2, FilterWorld.Inst, insts, Walking.link_insts(world_links(world, links))))
  smallest(reaches(List.take(&2, Anchor.Point, points, n), masses, hops_of(List.drop(&2, Anchor.Point, points, n), masses), Nil{}), None{})

def within(found: Maybe<&2, Reach>, +min: Maybe<&2, U32>, +max: Maybe<&2, U32>) -> Bool:
  match found:
    case None{}:
      Maybe.is_none(&2, U32, max)
    case Some{Reach{_, _, +area}}:
      Checks.at_least(area, min) && Checks.at_most(area, max)

def grown(+b: Bounds, +m: Landmass.Mass) -> Bounds:
  match b m:
    case Bounds{+x0, +y0, +x1, +y1} Landmass.Mass{_, +tx0, +ty0, +tx1, +ty1}:
      Bounds{U32.min(x0, tx0), U32.min(y0, ty0), U32.max(x1, tx1), U32.max(y1, ty1)}

def bounds_of(found: List<&2, Reached>, +masses: Landmass.Masses, +b: Bounds) -> Bounds:
  match found:
    case Nil{}:
      b
    case Con{Reached{+m, _}, rest}:
      bounds_of(rest, masses, grown(b, Landmass.mass(masses, m)))

def mass_items(found: List<&2, Reached>, +masses: Landmass.Masses, +w: U32) -> List<&2, String>:
  match found:
    case Nil{}:
      Nil{}
    case Con{Reached{+m, +tile}, rest}:
      ("{\"tx\":" ++ U32.show((tile % w : U32)) ++ ",\"ty\":" ++ U32.show((tile / w : U32)) ++ ",\"area\":" ++ U32.show(mass_area(masses, m)) ++ "}") <> mass_items(rest, masses, w)

def bounds_json(+b: Bounds) -> String:
  match b:
    case Bounds{+x0, +y0, +x1, +y1}:
      "{\"tx0\":" ++ U32.show(x0) ++ ",\"ty0\":" ++ U32.show(y0) ++ ",\"tx1\":" ++ U32.show(x1) ++ ",\"ty1\":" ++ U32.show(y1) ++ "}"

def first_tile(found: List<&2, Reached>) -> U32:
  match found:
    case Nil{}:
      0
    case Con{Reached{_, +tile}, _}:
      tile

def reach_fields(+build: Builds.Build, +world: FilterWorld.World, found: Maybe<&2, Reach>) -> String:
  match found:
    case None{}:
      ",\"area\":null"
    case Some{Reach{+inst, +reached, +area}}:
      +masses = FilterWorld.landmasses(world)
      +w = Checks.world_size(world)
      ",\"area\":" ++ U32.show(area) ++ ",\"at\":" ++ Witness.instance(build, inst) ++ ",\"tile\":" ++ Witness.tile(first_tile(reached), w, Checks.world_height(world))
        ++ ",\"landmasses\":[" ++ String.join(mass_items(reached, masses, w), ",") ++ "],\"bounds\":"
        ++ bounds_json(bounds_of(reached, masses, Bounds{4294967295, 4294967295, 0, 0}))

# Whether the rule holds and its witness fields: A, the instance that gives it, its anchor tile, its reach's landmasses
# and their tile bounds.
def check(+build: Builds.Build, +world: FilterWorld.World, rule: Rules.Island) -> Checks.Check:
  match rule:
    case Rules.Island{+at, +min, +max, +links, _}:
      +found = smallest_reach(world, at, links)
      Checks.Check{within(found, min, max), reach_fields(build, world, found)}

def bounded_holds(bounded: Bool, +world: FilterWorld.World, +at: List<&2, U32>, +min: Maybe<&2, U32>, +max: Maybe<&2, U32>, +links: Bool) -> Bool:
  match bounded:
    case True{}:
      within(smallest_reach(world, at, links), min, max)
    case False{}:
      True{}

# Whether the rule holds, without its witness (a rule without bounds always does).
def holds(+world: FilterWorld.World, rule: Rules.Island) -> Bool:
  match rule:
    case Rules.Island{+at, +min, +max, +links, _}:
      bounded_holds(Maybe.is_some(&2, U32, min) || Maybe.is_some(&2, U32, max), world, at, min, max, links)
