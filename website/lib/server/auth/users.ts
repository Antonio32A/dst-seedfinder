import { creditsToUnits, DAILY_CREDITS } from "@/lib/jobs/credits";

export const DAILY_CREDIT_UNITS = creditsToUnits(DAILY_CREDITS);

export interface UserRow {
    id: string;
    username: string;
    global_name: string | null;
    avatar: string | null;
    credit_units: number;
    credits_reset_day: string;
    last_ip: string | null;
    created_at: number;
    last_login_at: number;
}

export interface DiscordProfile {
    id: string;
    username: string;
    global_name: string | null;
    avatar: string | null;
}

function utcDay(date: Date = new Date()): string {
    return date.toISOString().slice(0, 10);
}

export function nextResetAt(now: Date = new Date()): string {
    return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).toISOString();
}

/** Applies the lazy daily top-up first: the balance rises to the daily grant minus what unsettled searches reserved. */
export async function loadUser(db: D1Database, id: string): Promise<UserRow | null> {
    const today = utcDay();
    const [, selected] = await db.batch<UserRow>([
        db
            .prepare(
                `UPDATE users SET
           credit_units = MAX(credit_units, ?1 - (SELECT COALESCE(SUM(max_cost), 0) FROM jobs WHERE user_id = users.id AND cost IS NULL)),
           credits_reset_day = ?2
         WHERE id = ?3 AND credits_reset_day < ?2`
            )
            .bind(DAILY_CREDIT_UNITS, today, id),
        db.prepare("SELECT * FROM users WHERE id = ?").bind(id)
    ]);
    return selected.results[0] ?? null;
}

export async function upsertUser(db: D1Database, profile: DiscordProfile, ip: string | null): Promise<void> {
    const now = Date.now();
    await db
        .prepare(
            `INSERT INTO users (id, username, global_name, avatar, credit_units, credits_reset_day, last_ip, created_at, last_login_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (id) DO UPDATE SET
         username = excluded.username,
         global_name = excluded.global_name,
         avatar = excluded.avatar,
         last_ip = COALESCE(excluded.last_ip, users.last_ip),
         last_login_at = excluded.last_login_at`
        )
        .bind(profile.id, profile.username, profile.global_name, profile.avatar, DAILY_CREDIT_UNITS, utcDay(), ip, now, now)
        .run();
}
