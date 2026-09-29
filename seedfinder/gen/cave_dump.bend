import Base
import ../storygen/graph.bend as StoryGraph
import ../trace/canon.bend as Canon
import ../worldsim/grid.bend as Grid
import ../data/cave_story.bend as CaveStory
import ../storygen/catalog.bend as StoryCatalog
import ./tags.bend as GenTags

# The text records `seedfinder gen --shard caves` prints on request: the story graph of an attempt as one JSON line and
# its tile map as run-length pairs (`tiles`, row-major with x fastest, `tile*count` runs joined by commas), the formats of the real
# server's world dumps (scripts/groundtruth) so the two can be compared line by line.

def run_token(+tile: U32, +count: U32) -> String:
  U32.show(tile) ++ "*" ++ U32.show(count)

def flushed(+count: U32, +tile: U32, +tokens: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_zero(count), tokens, run_token(tile, count) <> tokens)

def rle_loop(n: Nat, got: Array<U32> & U32, +i: U32, +tile: U32, +count: U32, +tokens: List<&2, String>) -> Array<U32> & List<&2, String>:
  match n:
    case 0n:
      (cells, _) = got
      (cells, List.reverse(&2, String, flushed(count, tile, tokens)))
    case 1n+p:
      (cells, +v) = got
      +at = (v .&. 65535 : U32)
      +same = U32.is_eq(at, tile) && Bool.not(U32.is_zero(count))
      rle_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), at, Bool.pick(U32, same, (count + 1 : U32), 1), Bool.pick(List<&2, String>, same, tokens, flushed(count, tile, tokens)))

def rle_text(got: Array<U32> & List<&2, String>) -> String:
  (_, tokens) = got
  String.join(tokens, ",")

def tiles_record(+seed: U32, +a: U32, +label: String, +width: U32, +height: U32, +rle: String) -> String:
  Canon.record("tiles", [Canon.number("seed", seed), Canon.number("a", a), Canon.field("label", label), Canon.number("w", width),
    Canon.number("h", height), Canon.field("rle", rle)])

# The `tiles` record of a grid.
def tiles_line(+seed: U32, +a: U32, g: Grid.Grid, +label: String) -> String:
  match g:
    case Grid.Grid{cells, +width, +height}:
      tiles_record(seed, a, label, width, height, rle_text(rle_loop(U32.to_nat((width * height : U32)), cells[0], 0, 0, 0, Nil{})))

def quoted_all(names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}:
      Nil{}
    case Con{+name, rest}:
      Canon.quoted(name) <> quoted_all(rest)

def node_json(+s: StoryGraph.St, +n: U32) -> String:
  "[" ++ Canon.quoted(StoryGraph.node_name(s, n)) ++ "," ++ U32.show(StoryGraph.nf(s, n, StoryGraph.f_type())) ++ "," ++ U32.show(GenTags.poison(s, n))
    ++ ",[" ++ String.join(quoted_all(GenTags.cave_tag_names(s, n)), ",") ++ "]]"

def nodes_json(n: Nat, +s: StoryGraph.St, +i: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      node_json(s, i) <> nodes_json(p, s, (i + 1 : U32))

def edge_json(+s: StoryGraph.St, +e: U32) -> String:
  +slot = (StoryGraph.edge_base() + (e * 2 : U32) : U32)
  "[" ++ U32.show(StoryGraph.get(s, slot)) ++ "," ++ U32.show(StoryGraph.get(s, (slot + 1 : U32))) ++ "]"

def edges_json(n: Nat, +s: StoryGraph.St, +e: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      edge_json(s, e) <> edges_json(p, s, (e + 1 : U32))

def global_json(+s: StoryGraph.St, +k: U32) -> String:
  +slot = (StoryGraph.global_base() + (k * 3 : U32) : U32)
  "[" ++ Canon.quoted(CaveStory.tag_name(StoryGraph.get(s, slot))) ++ "," ++ Canon.quoted(StoryCatalog.task_name(StoryGraph.gf(s, StoryGraph.get(s, (slot + 1 : U32)), StoryGraph.g_part())))
    ++ "," ++ Canon.quoted(StoryGraph.node_name(s, StoryGraph.get(s, (slot + 2 : U32)))) ++ "]"

def globals_json(n: Nat, +s: StoryGraph.St, +k: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      global_json(s, k) <> globals_json(p, s, (k + 1 : U32))

# The story graph of an attempt: every node as [id, NODE_TYPE, poison bits, tags] and every link or lock as a pair of
# node indices, in creation order, and Story.GlobalTags as [tag, task, node id] in insertion order.
def story_json(+seed: U32, +a: U32, +s: StoryGraph.St) -> String:
  "{\"seed\":" ++ U32.show(seed) ++ ",\"attempt\":" ++ U32.show(a) ++ ",\"nodes\":[" ++ String.join(nodes_json(U32.to_nat(StoryGraph.get(s, StoryGraph.s_nodes())), s, 0), ",")
    ++ "],\"edges\":[" ++ String.join(edges_json(U32.to_nat(StoryGraph.get(s, StoryGraph.s_edges())), s, 0), ",")
    ++ "],\"globals\":[" ++ String.join(globals_json(U32.to_nat(StoryGraph.get(s, StoryGraph.s_globals())), s, 0), ",") ++ "]}"
