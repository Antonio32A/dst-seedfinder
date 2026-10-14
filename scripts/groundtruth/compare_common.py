"""Shared by the compare_caves_*.py tools and parse_worldgen.py."""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main_checkout():
    """The repository's main checkout: ROOT, or the checkout a git worktree at ROOT belongs to."""
    git = ROOT / ".git"
    return Path(git.read_text().split(":", 1)[1].strip()).parents[2] if git.is_file() else ROOT


GT_ROOT = Path(os.environ.get("GT_ROOT") or main_checkout() / "build/groundtruth")


def latest_build():
    """The latest game build of builds.json, the default one."""
    return json.loads((ROOT / "builds.json").read_text())["latest"]


def groundtruth(build):
    """The ground truth of a game build: data/worlds, data/worlds_caves, dstw, dstw_caves, windows_caves, logs."""
    return GT_ROOT / str(build)


def cave_worlds(build, platform):
    """The real cave world JSONs of a build generated on a platform's server."""
    return groundtruth(build) / ("windows_caves" if platform == "windows" else "data/worlds_caves")


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
