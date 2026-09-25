# runner

The image a vast.ai instance runs for one search: a static, CPU-only `seedfinder` (musl, generic x86-64, no
CUDA/Metal) plus `run.sh`, which fetches the search config from the Worker, runs the search and streams its output
back every second. Busybox `sh` and `wget` only; HTTPS goes through alpine's `ssl_client` and CA bundle.

The protocol (env vars, requests, status codes, output lines) is specified in
[`.scratch/spec/runner-v1.md`](../.scratch/spec/runner-v1.md), sections "Runner image" and "Runner protocol".
As the spec says, no `--gpu` flag is passed: the build is CPU-only (no `-DBEND_CUDA`/`-DBEND_METAL`) and a future
binary may not accept the flag at all. Deviations from the spec and other details:

- NUL bytes are stripped from the output before it is stored and chunked (the `X-Offset`s count the stripped
  stream): busybox `wget --post-file` sizes the body with `strlen`, so a NUL would cut the POST short and the runner
  would resend the same gap forever.
- `SIGTERM`/`SIGINT` (the container's PID 1 gets no default handlers) kill the seedfinder and exit (143/130) within
  two seconds, even mid-request.
- busybox `wget` exits on a non-2xx status before reading the response headers, so the `X-Offset` of a `409` is not
  visible. The runner resends from offset 0 instead; the Worker keeps only bytes past what it has, so this converges
  (at 256 KiB per POST) to the same result.
- Empty POSTs are sent every second while nothing new was printed; they double as the liveness heartbeat.

## Build and push

```sh
runner/build.sh          # emits the C (scripts/build.sh), builds the image
runner/build.sh --push   # also pushes both tags
```

The C is emitted into `.scratch/runner-build/` (override with `RUNNER_BUILD_DIR`) and passed to `docker build` as the
named context `csrc`. The image repository comes from `RUNNER_REPOSITORY` (e.g.
`ghcr.io/<user>/dst-seedfinder-runner`), taken from the environment or else from `website/.dev.vars` (the last
`RUNNER_REPOSITORY=` line; surrounding `"` or `'` quotes are dropped); the script fails when neither has it. The image
is built for `linux/amd64` and tagged `<RUNNER_REPOSITORY>:<git short sha>` (`<sha>-dirty-<unix time>` when
`runner/`, `seedfinder/` or `scripts/` have uncommitted changes, so every dirty build gets its own tag) and `:latest`.

The last line printed is the Worker's `RUNNER_IMAGE` value: after `--push` it is the pushed digest,
`<RUNNER_REPOSITORY>@sha256:…`, so instances pull exactly that image even if the tag moves; without `--push` it is the
local `<RUNNER_REPOSITORY>:<tag>`. Pushing needs `docker login ghcr.io` with a token that has `write:packages`.

## Pull credentials for the Worker

The package is private, so vast pulls it with `image_login` = `-u <GHCR_USER> -p <GHCR_PULL_TOKEN> ghcr.io`:

- `GHCR_USER`: the GitHub user that owns the package.
- `GHCR_PULL_TOKEN`: a classic personal access token with only the `read:packages` scope (a fine-grained token with
  read-only Packages access works too where GitHub supports it for the container registry). Give it no other scopes;
  it ends up on every instance's host.
