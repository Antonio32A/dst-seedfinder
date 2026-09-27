import { beforeAll, describe, expect, it } from "vitest";
import { endpointKey, endpointPath, ENDPOINTS } from "./endpoints";
import {
    api,
    db,
    randomToken,
    SEARCH_REQUEST,
    seedFinishedJob,
    sha256Hex,
    type SignedIn,
    signIn,
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
        jobId = await seedFinishedJob(owner.profile.id);
        session = await credential(owner);
    });

    it.each(USER_ENDPOINTS.map((endpoint) => ({
        ...endpoint,
        key: endpointKey(endpoint)
    })))("$key is 401", async (endpoint) => {
        const body = endpoint.method === "GET" ? undefined : SEARCH_REQUEST;
        const response = await api(endpointPath(endpoint, jobId), { method: endpoint.method, session, body });
        expect(response.status).toBe(401);
        expect(await response.json()).toEqual({ error: expect.any(String) });
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

    it("POST /api/jobs/[id]/cancel leaves the job alone", async () => {
        const before = await db().prepare("SELECT * FROM jobs WHERE id = ?").bind(jobId).first();
        await api(`/api/jobs/${jobId}/cancel`, { method: "POST", session });
        expect(await db().prepare("SELECT * FROM jobs WHERE id = ?").bind(jobId).first()).toEqual(before);
    });
});

it("a live session reaches the same endpoints", async () => {
    const { profile, session } = await signIn();
    const jobId = await seedFinishedJob(profile.id);
    const statuses = await Promise.all(
        USER_ENDPOINTS.filter(({ method }) => method === "GET").map(async (endpoint) => {
            const response = await api(endpointPath(endpoint, jobId), { session });
            await response.body?.cancel();
            return response.status;
        })
    );
    expect(statuses).toEqual(statuses.map(() => 200));
});
