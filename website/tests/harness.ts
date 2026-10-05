import { createHash, randomBytes, randomInt, randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll, expect } from "vitest";
import { createTestHarness, type TestHarness, type WorkerHandle } from "wrangler";
import type { JobRow } from "@/lib/server/jobs/jobs";
import type { DiscordProfile } from "@/lib/server/auth/users";

export const ORIGIN = "https://seedfinder.test";

const DISCORD_API = "https://discord.com/api";
export const VAST_API = "https://console.vast.ai/api";
const POLL_MS = 50;

type StringVar = {
    [K in keyof Cloudflare.Env]-?: NonNullable<Cloudflare.Env[K]> extends string ? K : never
}[keyof Cloudflare.Env];

export const SECRETS: Record<StringVar | "RUNNER_REPOSITORY", string> = {
    DISCORD_CLIENT_ID: "test-client-id",
    DISCORD_CLIENT_SECRET: "test-client-secret",
    DISCORD_REDIRECT_URI: `${ORIGIN}/api/auth/callback`,
    VAST_API_KEY: "test-vast-key",
    GHCR_USER: "test-ghcr-user",
    GHCR_PULL_TOKEN: "test-ghcr-token",
    RUNNER_IMAGE: "ghcr.io/test/runner:test",
    RUNNER_REPOSITORY: "ghcr.io/test/runner",
    PUBLIC_ORIGIN: ORIGIN,
    MAX_INSTANCES: "100",
    EVENTS_SESSION_CHECK_MS: "200"
};

export const OFFER = {
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

interface Grant {
    profile: DiscordProfile;
    redirectUri: string;
}

const grantsByCode = new Map<string, Grant>();
const runnerTokens = new Map<string, string[]>();
const unhandledRequests: string[] = [];
let nextInstanceId = 1000;
let refusedRentals = 0;
let harness: TestHarness | null = null;
let database: D1Database | null = null;

function isValidTokenExchange(form: URLSearchParams): boolean {
    const grant = grantsByCode.get(form.get("code") ?? "");
    return grant !== undefined
        && form.get("grant_type") === "authorization_code"
        && form.get("client_id") === SECRETS.DISCORD_CLIENT_ID
        && form.get("client_secret") === SECRETS.DISCORD_CLIENT_SECRET
        && form.get("redirect_uri") === grant.redirectUri;
}

export const network = setupServer(
    http.post(`${DISCORD_API}/oauth2/token`, async ({ request }) => {
        const form = new URLSearchParams(await request.text());
        if (!isValidTokenExchange(form)) return HttpResponse.json({ error: "invalid_grant" }, { status: 400 });
        return HttpResponse.json({ access_token: `access-${form.get("code")}`, token_type: "Bearer" });
    }),
    http.get(`${DISCORD_API}/users/@me`, ({ request }) => {
        const grant = grantsByCode.get(request.headers.get("Authorization")?.replace("Bearer access-", "") ?? "");
        return grant ? HttpResponse.json(grant.profile) : HttpResponse.json({ message: "401: Unauthorized" }, { status: 401 });
    }),
    http.get(`${VAST_API}/v1/instances`, () => HttpResponse.json({ instances: [] })),
    http.post(`${VAST_API}/v0/bundles/`, () => HttpResponse.json({ offers: [OFFER] })),
    http.put(`${VAST_API}/v0/asks/:askId/`, async ({ request }) => {
        const { env } = (await request.json()) as { env: Record<string, string> };
        const jobId = new URL(env.CALLBACK_URL).pathname.split("/").at(-1) ?? "";
        runnerTokens.set(jobId, [...(runnerTokens.get(jobId) ?? []), env.RUNNER_TOKEN]);
        if (refusedRentals > 0) {
            refusedRentals--;
            return HttpResponse.json({ success: false, error: "no_such_ask" }, { status: 400 });
        }
        return HttpResponse.json({ success: true, new_contract: nextInstanceId++ });
    }),
    http.delete(`${VAST_API}/v0/instances/:id/`, () => HttpResponse.json({ success: true }))
);

/**
 * Runs the built worker with migrated D1 and the mocked network for this test file; unmocked requests fail the
 * test.
 */
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
            workers: [
                { configPath: "./dist/server/wrangler.json", secrets: SECRETS },
                { configPath: "./tests/fixtures/preview-stub/wrangler.jsonc" }
            ]
        });
        await harness.listen();
        await worker().applyD1Migrations("DB");
        database = (await worker().getEnv()).DB;
    });
    afterEach(() => {
        network.resetHandlers();
        refusedRentals = 0;
        expect(unhandledRequests.splice(0)).toEqual([]);
    });
    afterAll(async () => {
        await harness?.close();
        globalThis.fetch = interceptedFetch;
        network.close();
    });
}

