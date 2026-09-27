import { beforeAll, describe, expect, it } from "vitest";
import { endpointKey, endpointPath, ENDPOINTS } from "./endpoints";
import { api, loadJob, type SignedIn, signIn, type StartedSearch, startSearch, useWorker } from "./harness";

useWorker();

const allowed = (route: string) => ENDPOINTS.filter((endpoint) => endpoint.route === route).map(({ method }) => method).sort().join(", ");

describe("OPTIONS", () => {
    let user: SignedIn;
    let search: StartedSearch;

    beforeAll(async () => {
        user = await signIn();
        search = await startSearch(user.session);
    });

    it.each(ENDPOINTS.filter(({ access }) => access === "preflight").map((endpoint) => ({
        ...endpoint,
        key: endpointKey(endpoint)
    })))(
        "$key only lists the route's methods, even for a cross-origin preflight",
        async (endpoint) => {
            const before = await loadJob(search.id);
            const response = await api(endpointPath(endpoint, search.id), {
                method: "OPTIONS",
                session: user.session,
                headers: { Origin: "https://evil.example", "Access-Control-Request-Method": "POST" }
            });
            expect(response.status).toBe(204);
            expect(response.headers.get("Allow")).toBe(allowed(endpoint.route));
            expect([...response.headers.keys()].filter((name) => name.startsWith("access-control-"))).toEqual([]);
            expect(response.headers.getSetCookie()).toEqual([]);
            expect(await response.text()).toBe("");
            expect(await loadJob(search.id)).toEqual(before);
        }
    );
});

describe("HEAD /api/runner/[id]", () => {
    let search: StartedSearch;

    beforeAll(async () => {
        search = await startSearch((await signIn()).session);
    });

    it("is 405 even with the search's own token, so it can't start the search", async () => {
        const response = await api(`/api/runner/${search.id}`, {
            method: "HEAD",
            headers: { Authorization: `Bearer ${search.token}` }
        });
        expect(response.status).toBe(405);
        expect(response.headers.get("Allow")).toBe("GET, OPTIONS, POST");
        expect((await loadJob(search.id))?.status).toBe("starting");
    });

    it("left the token working for GET", async () => {
        const response = await api(`/api/runner/${search.id}`, { headers: { Authorization: `Bearer ${search.token}` } });
        expect(response.status).toBe(200);
        await response.body?.cancel();
        expect((await loadJob(search.id))?.status).toBe("running");
    });
});
