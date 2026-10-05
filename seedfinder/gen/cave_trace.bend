import Base
import ../rng/pcg.bend as Pcg
import ../trace/canon.bend as Canon
import ../f64/repr.bend as F64Repr
import ../f64/random.bend as F64Random
import ../data/enums.bend as Enums
import ../data/strings.bend as Strings
import ../data/cave_story.bend as CaveStory
import ../storygen/graph.bend as StoryGraph
import ../storygen/catalog.bend as StoryCatalog
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/cave/automaton.bend as CaveAutomaton
import ../worldsim/cave/maze.bend as WorldCaveMaze
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/voronoi/polygon.bend as VoronoiPolygon
import ../worldsim/tiles/convert.bend as TileConvert
import ../worldsim/tiles/separate.bend as TileSeparate
import ../worldsim/tiles/connect.bend as TileConnect
import ../worldsim/tiles/disconnect.bend as TileDisconnect
import ../populate/entities.bend as Entities
import ../populate/state.bend as PopulateState
import ../populate/ground.bend as PopulateGround
import ../populate/land.bend as PopulateLand
import ../populate/voronoi.bend as PopulateVoronoi
import ../ocean/state.bend as OceanState
import ../ocean/ents.bend as OceanEnts
import ../ocean/post.bend as OceanPost
import ../ocean/bunches.bend as Bunches
import ../post/archive.bend as Archive
import ../post/finish.bend as Finish
import ./trace.bend as GenTrace
import ./graph.bend as GenGraph
import ./generate.bend as Generate
import ./job.bend as GenJob
import ./cave_custom.bend as CaveCustom
import ./cave_required.bend as CaveRequired
import ./cave_names.bend as CaveNames
import ./maze_env.bend as MazeEnv
import ./maze_labyrinth.bend as MazeLabyrinth
import ./maze_meta.bend as MazeMeta
import ./maze_tags.bend as MazeTags
import ../filters/dump.bend as FilterDump

# The `cavegen` trace stage: one attempt of the caves' forest_map.Generate through the job state machine, from the start of
# the seed's stream or (input: a stream position) from the position of a later attempt, printing one record per stage
# boundary in execution order. Counters are positions in the PCG32 stream; `before` and `after` bracket an engine call, so
# the draws between one call's `after` and the next call's `before` are the Lua side's math.random() calls.
#   cattempt a ctr                         the attempt begins
#   attempt/call/... graph/kkpos/poly      the forest's story, graph and Voronoi records (gen/trace.bend)
#   ccommit a ok                           WorldGen_Commit passed
#   cdigest a at ctr w h tiles             FNV-1a 64 of the tile map after tilemap, separate_islands, force_connectivity,
#                                          before_mazes, after_mazes, land_done, after_populate
#   cca a k id iterations mode points before after       RunCA
#   cpoints a k kind id area before after count hash     GetPointsForSite (kind ca or populate)
#   cmaze a k kind tag nodes before after count hash     RunMaze (runmaze) and GetPointsForMetaMaze (metamaze)
#   creserve a k node size start fill pos n before after ok x y   ReserveSpace
#   cdisconnect a count exceeds            DetectDisconnect
#   cents a at n ctr                       the entity count after mazes, populate, atrium, post, filter, bunches, archive
#   creq a prefab need have                the required prefab table
#   cstatus a ok                           the required prefab check
#   cverdict a result ctr                  world, commit, areas, disconnect, required or gaveup; ctr is the stream position
#                                          the next attempt starts from (the world's end for a world); crashed:runca when
#                                          the custom tile pass would crash the game (GenJob's check before the areas)

type Tr is Data:
  Tr{seed: U32, ctr: U32, last: U32, chunks: List<&2, List<&2, String>>}

type Rc is Data:
  Rc{seed: U32, a: U32, story: StoryGraph.St}

def handles(+stage: String) -> Bool:
  String.eq(stage, "cavegen")

def rc_story(+rc: Rc) -> StoryGraph.St:
  match rc:
    case Rc{_, _, +s}:
      s

def counter(+rc: Rc, +rng: Pcg.Rng) -> U32:
  match rc:
    case Rc{+seed, _, _}:
      Pcg.counter(seed, rng)

def attempt_of(+rc: Rc) -> U32:
  match rc:
    case Rc{_, +a, _}:
      a

def node_text(+rc: Rc, +n: U32) -> String:
  Canon.quoted(StoryGraph.node_name(rc_story(rc), n))

def names_of(+s: StoryGraph.St, nodes: List<&2, U32>) -> List<&2, String>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      StoryGraph.node_name(s, n) <> names_of(s, rest)

def nodes_text(+rc: Rc, nodes: List<&2, U32>) -> String:
  Canon.quoted(String.join(names_of(rc_story(rc), nodes), ";"))

def pts_hash(ps: List<&2, Points.Pt>, h: Grid.Hash) -> Grid.Hash:
  match ps:
    case Nil{}:
      h
    case Con{Points.Pt{+x, +y, +t}, rest}:
      pts_hash(rest, Grid.fnv_u32(Grid.fnv_u32(Grid.fnv_u32(h, x), y), t))

