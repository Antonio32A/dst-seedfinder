import { env } from "cloudflare:workers";
import type { DiscordProfile } from "./users";

const DISCORD_API = "https://discord.com/api";
const DISCORD_TIMEOUT_MS = 10_000;

export function discordRedirectUri(request: Request): string {
    return env.DISCORD_REDIRECT_URI || `${new URL(request.url).origin}/api/auth/callback`;
}

export function discordAuthorizeUrl(redirectUri: string, state: string): string {
    const params = new URLSearchParams({
        client_id: env.DISCORD_CLIENT_ID,
        redirect_uri: redirectUri,
        response_type: "code",
        scope: "identify",
        state,
        prompt: "none"
    });
    return `https://discord.com/oauth2/authorize?${params}`;
}

export async function fetchDiscordProfile(code: string, redirectUri: string): Promise<DiscordProfile> {
    const tokenResponse = await fetch(`${DISCORD_API}/oauth2/token`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
            client_id: env.DISCORD_CLIENT_ID,
            client_secret: env.DISCORD_CLIENT_SECRET,
            grant_type: "authorization_code",
            code,
            redirect_uri: redirectUri
        }),
        signal: AbortSignal.timeout(DISCORD_TIMEOUT_MS)
    });
    if (!tokenResponse.ok) throw new Error(`Discord token exchange failed (${tokenResponse.status})`);
    const { access_token: accessToken } = (await tokenResponse.json()) as { access_token: string };

    const userResponse = await fetch(`${DISCORD_API}/users/@me`, {
        headers: { Authorization: `Bearer ${accessToken}` },
        signal: AbortSignal.timeout(DISCORD_TIMEOUT_MS)
    });
    if (!userResponse.ok) throw new Error(`Discord user lookup failed (${userResponse.status})`);
    const { id, username, global_name, avatar } = (await userResponse.json()) as DiscordProfile;
    return { id, username, global_name: global_name ?? null, avatar: avatar ?? null };
}

export function discordAvatarUrl(userId: string, avatar: string | null): string {
    if (avatar === null) return `https://cdn.discordapp.com/embed/avatars/${Number((BigInt(userId) >> BigInt(22)) % BigInt(6))}.png`;
    const extension = avatar.startsWith("a_") ? "gif" : "png";
    return `https://cdn.discordapp.com/avatars/${userId}/${avatar}.${extension}?size=128`;
}
