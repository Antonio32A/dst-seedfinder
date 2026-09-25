#!/usr/bin/env python3
"""Writes data/populate.bend from out/story.json and out/layouts.json: what the land population (populate/) needs on
top of data/rooms.bend and data/layouts.bend, the level's start set piece (AddStartingSetPiece's countstaticlayouts
key and its layout). `-` prints the module instead."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402


def main():
    level = blob.sidecar("story.json")["level"]
    start = level["start_setpeice"]
    m = blob.Module("populate", "scripts/gen/gen_populate.py",
                    "Level constants of the land population (ConvertGround, PopulateVoronoi).", imports=())
    m.comment(f"gen_params.start_setpeice ({start}): its string id and layout index.")
    m.const("start_key", ids.sid(start))
    m.const("start_layout", ids.layout_index(start))
    m.emit()


if __name__ == "__main__":
    main()
