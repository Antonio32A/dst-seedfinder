import { createHash, randomBytes, randomInt, randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll, expect } from "vitest";
import { createTestHarness, type TestHarness } from "wrangler";
import type { JobRow } from "@/lib/server/jobs/jobs";
import type { DiscordProfile } from "@/lib/server/auth/users";

const ORIGIN = "https://seedfinder.test";

const DISCORD_API = "https://discord.com/api";
const VAST_API = "https://console.vast.ai/api";
const POLL_MS = 50;

const SECRETS = {
    DISCORD_CLIENT_ID: "test-client-id",
    DISCORD_CLIENT_SECRET: "test-client-secret",
    DISCORD_REDIRECT_URI: `${ORIGIN}/api/auth/callback`,
    VAST_API_KEY: "test-vast-key",
    GHCR_USER: "test-ghcr-user",
    GHCR_PULL_TOKEN: "test-ghcr-token",
    RUNNER_IMAGE: "ghcr.io/test/runner:test",
    RUNNER_REPOSITORY: "ghcr.io/test/runner",
    PUBLIC_ORIGIN: ORIGIN,
    MAX_INSTANCES: "100"
};

const OFFER = {
    ask_contract_id: 4242,
    cpu_name: "Test CPU",
    cpu_cores_effective: 64,
    cpu_ghz: 3,
    cpu_ram: 64 * 1024,
    dph_total: 0.2,
    reliability: 0.99,
    verification: "verified",
    cpu_arch: "amd64"
};

export const SEARCH_REQUEST = { config: {}, wanted: 1, maxCost: 200 };

const profilesByCode = new Map<string, DiscordProfile>();
const runnerTokens = new Map<string, string>();
const unhandledRequests: string[] = [];
let nextInstanceId = 1000;
let harness: TestHarness | null = null;
let database: D1Database | null = null;

export const network = setupServer(
    http.post(`${DISCORD_API}/oauth2/token`, async ({ request }) => {
        const code = new URLSearchParams(await request.text()).get("code") ?? "";
        if (!profilesByCode.has(code)) return HttpResponse.json({ error: "invalid_grant" }, { status: 400 });
        return HttpResponse.json({ access_token: `access-${code}`, token_type: "Bearer" });
    }),
    http.get(`${DISCORD_API}/users/@me`, ({ request }) => {
        const profile = profilesByCode.get(request.headers.get("Authorization")?.replace("Bearer access-", "") ?? "");
        return profile ? HttpResponse.json(profile) : HttpResponse.json({ message: "401: Unauthorized" }, { status: 401 });
    }),
    http.get(`${VAST_API}/v1/instances`, () => HttpResponse.json({ instances: [] })),
    http.post(`${VAST_API}/v0/bundles/`, () => HttpResponse.json({ offers: [OFFER] })),
    http.put(`${VAST_API}/v0/asks/:askId/`, async ({ request }) => {
        const { env } = (await request.json()) as { env: Record<string, string> };
        runnerTokens.set(new URL(env.CALLBACK_URL).pathname.split("/").at(-1) ?? "", env.RUNNER_TOKEN);
        return HttpResponse.json({ success: true, new_contract: nextInstanceId++ });
    }),
    http.delete(`${VAST_API}/v0/instances/:id/`, () => HttpResponse.json({ success: true }))
);

/** Runs the built worker with migrated D1 and the mocked network for this test file; unmocked requests fail the test. */
export function useWorker(): void {
    let interceptedFetch: typeof fetch;
    beforeAll(async () => {
        network.listen({
            onUnhandledRequest: (request, print) => {
                unhandledRequests.push(`${request.method} ${request.url}`);
                print.error();
            }
        });
        interceptedFetch = globalThis.fetch;
        // The harness passes its Request as `init`, and MSW spreading `init` drops the Request's headers.
        globalThis.fetch = (input, init) => interceptedFetch(new Request(input, init));
        harness = createTestHarness({
            root: fileURLToPath(new URL("..", import.meta.url)),
            workers: [{ configPath: "./dist/server/wrangler.json", secrets: SECRETS }]
        });
        await harness.listen();
        const worker = harness.getWorker<Cloudflare.Env>();
        await worker.applyD1Migrations("DB");
        database = (await worker.getEnv()).DB;
    });
    afterEach(() => {
        network.resetHandlers();
        expect(unhandledRequests.splice(0)).toEqual([]);
    });
    afterAll(async () => {
        await harness?.close();
        globalThis.fetch = interceptedFetch;
        network.close();
    });
}

export function db(): D1Database {
    if (database === null) throw new Error("useWorker() has not started the worker");
    return database;
}

export interface Call {
    session?: string;
    method?: string;
    site?: string;
    body?: unknown;
    headers?: Record<string, string>;
}

