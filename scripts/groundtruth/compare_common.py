"""Shared by the compare_caves_*.py tools."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAVE_WORLDS = ROOT / "build/groundtruth/data/worlds_caves"


def seeds_of(text):
    """`1-120` or `1,5,9` as a list of seeds."""
    out = []
    for part in text.split(","):
        first, _, last = part.partition("-")
        out += range(int(first), int(last or first) + 1)
    return out


def attempts_of_seeds(seeds, worlds_dir, first_attempts):
    """The (world JSON, attempt) pairs to check: every attempt of every seed, or only the first."""
    work = []
    for seed in seeds_of(seeds):
        world = json.loads((Path(worlds_dir) / f"{seed}.json").read_text())
        work += [(world, attempt) for attempt in ([1] if first_attempts else range(1, world["attempts"] + 1))]
    return work
