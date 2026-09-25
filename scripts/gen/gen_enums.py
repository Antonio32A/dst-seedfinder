#!/usr/bin/env python3
"""Writes data/enums.bend from out/story.json: the game enums the ported worldgen compares against (NODE_TYPE,
NODE_INTERNAL_CONNECTION_TYPE, LAYOUT, LAYOUT_POSITION, PLACE_MASK, WORLD_TILES, LOCKS, KEYS) as constants.
`-` prints the module instead."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402

PREFIXES = {
    "NODE_TYPE": "node_type", "NODE_INTERNAL_CONNECTION_TYPE": "connection", "LAYOUT": "layout",
    "LAYOUT_POSITION": "layout_position", "PLACE_MASK": "place_mask", "WORLD_TILES": "tile", "LOCKS": "lock",
    "KEYS": "key",
}


def snake(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower()


def main():
    enums = blob.sidecar("story.json")["enums"]
    m = blob.Module("enums", "scripts/gen/gen_enums.py", "Game enums (constants.lua, lockandkey.lua, tiles).",
                    imports=())
    seen = set()
    for enum, prefix in PREFIXES.items():
        m.comment(enum)
        for name, value in sorted(enums[enum].items(), key=lambda kv: (kv[1], kv[0])):
            ident = f"{prefix}_{snake(name)}"
            assert ident not in seen, ident
            seen.add(ident)
            m.const(ident, value)
    m.emit()


if __name__ == "__main__":
    main()
