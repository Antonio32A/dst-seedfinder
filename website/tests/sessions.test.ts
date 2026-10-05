import { describe, expect, it } from "vitest";
import { endpointKey, endpointPath, ENDPOINTS } from "./endpoints";
import {
    api,
    db,
    newProfile,
    SEARCH_REQUEST,
    SECRETS,
    seedJob,
    setCookie,
    sha256Hex,
    signIn,
    startSearch,
    useWorker
} from "./harness";

useWorker();

const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;
const SESSION_COOKIE_FLAGS = [/;\s*HttpOnly(;|$)/i, /;\s*Secure(;|$)/i, /;\s*SameSite=Lax(;|$)/i, /;\s*Path=\/(;|$)/i];

const SESSION_CHECK_MS = Number(SECRETS.EVENTS_SESSION_CHECK_MS);

async function endsWithin(reader: ReadableStreamDefaultReader<Uint8Array>, timeoutMs: number): Promise<boolean> {
    const timeout = new Promise<"open">((resolve) => setTimeout(() => resolve("open"), timeoutMs));
    for (; ;) {
        const read = await Promise.race([reader.read(), timeout]);
        if (read === "open") return false;
        if (read.done) return true;
    }
}

async function meId(session: string): Promise<string | null> {
    const { user } = (await (await api("/api/me", { session })).json()) as { user: { id: string } | null };
    return user?.id ?? null;
}

describe("the session cookie", () => {
    it("is HttpOnly, Secure, SameSite=Lax, site-wide and lasts 30 days", async () => {
        const { response } = await signIn();
        const cookie = setCookie(response, "session") ?? "";
        SESSION_COOKIE_FLAGS.forEach((flag) => expect(cookie).toMatch(flag));
        expect(cookie).toMatch(new RegExp(`;\\s*Max-Age=${SESSION_TTL_SECONDS}(;|$)`, "i"));
    });

    it("is stored only as its SHA-256 hash", async () => {
        const { profile, session } = await signIn();
        const { results } = await db().prepare("SELECT id FROM sessions WHERE user_id = ?").bind(profile.id).all<{
            id: string;
        }>();
        expect(results).toEqual([{ id: sha256Hex(session) }]);
    });

    it("is new for every login", async () => {
        const first = await signIn();
        const second = await signIn(first.profile);
        expect(second.session).not.toBe(first.session);
    });
});

describe("logging in again", () => {
    it("ends the session the browser had and leaves the user's other sessions", async () => {
        const browser = await signIn();
        const otherDevice = await signIn(browser.profile);
        const again = await signIn(browser.profile, "/", browser.session);
        expect((await api("/api/jobs", { session: browser.session })).status).toBe(401);
        expect(await meId(otherDevice.session)).toBe(browser.profile.id);
        expect(await meId(again.session)).toBe(browser.profile.id);
    });

    it("doesn't keep a session cookie planted before the login", async () => {
        const planter = await signIn();
        const victim = await signIn(newProfile(), "/", planter.session);
        expect(await meId(planter.session)).toBeNull();
        expect(await meId(victim.session)).toBe(victim.profile.id);
    });
});

describe("logout", () => {
    it("ends the session and clears the cookie with the same flags", async () => {
        const { profile, session } = await signIn();
        const response = await api("/api/auth/logout", { method: "POST", session });
        expect(response.status).toBe(200);
        const cleared = setCookie(response, "session") ?? "";
        expect(cleared).toMatch(/^session=;/);
        expect(cleared).toMatch(/;\s*Max-Age=0(;|$)/i);
        SESSION_COOKIE_FLAGS.forEach((flag) => expect(cleared).toMatch(flag));
        expect(await meId(session)).toBeNull();
        expect((await api("/api/jobs", { session })).status).toBe(401);
        const row = await db().prepare("SELECT COUNT(*) AS count FROM sessions WHERE user_id = ?").bind(profile.id).first<{
            count: number;
        }>();
        expect(row?.count).toBe(0);
    });

    it("leaves the user's other sessions and other users signed in", async () => {
        const first = await signIn();
        const second = await signIn(first.profile);
        const other = await signIn();
        await api("/api/auth/logout", { method: "POST", session: first.session });
        expect(await meId(first.session)).toBeNull();
        expect(await meId(second.session)).toBe(first.profile.id);
        expect(await meId(other.session)).toBe(other.profile.id);
    });

    it("ends an open search stream and a reconnect is refused", async () => {
        const { session } = await signIn();
        const { id } = await startSearch(session);
        const stream = await api(`/api/jobs/${id}/events`, { session });
        expect(stream.status).toBe(200);
        const reader = (stream.body as ReadableStream<Uint8Array>).getReader();
        expect((await reader.read()).done).toBe(false);
        expect(await endsWithin(reader, 5 * SESSION_CHECK_MS)).toBe(false);
        await api("/api/auth/logout", { method: "POST", session });
        expect(await endsWithin(reader, 20 * SESSION_CHECK_MS)).toBe(true);
        expect((await api(`/api/jobs/${id}/events`, { session })).status).toBe(401);
    });

    it("without a session succeeds and touches no sessions", async () => {
        const { profile, session } = await signIn();
        const response = await api("/api/auth/logout", { method: "POST" });
        expect(response.status).toBe(200);
        expect(await meId(session)).toBe(profile.id);
    });
});

describe("per-user responses", () => {
    it.each(ENDPOINTS.filter(({ access }) => access === "user" || access === "optional").map((endpoint) => ({
        ...endpoint,
        key: endpointKey(endpoint)
    })))("$key is Cache-Control: no-store", async (endpoint) => {
        const { profile, session } = await signIn();
        const jobId = await seedJob(profile.id);
        const body = endpoint.route === "/api/jobs" && endpoint.method === "POST" ? SEARCH_REQUEST : undefined;
        const response = await api(endpointPath(endpoint, jobId), { method: endpoint.method, session, body });
        await response.body?.cancel();
        expect(response.status).toBeLessThan(300);
        expect(response.headers.get("Cache-Control")).toBe("no-store");
    });

    it("are no-store when refused too", async () => {
        const response = await api("/api/jobs");
        expect(response.status).toBe(401);
        expect(response.headers.get("Cache-Control")).toBe("no-store");
    });
});
