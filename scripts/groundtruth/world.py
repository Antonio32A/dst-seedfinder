"""World data (world.json from the emulator or the groundtruth dump) with the game's tile conventions."""

import base64
import json
import struct
from dataclasses import dataclass

import numpy as np

TILE_SCALE = 4
TILE_HEADER_BYTES = 9
LAND_RANGES = ((2, 127), (256, 10497))
WORMHOLE_PREFAB = "wormhole"
PILLAR_PREFABS = ("tentacle_pillar", "tentacle_pillar_atrium")


def is_land_tile(tile):
    """TileGroupManager:IsLandTile: the legacy land ids 2..127 or the land+noise ids 256..10497."""
    return any(low <= tile <= high for low, high in LAND_RANGES)


def decode_tiles(encoded):
    raw = base64.b64decode(encoded)
    count = (len(raw) - TILE_HEADER_BYTES) // 2
    return list(struct.unpack("<%dH" % count, raw[TILE_HEADER_BYTES:TILE_HEADER_BYTES + 2 * count]))


def tile_coordinate(value, size):
    """Map:GetTileCoordsAtPoint for one axis, in float32 like the game: trunc((v + 2 + 2*size) * 0.25)."""
    shifted = np.float32(value) + np.float32(2.0) + np.float32(size) * np.float32(TILE_SCALE) * np.float32(0.5)
    return int(shifted * np.float32(0.25))


@dataclass(frozen=True)
class Instance:
    """One entity of savedata.ents: `index` is its position in the prefab's list."""
    prefab: str
    index: int
    x: float
    z: float

    @property
    def key(self):
        return self.prefab, self.index

    def as_json(self):
        return {"prefab": self.prefab, "index": self.index, "x": self.x, "z": self.z}


class World:
    """Tiles, entities and wormhole pairs of one generated forest world."""

    def __init__(self, width, height, tiles, entities, tile_names, wormhole_links, level=None, seed=None):
        self.width = width
        self.height = height
        self.tiles = tiles
        self.entities = entities
        self.tile_names = tile_names
        self.wormhole_links = wormhole_links
        self.level = level
        self.seed = seed
        self.land = bytearray(1 if is_land_tile(tile) else 0 for tile in tiles)
        self.land_centres = None
        self.anchors = {}

    @classmethod
    def load(cls, path):
        with open(path, encoding="utf-8") as handle:
            return cls.from_json(json.load(handle))

    @classmethod
    def from_json(cls, data):
        if data.get("status") not in (None, "ok") or "entities" not in data:
            raise WorldUnavailable(f"world generation did not finish (status {data.get('status')})")
        entities = {
            prefab: [Instance(prefab, index, x, z) for index, (x, z) in enumerate(positions)]
            for prefab, positions in data["entities"].items()
        }
        return cls(data["width"], data["height"], decode_tiles(data["tiles"]), entities, data["world_tile_map"],
                   wormhole_links_of(data.get("teleporters") or [], entities), level_of(data), data.get("seed"))

    def instances(self, prefabs):
        return [instance for prefab in prefabs for instance in self.entities.get(prefab, [])]

    def tile_xy(self, x, z):
        tx, ty = tile_coordinate(x, self.width), tile_coordinate(z, self.height)
        if 0 <= tx < self.width and 0 <= ty < self.height:
            return tx, ty
        return None

    def tile_index(self, x, z):
        xy = self.tile_xy(x, z)
        return None if xy is None else xy[1] * self.width + xy[0]

    def land_tile_of(self, instance):
        index = self.tile_index(instance.x, instance.z)
        return index if index is not None and self.land[index] else None

    def walk_anchor(self, instance):
        """(land tile, offset): the instance's own tile with offset 0 if it is land, otherwise the land tile whose
        centre is nearest in Euclidean distance (lowest tile index on ties) with that distance; None without land."""
        if instance.key not in self.anchors:
            own = self.land_tile_of(instance)
            self.anchors[instance.key] = (own, 0.0) if own is not None else self.nearest_land(instance.x, instance.z)
        return self.anchors[instance.key]

    def nearest_land(self, x, z):
        if self.land_centres is None:
            indices = np.flatnonzero(np.frombuffer(bytes(self.land), dtype=np.uint8))
            centres = np.stack([(indices % self.width - self.width / 2.0) * TILE_SCALE,
                                (indices // self.width - self.height / 2.0) * TILE_SCALE], axis=1)
            self.land_centres = indices, centres
        indices, centres = self.land_centres
        if not len(indices):
            return None
        squared = (centres[:, 0] - x) ** 2 + (centres[:, 1] - z) ** 2
        best = int(np.argmin(squared))
        return int(indices[best]), float(np.sqrt(squared[best]))

    def tile_center(self, index):
        tx, ty = index % self.width, index // self.width
        return (tx - self.width / 2.0) * TILE_SCALE, (ty - self.height / 2.0) * TILE_SCALE


class WorldUnavailable(Exception):
    pass


def wormhole_links_of(teleporters, entities):
    """Directed links (entry instance, exit instance) from `teleporter.target` of the wormhole entities."""
    by_id = {record["id"]: record for record in teleporters if record["prefab"] == WORMHOLE_PREFAB}
    links = []
    for record in by_id.values():
        target = by_id.get(record["target"])
        if target is not None:
            links.append((entities[WORMHOLE_PREFAB][record["index"]], entities[WORMHOLE_PREFAB][target["index"]]))
    return links


def pillar_links_of(teleporters, entities):
    """Directed links (entry instance, exit instance) from `teleporter.target` of the caves' tentacle pillars, which
    link across the pillar prefabs (the atrium pillars have their own prefab)."""
    by_id = {record["id"]: record for record in teleporters if record["prefab"] in PILLAR_PREFABS}
    links = []
    for record in by_id.values():
        target = by_id.get(record["target"])
        if target is not None:
            links.append((entities[record["prefab"]][record["index"]], entities[target["prefab"]][target["index"]]))
    return links


def level_of(data):
    placements = data.get("task_set_pieces")
    if placements is None:
        return None
    swaps = data.get("prefab_swaps")
    return {
        "prefab_swaps": swaps if isinstance(swaps, dict) and swaps else None,
        "tasks": [{"task": entry["task"],
                   "set_pieces": [piece["name"] if isinstance(piece, dict) else piece for piece in entry["set_pieces"]],
                   "random_set_pieces": list(entry["random_set_pieces"])} for entry in placements],
    }
