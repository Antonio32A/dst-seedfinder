#!/usr/bin/env python3
"""Python model of the forest level table (everything decided before forest_map.Generate).

It is a spec for the Bend port: prefab swaps, ChooseTasks, AddSetPeices and ChooseSetPieces, with the
pairs() order of level.set_pieces taken from an emulation of stock Lua 5.1 ltable.c.

usage: model.py FROM TO [--order]   prints "seed {summary}" lines in the harness world format
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_catalog import BOONS, POI, PROTECTED, TRAPS  # noqa: E402

M32 = 0xFFFFFFFF
M64 = (1 << 64) - 1
MULT = 0x5851F42D4C957F2D
INC = 0xB47C73972972B7B7

REQUIRED_TASKS = ["Make a pick", "Dig that rock", "Great Plains", "Squeltch", "Beeeees!", "Speak to the king",
                  "Forest hunters", "Badlands", "For a nice walk", "Lightning Bluff"]
MOON_TASKS = ["MoonIsland_IslandShards", "MoonIsland_Beach", "MoonIsland_Forest", "MoonIsland_Baths",
              "MoonIsland_Mine"]
OPTIONAL_TASKS = ["Befriend the pigs", "Kill the spiders", "Killer bees!", "Make a Beehat", "The hunters",
                  "Magic meadow", "Frogs and bugs", "Mole Colony Deciduous", "Mole Colony Rocks",
                  "MooseBreedingTask"]
ROOM_BG = {
    "Make a pick": "GRASS", "Dig that rock": "ROCKY", "Great Plains": "SAVANNA", "Squeltch": "MARSH",
    "Beeeees!": "GRASS", "Speak to the king": "GRASS", "Forest hunters": "FOREST", "Badlands": "DIRT",
    "For a nice walk": "FOREST", "Lightning Bluff": "DIRT", "Befriend the pigs": "FOREST",
    "Kill the spiders": "ROCKY", "Killer bees!": "GRASS", "Make a Beehat": "GRASS", "The hunters": "SAVANNA",
    "Magic meadow": "FOREST", "Frogs and bugs": "GRASS", "Mole Colony Deciduous": "DECIDUOUS",
    "Mole Colony Rocks": "ROCKY", "MooseBreedingTask": "GRASS",
}
TASKSET_SET_PIECES = [
    ("ResurrectionStone", 2, ["Make a pick", "Dig that rock", "Great Plains", "Squeltch", "Beeeees!",
                              "Speak to the king", "Forest hunters", "Badlands"]),
    ("WormholeGrass", 8, ["Make a pick", "Dig that rock", "Great Plains", "Squeltch", "Beeeees!",
                          "Speak to the king", "Forest hunters", "Befriend the pigs", "For a nice walk",
                          "Kill the spiders", "Killer bees!", "Make a Beehat", "The hunters", "Magic meadow",
                          "Frogs and bugs", "Badlands"]),
    ("MooseNest", 9, ["Make a pick", "Beeeees!", "Speak to the king", "Forest hunters", "Befriend the pigs",
                      "For a nice walk", "Make a Beehat", "Magic meadow", "Frogs and bugs"]),
    ("CaveEntrance", 10, ["Make a pick", "Dig that rock", "Great Plains", "Squeltch", "Beeeees!",
                          "Speak to the king", "Forest hunters", "Befriend the pigs", "For a nice walk",
                          "Kill the spiders", "Killer bees!", "Make a Beehat", "The hunters", "Magic meadow",
                          "Frogs and bugs"]),
    ("MoonAltarRockGlass", 1, ["MoonIsland_Mine"]),
    ("MoonAltarRockIdol", 1, ["MoonIsland_Mine"]),
    ("MoonAltarRockSeed", 1, ["MoonIsland_Mine"]),
    ("BathbombedHotspring", 1, ["MoonIsland_Baths"]),
    ("MoonFissures", 1, ["MoonIsland_Fissures", "MoonIsland_Mine", "MoonIsland_Forest"]),
]
REQUIRED_SET_PIECES = ["Sculptures_1", "Maxwell5"]
RANDOM_SET_PIECES = ["Sculptures_2", "Sculptures_3", "Sculptures_4", "Sculptures_5", "Chessy_1", "Chessy_2",
                     "Chessy_3", "Chessy_4", "Chessy_5", "Chessy_6", "Maxwell1", "Maxwell2", "Maxwell3",
                     "Maxwell4", "Maxwell6", "Maxwell7", "Warzone_1", "Warzone_2", "Warzone_3"]
SWAP_CATEGORIES = [("grass", "regular grass", "grass gekko"), ("twigs", "regular twigs", "twiggy trees"),
                   ("berries", "regular berries", "juicy berries")]
SWAP_THRESHOLD = 3221225472
BOON_RANGES = {"never": (0, 0), "rare": (1, 4), "uncommon": (2, 6), "default": (3, 8), "often": (4, 12),
               "mostly": (6, 18), "always": (9, 24), "insane": (18, 48)}


def lua_string_hash(s):
    data = s.encode()
    h = len(data)
    step = (len(data) >> 5) + 1
    i = len(data)
    while i >= step:
        h = (h ^ (((h << 5) & M32) + (h >> 2) + data[i - 1])) & M32
        i -= step
    return h


def ceil_log2(x):
    return (x - 1).bit_length()


class LuaTable:
    """Node placement of a string-keyed Lua 5.1 table (no array part, no deletions)."""

    def __init__(self, hash_size=0):
        self.set_node_vector(hash_size)

    def set_node_vector(self, size):
        self.size = 0 if size == 0 else 1 << ceil_log2(size)
        self.nodes = [None] * max(self.size, 1)
        self.last_free = self.size

    def main_position(self, key):
        return lua_string_hash(key) & (self.size - 1) if self.size else 0

    def free_position(self):
        while self.last_free > 0:
            self.last_free -= 1
            if self.nodes[self.last_free] is None:
                return self.last_free
        return None

    def rehash(self):
        old = self.nodes[:self.size] if self.size else []
        self.set_node_vector(sum(k is not None for k in old) + 1)
        for key in reversed(old):
            if key is not None:
                self.insert(key)

    def insert(self, key):
        mp = self.main_position(key)
        if self.size and self.nodes[mp] is None:
            self.nodes[mp] = key
            return
        free = self.free_position() if self.size else None
        if free is None:
            self.rehash()
            self.insert(key)
            return
        if self.main_position(self.nodes[mp]) != mp:
            self.nodes[free] = self.nodes[mp]
            self.nodes[mp] = key
        else:
            self.nodes[free] = key

    def keys(self):
        return [k for k in self.nodes[:self.size] if k is not None]


def taskset_set_pieces_table():
    literal = LuaTable(len(TASKSET_SET_PIECES))
    for name, _, _ in TASKSET_SET_PIECES:
        literal.insert(name)
    copy = LuaTable()
    for name in literal.keys():
        copy.insert(name)
    return copy


class Rng:
    def __init__(self, seed):
        self.state = ((seed + INC) * MULT + INC) & M64
        self.count = 0

    def raw(self):
        s = self.state
        xs = (((s >> 18) ^ s) >> 27) & M32
        rot = s >> 59
        self.state = (s * MULT + INC) & M64
        self.count += 1
        return ((xs >> rot) | (xs << ((32 - rot) & 31))) & M32

    def roll(self, n):
        return int(self.raw() / 4294967295.0 * n)

    def rare_reroll(self):
        return self.raw() / 4294967295.0 < 0.98


def pick(rng, areas):
    keys = list(range(len(areas)))
    i = rng.roll(len(keys))
    a = keys[i]
    if (areas[a][0] == "Rare" and rng.rare_reroll()) or not areas[a][1]:
        del keys[i]
        a = keys[rng.roll(len(keys))]
    if not areas[a][1]:
        return None
    area, items, _ = areas[a]
    return area, items[rng.roll(len(items))]


def world(seed, boons="default", traps=True, poi=True, protected=True):
    rng = Rng(seed)
    rng.raw()
    swaps = {cat: (swapped if rng.raw() >= SWAP_THRESHOLD else regular) for cat, regular, swapped in
             [SWAP_CATEGORIES[i] for i in SWAP_ORDER]}
    optional = OPTIONAL_TASKS + [None]
    for i in range(10, 1, -1):
        j = rng.roll(i)
        optional[i - 1], optional[j] = optional[j], optional[i - 1]
    chosen = REQUIRED_TASKS + MOON_TASKS + optional[:5]
    placeable = REQUIRED_TASKS + optional[:5]

    table = taskset_set_pieces_table()
    entries = {name: [count, tasks] for name, count, tasks in TASKSET_SET_PIECES}
    low, high = BOON_RANGES[boons]
    picks = [areas for areas, on in ((TRAPS, traps), (POI, poi), (PROTECTED, protected)) if on]
    order_of_picks = [pick(rng, areas) for areas in picks]
    if high:
        order_of_picks += [pick(rng, BOONS) for _ in range(low + rng.roll(high - low + 1))]
    for chosen_pick in order_of_picks:
        if chosen_pick is None:
            continue
        area, name = chosen_pick
        tasks = [t for t in placeable if area in ("Any", "Rare") or ROOM_BG[t] == area]
        if not tasks:
            continue
        if name in entries:
            entries[name] = [entries[name][0] + 1, tasks]
        else:
            entries[name] = [1, tasks]
            table.insert(name)

    order = table.keys()
    set_pieces = {t: [] for t in chosen}
    random_set_pieces = {t: [] for t in chosen}
    specials = REQUIRED_SET_PIECES + [RANDOM_SET_PIECES[rng.roll(19)] for _ in range(4)]
    for name in specials:
        random_set_pieces[placeable[rng.roll(len(placeable))]].append(name)
    for name in order:
        count, tasks = entries[name]
        choices = [t for t in tasks if t in chosen]
        while count > 0 and choices:
            set_pieces[choices.pop(rng.roll(len(choices)))].append(name)
            count -= 1
    return {
        "prefab_swaps": {cat: swaps[cat] for cat, _, _ in SWAP_CATEGORIES},
        "tasks": [{"task": t, "set_pieces": set_pieces[t], "random_set_pieces": random_set_pieces[t]}
                  for t in chosen],
        "order": order,
    }


def pairs_order_of_base_sets():
    base = LuaTable()
    for cat, _, _ in SWAP_CATEGORIES:
        base.insert(cat)
    copy = LuaTable()
    for cat in base.keys():
        copy.insert(cat)
    names = [c for c, _, _ in SWAP_CATEGORIES]
    return [names.index(k) for k in copy.keys()]


SWAP_ORDER = pairs_order_of_base_sets()


def main():
    lo, hi = int(sys.argv[1]), int(sys.argv[2])
    with_order = "--order" in sys.argv
    for seed in range(lo, hi + 1):
        w = world(seed)
        if not with_order:
            del w["order"]
        print(seed, json.dumps(w, separators=(",", ":")))


if __name__ == "__main__":
    main()