export function worker(): WorkerHandle<Cloudflare.Env> {
    if (harness === null) throw new Error("useWorker() has not started the worker");
    return harness.getWorker<Cloudflare.Env>();
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

/**
 * Requests `path` as `ORIGIN` without following redirects; `site` is `Sec-Fetch-Site`, and a non-raw `body` goes as
 * JSON.
 */
export function api(path: string, { session, method = "GET", site, body, headers = {} }: Call = {}): Promise<Response> {
    const raw = typeof body === "string" || body instanceof ReadableStream || body instanceof Uint8Array;
    const optional = {
        Cookie: session === undefined ? undefined : `session=${session}`,
        "Sec-Fetch-Site": site,
        "Content-Type": body === undefined || raw ? undefined : "application/json"
    };
    const present = Object.entries(optional).filter((entry): entry is [string, string] => entry[1] !== undefined);
    // harness.fetch goes through a dev proxy that drops its connection after a response leaves the request body unread.
    return worker().fetch(`${ORIGIN}${path}`, {
        method,
        redirect: "manual",
        headers: { ...Object.fromEntries(present), ...headers },
        body: raw ? body : body === undefined ? undefined : JSON.stringify(body),
        duplex: "half"
    } as Parameters<WorkerHandle["fetch"]>[1]) as unknown as Promise<Response>;
}

export function chunkedBody(bytes: number): ReadableStream<Uint8Array> {
    let left = bytes;
    return new ReadableStream({
        pull(controller) {
            const size = Math.min(left, 64 * 1024);
            left -= size;
            if (size === 0) controller.close();
            else controller.enqueue(new Uint8Array(size).fill(0x20));
        }
    });
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
    redirectUri: string;
    stateCookie: string;
    response: Response;
}

/** `GET /api/auth/login`, returning what it sent to Discord and the `oauth_state` cookie. */
export async function beginLogin(returnTo?: string): Promise<LoginStart> {
    const query = returnTo === undefined ? "" : `?${new URLSearchParams({ return: returnTo })}`;
    const response = await api(`/api/auth/login${query}`);
    const authorize = new URL(response.headers.get("Location") ?? "");
    expect(authorize.searchParams.get("client_id")).toBe(SECRETS.DISCORD_CLIENT_ID);
    return {
        state: authorize.searchParams.get("state") ?? "",
        redirectUri: authorize.searchParams.get("redirect_uri") ?? "",
        stateCookie: cookieValue(response, "oauth_state") ?? "",
        response
    };
}

/** An authorization code the mocked Discord exchanges for `profile` when the app sends it with `redirectUri`. */
export function discordCode(profile: DiscordProfile, redirectUri = SECRETS.DISCORD_REDIRECT_URI): string {
    const code = randomUUID();
    grantsByCode.set(code, { profile, redirectUri });
    return code;
}

/** `GET /api/auth/callback` with `params`, the `oauth_state` cookie and the browser's current `session` cookie. */
export function callback(params: Record<string, string>, stateCookie?: string, session?: string): Promise<Response> {
    const cookies = [stateCookie === undefined ? null : `oauth_state=${stateCookie}`, session === undefined ? null : `session=${session}`];
    const cookie = cookies.filter((pair) => pair !== null).join("; ");
    return api(`/api/auth/callback?${new URLSearchParams(params)}`, { headers: cookie ? { Cookie: cookie } : {} });
}

export interface SignedIn {
    profile: DiscordProfile;
    session: string;
    response: Response;
}

/** Logs in through the OAuth flow against the mocked Discord, from a browser holding `previousSession` if given. */
export async function signIn(
    profile: DiscordProfile = newProfile(),
    returnTo?: string,
    previousSession?: string
): Promise<SignedIn> {
    const { state, redirectUri, stateCookie } = await beginLogin(returnTo);
    const response = await callback({ code: discordCode(profile, redirectUri), state }, stateCookie, previousSession);
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
export async function until<T>(
    check: () => Promise<T | null | undefined | false> | T | null | undefined | false,
    timeoutMs = 15_000
): Promise<T> {
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

export function issuedTokens(jobId: string): string[] {
    return runnerTokens.get(jobId) ?? [];
}

export function refuseRentals(count: number): void {
    refusedRentals = count;
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
    await until(async () => (await loadJob(job.id))?.instance_id);
    return { id: job.id, token: issuedTokens(job.id).at(-1) ?? "" };
}

export type SeededJob = Partial<Pick<JobRow, "status" | "max_cost" | "cost" | "updated_at" | "started_at" | "machine" | "finished_at">>;

/** Inserts a job straight into D1 with no JobRoom behind it, finished unless `fields` say otherwise. */
export async function seedJob(userId: string, fields: SeededJob = {}): Promise<string> {
    const id = randomUUID();
    const now = Date.now();
    const row = {
        status: "done",
        max_cost: 20000,
        cost: 0,
        updated_at: now,
        started_at: null,
        machine: null,
        finished_at: now, ...fields
    };
    await db()
        .prepare(
            `INSERT INTO jobs (id, user_id, status, config, wanted, max_cost, cost, created_at, updated_at, started_at,
                               machine, finished_at)
             VALUES (?, ?, ?, '{"version":1,"platform":"windows"}', 1, ?, ?, ?, ?, ?, ?, ?)`
        )
        .bind(
            id,
            userId,
            row.status,
            row.max_cost,
            row.cost,
            now,
            row.updated_at,
            row.started_at,
            row.machine,
            row.finished_at
        )
        .run();
    return id;
}
