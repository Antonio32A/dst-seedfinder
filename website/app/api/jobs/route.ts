import { env } from "cloudflare:workers";
import { creditsToUnits, formatCredits, unitsToCredits } from "@/lib/credits";
import { MAX_ACTIVE_SEARCHES } from "@/lib/job-events";
import { dispatcherStub, jobRoomStub, MAX_WAITING } from "@/lib/server/dispatcher";
import { clientIp, isCrossOrigin, json, jsonError } from "@/lib/server/http";
import { ACTIVE_STATUS_SQL, type JobRow, loadJob, settleJob, toJobView } from "@/lib/server/jobs";
import { getCurrentUser } from "@/lib/server/session";
import { DEFAULT_PLATFORM, DEFAULT_START_SEED } from "@/lib/seedfinder-config";
import { validateJobRequest } from "@/lib/validate-config";

const RECENT_JOBS = 20;
const MAX_BODY_BYTES = 512 * 1024;
const DISPATCH_FAILED = "Couldn't start the search. Your credits were refunded.";
const TOO_MANY_ACTIVE = `You already have ${MAX_ACTIVE_SEARCHES} searches going. Wait for one to finish or stop one.`;
const QUEUE_FULL = "Too many searches are waiting right now. Try again in a few minutes.";

export async function GET() {
    const user = await getCurrentUser();
    if (user === null) return jsonError(401, "Log in to see your searches.");
    const { results } = await env.DB.prepare("SELECT * FROM jobs WHERE user_id = ? ORDER BY created_at DESC LIMIT ?")
        .bind(user.id, RECENT_JOBS)
        .all<JobRow>();
    return json({ jobs: results.map(toJobView) });
}

const ACTIVE_COUNT_SQL = `SELECT COUNT(*) AS active FROM jobs WHERE user_id = ?1 AND status IN (${ACTIVE_STATUS_SQL})`;

async function atActiveLimit(userId: string): Promise<boolean> {
    const row = await env.DB.prepare(ACTIVE_COUNT_SQL).bind(userId).first<{ active: number }>();
    return (row?.active ?? 0) >= MAX_ACTIVE_SEARCHES;
}

export async function POST(request: Request) {
    if (isCrossOrigin(request)) return jsonError(403, "Requests from other sites aren't allowed.");
    const user = await getCurrentUser();
    if (user === null) return jsonError(401, "Log in to start a search.");
    await env.DB.prepare("UPDATE users SET last_ip = COALESCE(?, last_ip) WHERE id = ?").bind(clientIp(request), user.id).run();

    if (Number(request.headers.get("Content-Length")) > MAX_BODY_BYTES) return jsonError(413, "The search is too large.");
    const validation = validateJobRequest(await request.json().catch(() => undefined));
    if (!validation.ok) return jsonError(400, validation.error);
    const { config } = validation.value;

    const live = [env.VAST_API_KEY, env.GHCR_USER, env.GHCR_PULL_TOKEN, env.RUNNER_IMAGE].every(Boolean);
    if (!live) return jsonError(503, "Seed searches aren't live yet.");

    if (await atActiveLimit(user.id)) return jsonError(409, TOO_MANY_ACTIVE);
    if ((await dispatcherStub(env).waiting()) >= MAX_WAITING) return jsonError(503, QUEUE_FULL);

    const job = validation.value;
    const reserved = creditsToUnits(job.maxCost);
    const id = crypto.randomUUID();
    const now = Date.now();
    const reservation = await env.DB.batch([
        env.DB.prepare(
            `INSERT INTO jobs (id, user_id, status, config, wanted, max_cost, created_at, updated_at)
       SELECT ?7, id, 'queued', ?2, ?3, ?4, ?5, ?5 FROM users
       WHERE id = ?1 AND credit_units >= ?4 AND (${ACTIVE_COUNT_SQL}) < ?6`
        ).bind(user.id, JSON.stringify(job.config), job.wanted, reserved, now, MAX_ACTIVE_SEARCHES, id),
        env.DB.prepare("UPDATE users SET credit_units = credit_units - ? WHERE id = ? AND EXISTS (SELECT 1 FROM jobs WHERE id = ?)")
            .bind(reserved, user.id, id)
    ]);
    if (reservation[0].meta.changes === 0) {
        if (await atActiveLimit(user.id)) return jsonError(409, TOO_MANY_ACTIVE);
        return jsonError(
            402,
            `Max cost is ${formatCredits(job.maxCost)} credits but you have ${formatCredits(unitsToCredits(user.credit_units))}. Lower it or wait for the 00:00 UTC refill.`
        );
    }

    const started = await jobRoomStub(env, id)
        .start({
            id,
            userId: user.id,
            maxCost: job.maxCost,
            maxCostUnits: reserved,
            wanted: job.wanted,
            startSeed: job.startSeed ?? DEFAULT_START_SEED,
            config: JSON.stringify(job.config),
            platform: config.platform ?? DEFAULT_PLATFORM,
            origin: env.PUBLIC_ORIGIN || new URL(request.url).origin
        })
        .then(
            () => true,
            () => false
        );
    if (!started) {
        await settleJob(
            env.DB,
            { id, user_id: user.id, max_cost: reserved },
            { status: "failed", costUnits: 0, result: null, error: DISPATCH_FAILED }
        );
        return jsonError(502, DISPATCH_FAILED);
    }

    const row = await loadJob(env.DB, id);
    return json({ job: row && toJobView(row) }, 201);
}
