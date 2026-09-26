export const OAUTH_STATE_COOKIE = "oauth_state";

export const OAUTH_STATE_COOKIE_OPTIONS = {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/api/auth",
    maxAge: 600
} as const;

export interface OAuthState {
    state: string;
    returnPath: string;
}

/** Keeps login redirects on this site: anything off-origin becomes "/". */
export function sameOriginPath(requested: string, origin: string): string {
    const target = URL.parse(requested, origin);
    return target?.origin === origin ? `${target.pathname}${target.search}${target.hash}` : "/";
}

export function encodeOAuthState({ state, returnPath }: OAuthState): string {
    return `${state}.${encodeURIComponent(returnPath)}`;
}

export function decodeOAuthState(value: string | undefined, origin: string): OAuthState | null {
    const separator = value?.indexOf(".") ?? -1;
    if (value === undefined || separator <= 0) return null;
    try {
        return {
            state: value.slice(0, separator),
            returnPath: sameOriginPath(decodeURIComponent(value.slice(separator + 1)), origin)
        };
    } catch {
        return null;
    }
}
