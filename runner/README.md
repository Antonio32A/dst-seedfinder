# runner

The image a vast.ai instance runs for one search: a static, CPU-only `seedfinder` (musl, generic x86-64, no
CUDA/Metal) plus `run.sh`, which fetches the search config from the Worker, runs the search and streams its output
back every second. Busybox `sh` and `wget` only; HTTPS goes through alpine's `ssl_client` and CA bundle.

No `--gpu` flag is passed: the build is CPU-only (no `-DBEND_CUDA`/`-DBEND_METAL`) and a future binary may not
accept the flag at all.

## Protocol

Instance env (set by the Worker at create time; every value is free of spaces and quotes):

| var              | example                                                                |
|------------------|------------------------------------------------------------------------|
| `CALLBACK_URL`   | `https://<origin>/api/runner/<job id>`                                 |
| `RUNNER_TOKEN`   | 64 hex chars, per job; the Durable Object stores only its SHA-256      |
| `JOB_LIMIT`      | `25` (`--limit`)                                                       |
| `JOB_TIME_LIMIT` | `37.5` (`--time-limit`, seconds; see "Credits" in `website/README.md`) |
| `JOB_START_SEED` | `0` (`--start-seed`)                                                   |

1. `GET $CALLBACK_URL` with `Authorization: Bearer $RUNNER_TOKEN` → `200` with the config file (JSON, as is). The first
   GET is the billing start. Repeated GETs return the same config until the first chunk arrives, `409` after.
   `401` bad token (a header that isn't `Bearer <64 hex>` is refused before the Durable Object is asked), `410` when the
   search is cancelled/finished or this attempt was given up on (runner exits 0).
2. Runner runs `seedfinder -- world find --start-seed $JOB_START_SEED --limit $JOB_LIMIT --time-limit $JOB_TIME_LIMIT
   --config <file>` (no `--json`; no `--threads`, the binary's default honours cgroup `cpu.max`; no `--gpu`, the build
   is CPU-only) with stdout and stderr merged into one file, NUL bytes stripped.
3. Every 1 s: `POST $CALLBACK_URL` with the bearer token, header `X-Offset: <byte offset of the first byte sent>`,
   body = the new bytes (at most 256 KiB per POST; the rest goes next tick). The Durable Object keeps only bytes past
   what it already has, so resends are harmless; a gap (offset past its length) is `409` with `X-Offset: <its length>`
   in the response (busybox wget can't read headers on a 4xx, so the runner resends from 0; the dedupe absorbs it).
   `410` = cancelled: kill the seedfinder and exit. Empty POSTs are the heartbeat.
   The Worker reads the body as a stream and answers `413` as soon as it passes 256 KiB. Past 16 MiB of output in all
   the search ends as `failed` ("The search printed more output than expected.") and the POST gets `410`.
4. After the seedfinder exits: POST all remaining bytes with `X-Exit: <exit code>` (0 hits, 1 no hits, 2 error, other =
   crash). Retry until `200`. The final POST's arrival is the billing end. Then exit 0. An empty or non-integer `X-Exit`
   counts as no header. The Durable Object records the ending and replies `200` at once; destroying the instance and
   settling happen in its alarm right after, so the runner never waits on vast.ai.

Output lines the Durable Object parses (per line, `\n`-separated):

- `scanned <n>/<space> matches <m> (<r> seeds/s)` → progress
- `search: scanned <n>, [levels <l>, ]worlds <w>, generating <g> … hits <h> (…)` → progress of world-filter searches
  (`scanned` is the first seed not yet decided, so everything before it is checked; seeds/s is its growth over the
  last 30 s, or over the whole search when there is no earlier line in that window), with worlds generated so far and
  worlds being generated now; `levels` (the level-table pre-pass, which runs far ahead) is ignored
- `<seed> {json}` → a hit; the JSON is a `SearchHit` without `seed`
- `done {json}` → summary `{scanned, last_scanned, next_seed, hits, stopped}`
- `config: <message>` or `{"error": "..."}` → config error
- anything else is ignored

A line longer than 64 KiB is dropped (an unterminated one is discarded as it grows, never buffered). Only the first
`wanted` hits are kept.

The stored D1 `result` is the same job object `--json` prints ([`docs/config.md`](../docs/config.md) § 8):
`{version, platform, hits, scanned, last_scanned, next_seed, stopped}`, read by `parseJobResult`. On a config error it
is `{"error": "config: ..."}`.

Details of `run.sh`:

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

The C is emitted into `build/runner/` (override with `RUNNER_BUILD_DIR`) and passed to `docker build` as the
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
