import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../f64/repr.bend as F64Repr
import ../worldsim/grid.bend as Grid
import ../ocean/ents.bend as OceanEnts
import ../ocean/state.bend as OceanState

# map/archive_worldgen.lua's AncientArchivePass: when the archive has fewer than 3 lockbox dispensers (and some), three
# of the temporary dispensers, each picked with math.random(1, #left), become dispensers; the temporary ones are then
# gone. Nothing happens, and nothing is drawn, without dispensers. The products they get are not in the dump.

# The temporary dispensers not picked yet, the picked ones (newest first) and the RNG.
type Picks is Type:
  Picks{pool: List<&2, OceanEnts.Ent>, taken: List<&2, OceanEnts.Ent>, rng: Pcg.Rng}

def nth(xs: List<&2, OceanEnts.Ent>, +k: U32) -> OceanEnts.Ent:
  match xs:
    case Nil{}:
      OceanEnts.Ent{0, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}
    case Con{+e, +rest}:
      Bool.pick(OceanEnts.Ent, U32.is_zero(k), e, nth(rest, (k - 1 : U32)))

def dropped(xs: List<&2, OceanEnts.Ent>, +k: U32) -> List<&2, OceanEnts.Ent>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+e, +rest}:
      Bool.pick(List<&2, OceanEnts.Ent>, U32.is_zero(k), rest, e <> dropped(rest, (k - 1 : U32)))

def picked(got: U32 & Pcg.Rng, +pool: List<&2, OceanEnts.Ent>, +taken: List<&2, OceanEnts.Ent>) -> Picks:
  (+k, rng) = got
  Picks{dropped(pool, (k - 1 : U32)), nth(pool, (k - 1 : U32)) <> taken, rng}

def pick_from(empty: Bool, +pool: List<&2, OceanEnts.Ent>, +taken: List<&2, OceanEnts.Ent>, rng: Pcg.Rng) -> Picks:
  match empty:
    case True{}:
      Picks{pool, taken, rng}
    case False{}:
      picked(MathRandom.random_range(rng, 1, U32.from_nat(List.length(&2, OceanEnts.Ent, pool))), pool, taken)

def picks_loop(n: Nat, p: Picks) -> Picks:
  match n:
    case 0n:
      p
    case 1n+m:
      match p:
        case Picks{+pool, +taken, rng}:
          picks_loop(m, pick_from(List.is_empty(&2, OceanEnts.Ent, pool), pool, taken, rng))

def finished(p: Picks, +dispenser: U32, +temporary: U32, g: Grid.Grid, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  match p:
    case Picks{_, +taken, rng}:
      OceanState.Sea{g, ids, rng, OceanEnts.appended(OceanEnts.without(ents, temporary), List.reverse(&2, OceanEnts.Ent, taken), dispenser), topo, events}

def picks_needed(+dispensers: List<&2, OceanEnts.Ent>) -> Nat:
  +short = (U32.from_nat(List.length(&2, OceanEnts.Ent, dispensers)) < 3 : U32)
  Bool.pick(Nat, short && Bool.not(List.is_empty(&2, OceanEnts.Ent, dispensers)), 3n, 0n)

# AncientArchivePass on savedata.ents: `dispenser` is archive_lockbox_dispencer, `temporary` its _temp prefab.
def run(+dispenser: U32, +temporary: U32, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      finished(picks_loop(picks_needed(OceanEnts.of_prefab(ents, dispenser)), Picks{OceanEnts.of_prefab(ents, temporary), Nil{}, rng}),
        dispenser, temporary, g, ids, ents, topo, events)
