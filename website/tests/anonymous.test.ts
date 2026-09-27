import { beforeAll, describe, expect, it } from "vitest";
import { endpointKey, endpointPath, ENDPOINTS, jsonBody } from "./endpoints";
import {
    api,
    db,
    loadJob,
    randomToken,
    SEARCH_REQUEST,
    seedJob,
    sha256Hex,
    type SignedIn,
    signIn,
    startSearch,
    useWorker
} from "./harness";

useWorker();

const USER_ENDPOINTS = ENDPOINTS.filter(({ access }) => access === "user");

interface Credential {
    name: string;
    session: (owner: SignedIn) => Promise<string | undefined>;
}

const CREDENTIALS: Credential[] = [
    { name: "no session cookie", session: async () => undefined },
    { name: "an empty session cookie", session: async () => "" },
    { name: "a garbage session cookie", session: async () => "not-a-session" },
    { name: "a well-formed but unknown session token", session: async () => randomToken() },
    {
        name: "the job owner's expired session",
        session: async ({ session }) => {
            await db().prepare("UPDATE sessions SET expires_at = ? WHERE id = ?").bind(Date.now() - 1, sha256Hex(session)).run();
            return session;
        }
    },
    {
        name: "the session of a deleted user",
        session: async () => {
            const { profile, session } = await signIn();
            await db().prepare("DELETE FROM users WHERE id = ?").bind(profile.id).run();
            return session;
        }
    }
];

describe.each(CREDENTIALS)("with $name", ({ session: credential }) => {
    let session: string | undefined;
    let jobId: string;

    beforeAll(async () => {
        const owner = await signIn();
        jobId = (await startSearch(owner.session)).id;
        session = await credential(owner);
    });

    it.each(USER_ENDPOINTS.map((endpoint) => ({
        ...endpoint,
        key: endpointKey(endpoint)
    })))("$key is 401", async (endpoint) => {
        const body = endpoint.method === "POST" ? SEARCH_REQUEST : undefined;
        const response = await api(endpointPath(endpoint, jobId), { method: endpoint.method, session, body });
        expect(response.status).toBe(401);
        expect(await jsonBody(response)).toEqual(endpoint.method === "HEAD" ? null : { error: expect.any(String) });
    });

    it("GET /api/me has no user", async () => {
        const response = await api("/api/me", { session });
        expect(response.status).toBe(200);
        expect(await response.json()).toEqual({ user: null });
    });

    it("POST /api/jobs creates no job", async () => {
        const before = await db().prepare("SELECT COUNT(*) AS count FROM jobs").first<{ count: number }>();
        await api("/api/jobs", { method: "POST", session, body: SEARCH_REQUEST });
        expect(await db().prepare("SELECT COUNT(*) AS count FROM jobs").first<{ count: number }>()).toEqual(before);
    });

    it("POST /api/jobs/[id]/cancel leaves the running search alone", async () => {
        const before = await loadJob(jobId);
        expect(before?.status).toBe("starting");
        await api(`/api/jobs/${jobId}/cancel`, { method: "POST", session });
        expect(await loadJob(jobId)).toEqual(before);
    });
});

it("a live session reaches the same endpoints", async () => {
    const { profile, session } = await signIn();
    const jobId = await seedJob(profile.id);
    const statuses = await Promise.all(
        USER_ENDPOINTS.filter(({ method }) => method !== "POST").map(async (endpoint) => {
            const response = await api(endpointPath(endpoint, jobId), { method: endpoint.method, session });
            await response.body?.cancel();
            return response.status;
        })
    );
    expect(statuses).toEqual(statuses.map(() => 200));
});
