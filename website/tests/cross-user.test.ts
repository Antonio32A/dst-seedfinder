import { beforeAll, describe, expect, it } from "vitest";
import { endpointKey, endpointPath, ENDPOINTS, jsonBody } from "./endpoints";
import { api, loadJob, seedJob, type SignedIn, signIn, startSearch, useWorker } from "./harness";

useWorker();

interface OwnedJob {
    name: string;
    create: (owner: SignedIn) => Promise<string>;
}

const OWNED_JOBS: OwnedJob[] = [
    { name: "an active search", create: async ({ session }) => (await startSearch(session)).id },
    { name: "a finished search", create: async ({ profile }) => seedJob(profile.id) }
];

describe.each(OWNED_JOBS)("another user's job, $name", ({ create }) => {
    let owner: SignedIn;
    let intruder: SignedIn;
    let jobId: string;

    beforeAll(async () => {
        owner = await signIn();
        intruder = await signIn();
        jobId = await create(owner);
    });

    it.each(ENDPOINTS.filter(({ owned }) => owned).map((endpoint) => ({
        ...endpoint,
        key: endpointKey(endpoint)
    })))("$key is 404", async (endpoint) => {
        const response = await api(endpointPath(endpoint, jobId), {
            method: endpoint.method,
            session: intruder.session
        });
        expect(response.status).toBe(404);
        expect(await jsonBody(response)).toEqual(endpoint.method === "HEAD" ? null : { error: "Search not found." });
    });

    it("is not in the other user's list", async () => {
        const response = await api("/api/jobs", { session: intruder.session });
        expect(response.status).toBe(200);
        expect(await response.json()).toEqual({ jobs: [] });
    });

    it("is still the owner's", async () => {
        const job = await api(`/api/jobs/${jobId}`, { session: owner.session });
        expect(job.status).toBe(200);
        const list = (await (await api("/api/jobs", { session: owner.session })).json()) as { jobs: { id: string }[] };
        expect(list.jobs.map(({ id }) => id)).toEqual([jobId]);
    });
});

describe("another user's active search", () => {
    let owner: SignedIn;
    let intruder: SignedIn;
    let jobId: string;

    beforeAll(async () => {
        owner = await signIn();
        intruder = await signIn();
        jobId = (await startSearch(owner.session)).id;
    });

    it("is still starting after the other user cancels it", async () => {
        const before = await loadJob(jobId);
        expect(before?.status).toBe("starting");
        await api(`/api/jobs/${jobId}/cancel`, { method: "POST", session: intruder.session });
        expect(await loadJob(jobId)).toEqual(before);
    });

    it("the owner can cancel it", async () => {
        const response = await api(`/api/jobs/${jobId}/cancel`, { method: "POST", session: owner.session });
        expect(response.status).toBe(200);
        expect(await loadJob(jobId)).toMatchObject({ status: "cancelled", cost: expect.any(Number) });
    });
});
