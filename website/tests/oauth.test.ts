import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import type { DiscordProfile } from "@/lib/server/auth/users";
import {
    api,
    beginLogin,
    callback,
    cookieValue,
    db,
    discordCode,
    network,
    newProfile,
    randomToken,
    setCookie,
    signIn,
    useWorker
} from "./harness";

useWorker();

const LOGIN_EXPIRED = { error: "Login expired or was invalid. Try again." };
const OFF_SITE_RETURNS = [
    "https://evil.example",
    "https://evil.example/path",
    "//evil.example/",
    "/\\evil.example",
    "javascript:alert(1)",
    "http://seedfinder.test.evil.example/",
    "https://seedfinder.test//evil.example",
    "http://seedfinder.test//evil.example",
    "/.//evil.example",
    "/%2e//evil.example",
    "/..//evil.example",
    "/./\\evil.example",
    "/.\\/evil.example"
];
const DISCORD_FAILED = { error: "Couldn't log in with Discord. Try again." };

async function sessionCount(): Promise<number> {
    return (await db().prepare("SELECT COUNT(*) AS count FROM sessions").first<{ count: number }>())?.count ?? 0;
}

function redirectPath(response: Response): string {
    const location = new URL(response.headers.get("Location") ?? "", "http://unset.invalid");
    return `${location.host} ${location.pathname}${location.search}${location.hash}`;
}

describe("login", () => {
    it("sends a fresh state to Discord and pins it in an HttpOnly, Secure, SameSite=Lax cookie on /api/auth", async () => {
        const first = await beginLogin();
        const second = await beginLogin();
        expect(first.state).toMatch(/^[0-9a-f]{64}$/);
        expect(first.state).not.toBe(second.state);
        expect(first.stateCookie.startsWith(`${first.state}.`)).toBe(true);
        const cookie = setCookie(first.response, "oauth_state") ?? "";
        [/;\s*HttpOnly(;|$)/i, /;\s*Secure(;|$)/i, /;\s*SameSite=Lax(;|$)/i, /;\s*Path=\/api\/auth(;|$)/i].forEach((flag) => expect(cookie).toMatch(flag));
    });

    it("returns to the requested page on this site", async () => {
        const { response } = await signIn(newProfile(), "/search?tab=1#top");
        expect(redirectPath(response)).toBe("seedfinder.test /search?tab=1#top");
    });

    it.each(OFF_SITE_RETURNS)("sends an off-site return %s to / and never stores it", async (returnTo) => {
        const stored = decodeURIComponent(decodeURIComponent((await beginLogin(returnTo)).stateCookie));
        expect(stored.slice(stored.indexOf(".") + 1)).toBe("/");
        const { response } = await signIn(newProfile(), returnTo);
        expect(redirectPath(response)).toBe("seedfinder.test /");
    });

    it.each(["https://evil.example/", "//evil.example", "/.//evil.example", "/%2e//evil.example"])(
        "sends an off-site return path %s forged into the state cookie to /",
        async (forged) => {
            const state = randomToken();
            const response = await callback({
                code: discordCode(newProfile()),
                state
            }, `${state}.${encodeURIComponent(forged)}`);
            expect(response.status).toBe(307);
            expect(redirectPath(response)).toBe("seedfinder.test /");
        }
    );

    it("clears the state cookie once used", async () => {
        const { response } = await signIn();
        expect(setCookie(response, "oauth_state")).toMatch(/^oauth_state=;.*Max-Age=0/i);
    });
});

describe("the callback refuses", () => {
    const refusals: { name: string; request: () => Promise<Response> }[] = [
        {
            name: "a missing state cookie",
            request: async () => callback({ code: discordCode(newProfile()), state: (await beginLogin()).state })
        },
        {
            name: "a state that doesn't match the cookie",
            request: async () => callback({
                code: discordCode(newProfile()),
                state: (await beginLogin()).state
            }, (await beginLogin()).stateCookie)
        },
        {
            name: "a missing state parameter",
            request: async () => callback({ code: discordCode(newProfile()) }, (await beginLogin()).stateCookie)
        },
        {
            name: "an empty state in both",
            request: async () => callback({ code: discordCode(newProfile()), state: "" }, `.${encodeURIComponent("/")}`)
        },
        {
            name: "a state cookie without a return path",
            request: async () => {
                const state = randomToken();
                return callback({ code: discordCode(newProfile()), state }, state);
            }
        },
        {
            name: "a state cookie with a malformed return path",
            request: async () => {
                const state = randomToken();
                return callback({ code: discordCode(newProfile()), state }, `${state}.%E0%A4%A`);
            }
        }
    ];

    it.each(refusals)("$name with 400 and no session", async ({ request }) => {
        const before = await sessionCount();
        const response = await request();
        expect(response.status).toBe(400);
        expect(await response.json()).toEqual(LOGIN_EXPIRED);
        expect(cookieValue(response, "session")).toBeUndefined();
        expect(await sessionCount()).toBe(before);
    });
});

describe("a failed Discord login", () => {
    const failures: { name: string; code: (profile: DiscordProfile) => string }[] = [
        { name: "Discord rejects the code", code: () => "code-discord-never-issued" },
        {
            name: "Discord's user lookup fails",
            code: (profile) => {
                network.use(http.get("https://discord.com/api/users/@me", () => HttpResponse.json({ message: "down" }, { status: 500 })));
                return discordCode(profile);
            }
        }
    ];

    it.each(failures)("when $name is 502 with no session or user", async ({ code }) => {
        const profile = newProfile();
        const { state, stateCookie } = await beginLogin();
        const before = await sessionCount();
        const response = await callback({ code: code(profile), state }, stateCookie);
        expect(response.status).toBe(502);
        expect(await response.json()).toEqual(DISCORD_FAILED);
        expect(cookieValue(response, "session")).toBeUndefined();
        expect(setCookie(response, "oauth_state")).toMatch(/^oauth_state=;.*Max-Age=0/i);
        expect(await sessionCount()).toBe(before);
        expect(await db().prepare("SELECT id FROM users WHERE id = ?").bind(profile.id).first()).toBeNull();
    });

    it("when the user denied access (no code) redirects back with no session", async () => {
        const { state, stateCookie } = await beginLogin("/account");
        const before = await sessionCount();
        const response = await callback({ state, error: "access_denied" }, stateCookie);
        expect(response.status).toBe(307);
        expect(redirectPath(response)).toBe("seedfinder.test /account");
        expect(cookieValue(response, "session")).toBeUndefined();
        expect(await sessionCount()).toBe(before);
    });
});

it("a completed login signs in as the Discord user", async () => {
    const { profile, session } = await signIn();
    const { user } = (await (await api("/api/me", { session })).json()) as { user: { id: string; username: string } };
    expect(user).toMatchObject({ id: profile.id, username: profile.username });
});