def found_hash(ps: List<&2, WorldCaveMaze.Found>, h: Grid.Hash) -> Grid.Hash:
  match ps:
    case Nil{}:
      h
    case Con{WorldCaveMaze.Found{+key, +x, +y}, rest}:
      found_hash(rest, Grid.fnv_u32(Grid.fnv_u32(Grid.fnv_u32(h, x), y), key))

def hash_text(+h: Grid.Hash) -> String:
  GenTrace.hash_text(h)

def digest_of(got: Grid.Grid & Grid.Hash, +rc: Rc, +at: String, +ctr: U32) -> Grid.Grid & String:
  (g, +h) = got
  match g:
    case Grid.Grid{cells, +w, +ht}:
      (Grid.Grid{cells, w, ht}, Canon.record("cdigest", [Canon.number("a", attempt_of(rc)), Canon.field("at", Canon.quoted(at)), Canon.number("ctr", ctr),
        Canon.number("w", w), Canon.number("h", ht), Canon.field("tiles", hash_text(h))]))

def digest(g: Grid.Grid, +rc: Rc, +at: String, +ctr: U32) -> Grid.Grid & String:
  digest_of(Grid.tiles_digest(g), rc, at, ctr)

def line_of(got: Grid.Grid & String) -> String:
  (_, +line) = got
  line

def digest_line(g: Grid.Grid, +rc: Rc, +at: String, +ctr: U32) -> String:
  line_of(digest(g, rc, at, ctr))

def points_record(+rc: Rc, +kind: String, +k: U32, +id: String, +area: U32, +before: Pcg.Rng, +after: Pcg.Rng, +kept: List<&2, Points.Pt>) -> String:
  Canon.record("cpoints", [Canon.number("a", attempt_of(rc)), Canon.number("k", k), Canon.field("kind", Canon.quoted(kind)), Canon.field("id", id),
    Canon.number("area", area), Canon.number("before", counter(rc, before)), Canon.number("after", counter(rc, after)),
    Canon.number("count", U32.from_nat(List.length(&2, Points.Pt, kept))), Canon.field("hash", hash_text(pts_hash(kept, Grid.fnv_offset())))])

# ConvertToTileMap's paint, then SeparateIslands and ForceConnectivity(join_islands) of the caves.
def paint_line(+rc: Rc, +world: TileWorld.World, +ctr: U32) -> String:
  digest_line(TileConvert.paint(world, TileConvert.site_tiles(world)), rc, "tilemap", ctr)

def forced_after(got: Grid.Grid & String, +rc: Rc, +world: TileWorld.World, +ctr: U32) -> List<&2, String>:
  (g, +line) = got
  [line, digest_line(TileConnect.force(world, TileConnect.islands(world, True{}), g), rc, "force_connectivity", ctr)]

def forced_lines(+rc: Rc, +world: TileWorld.World, +ctr: U32) -> List<&2, String>:
  forced_after(digest(TileSeparate.separate(world, TileConvert.paint(world, TileConvert.site_tiles(world))), rc, "separate_islands", ctr), rc, world, ctr)

type CaTr is Type:
  CaTr{ca: CaveCustom.Ca, lines: List<&2, String>, k: U32}

def ca_translated(picked: Points.Picked, placed: List<&2, CaveCustom.Placed>, +room: U32, +site: TileWorld.Site, +lines: List<&2, String>, +k: U32) -> CaTr:
  CaTr{CaveCustom.picked_translated(picked, placed, room, site), lines, (k + 1 : U32)}

def ca_picked(picked: Points.Picked, placed: List<&2, CaveCustom.Placed>, +room: U32, +site: TileWorld.Site, +rc: Rc, +vertex: U32, +sites: Points.Sites, +id: String, +before: Pcg.Rng, +lines: List<&2, String>, +k: U32) -> CaTr:
  match picked:
    case Points.Picked{g, +rng, +n, shuffled, +kept}:
      ca_translated(Points.Picked{g, rng, n, shuffled, kept}, placed, room, site,
        points_record(rc, "ca", k, id, Points.site_area(sites, vertex), before, rng, kept) <> lines, k)

def ca_painted(ran: CaveAutomaton.Painted, placed: List<&2, CaveCustom.Placed>, +rc: Rc, +windows: Bool, +sites: Points.Sites, +room: U32, +vertex: U32, +site: TileWorld.Site, +id: String, +before: Pcg.Rng, +lines: List<&2, String>, +k: U32) -> CaTr:
  match ran:
    case CaveAutomaton.Painted{g, +rng}:
      +line = Canon.record("cca", [Canon.number("a", attempt_of(rc)), Canon.number("k", k), Canon.field("id", id),
        Canon.number("iterations", CaveStory.room_ca_iterations(room)), Canon.number("mode", CaveStory.room_ca_seed_mode(room)),
        Canon.number("points", CaveStory.room_ca_random_points(room)), Canon.number("before", counter(rc, before)), Canon.number("after", counter(rc, rng))])
      ca_picked(Points.points_for_site(windows, sites, vertex, g, rng), placed, room, site, rc, vertex, sites, id, rng, line <> lines, k)

