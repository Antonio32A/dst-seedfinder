import Base
import ../../data/tile_groups.bend as TileGroupsData
import ../grid.bend as Grid
import ./groups.bend as TileGroups

# WorldSim:DetectDisconnect: every walkable tile the 8-neighbour flood from the start tile does not reach becomes
# impassable and gets the disconnected flag (no reachable cave room or layout calls MakeSafeFromDisconnect). The flood only
# needs the reached set, so it drains a work list in any order.

type Flood is Type:
  Flood{cells: Array<U32>, seen: Array<U32>, queue: Array<U32>, head: U32, tail: U32, go: Bool}

type Sweep is Type:
  Sweep{cells: Array<U32>, seen: Array<U32>, count: U32}

def flood(cells: Array<U32>, seen: Array<U32>, queue: Array<U32>, +head: U32, +tail: U32) -> Flood:
  Flood{cells, seen, queue, head, tail, (head < tail : U32)}

# Land tiles and the fake ground the flood may cross.
def walkable(+tile: U32) -> Bool:
  TileGroups.is_land(tile) || U32.is_eq(tile, TileGroupsData.tile_fake_ground())

def enqueue_if(fresh: Bool, cells: Array<U32>, seen: Array<U32>, queue: Array<U32>, +i: U32, +head: U32, +tail: U32) -> Flood:
  match fresh:
    case True{}:
      seen[i] <- 1
      queue[tail] <- i
      flood(cells, seen, queue, head, (tail + 1 : U32))
    case False{}:
      flood(cells, seen, queue, head, tail)

def claim_seen(got: Array<U32> & U32, cells: Array<U32>, queue: Array<U32>, +i: U32, +head: U32, +tail: U32) -> Flood:
  (seen, +mark) = got
  enqueue_if(U32.is_zero(mark), cells, seen, queue, i, head, tail)

def claim_if(open: Bool, cells: Array<U32>, seen: Array<U32>, queue: Array<U32>, +i: U32, +head: U32, +tail: U32) -> Flood:
  match open:
    case True{}:
      claim_seen(seen[i], cells, queue, i, head, tail)
    case False{}:
      flood(cells, seen, queue, head, tail)

def visit_tile(got: Array<U32> & U32, seen: Array<U32>, queue: Array<U32>, +i: U32, +head: U32, +tail: U32) -> Flood:
  (cells, +cell) = got
  claim_if(walkable(Grid.tile_of(cell)), cells, seen, queue, i, head, tail)

def visit_if(inside: Bool, f: Flood, +i: U32) -> Flood:
  match inside:
    case True{}:
      match f:
        case Flood{cells, seen, queue, +head, +tail, _}:
          visit_tile(cells[i], seen, queue, i, head, tail)
    case False{}:
      match f:
        case Flood{cells, seen, queue, +head, +tail, _}:
          flood(cells, seen, queue, head, tail)

def probe(f: Flood, +nx: U32, +ny: U32, +width: U32, +height: U32) -> Flood:
  visit_if((nx < width : U32) && (ny < height : U32), f, Grid.index(nx, ny, width))

def probe_around(n: Nat, f: Flood, +x: U32, +y: U32, +k: U32, +width: U32, +height: U32) -> Flood:
  match n:
    case 0n:
      f
    case 1n+p:
      probe_around(p, probe(f, (x + U32.mod(k, 3) - 1 : U32), (y + (k / 3) - 1 : U32), width, height), x, y, (k + 1 : U32), width, height)

def expand(got: Array<U32> & U32, cells: Array<U32>, seen: Array<U32>, +head: U32, +tail: U32, +width: U32, +height: U32) -> Flood:
  (queue, +i) = got
  probe_around(9n, flood(cells, seen, queue, (head + 1 : U32), tail), U32.mod(i, width), (i / width : U32), 0, width, height)

def drain(n: Nat, f: Flood, +width: U32, +height: U32) -> Flood:
  match n:
    case 0n:
      f
    case 1n+p:
      match f:
        case Flood{cells, seen, queue, +head, +tail, +go}:
          match go:
            case False{}:
              flood(cells, seen, queue, head, tail)
            case True{}:
              drain(p, expand(queue[head], cells, seen, head, tail, width, height), width, height)

def drop_if(lost: Bool, cells: Array<U32>, seen: Array<U32>, +cell: U32, +count: U32, +i: U32) -> Sweep:
  match lost:
    case True{}:
      cells[i] <- Grid.cell(TileGroups.impassable(), (Grid.flags_of(cell) .|. Grid.disconnected_flag() : U32))
      Sweep{cells, seen, (count + 1 : U32)}
    case False{}:
      Sweep{cells, seen, count}

def judge(got: Array<U32> & U32, cells: Array<U32>, +cell: U32, +count: U32, +i: U32) -> Sweep:
  (seen, +mark) = got
  drop_if(U32.is_zero(mark) && walkable(Grid.tile_of(cell)), cells, seen, cell, count, i)

def sweep_cell(got: Array<U32> & U32, seen: Array<U32>, +count: U32, +i: U32) -> Sweep:
  (cells, +cell) = got
  judge(seen[i], cells, cell, count, i)

def sweep(n: Nat, s: Sweep, +i: U32) -> Sweep:
  match n:
    case 0n:
      s
    case 1n+p:
      match s:
        case Sweep{cells, seen, +count}:
          sweep(p, sweep_cell(cells[i], seen, count, i), (i + 1 : U32))

def finished(s: Sweep, +width: U32, +height: U32) -> Grid.Grid & U32:
  match s:
    case Sweep{cells, _, +count}:
      (Grid.Grid{cells, width, height}, count)

def swept(f: Flood, +width: U32, +height: U32) -> Grid.Grid & U32:
  match f:
    case Flood{cells, seen, _, _, _, _}:
      finished(sweep(U32.to_nat((width * height : U32)), Sweep{cells, seen, 0}, 0), width, height)

# DetectDisconnect from the tile (start_x, start_y): the grid with every walkable tile the flood misses turned
# impassable and flagged disconnected, and how many that was.
def detect(g: Grid.Grid, +start_x: U32, +start_y: U32) -> Grid.Grid & U32:
  match g:
    case Grid.Grid{cells, +width, +height}:
      +size = (width * height : U32)
      +depth = Grid.depth_for(24n, (size + 1 : U32), 0n, 1)
      swept(drain(U32.to_nat((size + 1 : U32)), flood(cells, Grid.alloc(depth, 0), Grid.alloc(depth, Grid.index(start_x, start_y, width)), 0, 1), width, height), width, height)

# The failure rule of forest_map's Generate: more than floor(width * height * 0.05) disconnected tiles fails the attempt.
def exceeds(+count: U32, +width: U32, +height: U32) -> Bool:
  (count > ((width * height : U32) / 20 : U32) : U32)
