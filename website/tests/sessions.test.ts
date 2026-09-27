import { describe, expect, it } from "vitest";
import { endpointKey, endpointPath, ENDPOINTS } from "./endpoints";
import { api, db, SEARCH_REQUEST, seedFinishedJob, setCookie, sha256Hex, signIn, useWorker } from "./harness";

useWorker();

const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;
const SESSION_COOKIE_FLAGS = [/;\s*HttpOnly(;|$)/i, /;\s*Secure(;|$)/i, /;\s*SameSite=Lax(;|$)/i, /;\s*Path=\/(;|$)/i];

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
            id: string
        }>();
        expect(results).toEqual([{ id: sha256Hex(session) }]);
    });

    it("is new for every login", async () => {
        const first = await signIn();
        const second = await signIn(first.profile);
        expect(second.session).not.toBe(first.session);
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
            count: number
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
        const jobId = await seedFinishedJob(profile.id);
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
