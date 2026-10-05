# World dump format (`.dstw`, format 3)

A `.dstw` file holds one generated world of one shard (the forest or the caves): its tile map, every entity the world
generation saved, the wormhole links (forest) or tentacle pillar links (caves), its roads, its node graph (topology)
and, when the seedfinder generated it, the set pieces the world generation placed. `seedfinder world
eval --world` and `seedfinder world find --worlds DIR` read it. `seedfinder world dump` writes it for the worlds the
seedfinder generates, and `scripts/groundtruth/world_dump.py` from a world dumped on the real dedicated server.
`scripts/groundtruth/dstw.py` reads it, as a Python library (`World`, `read_dstw`) and from the command line (`info`,
`diff`, `graph`, `ents`). The file describes itself: it carries every name it uses, so reading it needs no catalog or
game data.

## 1. Conventions

- Every integer is little-endian. `u16` and `u32` are unsigned, `i32` is two's complement.
- The header, every section and every field inside a section start at a multiple of 4 bytes from the start of the
  file.
- A **string** is a `u32` byte count `n`, then `n` bytes of UTF-8 (no terminator), then zero bytes up to the next
  multiple of 4 (`(4 - n % 4) % 4` of them).
- Names are compared byte by byte (so `"ROAD" < "ROCKY" < "rock1"`).

## 2. Header

| Offset | Type | Field | Value |
|---|---|---|---|
| 0 | 4 bytes | magic | `DSTW` (`44 53 54 57`) |
| 4 | u32 | version | `3` |
| 8 | u32 | seed | the world seed |
| 12 | u32 | status | `1` generated, `0` the world generation gave up |
| 16 | u32 | platform | the OS of the host that generated the world: `0` unknown, `1` Windows, `2` Linux |
| 20 | u32 | shard | the shard the world belongs to: `0` forest (`SURVIVAL_TOGETHER`), `1` caves (`DST_CAVE`) |
| 24 | u32 | game build | the game's build number (e.g. `756039`), `0` when unknown |
| 28 | u32 | width | tiles along x |
| 32 | u32 | height | tiles along z |
| 36 | | sections | until the end of the file (§ 3) |

A file whose world generation gave up ends after `shard`: it is exactly 24 bytes.

A reader rejects a file with another magic, and one with another version with an error that names the version
(format 1 files have no sections, format 2 files have no shard field and are 4 bytes shorter in the header; regenerate
them). A reader that handles one shard only rejects a dump of the other shard.

## 3. Sections

A section is a 4-byte ASCII tag, a `u32` payload length `L` in bytes (a multiple of 4), then the payload. The next
section starts right after it, `8 + L` bytes after the tag. A generated world has `TNAM`, `TILE`, `ENTS` and `WORM`
exactly once, in this order; a world of the caves shard then has `PILL` once; and it may then have `SETP`, `ROAD` and
`GRPH` once each, in this order. A reader finds them by tag and skips any tag it does not know.

### `TNAM`: tile names

`u32` count, then per entry a `u32` tile id and the tile's name (a string), in ascending name order.

These are the game's `world_tile_map` (the `WORLD_TILES` names and ids of the game build, e.g. `GRASS` = 6). A tile
id in `TILE` means the tile of that name.

### `TILE`: tiles

`width × height` `u16` tile ids, row-major, then 2 zero bytes when `width × height` is odd. The tile at column `tx`
(x) and row `ty` (z) is entry `ty × width + tx`, with `0 ≤ tx < width` and `0 ≤ ty < height`.

A tile is 4 world units wide. Its centre is at `x = (tx − width / 2) × 4`, `z = (ty − height / 2) × 4`, and a world
point `(x, z)` is in tile `tx = trunc((x + 2 + 2 × width) / 4)`, `ty = trunc((z + 2 + 2 × height) / 4)`, computed in
float32 like the game's `Map:GetTileCoordsAtPoint`.

### `ENTS`: entities

`u32` prefab count, then per prefab, in ascending name order:
- its name (a string),
- `u32` instance count `n` (at least 1),
- `n` instances, each `i32 xk`, `i32 zk`, in the order of that prefab's entries in the savedata (`savedata.ents`).

An instance's **index** is its position in its prefab's list, from 0. The position is `x = xk / 100`,
`z = zk / 100` world units (the double nearest to it), and `x` is a whole number exactly when `xk % 100 = 0`.

**Rounding.** `xk` is the savedata `x` printed with `printf("%.2f")` on the platform that generated the world, times
100: the integer nearest to `100 × x` computed exactly (not in floating point). An exact tie goes to the even integer
on Linux (glibc) and away from zero on Windows (MSVCR90). So `x = 0.125` gives `xk = 12` on Linux and `13` on
Windows. The same holds for `z` and `zk`.

