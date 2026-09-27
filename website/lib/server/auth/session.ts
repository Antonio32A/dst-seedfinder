import { env } from "cloudflare:workers";
import { cookies } from "next/headers";
import { randomToken, sha256Hex } from "@/lib/server/tokens";
import { loadUser, type UserRow } from "./users";

export const SESSION_COOKIE = "session";
export const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;

export const SESSION_COOKIE_OPTIONS = {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/"
} as const;

export async function createSession(userId: string, ip: string | null): Promise<string> {
    const token = randomToken();
    const now = Date.now();
    await env.DB.batch([
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ? AND expires_at <= ?").bind(userId, now),
        env.DB.prepare("INSERT INTO sessions (id, user_id, created_at, expires_at, ip) VALUES (?, ?, ?, ?, ?)").bind(
            await sha256Hex(token),
            userId,
            now,
            now + SESSION_TTL_SECONDS * 1000,
            ip
        )
    ]);
    return token;
}

export async function deleteSession(token: string): Promise<void> {
    await env.DB.prepare("DELETE FROM sessions WHERE id = ?").bind(await sha256Hex(token)).run();
}

/** The id of the user a session token belongs to, or null once it expired or was logged out. */
export async function sessionUserId(token: string): Promise<string | null> {
    const session = await env.DB.prepare("SELECT user_id FROM sessions WHERE id = ? AND expires_at > ?")
        .bind(await sha256Hex(token), Date.now())
        .first<{ user_id: string }>();
    return session?.user_id ?? null;
}

export async function getCurrentUser(): Promise<UserRow | null> {
    const token = (await cookies()).get(SESSION_COOKIE)?.value;
    const userId = token ? await sessionUserId(token) : null;
    return userId === null ? null : loadUser(env.DB, userId);
}
