# DST Seedfinder website

A vinext (Next.js on Vite) app on Cloudflare Workers with D1 and Discord login.

## Deploy

Wrangler needs Node 22 or newer.

1. `npx wrangler login`
2. Set the secrets (this creates the Worker if it doesn't exist yet), one by one with `npx wrangler secret put <NAME>`
   or all at once with `npx wrangler secret bulk <file>` from a `KEY=VALUE` file with the production values:
   - `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`
   - optional: `DISCORD_REDIRECT_URI` (defaults to `<origin>/api/auth/callback`)
   - `VAST_API_KEY` (a vast.ai API key), `GHCR_USER` and `GHCR_PULL_TOKEN` (a GitHub user and a token with
     `read:packages`, used as the instances' `image_login`)
   - `RUNNER_IMAGE`: the `<RUNNER_REPOSITORY>@sha256:…` digest printed by `../runner/build.sh --push`
   - optional: `PUBLIC_ORIGIN`, the origin runners call back on (defaults to the origin of the request that starts
     the search; it has to be reachable without Cloudflare Access)
   - optional: `MAX_INSTANCES`, live instances at once (default 10)

   Until `VAST_API_KEY`, `GHCR_USER`, `GHCR_PULL_TOKEN` and `RUNNER_IMAGE` are all set, searches are refused with 503.
3. `npm run build && npm run deploy`. The first deploy creates the `dst-seedfinder` D1 database and binds it. The
   `JobRoom` and `Dispatcher` Durable Objects (SQLite-backed) and the `*/5 * * * *` sweeper cron come with it.
4. `npx wrangler d1 migrations apply dst-seedfinder --remote`
5. Add `<origin>/api/auth/callback` as a redirect in the Discord application's OAuth2 settings.

### Testing

vast.ai instances have to reach the Worker, so searches are tested on the deployed Worker with real instances. Watch
`npx wrangler tail dst-seedfinder` for the JobRoom and the sweeper, and the vast.ai console for its instances.

## Local development

1. `cp .dev.vars.example .dev.vars` and fill it in.
2. `npx wrangler d1 migrations apply dst-seedfinder --local`
3. `npm run dev`

Run `npm run cf-typegen` after changing `wrangler.jsonc`.

## Search configs

Configs follow search format v1 (`../.scratch/spec/search-v1.md`). `lib/seedfinder-config.ts` has the types and caps,
and `lib/validate-config.ts` validates them strictly with the finder's error messages (`config: <message>`).

`platform` (`"windows"` or `"linux"`, the OS that generates the world) defaults to `"windows"`. The level table is the
same on both, but generated worlds differ. The site always writes `platform`, and `validateConfig` fills it in when
it's missing.

`lib/world-catalog.ts` (prefabs, prefab groups, land tiles, game build) is generated from
`../.scratch/catalog/catalog.json`. Regenerate it after every catalog regen, then check it against the spec:

```sh
node .scratch/gen-world-catalog.mjs [path/to/catalog.json]
JITI_ALIAS='{"@/":"'"$PWD"'/"}' ./node_modules/.bin/jiti .scratch/verify-spec.ts
```

## Credits

Every user is topped up to 1000 credits a day at 00:00 UTC (`loadUser`): the balance plus the credits reserved by
unsettled searches is raised to 1000, and a larger balance (granted by hand in D1) is kept. Refunds are not capped. D1 stores credits as integer hundredths
(`users.credit_units`, `jobs.max_cost`, `jobs.cost`). A search reserves its max cost (20 to 1000 credits, default 100)
up front, atomically with the "one active search per user" check (a partial unique index on `jobs.user_id` over the
active statuses).

Credits follow the machine's price: `credits = 40 × seconds × $/h`, so 1000 credits buy 100 s on a $0.25/h machine
(`MAX_DOLLARS_PER_HOUR`, the most an offer may cost) and 400 s on a $0.10/h one. On top of that there is a starting
fee of 10 credits (`STARTING_FEE`), part of the max cost, charged once a machine has been rented for the search (also
when it is cancelled while starting), but not when no machine could be found or none would boot. The runner's
`--time-limit` is `(maxCost − 10) ÷ (40 × $/h)`, worked out for each offer tried and capped at 10 minutes
(`MAX_SEARCH_SECONDS`), so 100 credits buy 9 s at $0.25/h. A search is charged the fee plus its search time, from the
runner's first config GET to its final POST (or the cancel, the deadline, or its last POST when contact is lost),
rounded up to a hundredth and capped at the max cost; queueing and booting are free apart from the fee. The rest is
refunded when the search settles.

## Searches on vast.ai

The contract is `../.scratch/spec/runner-v1.md`. Each search gets its own `JobRoom` Durable Object (keyed by job id)
that owns the whole lifecycle, and a singleton `Dispatcher` caps live instances at `MAX_INSTANCES` with a FIFO queue.

- `queued`: waiting for a Dispatcher slot; the room is told its 1-based queue position. At 200 waiting searches,
  `POST /api/jobs` answers 503 before reserving anything.
- `starting`: before each of up to 3 attempts the room searches `/bundles/` again; `lib/server/offers.ts`
  (`pickOffers`, the replaceable offer algorithm) ranks the offers by cores × GHz ÷ $/h (at least 200 MB of RAM per
  core) and the room rents the best one it hasn't tried, giving it 3 minutes to fetch its config. Only a definite
  refusal of an offer (vast.ai 4xx) or a boot timeout uses up an attempt; vast.ai hiccups (429, 5xx, timeouts) are
  retried every 20 s. Nothing boots within 3 attempts or 10 minutes → `failed`, charged 0.
- `running`: from the runner's first `GET /api/runner/<id>`. The runner POSTs its output every second with `X-Offset`
  (256 KiB at most per POST; a gap is 409 with the expected `X-Offset`) and the final chunk with `X-Exit`. The room
  parses the lines (progress, the first `wanted` hits, the `done` line, config errors; lines over 64 KiB are dropped)
  and stores the finder's `--json` job object as the result. Exit 0/1 is `done` only after a `done` line. No POST for
  60 s, no end by the time limit + 10 s, or more than 16 MiB of output → `failed`, charged the time so far, hits kept.
- `POST /api/jobs/<id>/cancel` destroys the instance and charges the fee (once rented) and the time since the config
  GET.

Every end settles D1 once (`settleJob`), destroys every instance labelled with the search (including ones a failed
create may have rented) and only then frees the slot. Browsers follow a search on
`GET /api/jobs/<id>/events` (server-sent `data: <JobEvent JSON>` messages, `lib/job-events.ts`), which replays the
status, the latest progress and every hit on connect and closes after `end`. The runner token is 32 random bytes per
attempt; the room keeps only its SHA-256.

The custom Worker entry `worker/index.ts` re-exports vinext's fetch handler (`vinext/server/fetch-handler`) next to
the two Durable Object classes and the `scheduled` handler. The cron (`lib/server/sweeper.ts`) destroys
`dst-seedfinder:*` instances whose search is over or unknown, stops and settles searches that are stuck whatever their
room says (running 10 minutes past their time limit, or queued/starting for 30 minutes), drops Dispatcher entries of
searches that aren't active in D1 any more, and pokes rooms of searches that have gone quiet (settling them when their
room is empty).

`POST /api/jobs` refuses bodies over 512 KiB and requests a browser marks as cross-origin (`Sec-Fetch-Site`), as do
`POST /api/jobs/<id>/cancel` and `POST /api/auth/logout`.