### `WORM`: wormhole links

`u32` count, then per link a `u32` entry index and a `u32` exit index, both indices of `wormhole` instances in
`ENTS`. Jumping into the entry wormhole comes out at the exit one. A link is directed, and a wormhole pair is two
links. Links are in the order of their entry wormholes in the savedata.

### `PILL`: tentacle pillar links

Only in a dump of the caves shard (`WORM` is then empty, as the caves have no wormholes). `u32` count, then per link
four `u32`: the entry pillar's prefab (its position in `ENTS`, from 0), its instance index in that prefab, and the same
two for the exit pillar. The pillars are the `tentacle_pillar` prefab (paired at random) and the two
`tentacle_pillar_atrium` ones (paired with each other); a link never leaves its group. Jumping into the entry pillar
comes out at the exit one. A link is directed, and a pillar pair is two links. Links are in the order of their entry
pillars in the savedata (prefabs in name order, then instance order).

### `SETP`: set pieces

Every static layout the world generation placed through the game's layout code (`map/object_layout.lua`'s
`ReserveAndPlaceLayout`): the task set pieces, the rooms' static layouts, the starting set piece, the map tags'
layouts and the ocean set pieces. `seedfinder world dump` writes this section; `scripts/groundtruth/world_dump.py` does
not, because the game's savedata does not say where the layouts went. A file without it says nothing about set pieces
(it does not mean there are none); a file with it lists them all, and may list none.

`u32` count, then per layout, in the order the world generation placed them:
- its name (a string): the layout's name as the game names it (the key of `map/layouts.lua` and the other layout
  tables, e.g. `MooseNest`),
- `u32` source: where the layout comes from:

  | Code | Source |
  |---|---|
  | 0 | a room's `countstaticlayouts` (e.g. `MoonbaseOne`) |
  | 1 | a task set piece (`set_pieces` or `random_set_pieces`, put in a node by `Story:InsertAdditionalSetPieces`) |
  | 2 | the starting set piece of the START node (`AddStartingSetPiece`, e.g. `DefaultStart`) |
  | 3 | a map tag's layout (`terrain_contents_extra.static_layouts`) |
  | 4 | the level's `ocean_prefill_setpieces` |
  | 5 | an ocean room's `countstaticlayouts` (`PopulateOcean`) |
  | 6 | a maze or labyrinth of the caves' maze passes (not a layout of the game's tables): its name is its task's id (`ArchiveMaze`, `AtriumMaze`, ...) or `Labyrinth`, and its members are the entities the pass put in it (the Labyrinth's chests, a maze's layouts' objects and seals) |

  A reader treats another code as unknown.
- `u32` transform: how the layout was turned, as `ReserveAndPlaceLayout` applies it. Bit 0 is `switch_xy`, bit 1 is
  `flip_x = -1` and bit 2 is `flip_y = -1`. The object a layout defines at `(ox, oy)` lands at
  `x = xc + 4 × scale × u`, `z = zc + 4 × scale × v` (then rounded like every entity), with
  `(u, v) = (fx × ox, fy × oy)`, or `(fy × oy, fx × ox)` when bit 0 is set. `fx` is -1 when bit 1 is set and 1
  otherwise, `fy` likewise with bit 2, and `scale` is the layout's scale.
