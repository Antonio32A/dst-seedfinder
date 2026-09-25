import Base
import ../rng/pcg.bend as R
import ../level/summary.bend as W
import ../trace/canon.bend as CN
import ./graph.bend as GG
import ./story.bend as GY

# The `storygen` trace stage: forest_map.Generate from its first WorldSim call to WorldGen_Commit, for every
# `attempt a ctr` record of the input (the draw counter at the attempt's first WorldSim call), with GetSite answered
# from the input's `poly a at="VoronoiPass(100)"` records. Prints the oracle's `attempt`, `call` and `lua` records
# (draws) and `child` and `link` records (graph) of that window, in execution order. Linked into seedfinder by
# trace/lane_s.bend only when the main build can afford it (see .scratch/port/status/M7.md).

def method_name(+m: U32) -> String:
  match m:
    case 0:
      "SetPointsBarrenOrReservedTile"
    case 1:
      "SetResolveNoiseFunction"
    case 2:
      "SetValidateGroundTileFunction"
    case 3:
      "LuaPrint"
    case 4:
      "SetWorldSize"
    case 5:
      "GetSite"
    case 6:
      "WorldGen_InitializeNodePoints"
    case 7:
      "WorldGen_VoronoiPass"
    case 8:
      "WorldGen_AddNewPositions"
    case _:
      "WorldGen_Commit"

def lua_name(+f: U32) -> String:
  match f:
    case 0:
      "BuildStory"
    case 1:
      "Story:GenerateNodesFromTasks"
    case 2:
      "Story:AddBGNodes"
    case 3:
      "Story:AddCoveNodes"
    case 4:
      "Story:InsertAdditionalSetPieces"
    case 5:
      "Story:AddRegionsToMainland"
    case 6:
      "Story:LinkNodesByKeys"
    case 7:
      "Story:RestrictNodesByKey"
    case 8:
      "Story:ProcessOceanContent"
    case 9:
      "Story:PlaceTeleportatoParts"
    case _:
      "Story:ProcessExtraTags"

def optional_number(+v: U32) -> String:
  Bool.pick(String, U32.is_eq(v, GG.none()), "nil", U32.show(v))

def call_line(+a: String, +i: U32, +method: String, +ctr: U32) -> String:
  CN.record("call", [CN.field("a", a), CN.number("i", i), CN.field("m", method), CN.number("before", ctr), CN.number("after", ctr)])

def graph_child_line(+s: GG.St, +a: String, +g: U32) -> String:
  +kind = GG.gf(s, g, GG.g_kind())
  CN.record("child", [CN.field("a", a), CN.field("parent", CN.quoted("GAME_root")), CN.field("id", CN.quoted(GG.graph_name(s, g))),
    CN.number("tile", GG.gf(s, g, GG.g_tile())), CN.field("type", Bool.pick(String, U32.is_eq(kind, GG.k_task()), "nil", CN.quoted("blank"))),
    CN.field("itype", "nil")])

def node_child_line(+s: GG.St, +a: String, +n: U32) -> String:
  CN.record("child", [CN.field("a", a), CN.field("parent", CN.quoted(GG.graph_name(s, GG.nf(s, n, GG.f_graph())))),
    CN.field("id", CN.quoted(GG.node_name(s, n))), CN.number("tile", GG.nf(s, n, GG.f_value())),
    CN.field("type", optional_number(GG.nf(s, n, GG.f_type()))), CN.field("itype", optional_number(GG.nf(s, n, GG.f_itype())))])

def link_line(+s: GG.St, +a: String, +k: U32, +external: Bool, +from: U32, +to: U32) -> String:
  CN.record("link", [CN.field("a", a), CN.number("k", k), CN.field("m", Bool.pick(String, external, "AddExternalLink", "AddLink")),
    CN.field("from", CN.quoted(GG.node_name(s, from))), CN.field("to", CN.quoted(GG.node_name(s, to)))])

def lua_line(+a: String, +f: U32, +before: U32, +after: U32) -> String:
  CN.record("lua", [CN.field("a", a), CN.field("f", lua_name(f)), CN.number("before", before), CN.number("after", after)])

def event_lines(log: List<&2, GG.Ev>, +s: GG.St, +seed: U32, +a: String, +i: U32, +k: U32) -> List<&2, String>:
  match log:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case GG.EGraph{+g, +rng}:
          call_line(a, i, "AddChild", R.counter(seed, rng)) <> graph_child_line(s, a, g)
            <> event_lines(rest, s, seed, a, (i + 1 : U32), k)
        case GG.ENode{+n, +rng}:
          call_line(a, i, "AddChild", R.counter(seed, rng)) <> node_child_line(s, a, n)
            <> event_lines(rest, s, seed, a, (i + 1 : U32), k)
        case GG.ELink{+external, +from, +to, +rng}:
          call_line(a, i, Bool.pick(String, external, "AddExternalLink", "AddLink"), R.counter(seed, rng))
            <> link_line(s, a, k, external, from, to) <> event_lines(rest, s, seed, a, (i + 1 : U32), (k + 1 : U32))
        case GG.ECall{+m, +rng}:
          call_line(a, i, method_name(m), R.counter(seed, rng)) <> event_lines(rest, s, seed, a, (i + 1 : U32), k)
        case GG.ELua{+f, +before, +after}:
          lua_line(a, f, R.counter(seed, before), R.counter(seed, after)) <> event_lines(rest, s, seed, a, i, k)

