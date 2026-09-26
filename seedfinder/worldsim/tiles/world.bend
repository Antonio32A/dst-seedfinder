import Base
import ../../f64/repr.bend as F64Repr
import ./table.bend as TileTable

# The inputs of the tile stages: the committed map after ConvertToTileMap's final Voronoi build.

type Point is Data:
  Point{x: F32, y: F32}

type DPoint is Data:
  DPoint{x: F64Repr.F64, y: F64Repr.F64}

# One half-edge of a cell ring: the twin cell's source index (>= the site count for a boundary segment), its
# vertices (None = infinite) and the double points DrawVoronoiEdge rasterises (clipped or sampled when needed).
type VEdge is Data:
  VEdge{twin: U32, v0: Maybe<&2, DPoint>, v1: Maybe<&2, DPoint>, points: List<&2, DPoint>}

type Cell is Data:
  Cell{src: U32, edges: List<&2, VEdge>}

# A site's Klei node (kind = Klei node type): `number` identifies the node (a site's node is numbered by its site), `parent`/`grand` its
# parent and grandparent numbers, `parent_site` the parent's site; NONE (4294967295) when absent. `pig` is 1 for a
# PigKingdom name, 2 for a PigVillage name, 0 otherwise.
type Node is Data:
  Node{number: U32, kind: U32, itype: U32, tile: U32, flags: U32, parent: U32, grand: U32, parent_kind: U32, parent_site: U32, pig: U32}

type Site is Data:
  Site{node: Node, x: F32, y: F32, cx: F32, cy: F32, polygon: List<&2, Point>}

type Edge is Data:
  Edge{s: U32, t: U32}

# sites/site_at: in vertex order; adjacency: each vertex's out-edge targets in Boost order; edges: boost::edges order
# (source first); cells: the diagram's point cells in cell order, cell_at: the same by source index.
type World is Data:
  World{width: U32, height: U32, count: U32, sites: List<&2, Site>, site_at: TileTable.Tree<Site>, adjacency: TileTable.Tree<List<&2, U32>>, edges: List<&2, Edge>, cells: List<&2, Cell>, cell_at: TileTable.Tree<Cell>}

def none() -> U32:
  4294967295

def is_none(+v: U32) -> Bool:
  U32.is_eq(v, 4294967295)

def site(+w: World, +i: U32) -> Site:
  match w:
    case World{_, _, _, _, +site_at, _, _, _, _}:
      TileTable.at(~Site, site_at, i)

def node_of(s: Site) -> Node:
  match s:
    case Site{+n, _, _, _, _, _}:
      n

def node(+w: World, +i: U32) -> Node:
  node_of(site(w, i))

def count(+w: World) -> U32:
  match w:
    case World{_, _, +n, _, _, _, _, _, _}:
      n

# The Voronoi cell of site i (an empty cell with source NONE when the site lost its cell).
def cell(+w: World, +i: U32) -> Cell:
  match w:
    case World{_, _, _, _, _, _, _, _, +cell_at}:
      TileTable.at(~Cell, cell_at, i)
