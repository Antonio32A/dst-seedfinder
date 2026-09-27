import { describe, expect, it } from "vitest";
import { endpointKey, ENDPOINTS } from "./endpoints";
import { api, db, loadJob, SEARCH_REQUEST, signIn, startSearch, useWorker } from "./harness";

useWorker();

interface Attempt {
    path: string;
    session: string;
    body?: unknown;
    unchanged: () => Promise<void>;
    applied: () => Promise<void>;
}

async function signedInUser(session: string): Promise<unknown> {
    return ((await (await api("/api/me", { session })).json()) as { user: unknown }).user;
}

async function jobCount(userId: string): Promise<number> {
    const row = await db().prepare("SELECT COUNT(*) AS count FROM jobs WHERE user_id = ?").bind(userId).first<{
        count: number
    }>();
    return row?.count ?? 0;
}

const ATTEMPTS: Record<string, () => Promise<Attempt>> = {
    "POST /api/jobs": async () => {
        const { profile, session } = await signIn();
        const user = await signedInUser(session);
        return {
            path: "/api/jobs",
            session,
            body: SEARCH_REQUEST,
            unchanged: async () => {
                expect(await jobCount(profile.id)).toBe(0);
                expect(await signedInUser(session)).toEqual(user);
            },
            applied: async () => expect(await jobCount(profile.id)).toBe(1)
        };
    },
    "POST /api/jobs/[id]/cancel": async () => {
        const { session } = await signIn();
        const { id } = await startSearch(session);
        const before = await loadJob(id);
        return {
            path: `/api/jobs/${id}/cancel`,
            session,
            unchanged: async () => expect(await loadJob(id)).toEqual(before),
            applied: async () => expect((await loadJob(id))?.status).toBe("cancelled")
        };
    },
    "POST /api/auth/logout": async () => {
        const { session } = await signIn();
        return {
            path: "/api/auth/logout",
            session,
            unchanged: async () => expect(await signedInUser(session)).not.toBeNull(),
            applied: async () => expect(await signedInUser(session)).toBeNull()
        };
    }
};

it("has an attempt for every CSRF-checked endpoint", () => {
    expect(Object.keys(ATTEMPTS).sort()).toEqual(ENDPOINTS.filter(({ csrf }) => csrf).map(endpointKey).sort());
});

describe.each(Object.entries(ATTEMPTS).map(([key, attempt]) => ({ key, attempt })))("$key", ({ attempt }) => {
    it.each(["cross-site", "same-site", "none"])("rejects Sec-Fetch-Site: %s with 403 and changes nothing", async (site) => {
        const { path, session, body, unchanged } = await attempt();
        const response = await api(path, { method: "POST", session, body, site });
        expect(response.status).toBe(403);
        expect(await response.json()).toEqual({ error: "Requests from other sites aren't allowed." });
        await unchanged();
    });

    it.each([
        { header: "Sec-Fetch-Site: same-origin", site: "same-origin" },
        { header: "no Sec-Fetch-Site", site: undefined }
    ])("allows $header", async ({ site }) => {
        const { path, session, body, applied } = await attempt();
        const response = await api(path, { method: "POST", session, body, site });
        expect(response.status).toBeLessThan(300);
        await applied();
    });
});