def hex_value(+c: U32) -> U32:
  Bool.pick(U32, (c >= 97 : U32), (c - 87 : U32), (c - 48 : U32))

def hex_loop(n: Nat, s: String, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      match s:
        case SNil{}:
          acc
        case SCon{Chr{+c}, rest}:
          hex_loop(p, rest, ((acc << 4n) .|. hex_value(c) : U32))

# The U32 of a record's 8-digit hex value (an f32; a `~decimal` suffix is ignored).
def hex_bits(+m: Maybe<&2, String>) -> U32:
  hex_loop(8n, CN.text_or(m, "00000000"), 0)

type Site is Data:
  Site{node: String, x: U32, y: U32}

def site_of(+fields: List<&2, String>) -> Site:
  Site{CN.text_or(CN.value_of("node", fields), ""), hex_bits(CN.value_of("sx", fields)), hex_bits(CN.value_of("sy", fields))}

def attempt_sites(polys: List<&2, List<&2, String>>, +a: String) -> List<&2, Site>:
  match polys:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      +tail = attempt_sites(rest, a)
      +mine = String.eq(CN.text_or(CN.value_of("a", fields), ""), a)
        && String.eq(CN.text_or(CN.value_of("at", fields), ""), "\"VoronoiPass(100)\"")
      Bool.pick(List<&2, Site>, mine && Bool.not(String.eq(CN.text_or(CN.value_of("sx", fields), ""), "")), site_of(fields) <> tail, tail)

def site_for(sites: List<&2, Site>, +name: String) -> Site:
  match sites:
    case Nil{}:
      Site{name, 0, 0}
    case Con{+site, rest}:
      match site:
        case Site{+node, +x, +y}:
          Bool.pick(Site, String.eq(node, name), Site{node, x, y}, site_for(rest, name))

def put_site(+s: GG.St, +n: U32, +site: Site) -> GG.St:
  match site:
    case Site{_, +x, +y}:
      +slot = (GG.site_base() + (n * 2 : U32) : U32)
      GG.put(GG.put(s, slot, x), (slot + 1 : U32), y)

def sites_loop(n: Nat, +s: GG.St, +sites: List<&2, Site>, +node: U32) -> GG.St:
  match n:
    case 0n:
      s
    case 1n+p:
      +site = site_for(sites, CN.quoted(GG.node_name(s, node)))
      sites_loop(p, put_site(s, node, site), sites, (node + 1 : U32))

# The oracle's GetSite answers for every node made so far.
def with_sites(+s: GG.St, +sites: List<&2, Site>) -> GG.St:
  sites_loop(U32.to_nat(GG.get(s, GG.s_nodes())), s, sites, 0)

def story_lines(+s: GG.St, +seed: U32, +a: String, +ctr: U32) -> List<&2, String>:
  CN.record("attempt", [CN.field("a", a), CN.number("ctr", ctr)]) <> event_lines(List.reverse(&2, GG.Ev, GG.log_of(s)), s, seed, a, 0, 0)

def attempt_lines(+seed: U32, +level: W.Summary, +polys: List<&2, List<&2, String>>, +fields: List<&2, String>) -> List<&2, String>:
  +a = CN.text_or(CN.value_of("a", fields), "0")
  +ctr = CN.number_or(CN.value_of("ctr", fields), 0)
  +built = GY.build(level, R.at_counter(seed, ctr))
  story_lines(GY.finish(with_sites(built, attempt_sites(polys, a)), level), seed, a, ctr)

def all_attempts(attempts: List<&2, List<&2, String>>, +seed: U32, +level: W.Summary, +polys: List<&2, List<&2, String>>) -> List<&2, String>:
  match attempts:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      List.append(&2, String, attempt_lines(seed, level, polys, fields), all_attempts(rest, seed, level, polys))

def storygen_lines(+seed: U32, +lines: List<&2, String>) -> List<&2, String>:
  all_attempts(CN.records("attempt", lines), seed, W.summary(seed), CN.records("poly", lines))

# The stage's records for a seed and the text of its input.
def run(+seed: U32, +input: String) -> List<&2, String>:
  storygen_lines(seed, String.split(input, '\n'))