def ca_node(t: CaTr, +rc: Rc, +windows: Bool, +sites: Points.Sites, +world: TileWorld.World, +kl: GenGraph.Klei, +n: U32) -> CaTr:
  match t:
    case CaTr{ca, +lines, +k}:
      match ca:
        case CaveCustom.Ca{g, +rng, _, placed}:
          +room = StoryCatalog.cave_room(StoryGraph.nf(rc_story(rc), n, StoryGraph.f_room()))
          +vertex = GenGraph.vertex_of(kl, n)
          +site = TileWorld.site(world, vertex)
          ca_painted(CaveAutomaton.run(windows, site, CaveStory.room_ca_iterations(room), CaveStory.room_ca_seed_mode(room),
            CaveStory.room_ca_random_points(room), g, rng), placed, rc, windows, sites, room, vertex, site, node_text(rc, n), rng, lines, k)

def ca_loop(nodes: List<&2, U32>, t: CaTr, +rc: Rc, +windows: Bool, +sites: Points.Sites, +world: TileWorld.World, +kl: GenGraph.Klei) -> CaTr:
  match nodes:
    case Nil{}:
      t
    case Con{+n, rest}:
      ca_loop(rest, ca_node(t, rc, windows, sites, world, kl, n), rc, windows, sites, world, kl)

def ca_start(g: Grid.Grid, +rng: Pcg.Rng) -> CaTr:
  CaTr{CaveCustom.Ca{g, rng, Nil{}, Nil{}}, Nil{}, 0}

# Every RunCA of the custom tile pass and the GetPointsForSite after it, from the tile map after ForceConnectivity.
def ca_traced(+rc: Rc, +windows: Bool, +kl: GenGraph.Klei, +sites: Points.Sites, +w: U32) -> CaTr:
  +world = CaveCustom.world_of(sites)
  +s = rc_story(rc)
  ca_loop(CaveCustom.custom_nodes(CaveCustom.nodes_order(s), s),
    ca_start(Generate.cave_tile_grid(world, TileConvert.site_tiles(world)), Generate.rng_after_tiles(s, w)), rc, windows, sites, world, kl)

type MzTr is Type:
  MzTr{p: MazeEnv.Pass, lines: List<&2, String>, k: U32}

def maze_record(+rc: Rc, +k: U32, +kind: String, +tag: String, +nodes: List<&2, U32>, +before: Pcg.Rng, +after: Pcg.Rng, +found: List<&2, WorldCaveMaze.Found>) -> String:
  Canon.record("cmaze", [Canon.number("a", attempt_of(rc)), Canon.number("k", k), Canon.field("kind", Canon.quoted(kind)), Canon.field("tag", Canon.quoted(tag)),
    Canon.field("nodes", nodes_text(rc, nodes)), Canon.number("before", counter(rc, before)), Canon.number("after", counter(rc, after)),
    Canon.number("count", U32.from_nat(List.length(&2, WorldCaveMaze.Found, found))), Canon.field("hash", hash_text(found_hash(found, Grid.fnv_offset())))])

def labyrinth_ran(ran: WorldCaveMaze.Ran, +e: MazeEnv.Env, +rc: Rc, +k: U32, +members: List<&2, U32>, +entrances: List<&2, U32>, +before: Pcg.Rng, ents: List<&2, Entities.Ent>, marks: List<&2, Pcg.Rng>, +lines: List<&2, String>) -> MzTr:
  match ran:
    case WorldCaveMaze.Ran{g, +found, +rng}:
      MzTr{MazeLabyrinth.ran_lines(WorldCaveMaze.Ran{g, found, rng}, e, members, entrances, before, ents, marks), maze_record(rc, k, "runmaze", "Labyrinth", members, before, rng, found) <> lines, (k + 1 : U32)}

def labyrinth_drawn(got: F64Repr.F64 & Pcg.Rng, +e: MazeEnv.Env, +rc: Rc, +k: U32, +members: List<&2, U32>, +entrances: List<&2, U32>, g: Grid.Grid, ents: List<&2, Entities.Ent>, marks: List<&2, Pcg.Rng>, +lines: List<&2, String>) -> MzTr:
  (+r, +rng) = got
  labyrinth_ran(WorldCaveMaze.run_maze(WorldCaveMaze.Params{MazeEnv.windows_of(e), 3, MazeLabyrinth.val_of(r), Enums.tile_impassable(), Enums.tile_brick()},
    MazeEnv.node_sites(members, e), g, rng), e, rc, k, members, entrances, rng, ents, marks, lines)

def labyrinth_task(t: MzTr, +e: MazeEnv.Env, +rc: Rc, +task: U32) -> MzTr:
  match t:
    case MzTr{p, +lines, +k}:
      match p:
        case MazeEnv.Pass{g, +rng, ents, marks}:
          labyrinth_drawn(F64Random.random(rng), e, rc, k, MazeTags.nodes(MazeEnv.story_of(e), "Labyrinth", task), MazeTags.nodes(MazeEnv.story_of(e), "LabyrinthEntrance", task),
            g, ents, marks, lines)

