import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { encodeShareParam } from "../lib/criteria/search-state";
import { api, type Call, randomToken, SECRETS, signIn, startSearch, useWorker, worker } from "./harness";

useWorker();

const CLIENT = fileURLToPath(new URL("../dist/client", import.meta.url));
const SCRIPT = readdirSync(CLIENT, {
    recursive: true,
    encoding: "utf8"
}).find((file) => file.startsWith("_next/") && file.endsWith(".js"));

const SECURITY_HEADERS = {
    "cross-origin-opener-policy": "same-origin",
    "cross-origin-embedder-policy": "require-corp",
    "content-security-policy": "frame-ancestors 'none'",
    "x-frame-options": "DENY"
};

const securityHeaders = (response: Response) =>
    Object.fromEntries(Object.keys(SECURITY_HEADERS).map((name) => [name, response.headers.get(name)]));

describe("every response carries the security headers", () => {
    const requests: { name: string; path: string; call?: Call }[] = [
        { name: "the page", path: "/" },
        { name: "a missing page", path: "/no-such-page" },
        { name: "a static asset", path: "/favicon.png" },
        { name: "a built script", path: `/${SCRIPT}` },
        { name: "an API response", path: "/api/me" },
        { name: "an API refusal", path: "/api/jobs" },
        { name: "a CSRF refusal", path: "/api/auth/logout", call: { method: "POST", site: "cross-site" } },
        {
            name: "a runner refusal",
            path: `/api/runner/${crypto.randomUUID()}`,
            call: { headers: { Authorization: `Bearer ${randomToken()}` } }
        },
        { name: "an OPTIONS answer", path: "/api/jobs", call: { method: "OPTIONS" } },
        { name: "a login redirect", path: "/api/auth/login" }
    ];

    it("found a built script", () => {
        expect(SCRIPT).toBeDefined();
    });

    it.each(requests)("on $name", async ({ path, call }) => {
        const response = await api(path, call);
        await response.body?.cancel();
        expect(response.status).toBeLessThan(500);
        expect(securityHeaders(response)).toEqual(SECURITY_HEADERS);
    });

    it.each(["/map/windows/1", "/map/windows/forest/1", "/map/windows/caves/1"])("on the world map %s, which serves the app", async (path) => {
        const response = await api(path);
        expect(response.status).toBe(200);
        expect(response.headers.get("Content-Type")).toMatch(/^text\/html/);
        const page = await response.text();
        expect(page).toContain("DST Seedfinder");
        expect(page).toContain('<a href="/" class="link-button">back</a>');
        expect(securityHeaders(response)).toEqual(SECURITY_HEADERS);
    });

    it("on the map picker, which serves the seed form under the site's header and footer", async () => {
        const response = await api("/map");
        expect(response.status).toBe(200);
        expect(response.headers.get("Content-Type")).toMatch(/^text\/html/);
        const page = await response.text();
        expect(page).toMatch(/<header class="header"><div class="brand">[\s\S]*antonio32a\.com[\s\S]*seedfinder/);
        expect(page).toMatch(/<form[^>]*>[\s\S]*World[\s\S]*Platform[\s\S]*Seed[\s\S]*>Map<\/button>/);
        expect(page).not.toContain("caves are well");
        expect(page).toContain('class="theme-toggle"');
        expect(securityHeaders(response)).toEqual(SECURITY_HEADERS);
    });

    it("on a world map with a search, which serves the app", async () => {
        const response = await api(`/map/linux/1?c=${encodeShareParam({ version: 1, platform: "windows" })}`);
        expect(response.status).toBe(200);
        expect(await response.text()).toContain("DST Seedfinder");
        expect(securityHeaders(response)).toEqual(SECURITY_HEADERS);
    });

    it("on a live search's event stream", async () => {
        const { session } = await signIn();
        const { id } = await startSearch(session);
        const response = await api(`/api/jobs/${id}/events`, { session });
        await response.body?.cancel();
        expect(response.headers.get("Content-Type")).toMatch(/^text\/event-stream/);
        expect(securityHeaders(response)).toEqual(SECURITY_HEADERS);
    });
});

describe("image optimization is off", () => {
    it("with no Images binding", async () => {
        expect(Object.keys(await worker().getEnv())).not.toContain("IMAGES");
    });

    it.each(["/_next/image", "/_vinext/image"])("so %s transforms nothing", async (path) => {
        const response = await api(`${path}?url=%2Ffavicon.png&w=64&q=75`, { headers: { Accept: "image/avif,image/webp,*/*" } });
        await response.body?.cancel();
        expect(response.status).not.toBe(200);
        expect(response.headers.get("Content-Type") ?? "").not.toMatch(/^image\//);
    });
});

it("the worker gets the test's own values for its vars and nothing from a .dev.vars", async () => {
    const env = await worker().getEnv() as unknown as Record<string, unknown>;
    const strings = Object.keys(env).filter((name) => typeof env[name] === "string").sort();
    expect(strings).toEqual(Object.keys(SECRETS).sort());
    expect(strings.filter((name) => env[name] !== SECRETS[name as keyof typeof SECRETS])).toEqual([]);
});
