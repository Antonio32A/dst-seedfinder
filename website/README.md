# DST Seedfinder website

A [vinext](https://github.com/cloudflare/vinext) (Next.js on Vite) app on Cloudflare Workers with D1. Users sign in
with Discord. Remote searches rent a [Vast.ai](https://vast.ai) server that runs the [runner](../runner/README.md)
image, and local searches run the seedfinder's WebAssembly build in the browser.

## Requirements

- Node 22 or newer.
- The WebAssembly build (`../scripts/build.sh wasm`, see [seedfinder/README.md](../seedfinder/README.md)).
  `npm run build` copies it from `../build/wasm/` into `public/wasm/` and fails without it. `npm run dev` works
  without it, but local search is off.
- A Discord application for OAuth2.
- For remote searches: a Vast.ai API key and the runner image pushed to a registry (`../runner/build.sh --push`).

## Configuration

Locally these go in `.dev.vars` (`cp .dev.vars.example .dev.vars`). In production they're Worker secrets.

- `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`: the Discord application. Add `<origin>/api/auth/callback` as a
  redirect in its OAuth2 settings (`http://localhost:3000/api/auth/callback` for local development).
- `DISCORD_REDIRECT_URI` (optional): overrides that callback URL.
- `VAST_API_KEY`: a Vast.ai API key.
- `GHCR_USER`, `GHCR_PULL_TOKEN`: a GitHub user and a token with `read:packages`, so instances can pull the runner
  image.
- `RUNNER_IMAGE`: the `RUNNER_IMAGE=...` line printed by `../runner/build.sh --push`.
- `PUBLIC_ORIGIN` (optional): the origin runners call back on. Defaults to the origin of the request that started the
  search, and it has to be reachable from the internet (not behind Cloudflare Access).
- `MAX_INSTANCES` (optional): the most Vast.ai instances running at once.
- `RUNNER_REPOSITORY` (`.dev.vars` only): the image repository `../runner/build.sh` builds and pushes to.

Remote searches stay disabled until `VAST_API_KEY`, `GHCR_USER`, `GHCR_PULL_TOKEN` and `RUNNER_IMAGE` are all set.

The bindings (the `DB` D1 database, the `JobRoom` and `Dispatcher` Durable Objects and the cron) are in
`wrangler.jsonc`. Run `npm run cf-typegen` after changing it.

## Local development

```sh
npm install
cp .dev.vars.example .dev.vars   # then fill it in
npx wrangler d1 migrations apply dst-seedfinder --local
npm run dev
```

`npm run preview` builds and runs the production Worker locally with Wrangler.

Vast.ai instances have to reach the Worker, so remote searches only work locally with `PUBLIC_ORIGIN` set to a public
tunnel. Otherwise test them on the deployed Worker and watch `npx wrangler tail dst-seedfinder`.

## Deploy

```sh
npx wrangler login
npx wrangler secret bulk secrets.env   # or `npx wrangler secret put <NAME>` for each one
npm run build && npm run deploy
npx wrangler d1 migrations apply dst-seedfinder --remote
```

Setting the secrets creates the Worker if it doesn't exist yet, and the first deploy creates the `dst-seedfinder` D1
database. Apply new migrations (`migrations/`) with the last command whenever one is added.

## Prefab catalog

`lib/catalog/world.ts` is generated from `scripts/catalog/catalog.json`. Regenerate it from the repository root after
the catalog changes:

```sh
node scripts/gen/gen_website_catalog.mjs
```
