#!/usr/bin/env bash
# usage: runner/build.sh [--push]
# env: RUNNER_REPOSITORY (e.g. ghcr.io/<user>/dst-seedfinder-runner; read from website/.dev.vars when unset),
#      RUNNER_BUILD_DIR (default .scratch/runner-build)
set -euo pipefail
root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
build="${RUNNER_BUILD_DIR:-$root/.scratch/runner-build}"
repo="${RUNNER_REPOSITORY:-}"
if [[ -z "$repo" && -f "$root/website/.dev.vars" ]]; then
  repo="$(sed -n -E "s/^RUNNER_REPOSITORY=([\"']?)(.*)\1\$/\2/p" "$root/website/.dev.vars" | tail -n 1)"
fi
if [[ -z "$repo" ]]; then
  echo "build.sh: set RUNNER_REPOSITORY (e.g. ghcr.io/<user>/dst-seedfinder-runner) or add it to website/.dev.vars" >&2
  exit 1
fi
tag="$(git -C "$root" rev-parse --short HEAD)"
if [[ -n "$(git -C "$root" status --porcelain -- runner seedfinder scripts)" ]]; then
  tag+="-dirty-$(date +%s)"
fi

mkdir -p "$build"
cd "$root"
scripts/build.sh seedfinder/main.bend "$build/seedfinder.c"
docker build --platform linux/amd64 --build-context csrc="$build" -t "$repo:$tag" -t "$repo:latest" "$root/runner"
if [[ "${1:-}" == --push ]]; then
  docker push "$repo:$tag"
  docker push "$repo:latest"
  echo "RUNNER_IMAGE=$(docker inspect --format '{{index .RepoDigests 0}}' "$repo:$tag")"
else
  echo "RUNNER_IMAGE=$repo:$tag"
fi
