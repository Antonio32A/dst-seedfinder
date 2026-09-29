import Base
import ../lua/table.bend as LuaTable
import ../lua/util.bend as LuaUtil
import ../level/prefix.bend as LevelPrefix
import ../level/summary.bend as LevelSummary
import ./plan.bend as StoryPlan
import ../data/story.bend as StoryData
import ../data/enums.bend as Enums
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder

# Story:InsertAdditionalSetPieces: every task's set_pieces (Level:ChooseSetPieces, in pairs(level.set_pieces) order)
# and random_set_pieces go into the first acceptable node of shuffledKeys(task.nodes) (countstaticlayouts[name] = 1).

# A set piece as string id << 16 | layout index.
def packed(+name: U32, +layout: U32) -> U32:
  ((name << 16n) .|. layout : U32)

def keyed_pieces(entries: List<&2, U32>, +task: U32) -> List<&2, U32>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, rest}:
      +tail = keyed_pieces(rest, task)
      +key = (entry .&. 63 : U32)
      +placed = U32.is_eq((((entry >> 6n) >> U32.to_nat(task)) .&. 1 : U32), 1)
      Bool.pick(List<&2, U32>, placed, packed(StoryData.piece_key(key), StoryData.piece_key_layout(key)) <> tail, tail)

def special_pieces(n: Nat, +codes: U32, +tasks: U32, +task: U32, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +tail = special_pieces(p, codes, tasks, task, (k + 1 : U32))
      +code = LevelPrefix.field5(codes, k)
      Bool.pick(List<&2, U32>, U32.is_eq(LevelPrefix.field5(tasks, k), task), packed(StoryData.piece_special(code), StoryData.piece_special_layout(code)) <> tail, tail)

def forest_set_pieces(+level: LevelSummary.Summary, +task: U32) -> List<&2, U32>:
  match level:
    case LevelSummary.Summary{_, _, +entries, _, _, _, _}:
      keyed_pieces(entries, task)

def forest_random_set_pieces(+level: LevelSummary.Summary, +task: U32) -> List<&2, U32>:
  match level:
    case LevelSummary.Summary{_, _, _, +codes, +tasks, +count, _}:
      special_pieces(U32.to_nat(count), codes, tasks, task, 0)

def cave_layout_unresolved() -> U32:
  65535

def cave_packed(keys: List<&2, U32>) -> List<&2, U32>:
  match keys:
    case Nil{}:
      Nil{}
    case Con{+key, rest}:
      packed(key, cave_layout_unresolved()) <> cave_packed(rest)

# task.set_pieces of a task; a caves piece is its data/cave_catalog.bend key with no layout yet.
def set_pieces(+plan: StoryPlan.Plan, +task: U32) -> List<&2, U32>:
  match plan:
    case StoryPlan.ForestPlan{+level}:
      forest_set_pieces(level, task)
    case StoryPlan.CavePlan{_, +placed, _}:
      cave_packed(StoryPlan.cave_piece_names(placed, task))

# task.random_set_pieces of a task (the caves have none).
def random_set_pieces(+plan: StoryPlan.Plan, +task: U32) -> List<&2, U32>:
  match plan:
    case StoryPlan.ForestPlan{+level}:
      forest_random_set_pieces(level, task)
    case StoryPlan.CavePlan{_, _, _}:
      Nil{}

def written(arr: Array<U32>, +i: U32, +v: U32) -> Array<U32>:
  arr[i] <- v

def fill_array(xs: List<&2, U32>, arr: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      arr
    case Con{+x, rest}:
      fill_array(rest, written(arr, i, x), (i + 1 : U32))

def read_out(n: Nat, got: Array<U32> & U32, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      (arr, +v) = got
      +rest = read_out(p, arr[(i + 1 : U32)], (i + 1 : U32))
      Bool.pick(List<&2, U32>, U32.is_eq(v, StoryGraph.none()), Nil{}, v <> rest)

type Picks is Data:
  Picks{order: List<&2, U32>, st: StoryGraph.St}

def unshuffled(sh: LuaUtil.Shuffled, +n: U32, +s: StoryGraph.St) -> Picks:
  match sh:
    case LuaUtil.Shuffled{items, rng}:
      Picks{read_out(U32.to_nat((n + 1 : U32)), items[0], 0), StoryGraph.with_rng(s, rng)}

# shuffledKeys(task.nodes): the keys in pairs() order, shuffleArray'd (n - 1 draws), as ipairs sees them.
def shuffled(+s: StoryGraph.St, +order: List<&2, U32>) -> Picks:
  +n = StoryOrder.count(order, 0)
  arr = fill_array(order, Array.new(U32, U32.to_nat(LuaTable.ceil_log2((n + 2 : U32))), StoryGraph.none()), 0)
  unshuffled(LuaUtil.shuffle_array(arr, n, StoryGraph.rng_of(s)), n, s)

def acceptable(+s: StoryGraph.St, +node: U32, +random: Bool) -> Bool:
  +not_blank = Bool.pick(Bool, random, U32.is_ne(StoryGraph.nf(s, node, StoryGraph.f_type()), Enums.node_type_blank()),
    Bool.not(StoryData.is_impassable(StoryGraph.nf(s, node, StoryGraph.f_value()))))
  Bool.not(StoryGraph.is_entrance(s, node)) && not_blank

def choice(order: List<&2, U32>, +s: StoryGraph.St, +random: Bool) -> U32:
  match order:
    case Nil{}:
      StoryGraph.none()
    case Con{+node, rest}:
      Bool.pick(U32, acceptable(s, node, random), node, choice(rest, s, random))

def placed_if(missing: Bool, +node: U32, +s: StoryGraph.St, +piece: U32) -> StoryGraph.St:
  match missing:
    case True{}:
      StoryGraph.say(s)
    case False{}:
      StoryGraph.place_piece(s, node, (piece >> 16n : U32), (piece .&. 65535 : U32))

def placed(+node: U32, +s: StoryGraph.St, +piece: U32) -> StoryGraph.St:
  placed_if(U32.is_eq(node, StoryGraph.none()), node, s, piece)

def place_one(+p: Picks, +piece: U32, +random: Bool) -> StoryGraph.Got:
  match p:
    case Picks{+order, +s}:
      +node = choice(order, s, random)
      StoryGraph.Got{node, placed(node, s, piece)}

# Placing set pieces: the state and whether a piece found no node (which ends the pass).
type Placing is Data:
  Placing{st: StoryGraph.St, stopped: Bool}

def placing_of(+g: StoryGraph.Got) -> Placing:
  match g:
    case StoryGraph.Got{+v, +s}:
      Placing{s, U32.is_eq(v, StoryGraph.none())}

def place_all(pieces: List<&2, U32>, +p: Placing, +order: List<&2, U32>, +random: Bool) -> StoryGraph.St:
  match pieces:
    case Nil{}:
      match p:
        case Placing{+s, _}:
          s
    case Con{+piece, rest}:
      match p:
        case Placing{+s, +stopped}:
          match stopped:
            case True{}:
              s
            case False{}:
              place_all(rest, placing_of(place_one(shuffled(s, order), piece, random)), order, random)

def pieces_of_graph(task_graph: Bool, +s: StoryGraph.St, +g: U32, +plan: StoryPlan.Plan) -> StoryGraph.St:
  match task_graph:
    case True{}:
      +task = StoryGraph.gf(s, g, StoryGraph.g_part())
      +order = StoryGraph.node_order(s, g)
      place_all(random_set_pieces(plan, task), Placing{place_all(set_pieces(plan, task), Placing{s, False{}}, order, False{}), False{}}, order, True{})
    case False{}:
      s

def pieces_loop(graphs: List<&2, U32>, +s: StoryGraph.St, +plan: StoryPlan.Plan) -> StoryGraph.St:
  match graphs:
    case Nil{}:
      s
    case Con{+g, rest}:
      pieces_loop(rest, pieces_of_graph(U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task()), s, g, plan), plan)

# Story:InsertAdditionalSetPieces over the given graphs (pairs order).
def insert_set_pieces(+s: StoryGraph.St, +graphs: List<&2, U32>, +plan: StoryPlan.Plan) -> StoryGraph.St:
  +before = StoryGraph.rng_of(s)
  StoryGraph.returned(pieces_loop(graphs, s, plan), StoryGraph.f_insert_additional_set_pieces(), before)
