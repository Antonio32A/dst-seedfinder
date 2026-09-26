import Base
import ../grid.bend as Grid
import ./groups.bend as TileGroups

# DrawTileLine (tiles.cpp): the float GridWalk from p0 to p1, both clamped to the map, painting every visited cell.

type Pen is Data:
  Pen{tile: U32, flag: Bool, only_invalid: Bool}

type Walk is Data:
  Walk{adx: F32, ady: F32, sx: F32, sy: F32, length: F32}

def clamp(+v: F32, +limit: U32) -> F32:
  +low = Bool.pick(F32, (v < 0.0 : F32), 0.0, v)
  Bool.pick(F32, (U32.to_f32(limit) <= low : F32), U32.to_f32((limit - 1 : U32)), low)

def painted(+pen: Pen, +old: U32) -> U32:
  match pen:
    case Pen{+tile, +flag, +only_invalid}:
      +keep = only_invalid && Bool.not(TileGroups.is_invalid(Grid.tile_of(old)))
      ((old .&. 2147418112 : U32) .|. Bool.pick(U32, keep, (old .&. 65535 : U32), (tile .&. 65535 : U32))
        .|. Bool.pick(U32, flag, 2147483648, 0) : U32)

def paint_got(got: Array<U32> & U32, +i: U32, +pen: Pen) -> Array<U32>:
  (cells, +old) = got
  cells[i] <- painted(pen, old)

def paint(cells: Array<U32>, +w: U32, +h: U32, +pen: Pen, +x: F32, +y: F32) -> Array<U32>:
  +fx = F32.to_u32(F32.floor(clamp(F32.floor(x), w)))
  +fy = F32.to_u32(F32.floor(clamp(F32.floor(y), h)))
  paint_got(cells[Grid.index(fx, fy, w)], Grid.index(fx, fy, w), pen)

def walk_loop(n: Nat, go: Bool, +k: Walk, cells: Array<U32>, +w: U32, +h: U32, +pen: Pen, +px: F32, +py: F32, +err: F32, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      cells
    case 1n+p:
      match go:
        case False{}:
          cells
        case True{}:
          match k:
            case Walk{+adx, +ady, +sx, +sy, +length}:
              +e1 = (ady + err : F32)
              +e2 = (err - adx : F32)
              +along_x = (F32.abs(e1) < F32.abs(e2) : F32)
              walk_loop(p, Bool.not((length <= U32.to_f32((i + 1 : U32)) : F32)), k, paint(cells, w, h, pen, px, py), w, h,
                pen, Bool.pick(F32, along_x, (sx + px : F32), px), Bool.pick(F32, along_x, py, (sy + py : F32)),
                Bool.pick(F32, along_x, e1, e2), (i + 1 : U32))

def unit_toward(+a: F32, +b: F32) -> F32:
  Bool.pick(F32, (a < b : F32), 1.0, (0.0 - 1.0 : F32))

def walk_from(cells: Array<U32>, +w: U32, +h: U32, +pen: Pen, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Array<U32>:
  +adx = F32.abs((x1 - x0 : F32))
  +ady = F32.abs((y1 - y0 : F32))
  +length = (adx + ady : F32)
  walk_loop(U32.to_nat((F32.to_u32(length) + 2 : U32)), (0.0 < length : F32),
    Walk{adx, ady, unit_toward(x0, x1), unit_toward(y0, y1), length}, cells, w, h, pen, x0, y0, 0.0, 0)

# DrawTileLine(p0, p1, tile, flag, only_invalid) on raw cells of a w x h map.
def draw_cells(cells: Array<U32>, +w: U32, +h: U32, +pen: Pen, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Array<U32>:
  walk_from(cells, w, h, pen, clamp(x0, w), clamp(y0, h), clamp(x1, w), clamp(y1, h))

def draw(g: Grid.Grid, +pen: Pen, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Grid.Grid:
  match g:
    case Grid.Grid{cells, +w, +h}:
      Grid.Grid{draw_cells(cells, w, h, pen, x0, y0, x1, y1), w, h}
