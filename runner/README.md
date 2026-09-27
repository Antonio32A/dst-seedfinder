# runner

The Docker image a Vast.ai instance boots for one search. It's Alpine with a static, CPU-only `seedfinder` and
`run.sh`, which pulls the search config from the website backend, runs the search and streams the output back.

## Build and push

```sh
runner/build.sh          # build the image
runner/build.sh --push   # build and push it
```

Pushing needs `docker login ghcr.io` with a token that has `write:packages`. The last line printed is the
`RUNNER_IMAGE=...` value to give the website (the pushed digest with `--push`, the local tag without).

Build config:

- `RUNNER_REPOSITORY`: image repository, e.g. `ghcr.io/<user>/dst-seedfinder-runner`. Read from the environment, or
  from `website/.dev.vars` when unset.
- `RUNNER_BUILD_DIR` (optional): where the emitted C goes, default `build/runner/`.

## Configuration

- `CALLBACK_URL`: the backend URL for this job
- `RUNNER_TOKEN`: the job's bearer token
- `JOB_LIMIT`, `JOB_TIME_LIMIT`, `JOB_START_SEED`: passed to `seedfinder world find` as `--limit`, `--time-limit` and
  `--start-seed`

The package is private, so the website also needs:
- `GHCR_USER` (the GitHub user that owns it) 
- `GHCR_PULL_TOKEN` (a token with only `read:packages`) to let Vast.ai pull it. This will be shared between all
machines/instances, but it's not a big deal since it just contains this image + the API will only let you use
the same callback once.
