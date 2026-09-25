# DST Seedfinder website

A vinext (Next.js on Vite) app on Cloudflare Workers with D1 and Discord login.

## Deploy

Wrangler needs Node 22 or newer.

1. `npx wrangler login`
2. Set the secrets (this creates the Worker if it doesn't exist yet):
   - `npx wrangler secret put DISCORD_CLIENT_ID`
   - `npx wrangler secret put DISCORD_CLIENT_SECRET`
   - optional: `DISCORD_REDIRECT_URI` (defaults to `<origin>/api/auth/callback`)
   - optional: `RUNPOD_ENDPOINT_ID`, `RUNPOD_API_KEY` and `RUNPOD_WEBHOOK_SECRET` (any long random string). Until all
     three are set, searches are refused.
   - optional: `PUBLIC_ORIGIN` (defaults to the origin of the request that starts the search), the public origin
     RunPod calls back on. Each job is sent with `webhook: <origin>/api/runpod/webhook?job=<id>&token=<RUNPOD_WEBHOOK_SECRET>`,
     which settles the job and refunds the unused part of its max cost.
3. `npm run deploy`. The first deploy creates the `dst-seedfinder` D1 database and binds it.
4. `npx wrangler d1 migrations apply dst-seedfinder --remote`
5. Add `<origin>/api/auth/callback` as a redirect in the Discord application's OAuth2 settings.

## Local development

1. `cp .dev.vars.example .dev.vars` and fill it in.
2. `npx wrangler d1 migrations apply dst-seedfinder --local`
3. `npm run dev`

Run `npm run cf-typegen` after changing `wrangler.jsonc`.

## Search configs

Configs follow search format v1 (`../.scratch/spec/search-v1.md`). `lib/seedfinder-config.ts` has the types and caps,
and `lib/validate-config.ts` validates them strictly with the finder's error messages (`config: <message>`). World
filters (`counts`, `distances`, `tiles`, `routes`) are validated but refused by `POST /api/jobs` while
`WORLD_FILTERS_LIVE` is false for the config's platform, because the Bend finder doesn't run them yet.

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

Every user gets 1000 credits a day (reset at 00:00 UTC). 1 credit is 100 ms of compute, and D1 stores credits as
integer hundredths (`users.credit_units`, `jobs.max_cost`, `jobs.cost`, 1 unit = 1 ms). A search reserves its max
cost (1 to 1000 credits, default 100) up front and is charged its RunPod execution time when the webhook settles it.

## RunPod

`POST /api/jobs` sends RunPod `/run` this body:

```json
{
  "input": { "config": { "version": 1, "criteria": [] }, "limit": 25, "time_limit": 10, "start_seed": 0 },
  "policy": { "executionTimeout": 20000 },
  "webhook": "https://<origin>/api/runpod/webhook?job=<job id>&token=<RUNPOD_WEBHOOK_SECRET>"
}
```

`limit`, `time_limit` and `start_seed` map to the binary's `--limit`, `--time-limit` (seconds, `maxCost` × 0.1) and
`--start-seed` (a uint32, the request's optional `startSeed`, default 0; the scan wraps around). The handler's
`output` is stored as the job's result (an output over 1 MB fails the job instead, so settling never hits D1's row
limit). RunPod calls the webhook when the job ends, and the site charges the job's `executionTime` (capped at its max
cost) and refunds the rest. `POST /api/jobs` refuses bodies over 512 KiB and requests a browser marks as cross-origin
(`Sec-Fetch-Site`), as does `POST /api/auth/logout`.
