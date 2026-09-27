import { describe, expect, it } from "vitest";
import { endpointKey, ENDPOINTS } from "./endpoints";
import { api, db, loadJob, ORIGIN, SEARCH_REQUEST, signIn, startSearch, useWorker } from "./harness";

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

interface Provenance {
    name: string;
    site?: string;
    origin?: string;
}

const REFUSED: Provenance[] = [
    ...["cross-site", "same-site", "none"].map((site) => ({ name: `Sec-Fetch-Site: ${site}`, site })),
    ...["https://evil.example", "null", "https://seedfinder.test.evil.example", "https://seedfinder.test:8443"].map((origin) => ({
        name: `Origin: ${origin}`,
        origin
    })),
    {
        name: "Sec-Fetch-Site: same-origin with Origin: https://evil.example",
        site: "same-origin",
        origin: "https://evil.example"
    }
];

const ALLOWED: Provenance[] = [
    { name: "Sec-Fetch-Site: same-origin", site: "same-origin" },
    { name: `Origin: ${ORIGIN}`, origin: ORIGIN },
    { name: `Sec-Fetch-Site: same-origin with Origin: ${ORIGIN}`, site: "same-origin", origin: ORIGIN },
    { name: "neither Sec-Fetch-Site nor Origin, as from a non-browser client" }
];

const originHeader = (origin?: string): Record<string, string> => (origin === undefined ? {} : { Origin: origin });

describe.each(Object.entries(ATTEMPTS).map(([key, attempt]) => ({ key, attempt })))("$key", ({ attempt }) => {
    it.each(REFUSED)("rejects $name with 403 and changes nothing", async ({ site, origin }) => {
        const { path, session, body, unchanged } = await attempt();
        const response = await api(path, { method: "POST", session, body, site, headers: originHeader(origin) });
        expect(response.status).toBe(403);
        expect(await response.json()).toEqual({ error: "Requests from other sites aren't allowed." });
        await unchanged();
    });

    it.each(ALLOWED)("allows $name", async ({ site, origin }) => {
        const { path, session, body, applied } = await attempt();
        const response = await api(path, { method: "POST", session, body, site, headers: originHeader(origin) });
        expect(response.status).toBeLessThan(300);
        await applied();
    });
});