- `i32 xk`, `i32 zk`: the centre `(xc, zc)` the layout's objects are placed around.
- `i32 x0k`, `i32 z0k`, `i32 x1k`, `i32 z1k`: the bounds, from `(x0, z0)` to `(x1, z1)`.
- `u32` member count `m`, then `m` members, each a `u32` prefab (the position of the member's prefab in `ENTS`, from 0)
  and a `u32` instance index of that prefab, ordered by prefab then index.

Positions and bounds are in hundredths of world units, rounded like `ENTS` positions.

The **bounds** are the square the layout takes up: centred on `(xc, zc)`, `8 × h` world units wide, where `h` is the
half-size in tiles `ReserveAndPlaceLayout` computes. For a layout with ground tiles, `h` is half the ground's side.
Otherwise `h` is the scale times half the larger side of its objects' bounding box.
- A land layout with ground: the bounds are exactly the tiles `ReserveSpace` reserved and painted.
- A land layout without ground: those tiles are the bounds rounded to whole tiles.
- An ocean layout: the bounds are its ground tiles (the box `PlaceOceanLayout` reserves is one tile lower on both
  axes).

A few layouts define objects past their ground or off their centre (e.g. `junk_yard`, `CropCircle`), and their members
can lie up to about 2 world units outside the bounds.

The **members** are the `ENTS` instances the layout's objects became, after the whole world generation:
- An object that was never added is not a member, and neither is an entry a later step removed. For example, a land
  layout skips an object that falls on a non-land tile, and the impassable filter removes entries on impassable tiles.
- An entry a later step renamed is a member under its final prefab and index. For example, a `wormhole_MARKER` becomes
  a `wormhole`, and a proxy prefab becomes the prefab it stands for.
- No instance is a member of two layouts.
- Two layouts can still overlap. Layouts that reserve no tiles can land on the same spot, each with its own members.

A layout the world generation found no place for is not listed.

### `ROAD`: roads

The roads the world generation saved (`save.map.roads` of `map/forest_map.lua`), as polylines. Both writers write this
section: `seedfinder world dump` and `scripts/groundtruth/world_dump.py`. A file without it (from an earlier version)
says nothing about roads and is read as having none.

`u32` count, then per road, in the order of the savedata's road list:
- `u32` weight: `3` for the road the road generator produced first, when it was kept (`forest_map.lua` saves it with
  weight 3 whatever the generator says), and `1` for every other road. The game draws a weight 3 road wide and edged,
  and any other weight as a narrow path.
- `u32` point count `n` (at least 3, the smallest minimum),
- `n` points, each `i32 xk`, `i32 zk`: the position in hundredths of world units, like an `ENTS` position. It is the
  savedata's `x`, `z` of the point times 100, and the savedata rounds every coordinate down to a tenth (in `x` and `z`
  the point is `floor((p - size / 2) × 4 × 10) / 10`, with `p` the float tile coordinate), so `xk` and `zk` are
  multiples of 10.

Roads the world generation dropped for having fewer points than its `math.random(3, 5)` minimum are not listed.

### `GRPH`: topology

The world's node graph: the nodes of the savedata's `map.topology` (every room, background, blank, cove, blocker and
link node of the story) and the graph edges between them that the world generation's tile stages see. Both writers
write this section. A file without it (from an earlier version) says nothing about the topology; a reader that needs
it (a `bridges` rule, [config.md](config.md) § 4 F) treats the world as unusable.

- `u32` node count `n`, then `n` nodes in ascending id order (byte by byte):
  - its id (a string): the `map.topology.ids` entry, e.g. `CentipedeCaveTask:BG_89:BGVentsRoom`, `START`,
  - `u32` type: its `NODE_TYPE` (`0` Default, `1` Blank, `2` Background, `3` Random, `4` Blocker, `5` Room,
    `6` BGRoom, `7` SeparatedRoom),
  - `i32 xk`, `i32 zk`: its site's position, the savedata node's `x` and `y` times 100 (so multiples of 100). The
    savedata rounds the site down to a whole world unit: `x = floor((p - size / 2) × 4)` in double, with `p` the
    site's float tile coordinate (`Node:SaveEncode`).
- `u32` edge count `m`, then `m` edges, each a `u32 n1` and a `u32 n2`: the positions of its two nodes in the node
  list, from 0. An edge keeps its direction (`n1` is the savedata edge's `n1`, its `node1`, whose turf the edge's
  site line paints), and the edges are in ascending `(n1, n2)` order.

The nodes leave out the squares the ocean stage appends to `map.topology` for its island layouts (`ocean_gen.lua`'s
`AddSquareTopology`, e.g. `StaticLayoutIsland:MonkeyIsland`): they are not part of the world generation's graph and
have no edges.

The edges are the savedata's `map.topology.edges` without those of a node tagged `ForceDisconnected` (the ruins mazes,
the moon island's and blockers' blanks, `LOOP_BLANK_SUB` nodes, ...): `ApplyPoisonTag` unlinks those in the game's
WorldSim, so they draw nothing, while the savedata keeps them.

## 4. What is in it

Only what the world generation saved for the dump's shard: the savedata's map tiles, every `savedata.ents` entry
(whatever its prefab), the teleporter targets of the wormholes (forest) or the tentacle pillars (caves), the roads
(the caves have none) and the topology's nodes and edges, and for worlds the seedfinder generated, where the world generation placed its layouts. This includes the pocket dimension containers the game adds at (0, 0) when the world
has none.

It does not hold anything the running game makes later: entities that prefabs spawn once the world loads (e.g. a
spawner's children), or what a server adds on its first start. The entities' own save data (other than position) and
the topology's polygons, centroids, areas, colours and tags are not included either.

## 5. Extending it

A new kind of data is a new section with a new tag, in the same version: older readers skip it. Add it after the
existing sections, document its payload here, and keep the payload length a multiple of 4. The version changes only
when the header or an existing section changes in a way an older reader would misread.
