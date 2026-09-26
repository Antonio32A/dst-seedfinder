import { type NextRequest, NextResponse } from "next/server";
import { discordAuthorizeUrl, discordRedirectUri } from "@/lib/server/discord";
import {
    encodeOAuthState,
    OAUTH_STATE_COOKIE,
    OAUTH_STATE_COOKIE_OPTIONS,
    sameOriginPath
} from "@/lib/server/oauth-state";
import { randomToken } from "@/lib/server/session";

export function GET(request: NextRequest) {
    const returnPath = sameOriginPath(request.nextUrl.searchParams.get("return") ?? "/", request.nextUrl.origin);
    const state = randomToken();
    const response = NextResponse.redirect(discordAuthorizeUrl(discordRedirectUri(request), state));
    response.cookies.set(OAUTH_STATE_COOKIE, encodeOAuthState({ state, returnPath }), OAUTH_STATE_COOKIE_OPTIONS);
    return response;
}
