import { env } from "cloudflare:workers";
import { cookies } from "next/headers";
import { loadUser, type UserRow } from "./users";

export const SESSION_COOKIE = "session";
export const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;

export const SESSION_COOKIE_OPTIONS = {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/"
} as const;

/** Sessions are stored by this hash, never by the raw token. */
async function hashToken(token: string): Promise<string> {
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function randomToken(): string {
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function createSession(userId: string, ip: string | null): Promise<string> {
    const token = randomToken();
    const now = Date.now();
    await env.DB.batch([
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ? AND expires_at <= ?").bind(userId, now),
        env.DB.prepare("INSERT INTO sessions (id, user_id, created_at, expires_at, ip) VALUES (?, ?, ?, ?, ?)").bind(
            await hashToken(token),
            userId,
            now,
            now + SESSION_TTL_SECONDS * 1000,
            ip
        )
    ]);
    return token;
}

export async function deleteSession(token: string): Promise<void> {
    await env.DB.prepare("DELETE FROM sessions WHERE id = ?").bind(await hashToken(token)).run();
}

export async function getCurrentUser(): Promise<UserRow | null> {
    const token = (await cookies()).get(SESSION_COOKIE)?.value;
    if (!token) return null;
    const session = await env.DB.prepare("SELECT user_id FROM sessions WHERE id = ? AND expires_at > ?")
        .bind(await hashToken(token), Date.now())
        .first<{ user_id: string }>();
    return session ? loadUser(env.DB, session.user_id) : null;
}
