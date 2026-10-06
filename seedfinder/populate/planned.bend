import Base
import ../level/summary.bend as LevelSummary
import ../level/prefix.bend as LevelPrefix
import ../storygen/graph.bend as StoryGraph
import ../storygen/plan.bend as StoryPlan
import ../storygen/setpieces.bend as StorySetpieces
import ./state.bend as PopulateState

# The level plan's task set pieces and whether an attempt placed them (the world dump's PLAN section). A piece is
# placed when Story:InsertAdditionalSetPieces put it in a node's countstaticlayouts and that node's ReserveSpace found
# its layout a spot. Placement goes through the story's piece slots, not the layout names: a piece the story found no
# node for, a second copy in a node that already holds one (countstaticlayouts keys are unique) and a piece whose
# ReserveSpace failed are all not placed.

# A planned task set piece: its task (world_catalog task id, which is also its string id), its name (string id) and
# whether its layout was placed.
type Planned is Data:
  Planned{task: U32, name: U32, placed: Bool}

# A layout the land converted: its story node, its name (string id) and whether ReserveSpace found it a spot.
type Reserved is Data:
  Reserved{node: U32, name: U32, ok: Bool}

# A story piece slot: its node, the node's task, the piece's name (string id) and whether its layout was placed.
type Slot is Data:
  Slot{node: U32, task: U32, name: U32, placed: Bool}

# The layouts in execution order from the events (newest first): each ELayout with the EReserve that followed it.
def reservations(events: List<&2, PopulateState.Ev>, +ok: Bool, +acc: List<&2, Reserved>) -> List<&2, Reserved>:
  match events:
    case Nil{}:
      acc
    case Con{PopulateState.EReserve{_, _, _, _, _, _, _, _, +found, _, _}, rest}:
      reservations(rest, found, acc)
    case Con{PopulateState.ELayout{+node, +name, _}, rest}:
      reservations(rest, False{}, Reserved{node, name, ok} <> acc)
    case Con{_, rest}:
      reservations(rest, ok, acc)

# Whether the node's first layout of that name found a spot (the countstaticlayouts entry comes before the map tags').
def first_reserved(records: List<&2, Reserved>, +node: U32, +name: U32) -> Bool:
  match records:
    case Nil{}:
      False{}
    case Con{Reserved{+at, +named, +ok}, rest}:
      Bool.pick(Bool, U32.is_eq(at, node) && U32.is_eq(named, name), ok, first_reserved(rest, node, name))

def is_taken(slots: List<&2, Slot>, +node: U32, +name: U32) -> Bool:
  match slots:
    case Nil{}:
      False{}
    case Con{Slot{+at, _, +named, _}, rest}:
      (U32.is_eq(at, node) && U32.is_eq(named, name)) || is_taken(rest, node, name)

def slots_loop(n: Nat, +s: StoryGraph.St, +records: List<&2, Reserved>, +k: U32, +acc: List<&2, Slot>) -> List<&2, Slot>:
  match n:
    case 0n:
      List.reverse(&2, Slot, acc)
    case 1n+p:
      +slot = (StoryGraph.piece_base() + (k * 3 : U32) : U32)
      +node = StoryGraph.get(s, slot)
      +name = StoryGraph.get(s, (slot + 1 : U32))
      +task = StoryGraph.gf(s, StoryGraph.nf(s, node, StoryGraph.f_graph()), StoryGraph.g_part())
      +placed = first_reserved(records, node, name) && Bool.not(is_taken(acc, node, name))
      slots_loop(p, s, records, (k + 1 : U32), Slot{node, task, name, placed} <> acc)

def task_slots(slots: List<&2, Slot>, +task: U32) -> List<&2, Planned>:
  match slots:
    case Nil{}:
      Nil{}
    case Con{Slot{_, +at, +name, +placed}, rest}:
      +tail = task_slots(rest, task)
      Bool.pick(List<&2, Planned>, U32.is_eq(at, task), Planned{at, name, placed} <> tail, tail)

# The task's planned names against its slots: the story fills the slots in plan order and stops a list at the first
# piece it finds no node for, so each slot is the next planned piece of its name.
def matched(names: List<&2, U32>, +task: U32, slots: List<&2, Planned>) -> List<&2, Planned>:
  match names slots:
    case Nil{} _:
      Nil{}
    case Con{+name, rest} Nil{}:
      Planned{task, name, False{}} <> matched(rest, task, Nil{})
    case Con{+name, rest} Con{Planned{+at, +named, +placed}, +others}:
      +same = U32.is_eq(named, name)
      Planned{task, name, same && placed} <> matched(rest, task, Bool.pick(List<&2, Planned>, same, others, Planned{at, named, placed} <> others))

def names_of(pieces: List<&2, U32>) -> List<&2, U32>:
  match pieces:
    case Nil{}:
      Nil{}
    case Con{+piece, rest}:
      (piece >> 16n : U32) <> names_of(rest)

def chosen_loop(n: Nat, +plan: StoryPlan.Plan, +lo: U32, +slots: List<&2, Slot>, +c: U32) -> List<&2, Planned>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +task = LevelPrefix.chosen_task(lo, c)
      +names = names_of(List.append(&2, U32, StorySetpieces.set_pieces(plan, task), StorySetpieces.random_set_pieces(plan, task)))
      List.append(&2, Planned, matched(names, task, task_slots(slots, task)), chosen_loop(p, plan, lo, slots, (c + 1 : U32)))

# The level plan's task set pieces in plan order (the forest's chosen tasks in chosen order, each task's set_pieces then
# random_set_pieces; none for the caves), each with whether the attempt with this story and these land events placed it.
def planned(+plan: StoryPlan.Plan, +s: StoryGraph.St, +events: List<&2, PopulateState.Ev>) -> List<&2, Planned>:
  match plan:
    case StoryPlan.ForestPlan{LevelSummary.Summary{_, +lo, _, _, _, _, _}}:
      +slots = slots_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_pieces())), s, reservations(events, False{}, Nil{}), 0, Nil{})
      chosen_loop(LevelSummary.chosen_count(), plan, lo, slots, 0)
    case StoryPlan.CavePlan{_, _, _}:
      Nil{}
