import { randomUUID } from "node:crypto";
import { beforeAll, describe, expect, it } from "vitest";
import { endpointKey, ENDPOINTS } from "./endpoints";
import { api, loadJob, randomToken, signIn, type StartedSearch, startSearch, until, useWorker } from "./harness";

useWorker();

const RUNNER_ENDPOINTS = ENDPOINTS.filter(({ access }) => access === "runner").map((endpoint) => ({
    ...endpoint,
    key: endpointKey(endpoint)
}));

function runner(method: string, jobId: string, authorization?: string, headers: Record<string, string> = {}): Promise<Response> {
    const credentials: Record<string, string> = authorization === undefined ? {} : { Authorization: authorization };
    return api(`/api/runner/${jobId}`, { method, headers: { "X-Offset": "0", ...headers, ...credentials } });
}

async function expectRefused(response: Response, status: number): Promise<void> {
    expect(response.status).toBe(status);
    expect(await response.text()).toBe(status === 401 ? "Bad token." : "Gone.");
}

const bearer = (token: string) => `Bearer ${token}`;

describe("a malformed Authorization header is 401 before the job is looked up", () => {
    const malformed: [string, string | undefined][] = [
        ["missing", undefined],
        ["empty", ""],
        ["without the Bearer scheme", randomToken()],
        ["a lowercase scheme", `bearer ${randomToken()}`],
        ["Basic auth", `Basic ${Buffer.from("runner:secret").toString("base64")}`],
        ["a short token", bearer(randomToken().slice(1))],
        ["a long token", bearer(`${randomToken()}0`)],
        ["uppercase hex", bearer(randomToken().toUpperCase())],
        ["a non-hex token", bearer("g".repeat(64))],
        ["trailing text", `${bearer(randomToken())} extra`],
        ["two tokens", `${bearer(randomToken())}, ${bearer(randomToken())}`]
    ];

    it.each(RUNNER_ENDPOINTS.flatMap((endpoint) => malformed.map(([name, authorization]) => ({
        ...endpoint,
        name,
        authorization
    }))))(
        "$key with $name",
        async ({ method, authorization }) => {
            await expectRefused(await runner(method, randomUUID(), authorization), 401);
        }
    );
});

describe("runner tokens", () => {
    let search: StartedSearch;
    let other: StartedSearch;

    beforeAll(async () => {
        const { session } = await signIn();
        search = await startSearch(session);
        other = await startSearch(session);
    });

    it("are unique per search", () => {
        expect(search.token).toMatch(/^[0-9a-f]{64}$/);
        expect(search.token).not.toBe(other.token);
    });

    it.each(RUNNER_ENDPOINTS)("$key with a well-formed wrong token is 401", async ({ method }) => {
        await expectRefused(await runner(method, search.id, bearer(randomToken())), 401);
    });

    it.each(RUNNER_ENDPOINTS)("$key with another search's token is 401", async ({ method }) => {
        await expectRefused(await runner(method, search.id, bearer(other.token)), 401);
    });

    it.each(RUNNER_ENDPOINTS)("$key for an unknown search is 410", async ({ method }) => {
        await expectRefused(await runner(method, randomUUID(), bearer(search.token)), 410);
    });

    it("don't open the user API", async () => {
        const response = await api(`/api/jobs/${search.id}`, { headers: { Authorization: bearer(search.token) } });
        expect(response.status).toBe(401);
    });

    it("left the searches untouched", async () => {
        expect((await loadJob(search.id))?.status).toBe("starting");
        expect((await loadJob(other.id))?.status).toBe("starting");
    });
});

describe("a search's own token", () => {
    let search: StartedSearch;

    beforeAll(async () => {
        const { session } = await signIn();
        search = await startSearch(session);
    });

    it("can't post output while the search is starting", async () => {
        await expectRefused(await runner("POST", search.id, bearer(search.token)), 410);
        expect((await loadJob(search.id))?.status).toBe("starting");
    });

    it("fetches the config while starting, which starts the search", async () => {
        const response = await runner("GET", search.id, bearer(search.token));
        expect(response.status).toBe(200);
        expect(await response.json()).toEqual({ version: 1, platform: "windows" });
        expect((await loadJob(search.id))?.status).toBe("running");
    });

    it("can post output and fetch the config while running", async () => {
        const posted = await runner("POST", search.id, bearer(search.token));
        expect(posted.status).toBe(200);
        await posted.body?.cancel();
        const fetched = await runner("GET", search.id, bearer(search.token));
        expect(fetched.status).toBe(200);
        await fetched.body?.cancel();
    });

    it("ends the search with X-Exit", async () => {
        const response = await runner("POST", search.id, bearer(search.token), { "X-Exit": "0" });
        expect(response.status).toBe(200);
        await response.body?.cancel();
        await until(async () => (await loadJob(search.id))?.cost !== null);
    });

    it.each(RUNNER_ENDPOINTS)("$key is 410 once the search finished", async ({ method }) => {
        await expectRefused(await runner(method, search.id, bearer(search.token)), 410);
    });
});

describe("a cancelled search's token", () => {
    let search: StartedSearch;

    beforeAll(async () => {
        const { session } = await signIn();
        search = await startSearch(session);
        const cancelled = await api(`/api/jobs/${search.id}/cancel`, { method: "POST", session });
        expect(cancelled.status).toBe(200);
    });

    it.each(RUNNER_ENDPOINTS)("$key is 410", async ({ method }) => {
        await expectRefused(await runner(method, search.id, bearer(search.token)), 410);
        expect((await loadJob(search.id))?.status).toBe("cancelled");
    });
});