/** Requests `path` as `ORIGIN` without following redirects; `site` is the `Sec-Fetch-Site` header. */
export function api(path: string, { session, method = "GET", site, body, headers = {} }: Call = {}): Promise<Response> {
    if (harness === null) throw new Error("useWorker() has not started the worker");
    const optional = {
        Cookie: session === undefined ? undefined : `session=${session}`,
        "Sec-Fetch-Site": site,
        "Content-Type": body === undefined ? undefined : "application/json"
    };
    const present = Object.entries(optional).filter((entry): entry is [string, string] => entry[1] !== undefined);
    return harness.fetch(`${ORIGIN}${path}`, {
        method,
        redirect: "manual",
        headers: { ...Object.fromEntries(present), ...headers },
        body: body === undefined ? undefined : JSON.stringify(body)
    }) as unknown as Promise<Response>;
}

export function setCookie(response: Response, name: string): string | undefined {
    return response.headers.getSetCookie().find((line) => line.startsWith(`${name}=`));
}

export function cookieValue(response: Response, name: string): string | undefined {
    return setCookie(response, name)?.slice(name.length + 1).split(";")[0];
}

export function newProfile(): DiscordProfile {
    const id = String((BigInt(Date.now()) << BigInt(22)) + BigInt(randomInt(1 << 22)));
    return { id, username: `user${id}`, global_name: null, avatar: null };
}

export interface LoginStart {
    state: string;
    stateCookie: string;
    response: Response;
}

/** `GET /api/auth/login`, returning the `state` sent to Discord and the `oauth_state` cookie. */
export async function beginLogin(returnTo?: string): Promise<LoginStart> {
    const query = returnTo === undefined ? "" : `?${new URLSearchParams({ return: returnTo })}`;
    const response = await api(`/api/auth/login${query}`);
    const authorize = new URL(response.headers.get("Location") ?? "");
    return {
        state: authorize.searchParams.get("state") ?? "",
        stateCookie: cookieValue(response, "oauth_state") ?? "",
        response
    };
}

/** An authorization code the mocked Discord exchanges for `profile`. */
export function discordCode(profile: DiscordProfile): string {
    const code = randomUUID();
    profilesByCode.set(code, profile);
    return code;
}

/** `GET /api/auth/callback` with `params` and the `oauth_state` cookie. */
export function callback(params: Record<string, string>, stateCookie?: string): Promise<Response> {
    const headers: Record<string, string> = stateCookie === undefined ? {} : { Cookie: `oauth_state=${stateCookie}` };
    return api(`/api/auth/callback?${new URLSearchParams(params)}`, { headers });
}

export interface SignedIn {
    profile: DiscordProfile;
    session: string;
    response: Response;
}

/** Logs in through the OAuth flow against the mocked Discord. */
export async function signIn(profile: DiscordProfile = newProfile(), returnTo?: string): Promise<SignedIn> {
    const { state, stateCookie } = await beginLogin(returnTo);
    const response = await callback({ code: discordCode(profile), state }, stateCookie);
    const session = cookieValue(response, "session") ?? "";
    expect(response.status).toBe(307);
    expect(session).toMatch(/^[0-9a-f]{64}$/);
    return { profile, session, response };
}

export function sha256Hex(text: string): string {
    return createHash("sha256").update(text).digest("hex");
}

/** A well-formed runner token no search was given. */
export function randomToken(): string {
    return randomBytes(32).toString("hex");
}

/** Polls `check` until it returns something other than `null`, `undefined` or `false`. */
export async function until<T>(check: () => Promise<T | null | undefined | false> | T | null | undefined | false, timeoutMs = 15_000): Promise<T> {
    const deadline = Date.now() + timeoutMs;
    for (; ;) {
        const value = await check();
        if (value !== null && value !== undefined && value !== false) return value;
        if (Date.now() > deadline) throw new Error(`Timed out after ${timeoutMs} ms waiting for ${check}`);
        await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    }
}

export function loadJob(id: string): Promise<JobRow | null> {
    return db().prepare("SELECT * FROM jobs WHERE id = ?").bind(id).first<JobRow>();
}

export interface StartedSearch {
    id: string;
    token: string;
}

/** `POST /api/jobs` as `session`, then waits until the job is `starting` on its rented (mocked) instance. */
export async function startSearch(session: string): Promise<StartedSearch> {
    const response = await api("/api/jobs", { method: "POST", session, body: SEARCH_REQUEST });
    expect(response.status).toBe(201);
    const { job } = (await response.json()) as { job: { id: string } };
    const token = await until(() => runnerTokens.get(job.id));
    await until(async () => (await loadJob(job.id))?.instance_id);
    return { id: job.id, token };
}

/** Inserts a finished job straight into D1, with no JobRoom behind it. */
export async function seedFinishedJob(userId: string): Promise<string> {
    const id = randomUUID();
    const now = Date.now();
    await db()
        .prepare(
            `INSERT INTO jobs (id, user_id, status, config, wanted, max_cost, cost, created_at, updated_at, finished_at)
             VALUES (?, ?, 'done', '{"version":1,"platform":"windows"}', 1, 20000, 0, ?, ?, ?)`
        )
        .bind(id, userId, now, now, now)
        .run();
    return id;
}
