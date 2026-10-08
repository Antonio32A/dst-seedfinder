#!/usr/bin/env python3
"""Writes data/story.bend from out/story.json, out/layouts.json and out/storygen.json: the tables storygen/ needs on
top of data/rooms.bend and data/tasks.bend. The set piece names of data/world_catalog.bend's level.set_pieces keys and
random set piece codes as string ids and layouts, each room's tags as rows of data/rooms.bend's maptags table, the
tile values IsImpassableTile accepts, and exact math.random() thresholds. `-` prints the module instead."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import blob  # noqa: E402
import ids  # noqa: E402
import gen_world_catalog as wc  # noqa: E402
import union  # noqa: E402
import model  # noqa: E402

LEGACY_IMPASSABLE = (128, 200)


def piece(name):
    return [ids.sid(name), ids.layout_index(name)]


SHAPE_RANDOM, SHAPE_CHANCE = 0, 1
RANDOM_BODY = re.compile(r"^function\(\) return (?:(\d+) ?\+ ?)?math\.random\((\w+)\)(?:-(\d+))? end$")
CONSTANT_BODY = re.compile(r"^function\(\) return (\d+) end$")
CHANCE_BODY = re.compile(r"^function\(\) return \(math\.random\(\) < ([0-9.]+)\) and (\d+) or (\d+) end$")


def count_closure_row(closure):
    """A room_choices count closure as [shape, a, b, c, d]: shape 0 is a + math.random(b) - c (b = 0: the constant a),
    shape 1 is (math.random() < p) and c or d with the exact threshold of p in units a, b."""
    body = closure["body"]
    values = {g["name"]: g["value"] for g in closure["globals"]}
    if m := RANDOM_BODY.match(body):
        n = int(values.get(m.group(2), m.group(2)))
        return [SHAPE_RANDOM, int(m.group(1) or 0), n, int(m.group(3) or 0), 0]
    if m := CONSTANT_BODY.match(body):
        return [SHAPE_RANDOM, int(m.group(1)), 0, 0, 0]
    m = CHANCE_BODY.match(body)
    assert m, body
    return [SHAPE_CHANCE] + blob.word(blob.random_threshold(float(m.group(1)))) + [int(m.group(2)), int(m.group(3))]


def count_closure_rows(story):
    used = {e["value"]["closure"] for t in story["tasks"] for e in t["room_choices"] if isinstance(e["value"], dict)}
    return [count_closure_row(c) if c["key"] in used else [] for c in ids.closures()]


def maptag_index():
    return {t["tag"]: i for i, t in enumerate(ids.maptags())}


def main():
    story = union.story()
    extra = blob.sidecar("storygen.json")
    impassable = extra["impassable_below_1024"]
    assert impassable == [extra["impassable_value"]] + list(range(LEGACY_IMPASSABLE[0], LEGACY_IMPASSABLE[1] + 1))
    assert all(r["value"] < 1024 for r in blob.sidecar("story.json")["rooms"])
    assert all(r["value"] < 1024 or not extra["impassable_range_first"] <= r["value"] <= extra["impassable_range_last"]
               for r in story["rooms"]), "a room tile in the impassable range above 1024"

    table = wc.keys()
    keys = [[]] + [piece(name) for name, _, _, _ in table]
    specials = [piece(name) for name in model.REQUIRED_SET_PIECES + model.RANDOM_SET_PIECES]

    tag_rows = maptag_index()
    rooms = sorted(story["rooms"], key=lambda r: ids.room_index(r["name"]))
    room_tags = [[tag_rows[t] for t in (r.get("tags") or {}).get("ipairs", [])] for r in rooms]

    m = blob.Module("story", "scripts/gen/gen_story.py",
                    "Storygen tables beyond data/rooms.bend and data/tasks.bend.")
    m.table("piece_keys", keys, "Row key (data/world_catalog.bend level.set_pieces key id): the set piece's string id "
                                "and layout index (row 0 is unused).")
    m.table("piece_specials", specials, "Row code (data/world_catalog.bend random set piece code): string id, layout.")
    m.table("room_maptags", room_tags, "Row room: its tags (ipairs order) as rows of data/rooms.bend's maptags table.")
    m.table("count_closures", count_closure_rows(story),
            "Row closure id (data/closures.bend), for the task room_choices count closures: shape 0 = a + "
            "math.random(b) - c (no draw when b = 0), shape 1 = (math.random() < p) and c or d, p's exact threshold as "
            "units a, b. Other rows are empty.")
    m.comment("TileGroupManager:IsImpassableTile for tile values below 1024: IMPASSABLE and the legacy range.")
    m.const("impassable_value", extra["impassable_value"])
    m.const("legacy_impassable_first", LEGACY_IMPASSABLE[0])
    m.const("legacy_impassable_last", LEGACY_IMPASSABLE[1])
    m.comment("math.random() < 0.5 holds exactly when the PCG output is below this.")
    m.const("half_threshold", blob.random_threshold(0.5))
    m.comment("Rooms storygen names directly: SeperateStoryByBlanks' and LinkRegions' graph backgrounds.")
    m.const("bg_impassable_room", ids.room_index("BGImpassable"))
    m.const("region_link_room", ids.room_index("MoonIsland_Meadows"))
    m.code('''
def piece_key(+key: U32) -> U32:
  piece_keys_at(key, 0)

def piece_key_layout(+key: U32) -> U32:
  piece_keys_at(key, 1)

def piece_special(+code: U32) -> U32:
  piece_specials_at(code, 0)

def piece_special_layout(+code: U32) -> U32:
  piece_specials_at(code, 1)

def is_impassable(+tile: U32) -> Bool:
  U32.is_eq(tile, impassable_value()) || ((tile >= legacy_impassable_first() : U32) && (tile <= legacy_impassable_last() : U32))
''')
    m.emit()


if __name__ == "__main__":
    main()
