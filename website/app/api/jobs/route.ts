import { env } from "cloudflare:workers";
import { creditsToUnits, formatCredits, unitsToCredits } from "@/lib/credits";
import { clientIp, isCrossOrigin, json, jsonError } from "@/lib/server/http";
import { settleJob, toJobView, type JobRow } from "@/lib/server/jobs";
import { dispatchToRunpod, runpodRunBody, webhookUrl } from "@/lib/server/runpod";
import { getCurrentUser } from "@/lib/server/session";
import { usesWorldFilters, worldFiltersUnavailable } from "@/lib/seedfinder-config";
import { validateJobRequest } from "@/lib/validate-config";

const RECENT_JOBS = 20;
const MAX_BODY_BYTES = 512 * 1024;
const DISPATCH_FAILED = "Couldn't start the search. Your credits were refunded.";

export async function GET() {
  const user = await getCurrentUser();
  if (user === null) return jsonError(401, "Log in to see your searches.");
  const { results } = await env.DB.prepare("SELECT * FROM jobs WHERE user_id = ? ORDER BY created_at DESC LIMIT ?")
    .bind(user.id, RECENT_JOBS)
    .all<JobRow>();
  return json({ jobs: results.map(toJobView) });
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
  const unavailable = usesWorldFilters(config) ? worldFiltersUnavailable(config.platform) : undefined;
  if (unavailable) return jsonError(503, unavailable);

  const { RUNPOD_ENDPOINT_ID: endpointId, RUNPOD_API_KEY: apiKey, RUNPOD_WEBHOOK_SECRET: webhookSecret } = env;
  if (!endpointId || !apiKey || !webhookSecret) return jsonError(503, "Seed searches aren't live yet.");

  const job = validation.value;
  const reserved = creditsToUnits(job.maxCost);
  const id = crypto.randomUUID();
  const now = Date.now();
  const [reservation] = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO jobs (id, user_id, status, config, wanted, max_cost, created_at, updated_at)
       SELECT ?1, id, 'queued', ?2, ?3, ?4, ?5, ?5 FROM users WHERE id = ?6 AND credit_units >= ?4`,
    ).bind(id, JSON.stringify(job.config), job.wanted, reserved, now, user.id),
    env.DB.prepare("UPDATE users SET credit_units = credit_units - ? WHERE id = ? AND EXISTS (SELECT 1 FROM jobs WHERE id = ?)")
      .bind(reserved, user.id, id),
  ]);
  if (reservation.meta.changes === 0) {
    return jsonError(
      402,
      `Max cost is ${formatCredits(job.maxCost)} credits but you have ${formatCredits(unitsToCredits(user.credit_units))}. Lower it or wait for the 00:00 UTC refill.`,
    );
  }

  const body = runpodRunBody(job, webhookUrl(env.PUBLIC_ORIGIN || new URL(request.url).origin, id, webhookSecret));
  const runpodId = await dispatchToRunpod({ endpointId, apiKey }, body).catch(() => null);
  if (runpodId === null) {
    await settleJob(
      env.DB,
      { id, user_id: user.id, max_cost: reserved },
      { status: "failed", costUnits: 0, result: null, error: DISPATCH_FAILED },
    );
    return jsonError(502, DISPATCH_FAILED);
  }

  const row = await env.DB.prepare("UPDATE jobs SET runpod_id = ?, updated_at = ? WHERE id = ? RETURNING *")
    .bind(runpodId, Date.now(), id)
    .first<JobRow>();
  return json({ job: row && toJobView(row) }, 201);
}
