#!/usr/bin/env python3
"""Writes data/distribute.bend (with `picks` as argument: data/picks.bend) from out/distribute.json.

distribute: for each room and deepcopy depth, the table PopulateVoronoi hands to pickspawnprefab after
resolveswappableprefabs (one GetRandomItem per swappable entry) and filterPrefabsForGlobalSwaps (the swap state),
deduplicated into variants; the land tile classes (tiles on which pickspawnprefab filters the same way); and the
ocean rooms' pickspawnprefab orders. picks: for each variant and tile class, the pairs() order of pickspawnprefab's
filtered `items` table as indices into the variant's entries (the order its total and subtraction loops use).
`-` as the last argument prints the module instead of writing it."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402
import union  # noqa: E402

KEY_BITS, WEIGHT_BITS = 12, 8
PICK_BITS = 5
PICKS_PER_UNIT = 4


def pair(entry):
    key, weight = ids.sid(entry["key"]), ids.weight_id(entry["value"])
    assert key < 1 << KEY_BITS and weight < 1 << WEIGHT_BITS
    return key << WEIGHT_BITS | weight


def tile_classes(d):
    columns, classes = {}, {}
    for i, tile in enumerate(d["land_tiles"]):
        column = tuple(v["tiles"][i] for v in d["variants"])
        classes[tile] = columns.setdefault(column, len(columns))
    representative = {}
    for i, tile in enumerate(d["land_tiles"]):
        representative.setdefault(classes[tile], i)
    return classes, [representative[c] for c in range(len(columns))]


def distribute_module(d):
    rooms = {r["name"]: r for r in d["rooms"]}
    names = ids.table()["rooms"]
    cases = []
    for name in names:
        for depth in (1, 2):
            r = rooms.get(name)
            if r is None:
                cases.append([])
                continue
            dd = r["depths"][depth - 1]
            row = [len(dd["swappable"])]
            for sw in dd["swappable"]:
                row += [ids.sid(sw["key"]), sw["count"]]
            radices = [sw["count"] for sw in dd["swappable"]]
            expected = []
            for c in dd["cases"]:
                index = 0
                for k, radix in zip(c["choices"], radices):
                    index = index * radix + (k - 1)
                expected.append((index * 8 + c["state"], c["variant"]))
            expected.sort()
            assert [e[0] for e in expected] == list(range(len(expected)))
            cases.append(row + [v for _, v in expected])
    variants = [[pair(e) for e in v["entries"]] for v in d["variants"]]
    classes, _ = tile_classes(d)
    ocean = []
    for o in d["ocean"]:
        row = [ids.room_index(o["name"]), o["tile"]]
        row += [pair(e) for e in o.get("pick", [])]
        ocean.append(row)
    m = blob.Module("distribute", "scripts/gen/gen_distribute.py",
                    "PopulateVoronoi distribute tables per room, deepcopy depth, GetRandomItem choices and swap state.")
    m.comment("Swap state bits: 1 grass gekko, 2 twiggy trees, 4 juicy berries (0 = the primary set of each category).",
              "Case of a room/depth: mixed radix of the choices (first swappable most significant, each choice",
              "math.random(n) - 1 of GetRandomItem, n = its count), times 8, plus the swap state.")
    m.table("cases", cases, "Row 2 * room + depth - 1: number of swappable entries, then per entry (key string id, "
                            "choice count) in pairs() order, then the variant of every case. Empty: no distribute.")
    m.table("variants", variants, "Row variant: the pickspawnprefab input table in pairs() order, one "
                                  "unit per entry: prefab string id << 8 | weight id (data/rooms.bend).")
    m.table("tile_classes", [[u for tile in sorted(classes) for u in (tile, classes[tile])]],
            "Row 0: (land tile, tile class) pairs, tiles ascending; pickspawnprefab filters equally on one class.")
    m.const("tile_class_count", len(set(classes.values())))
    m.table("ocean_picks", ocean, "Row i of level ocean_population: room, tile, then pickspawnprefab's items order "
                                  "for that tile, one unit per entry as in variants (PopulateWaterType uses the "
                                  "depth-1 distributeprefabs directly).")
    m.code('''
def swappable_count(+room: U32, +depth: U32) -> U32:
  Blob.at(cases((((room * 2 : U32) + depth : U32) - 1 : U32)), 0)

# The variant for a room, depth and case index (see above).
def variant(+room: U32, +depth: U32, +index: U32) -> U32:
  +row = cases((((room * 2 : U32) + depth : U32) - 1 : U32))
  Blob.at(row, (((Blob.at(row, 0) * 2 : U32) + 1 : U32) + index : U32))

def tile_class_pick(hit: Bool, +c: U32, +found: U32) -> U32:
  match hit:
    case True{}:
      c
    case False{}:
      found

def tile_class_scan(xs: List<&2, U32>, +tile: U32, +found: U32) -> U32:
  match xs:
    case Nil{}:
      found
    case Con{+t, Nil{}}:
      found
    case Con{+t, Con{+c, rest}}:
      tile_class_scan(rest, tile, tile_class_pick(U32.is_eq(t, tile), c, found))

# The prefab string id of a variants / ocean_picks unit.
def entry_prefab(+u: U32) -> U32:
  (u >> 8n : U32)

# The weight id (data/rooms.bend) of a variants / ocean_picks unit.
def entry_weight(+u: U32) -> U32:
  (u .&. 255 : U32)

# The pickspawnprefab tile class of a land tile (NONE for other tiles).
def tile_class(+tile: U32) -> U32:
  tile_class_scan(tile_classes(0), tile, 1048575)
''')
    return m


def picks_module(d):
    _, representatives = tile_classes(d)
    lists, index = [], {}
    by_variant = []
    for v in d["variants"]:
        keys = [e["key"] for e in v["entries"]]
        row = []
        for i in representatives:
            order = tuple(keys.index(e["key"]) for e in d["picks"][v["tiles"][i]])
            assert all(k < 1 << PICK_BITS for k in order)
            if order not in index:
                index[order] = len(lists)
                lists.append(order)
            row.append(index[order])
        by_variant.append(row)
    packed = []
    for order in lists:
        units = []
        for i in range(0, len(order), PICKS_PER_UNIT):
            group = order[i:i + PICKS_PER_UNIT]
            units.append(sum(k << (PICK_BITS * j) for j, k in enumerate(group)))
        packed.append([len(order)] + units)
    m = blob.Module("picks", "scripts/gen/gen_distribute.py",
                    "pickspawnprefab's filtered items order per distribute variant and land tile class.")
    m.table("variant_picks", by_variant, "Row variant (data/distribute.bend): the pick list of each tile class.")
    m.table("pick_lists", packed, "Row list: count, then indices into the variant's entries, 4 per unit (5 bits each, "
                                  "lowest first).")
    m.code('''
def digits(c: Nat, +u: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match c:
    case 0n:
      tail
    case 1n+p:
      (u .&. 31 : U32) <> digits(p, (u >> 5n : U32), tail)

def unpack(xs: List<&2, U32>, +n: Nat) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+u, rest}:
      digits(Nat.min(n, 4n), u, unpack(rest, Nat.sub(n, 4n)))

def unpack_list(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      unpack(rest, U32.to_nat(n))

# pickspawnprefab's items order for a distribute variant on a tile class: indices into the variant's entries.
def pick(+variant: U32, +class: U32) -> List<&2, U32>:
  unpack_list(pick_lists(Blob.at(variant_picks(variant), class)))
''')
    return m


def main():
    d = union.distribute()
    which = [a for a in sys.argv[1:] if a != "-"]
    module = picks_module(d) if which == ["picks"] else distribute_module(d)
    if sys.argv[-1:] == ["-"]:
        sys.stdout.write(module.text())
    else:
        (blob.ROOT / "seedfinder" / "data" / f"{module.name}.bend").write_text(module.text())


if __name__ == "__main__":
    main()