def meta_mapped(m: WorldCaveMaze.Mapped, +e: MazeEnv.Env, +rc: Rc, +k: U32, +g: U32, +members: List<&2, U32>, grid: Grid.Grid, +before: Pcg.Rng, ents: List<&2, Entities.Ent>, marks: List<&2, Pcg.Rng>, +lines: List<&2, String>) -> MzTr:
  match m:
    case WorldCaveMaze.Mapped{+found, +rng}:
      MzTr{MazeMeta.mapped(WorldCaveMaze.Mapped{found, rng}, e, g, grid, before, ents, marks), maze_record(rc, k, "metamaze", "Maze", members, before, rng, found) <> lines, (k + 1 : U32)}

def meta_task(t: MzTr, +e: MazeEnv.Env, +rc: Rc, +g: U32) -> MzTr:
  match t:
    case MzTr{p, +lines, +k}:
      match p:
        case MazeEnv.Pass{grid, +rng, ents, marks}:
          +members = MazeTags.nodes(MazeEnv.story_of(e), "Maze", g)
          meta_mapped(WorldCaveMaze.meta_maze(MazeEnv.windows_of(e), CaveStory.task_maze_size(StoryCatalog.cave_task(StoryGraph.gf(MazeEnv.story_of(e), g, StoryGraph.g_part()))),
            MazeEnv.node_sites(members, e), rng), e, rc, k, g, members, grid, rng, ents, marks, lines)

def labyrinth_loop(tasks: List<&2, U32>, t: MzTr, +e: MazeEnv.Env, +rc: Rc) -> MzTr:
  match tasks:
    case Nil{}:
      t
    case Con{+task, rest}:
      labyrinth_loop(rest, labyrinth_task(t, e, rc, task), e, rc)

def meta_loop(tasks: List<&2, U32>, t: MzTr, +e: MazeEnv.Env, +rc: Rc) -> MzTr:
  match tasks:
    case Nil{}:
      t
    case Con{+g, rest}:
      meta_loop(rest, meta_task(t, e, rc, g), e, rc)

def maze_lines_of(t: MzTr) -> List<&2, String>:
  match t:
    case MzTr{_, +lines, _}:
      lines

# Every RunMaze and GetPointsForMetaMaze of the Labyrinth and Maze passes, from the tile map before the mazes.
def maze_lines(+rc: Rc, +e: MazeEnv.Env, g: Grid.Grid, +rng: Pcg.Rng) -> List<&2, String>:
  +story = MazeEnv.story_of(e)
  List.reverse(&2, String, maze_lines_of(meta_loop(MazeTags.tasks(story, "Maze"),
    labyrinth_loop(MazeTags.tasks(story, "Labyrinth"), MzTr{MazeEnv.Pass{g, rng, Nil{}, Nil{}}, Nil{}, 0}, e, rc), e, rc)))

type Cn is Data:
  Cn{reserves: U32, points: U32, w: U32}

def optional(+ok: Bool, +v: U32) -> String:
  Bool.pick(String, ok, U32.show(v), "nil")

def reserve_record(+rc: Rc, +cn: Cn, +node: U32, +size: U32, +start: U32, +fill: U32, +pos: U32, +n: U32, +before: Pcg.Rng, +after: Pcg.Rng, +ok: Bool, +x: U32, +y: U32) -> String:
  match cn:
    case Cn{+k, _, _}:
      Canon.record("creserve", [Canon.number("a", attempt_of(rc)), Canon.number("k", k), Canon.field("node", node_text(rc, node)), Canon.field("size", Canon.hex32(size)),
        Canon.number("start", start), Canon.number("fill", fill), Canon.number("pos", pos), Canon.number("n", n), Canon.number("before", counter(rc, before)),
        Canon.number("after", counter(rc, after)), Canon.number("ok", Bool.to_u32(ok)), Canon.field("x", optional(ok, x)), Canon.field("y", optional(ok, y))])

def populate_digest_name(+at: U32) -> String:
  match at:
    case 0:
      "convert_ground"
    case 1:
      "land_done"
    case _:
      "after_populate"

def digest_record(+rc: Rc, +cn: Cn, +at: U32, +rng: Pcg.Rng, +tiles: Grid.Hash) -> String:
  match cn:
    case Cn{_, _, +w}:
      Canon.record("cdigest", [Canon.number("a", attempt_of(rc)), Canon.field("at", Canon.quoted(populate_digest_name(at))), Canon.number("ctr", counter(rc, rng)),
        Canon.number("w", w), Canon.number("h", w), Canon.field("tiles", hash_text(tiles))])

def digest_then(+at: U32, +disc: String, +rest: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(at, 1), disc <> rest, rest)

def bumped_reserve(+cn: Cn) -> Cn:
  match cn:
    case Cn{+r, +p, +w}:
      Cn{(r + 1 : U32), p, w}

def bumped_point(+cn: Cn) -> Cn:
  match cn:
    case Cn{+r, +p, +w}:
      Cn{r, (p + 1 : U32), w}

def points_k(+cn: Cn) -> U32:
  match cn:
    case Cn{_, +p, _}:
      p

