import Base
import ../data/enums.bend as Enums
import ../f64/repr.bend as F64Repr
import ../storygen/order.bend as StoryOrder
import ../worldsim/grid.bend as Grid
import ../worldsim/tiles/cellline.bend as TileCellLine
import ../worldsim/tiles/lines.bend as TileLines
import ../worldsim/tiles/world.bend as TileWorld
import ./graph.bend as GenGraph
import ./tags.bend as GenTags
import ./maze_env.bend as MazeEnv
import ./maze_tags.bend as MazeTags

# The lines the maze passes draw so a maze does not cut itself off from land: WorldSim:DrawCellLine along the edges of
# nodes (from site to site) and WorldSim:DrawGroundLine between two positions.

def line_between(both: Bool, g: Grid.Grid, +e: MazeEnv.Env, +a: U32, +b: U32, +pen: TileLines.Pen) -> Grid.Grid:
  match both:
    case True{}:
      TileCellLine.draw_cell_line(g, MazeEnv.site_of(e, a), MazeEnv.site_of(e, b), Enums.connection_edge_site(), pen)
    case False{}:
      g

# DrawCellLine(node1, node2, EdgeSite, pen.tile, pen.flag, pen.only_invalid): nothing when a node is unknown.
def cell_line(g: Grid.Grid, +e: MazeEnv.Env, +l: MazeTags.Link, +pen: TileLines.Pen) -> Grid.Grid:
  match l:
    case MazeTags.Link{+a, +b}:
      line_between(Bool.not(TileWorld.is_none(GenGraph.vertex_of(MazeEnv.klei_of(e), a))) && Bool.not(TileWorld.is_none(GenGraph.vertex_of(MazeEnv.klei_of(e), b))), g, e, a, b, pen)

def cell_line_if(drawn: Bool, g: Grid.Grid, +e: MazeEnv.Env, +l: MazeTags.Link, +pen: TileLines.Pen) -> Grid.Grid:
  match drawn:
    case True{}:
      cell_line(g, e, l, pen)
    case False{}:
      g

def crossing(+members: List<&2, U32>, +l: MazeTags.Link) -> Bool:
  match l:
    case MazeTags.Link{+a, +b}:
      U32.is_ne(Bool.to_u32(StoryOrder.contains(members, a)), Bool.to_u32(StoryOrder.contains(members, b)))

def boundary_link(g: Grid.Grid, +e: MazeEnv.Env, +members: List<&2, U32>, +pen: TileLines.Pen, +l: MazeTags.Link) -> Grid.Grid:
  cell_line_if(MazeTags.is_solid(MazeEnv.story_of(e), l) && crossing(members, l), g, e, l, pen)

def boundary_links(links: List<&2, MazeTags.Link>, g: Grid.Grid, +e: MazeEnv.Env, +members: List<&2, U32>, +pen: TileLines.Pen) -> Grid.Grid:
  match links:
    case Nil{}:
      g
    case Con{+l, rest}:
      boundary_links(rest, boundary_link(g, e, members, pen, l), e, members, pen)

# Every edge of `nodes` (in table order) between a node of `members` and one outside it, drawn when neither end is Blank.
def boundary(nodes: List<&2, U32>, g: Grid.Grid, +e: MazeEnv.Env, +members: List<&2, U32>, +pen: TileLines.Pen) -> Grid.Grid:
  match nodes:
    case Nil{}:
      g
    case Con{+n, rest}:
      boundary(rest, boundary_links(MazeTags.edges(MazeEnv.story_of(e), n), g, e, members, pen), e, members, pen)

def solid_link(g: Grid.Grid, +e: MazeEnv.Env, +pen: TileLines.Pen, +l: MazeTags.Link) -> Grid.Grid:
  cell_line_if(MazeTags.is_solid(MazeEnv.story_of(e), l), g, e, l, pen)

def solid_links(links: List<&2, MazeTags.Link>, g: Grid.Grid, +e: MazeEnv.Env, +pen: TileLines.Pen) -> Grid.Grid:
  match links:
    case Nil{}:
      g
    case Con{+l, rest}:
      solid_links(rest, solid_link(g, e, pen, l), e, pen)

# Every edge of the node, drawn when neither end is Blank.
def solid_edges(g: Grid.Grid, +e: MazeEnv.Env, +node: U32, +pen: TileLines.Pen) -> Grid.Grid:
  solid_links(MazeTags.edges(MazeEnv.story_of(e), node), g, e, pen)

def entrance_edges(nodes: List<&2, U32>, g: Grid.Grid, +e: MazeEnv.Env, +pen: TileLines.Pen) -> Grid.Grid:
  match nodes:
    case Nil{}:
      g
    case Con{+n, rest}:
      entrance_edges(rest, solid_edges(g, e, n, pen), e, pen)

def other_end(+l: MazeTags.Link, +entrance: U32) -> U32:
  match l:
    case MazeTags.Link{+a, +b}:
      Bool.pick(U32, U32.is_eq(a, entrance), b, a)

def fake_edges(cut: Bool, g: Grid.Grid, +e: MazeEnv.Env, +other: U32) -> Grid.Grid:
  match cut:
    case True{}:
      solid_edges(g, e, other, TileLines.Pen{Enums.tile_fake_ground(), False{}, True{}})
    case False{}:
      g

def bridged(solid: Bool, g: Grid.Grid, +e: MazeEnv.Env, +other: U32) -> Grid.Grid:
  fake_edges(solid && U32.is_eq(GenTags.disconnected(MazeEnv.story_of(e), other), 1), g, e, other)

# One edge of a maze entrance: the bridge line, and when the node across is ForceDisconnected the FAKE_GROUND lines
# along that node's own edges.
def bridge_link(g: Grid.Grid, +e: MazeEnv.Env, +entrance: U32, +tile: U32, +l: MazeTags.Link) -> Grid.Grid:
  bridged(MazeTags.is_solid(MazeEnv.story_of(e), l), cell_line_if(MazeTags.is_solid(MazeEnv.story_of(e), l), g, e, l, TileLines.Pen{tile, False{}, True{}}), e, other_end(l, entrance))

def bridge_links(links: List<&2, MazeTags.Link>, g: Grid.Grid, +e: MazeEnv.Env, +entrance: U32, +tile: U32) -> Grid.Grid:
  match links:
    case Nil{}:
      g
    case Con{+l, rest}:
      bridge_links(rest, bridge_link(g, e, entrance, tile, l), e, entrance, tile)

# The bridge lines of every maze entrance node (in table order).
def bridge(entrances: List<&2, U32>, g: Grid.Grid, +e: MazeEnv.Env, +tile: U32) -> Grid.Grid:
  match entrances:
    case Nil{}:
      g
    case Con{+n, rest}:
      bridge(rest, bridge_links(MazeTags.edges(MazeEnv.story_of(e), n), g, e, n, tile), e, tile)

# DrawGroundLine(x0, y0, x1, y1, tile, true, true) from tile coordinates.
def ground_line(g: Grid.Grid, +x0: F64Repr.F64, +y0: F64Repr.F64, +x1: F64Repr.F64, +y1: F64Repr.F64, +tile: U32) -> Grid.Grid:
  TileCellLine.draw_ground_line(g, x0, y0, x1, y1, TileLines.Pen{tile, True{}, True{}})
