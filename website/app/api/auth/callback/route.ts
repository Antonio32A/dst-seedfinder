import { env } from "cloudflare:workers";
import { type NextRequest, NextResponse } from "next/server";
import { discordRedirectUri, fetchDiscordProfile } from "@/lib/server/auth/discord";
import { decodeOAuthState, OAUTH_STATE_COOKIE, OAUTH_STATE_COOKIE_OPTIONS } from "@/lib/server/auth/oauth-state";
import { createSession, SESSION_COOKIE, SESSION_COOKIE_OPTIONS, SESSION_TTL_SECONDS } from "@/lib/server/auth/session";
import { upsertUser } from "@/lib/server/auth/users";
import { clientIp, jsonError } from "@/lib/server/http";

export async function GET(request: NextRequest) {
    const { origin, searchParams } = request.nextUrl;
    const saved = decodeOAuthState(request.cookies.get(OAUTH_STATE_COOKIE)?.value, origin);
    const code = searchParams.get("code");

    if (saved === null || searchParams.get("state") !== saved.state) {
        return jsonError(400, "Login expired or was invalid. Try again.");
    }
    if (code === null) return withClearedState(NextResponse.redirect(new URL(saved.returnPath, origin)));

    const ip = clientIp(request);
    const profile = await fetchDiscordProfile(code, discordRedirectUri(request)).catch(() => null);
    if (profile === null) return withClearedState(jsonError(502, "Couldn't log in with Discord. Try again."));

    await upsertUser(env.DB, profile, ip);
    const token = await createSession(profile.id, ip);

    const response = NextResponse.redirect(new URL(saved.returnPath, origin));
    response.cookies.set(SESSION_COOKIE, token, { ...SESSION_COOKIE_OPTIONS, maxAge: SESSION_TTL_SECONDS });
    return withClearedState(response);
}

function withClearedState<T extends Response>(response: T): T {
    response.headers.append("Set-Cookie", `${OAUTH_STATE_COOKIE}=; Path=${OAUTH_STATE_COOKIE_OPTIONS.path}; Max-Age=0; HttpOnly; Secure; SameSite=Lax`);
    return response;
}