def event_lines(evs: List<&2, PopulateState.Ev>, +rc: Rc, +cn: Cn, +disc: String) -> List<&2, String>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case PopulateState.EPoints{+node, +n, +before, +after, _, +kept}:
          points_record(rc, "populate", points_k(cn), node_text(rc, node), n, before, after, kept) <> event_lines(rest, rc, bumped_point(cn), disc)
        case PopulateState.EReserve{+node, +size, +start, +fill, +pos, +n, +before, +after, +ok, +x, +y}:
          reserve_record(rc, cn, node, size, start, fill, pos, n, before, after, ok, x, y) <> event_lines(rest, rc, bumped_reserve(cn), disc)
        case PopulateState.EDigest{+at, +rng, +tiles, _}:
          digest_record(rc, cn, at, rng, tiles) <> digest_then(at, disc, event_lines(rest, rc, cn, disc))
        case _:
          event_lines(rest, rc, cn, disc)

def cents_line(+rc: Rc, +at: String, +n: U32, +rng: Pcg.Rng) -> String:
  Canon.record("cents", [Canon.number("a", attempt_of(rc)), Canon.field("at", Canon.quoted(at)), Canon.number("n", n), Canon.number("ctr", counter(rc, rng))])

def land_summary(l: PopulateState.Land, +rc: Rc, +cn: Cn, +disc: String, +at: String) -> PopulateState.Land & List<&2, String>:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      (PopulateState.Land{g, rng, ents, events}, List.append(&2, String, event_lines(List.reverse(&2, PopulateState.Ev, events), rc, cn, disc),
        [cents_line(rc, at, U32.from_nat(List.length(&2, Entities.Ent, ents)), rng)]))

def disconnect_branch(exceeds: Bool, l: PopulateState.Land, +cx: PopulateState.Ctx, +rc: Rc, +disc: String) -> PopulateState.Land & List<&2, String>:
  match exceeds:
    case True{}:
      land_summary(l, rc, Cn{0, 0, PopulateState.width_of(cx)}, disc, "disconnect")
    case False{}:
      land_summary(PopulateVoronoi.populate(cx, l), rc, Cn{0, 0, PopulateState.width_of(cx)}, disc, "populate")

