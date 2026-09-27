# World dump format (`.dstw`, format 2)

A `.dstw` file holds one generated forest world: its tile map, every entity the world generation saved and the
wormhole links. `seedfinder world eval --world` and `seedfinder world find --worlds DIR` read it. `seedfinder world
dump` writes it for the worlds the seedfinder generates, and `scripts/groundtruth/world_dump.py` from a world dumped on
the real dedicated server. The file describes itself: it carries every name it uses, so reading it needs no catalog or
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
| 4 | u32 | version | `2` |
| 8 | u32 | seed | the world seed |
| 12 | u32 | status | `1` generated, `0` the world generation gave up |
| 16 | u32 | platform | the OS of the host that generated the world: `0` unknown, `1` Windows, `2` Linux |
| 20 | u32 | game build | the game's build number (e.g. `747465`), `0` when unknown |
| 24 | u32 | width | tiles along x |
| 28 | u32 | height | tiles along z |
| 32 | | sections | until the end of the file (§ 3) |

A file whose world generation gave up ends after `platform`: it is exactly 20 bytes.

A reader rejects a file with another magic, and one with another version (format 1 files have no sections and are
laid out differently; regenerate them).

## 3. Sections

A section is a 4-byte ASCII tag, a `u32` payload length `L` in bytes (a multiple of 4), then the payload. The next
section starts right after it, `8 + L` bytes after the tag. A generated world has each of the sections below exactly
once, in this order. A reader finds them by tag and skips any tag it does not know.

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

## 4. What is in it

Only what the world generation saved for the forest shard: the savedata's map tiles, every `savedata.ents` entry
(whatever its prefab) and the wormholes' teleporter targets. This includes the pocket dimension containers the game
adds at (0, 0) when the world has none.

It does not hold anything the running game makes later: entities that prefabs spawn once the world loads (e.g. a
spawner's children), what a server adds on its first start, or the caves. Roads, the node graph and the entities'
own save data (other than position) are not included either.

## 5. Extending it

A new kind of data is a new section with a new tag, in the same version: older readers skip it. Add it after the
existing sections, document its payload here, and keep the payload length a multiple of 4. The version changes only
when the header or an existing section changes in a way an older reader would misread.
