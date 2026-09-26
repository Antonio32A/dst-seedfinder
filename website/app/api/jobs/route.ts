import { env } from "cloudflare:workers";
import { creditsToUnits, formatCredits, unitsToCredits } from "@/lib/credits";
import { dispatcherStub, jobRoomStub, MAX_WAITING } from "@/lib/server/dispatcher";
import { clientIp, isCrossOrigin, json, jsonError } from "@/lib/server/http";
import { ACTIVE_STATUS_SQL, loadJob, settleJob, toJobView, type JobRow } from "@/lib/server/jobs";
import { getCurrentUser } from "@/lib/server/session";
import { DEFAULT_PLATFORM, DEFAULT_START_SEED } from "@/lib/seedfinder-config";
import { validateJobRequest } from "@/lib/validate-config";

const RECENT_JOBS = 20;
const MAX_BODY_BYTES = 512 * 1024;
const DISPATCH_FAILED = "Couldn't start the search. Your credits were refunded.";
const ALREADY_ACTIVE = "You already have a search going. Wait for it to finish or cancel it.";
const QUEUE_FULL = "Too many searches are waiting right now. Try again in a few minutes.";

export async function GET() {
  const user = await getCurrentUser();
  if (user === null) return jsonError(401, "Log in to see your searches.");
  const { results } = await env.DB.prepare("SELECT * FROM jobs WHERE user_id = ? ORDER BY created_at DESC LIMIT ?")
    .bind(user.id, RECENT_JOBS)
    .all<JobRow>();
  return json({ jobs: results.map(toJobView) });
}

async function activeJobId(userId: string): Promise<string | null> {
  const row = await env.DB.prepare(`SELECT id FROM jobs WHERE user_id = ? AND status IN (${ACTIVE_STATUS_SQL}) LIMIT 1`)
    .bind(userId)
    .first<{ id: string }>();
  return row?.id ?? null;
}

const alreadyActive = (jobId: string | null) => json({ error: ALREADY_ACTIVE, jobId }, 409);

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

  const active = await activeJobId(user.id);
  if (active !== null) return alreadyActive(active);
  if ((await dispatcherStub(env).waiting()) >= MAX_WAITING) return jsonError(503, QUEUE_FULL);

  const job = validation.value;
  const reserved = creditsToUnits(job.maxCost);
  const id = crypto.randomUUID();
  const now = Date.now();
  const reservation = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO jobs (id, user_id, status, config, wanted, max_cost, created_at, updated_at)
       SELECT ?1, id, 'queued', ?2, ?3, ?4, ?5, ?5 FROM users WHERE id = ?6 AND credit_units >= ?4`,
    ).bind(id, JSON.stringify(job.config), job.wanted, reserved, now, user.id),
    env.DB.prepare("UPDATE users SET credit_units = credit_units - ? WHERE id = ? AND EXISTS (SELECT 1 FROM jobs WHERE id = ?)")
      .bind(reserved, user.id, id),
  ]).catch((error: unknown) => {
    if (String(error).includes("UNIQUE constraint failed")) return null;
    throw error;
  });
  if (reservation === null) return alreadyActive(await activeJobId(user.id));
  if (reservation[0].meta.changes === 0) {
    return jsonError(
      402,
      `Max cost is ${formatCredits(job.maxCost)} credits but you have ${formatCredits(unitsToCredits(user.credit_units))}. Lower it or wait for the 00:00 UTC refill.`,
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
      origin: env.PUBLIC_ORIGIN || new URL(request.url).origin,
    })
    .then(
      () => true,
      () => false,
    );
  if (!started) {
    await settleJob(
      env.DB,
      { id, user_id: user.id, max_cost: reserved },
      { status: "failed", costUnits: 0, result: null, error: DISPATCH_FAILED },
    );
    return jsonError(502, DISPATCH_FAILED);
  }

  const row = await loadJob(env.DB, id);
  return json({ job: row && toJobView(row) }, 201);
}