def populated_job(got: PopulateState.Land & List<&2, String>, +ok: Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +w: U32, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  (land, +lines) = got
  (GenJob.cave_populated((land, ok), c, a, s, w, graph), lines)

def detected_lines(got: Grid.Grid & U32, +cx: PopulateState.Ctx, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>, +rc: Rc, +c: Generate.Seed, +w: U32, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  (g, +count) = got
  +exceeds = TileDisconnect.exceeds(count, PopulateState.width_of(cx), PopulateState.height_of(cx))
  populated_job(disconnect_branch(exceeds, PopulateState.Land{g, rng, ents, events}, cx, rc,
    Canon.record("cdisconnect", [Canon.number("a", attempt_of(rc)), Canon.number("count", count), Canon.number("exceeds", Bool.to_u32(exceeds))])),
    Bool.not(exceeds), c, attempt_of(rc), rc_story(rc), w, graph)

def replaced_lines(l: PopulateState.Land, +cx: PopulateState.Ctx, +sx: U32, +sy: U32, +rc: Rc, +c: Generate.Seed, +w: U32, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      detected_lines(TileDisconnect.detect(g, sx, sy), cx, rng, ents, events, rc, c, w, graph)

def populate_start(start: U32 & U32, +cx: PopulateState.Ctx, land: PopulateState.Land, +rc: Rc, +c: Generate.Seed, +w: U32, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  (+sx, +sy) = start
  replaced_lines(PopulateState.digest(PopulateLand.replaced(PopulateGround.convert_ground(cx, land)), cx, 1), cx, sx, sy, rc, c, w, graph)

# ConvertGround to PopulateVoronoi with the events recorded, and DetectDisconnect between them.
def populate_lines(+c: Generate.Seed, +k: GenGraph.Klei, +sites: Points.Sites, +w: U32, land: PopulateState.Land, +rc: Rc) -> GenJob.Job & List<&2, String>:
  populate_start(Generate.cave_start(rc_story(rc), k, sites), Generate.land_context(c, rc_story(rc), k, sites, w, True{}), land, rc, c, w,
    GenJob.sites_graph(rc_story(rc), k, sites))

type Ps is Type:
  Ps{sea: OceanState.Sea, lines: List<&2, String>}

type Facts is Data:
  Facts{n: U32, rng: Pcg.Rng}

def sea_facts(s: OceanState.Sea) -> OceanState.Sea & Facts:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      (OceanState.Sea{g, ids, rng, ents, topo, events}, Facts{U32.from_nat(List.length(&2, OceanEnts.Ent, ents)), rng})

def counted_facts(got: OceanState.Sea & Facts, +rc: Rc, +at: String, +lines: List<&2, String>) -> Ps:
  (sea, +facts) = got
  match facts:
    case Facts{+n, +rng}:
      Ps{sea, cents_line(rc, at, n, rng) <> lines}

def counted(ps: Ps, +rc: Rc, +at: String) -> Ps:
  match ps:
    case Ps{sea, +lines}:
      counted_facts(sea_facts(sea), rc, at, lines)

def post_populated(ps: Ps, +cx: OceanState.Ctx, +wormhole: U32) -> Ps:
  match ps:
    case Ps{sea, +lines}:
      Ps{OceanPost.post_populate(cx, wormhole, sea), lines}

def filtered(ps: Ps, +cx: OceanState.Ctx) -> Ps:
  match ps:
    case Ps{sea, +lines}:
      Ps{OceanPost.impassable_filter(cx, sea), lines}

def bunched(ps: Ps, +cx: OceanState.Ctx) -> Ps:
  match ps:
    case Ps{sea, +lines}:
      Ps{Bunches.bunches(cx, sea), lines}

def archived(ps: Ps, +dispenser: U32, +temporary: U32) -> Ps:
  match ps:
    case Ps{sea, +lines}:
      Ps{Archive.run(dispenser, temporary, sea), lines}

def req_loop(reqs: List<&2, OceanPost.Req>, +ents: List<&2, OceanEnts.Ent>, +rc: Rc, +missing: U32) -> List<&2, String>:
  match reqs:
    case Nil{}:
      [Canon.record("cstatus", [Canon.number("a", attempt_of(rc)), Canon.number("ok", Bool.to_u32(U32.is_zero(missing)))])]
    case Con{OceanPost.Req{+prefab, +count}, rest}:
      +have = OceanEnts.count(ents, prefab)
      Canon.record("creq", [Canon.number("a", attempt_of(rc)), Canon.field("prefab", Canon.quoted(Strings.name(prefab))), Canon.number("need", count), Canon.number("have", have)])
        <> req_loop(rest, ents, rc, (missing + Bool.to_u32((have < count : U32)) : U32))

def required_step(got: OceanState.Sea & List<&2, OceanEnts.Ent>, +cx: OceanState.Ctx, +rc: Rc, +lines: List<&2, String>, +c: Generate.Seed, +w: U32, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  (sea, +ents) = got
  (GenJob.cave_posted(Finish.checked(OceanPost.required(CaveRequired.required(rc_story(rc)), cx, sea), cx), c, attempt_of(rc), rc_story(rc), w, graph),
    List.append(&2, String, List.reverse(&2, String, lines), req_loop(CaveRequired.required(rc_story(rc)), ents, rc, 0)))

def post_final(ps: Ps, +cx: OceanState.Ctx, +rc: Rc, +c: Generate.Seed, +w: U32, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  match ps:
    case Ps{sea, +lines}:
      required_step(OceanState.ents_of(sea), cx, rc, lines, c, w, graph)

def post_chain(ps: Ps, shard: Finish.Shard, +cx: OceanState.Ctx, +rc: Rc, +c: Generate.Seed, +w: U32, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  match shard:
    case Finish.Shard{+wormhole, +dispenser, +temporary}:
      post_final(counted(archived(counted(bunched(counted(filtered(counted(post_populated(counted(ps, rc, "atrium"), cx, wormhole), rc, "post_populate"), cx), rc, "filter"), cx), rc, "bunches"),
        dispenser, temporary), rc, "archive"), cx, rc, c, w, graph)

# GlobalPostPopulate to the required prefab check on the caves' land, and the job that follows.
def post_lines(+c: Generate.Seed, +w: U32, land: PopulateState.Land, +rc: Rc, +graph: FilterDump.Graph) -> GenJob.Job & List<&2, String>:
  match land:
    case PopulateState.Land{g, +rng, +ents, _}:
      post_chain(Ps{GenJob.atriumed(OceanState.ents_of(GenJob.sea_of(GenJob.Landed{g, rng, ents, rc_story(rc), w, Nil{}, Nil{}, graph}))), Nil{}},
        GenJob.cave_shard(), OceanState.Ctx{Generate.windows_of(c), Generate.swaps_of(c), w, w, False{}, False{}}, rc, c, w, graph)

def ca_mazes(t: CaTr, +rc: Rc, +e: MazeEnv.Env) -> List<&2, String>:
  match t:
    case CaTr{ca, +lines, _}:
      match ca:
        case CaveCustom.Ca{g, +rng, _, _}:
          List.append(&2, String, List.reverse(&2, String, lines), maze_lines(rc, e, g, rng))

# The custom tile pass's engine calls and the mazes' that follow them.
def cave_lines(+rc: Rc, +c: Generate.Seed, +kl: GenGraph.Klei, +sites: Points.Sites, +w: U32) -> List<&2, String>:
  ca_mazes(ca_traced(rc, Generate.windows_of(c), kl, sites, w), rc, MazeEnv.Env{Generate.windows_of(c), Generate.swaps_of(c), rc_story(rc), kl, w, CaveCustom.world_of(sites)})

def verdict_line(+a: U32, +result: String, +ctr: U32) -> String:
  Canon.record("cverdict", [Canon.number("a", a), Canon.field("result", Canon.quoted(result)), Canon.number("ctr", ctr)])

def failed_at(+stage: U32) -> String:
  match stage:
    case 3:
      "commit"
    case 4:
      "areas"
    case 11:
      "disconnect"
    case _:
      "required"

def tr_seed(+st: Tr) -> U32:
  match st:
    case Tr{+seed, _, _, _}:
      seed

def tr_last(+st: Tr) -> U32:
  match st:
    case Tr{_, _, +last, _}:
      last

def tr_ctr(+st: Tr) -> U32:
  match st:
    case Tr{_, +ctr, _, _}:
      ctr

def rc_of(+st: Tr, +a: U32, +s: StoryGraph.St) -> Rc:
  Rc{tr_seed(st), a, s}

def gen_tr(+st: Tr, +a: U32) -> GenTrace.Tr:
  GenTrace.Tr{tr_seed(st), 0, a, tr_ctr(st), Nil{}}

def start_lines(+st: Tr, +a: U32, +rng: Pcg.Rng) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(a, 1), [Canon.record("cattempt", [Canon.number("a", a), Canon.number("ctr", Pcg.counter(tr_seed(st), rng))])],
    [verdict_line((a - 1 : U32), failed_at(tr_last(st)), Pcg.counter(tr_seed(st), rng))])

def commit_lines(+st: Tr, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +second: Generate.Pass) -> List<&2, String>:
  List.append(&2, String, GenTrace.first_lines(gen_tr(st, a), s, k, a, second),
    GenTrace.commit_lines(Generate.commit(c, second), Pcg.counter(tr_seed(st), StoryGraph.rng_of(s)), a, GenTrace.names_of(GenGraph.vertices_of(k), s)))

def tiles_lines(+st: Tr, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>) -> List<&2, String>:
  [Canon.record("ccommit", [Canon.number("a", a), Canon.number("ok", 1)]),
    paint_line(rc_of(st, a, s), Generate.tile_world(s, k, Generate.tile_size(size), Generate.tile_centred(size, sites), Generate.tile_build(c, size, sites)),
      Pcg.counter(tr_seed(st), Generate.rng_after_tiles(s, Generate.tile_size(size))))]

def tiled_pair(got: Grid.Grid & String, +rest: List<&2, String>) -> Grid.Grid & List<&2, String>:
  (g, +line) = got
  (g, line <> rest)

def tiled_lines(g: Grid.Grid, +st: Tr, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +rng: Pcg.Rng, +sites: Points.Sites) -> Grid.Grid & List<&2, String>:
  tiled_pair(digest(g, rc_of(st, a, s), "before_mazes", Pcg.counter(tr_seed(st), rng)), cave_lines(rc_of(st, a, s), c, k, sites, w))

def mazed_populated(got: GenJob.Job & List<&2, String>, +head: List<&2, String>) -> GenJob.Job & List<&2, String>:
  (job, +lines) = got
  (job, List.append(&2, String, head, lines))

def mazed_digest(got: Grid.Grid & String, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>, +st: Tr, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: Points.Sites) -> GenJob.Job & List<&2, String>:
  (g, +line) = got
  mazed_populated(populate_lines(c, k, sites, w, PopulateState.Land{g, rng, ents, events}, rc_of(st, a, s)),
    [line, cents_line(rc_of(st, a, s), "mazes", U32.from_nat(List.length(&2, Entities.Ent, ents)), rng)])

def mazed_lines(land: PopulateState.Land, +st: Tr, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: Points.Sites) -> GenJob.Job & List<&2, String>:
  match land:
    case PopulateState.Land{g, +rng, +ents, +events}:
      mazed_digest(digest(g, rc_of(st, a, s), "after_mazes", Pcg.counter(tr_seed(st), rng)), rng, ents, events, st, c, a, s, k, w, sites)

def world_digest(got: Grid.Grid & Grid.Hash, +a: U32, +ctr: U32, +n: U32) -> List<&2, String>:
  (g, +h) = got
  match g:
    case Grid.Grid{_, +w, +ht}:
      [Canon.record("cdigest", [Canon.number("a", a), Canon.field("at", Canon.quoted("final")), Canon.number("ctr", ctr), Canon.number("w", w), Canon.number("h", ht),
        Canon.field("tiles", hash_text(h))]),
        Canon.record("cents", [Canon.number("a", a), Canon.field("at", Canon.quoted("final")), Canon.number("n", n), Canon.number("ctr", ctr)]),
        verdict_line(a, "world", ctr)]

def world_lines(world: GenJob.Final, +seed: U32, +a: U32) -> List<&2, String>:
  match world:
    case GenJob.Final{g, +rng, +ents, _, _, _, _, _}:
      world_digest(Grid.tiles_digest(g), a, Pcg.counter(seed, rng), U32.from_nat(List.length(&2, OceanEnts.Ent, ents)))

def crashed_name(+last: U32) -> String:
  Bool.pick(String, U32.is_eq(last, 4), "runca", failed_at(last))

def done_name(+o: GenJob.Outcome, +last: U32) -> String:
  match o:
    case GenJob.Crashed{}:
      "crashed:" ++ crashed_name(last)
    case GenJob.GaveUp{}:
      "gaveup:" ++ failed_at(last)

def stopped(+c: Generate.Seed, +a: U32) -> GenJob.Job:
  GenJob.JDone{c, a, GenJob.GaveUp{}}

def start_job(first: Bool, +c: Generate.Seed, +a: U32, +rng: Pcg.Rng) -> GenJob.Job:
  match first:
    case True{}:
      GenJob.advance(GenJob.JStart{c, a, rng})
    case False{}:
      stopped(c, a)

def tiled_job(got: Grid.Grid & List<&2, String>, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +rng: Pcg.Rng, placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites) -> GenJob.Job & List<&2, String>:
  (g, +lines) = got
  (GenJob.advance(GenJob.JTiled{c, a, s, k, w, g, rng, placed, sites}), lines)

# The stage the job has just entered: its records, and the job after the stage (a stopped one at the end of the attempt).
def enter(job: GenJob.Job, +st: Tr) -> GenJob.Job & List<&2, String>:
  match job:
    case GenJob.JStart{+c, +a, +rng}:
      (start_job(U32.is_eq(a, 1), c, a, rng), start_lines(st, a, rng))
    case GenJob.JFirst{+c, +a, +s, +k}:
      (GenJob.advance(GenJob.JFirst{c, a, s, k}), Nil{})
    case GenJob.JSecond{+c, +a, +s, +k, +first}:
      (GenJob.advance(GenJob.JSecond{c, a, s, k, first}), Nil{})
    case GenJob.JCommit{+c, +a, +s, +k, +second}:
      (GenJob.advance(GenJob.JCommit{c, a, s, k, second}), commit_lines(st, c, a, s, k, second))
    case GenJob.JTiles{+c, +a, +s, +k, +size, +sites}:
      (GenJob.advance(GenJob.JTiles{c, a, s, k, size, sites}), tiles_lines(st, c, a, s, k, size, sites))
    case GenJob.JLand{+c, +a, +s, +k, +w, +world, +lists, +sites}:
      (GenJob.advance(GenJob.JLand{c, a, s, k, w, world, lists, sites}), forced_lines(rc_of(st, a, s), world, Pcg.counter(tr_seed(st), Generate.rng_after_tiles(s, w))))
    case GenJob.JTiled{+c, +a, +s, +k, +w, grid, +rng, placed, +sites}:
      tiled_job(tiled_lines(grid, st, c, a, s, k, w, rng, sites), c, a, s, k, w, rng, placed, sites)
    case GenJob.JMazed{+c, +a, +s, +k, +w, land, +sites}:
      mazed_lines(land, st, c, a, s, k, w, sites)
    case GenJob.JPost{+c, +a, +s, +w, land, +graph}:
      post_lines(c, w, land, rc_of(st, a, s), graph)
    case GenJob.JWorld{+c, +a, world}:
      (stopped(c, a), world_lines(world, tr_seed(st), a))
    case GenJob.JDone{+c, +a, +o}:
      (stopped(c, a), [verdict_line(a, done_name(o, tr_last(st)), 0)])
    case GenJob.JOcean{+c, +a, landed}:
      (stopped(c, a), Nil{})

def tr_chunks(+st: Tr) -> List<&2, List<&2, String>>:
  match st:
    case Tr{_, _, _, +chunks}:
      chunks

def stops(+stage: U32, +a: U32) -> Bool:
  U32.is_eq(stage, 7) || U32.is_eq(stage, 8) || (U32.is_eq(stage, 0) && (1 < a : U32))

type Next is Type:
  More{job: GenJob.Job}
  Ended{}

def moved(stop: Bool, job: GenJob.Job) -> Next:
  match stop:
    case True{}:
      Ended{}
    case False{}:
      More{job}

def entered(got: GenJob.Job & List<&2, String>, +st: Tr, +stage: U32, +a: U32) -> Tr & Next:
  (job, +lines) = got
  (Tr{tr_seed(st), tr_ctr(st), stage, lines <> tr_chunks(st)}, moved(stops(stage, a), job))

def with_rng(got: GenJob.Job & Pcg.Rng, +st: Tr, +stage: U32, +a: U32) -> Tr & Next:
  (job, +rng) = got
  entered(enter(job, Tr{tr_seed(st), GenTrace.start_counter(stage, tr_seed(st), tr_ctr(st), rng), tr_last(st), tr_chunks(st)}),
    Tr{tr_seed(st), GenTrace.start_counter(stage, tr_seed(st), tr_ctr(st), rng), tr_last(st), tr_chunks(st)}, stage, a)

def at_stage(got: GenJob.Job & GenJob.Where, +st: Tr) -> Tr & Next:
  (job, +at) = got
  match at:
    case GenJob.Where{+stage, +a}:
      with_rng(GenTrace.job_rng(job), st, stage, a)

def trace_loop(fuel: Nat, got: Tr & Next) -> Tr:
  match fuel:
    case 0n:
      (+st, _) = got
      st
    case 1n+f:
      (+st, next) = got
      match next:
        case Ended{}:
          st
        case More{job}:
          trace_loop(f, at_stage(GenJob.stage(job), st))

# The stage's records for a seed on the platform; the input is the stream position the attempt starts from (empty for the first).
def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  GenTrace.lines_of(GenTrace.Tr{seed, 0, 0, 0, tr_chunks(trace_loop(256n,
    (Tr{seed, 0, 0, Nil{}}, More{GenJob.start_caves(seed, windows, Maybe.default(&2, U32, U32.read(input), 0), False{})})))})
