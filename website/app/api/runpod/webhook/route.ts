import { env } from "cloudflare:workers";
import { settledCostUnits } from "@/lib/credits";
import { json, jsonError } from "@/lib/server/http";
import { settleJob, type JobRow, type JobSettlement } from "@/lib/server/jobs";

interface RunpodWebhook {
  id?: unknown;
  status?: unknown;
  output?: unknown;
  executionTime?: unknown;
}

type Outcome = Pick<JobSettlement, "status" | "error">;

const OUTCOMES = new Map<unknown, Outcome>([
  ["COMPLETED", { status: "done", error: null }],
  ["FAILED", { status: "failed", error: "The search failed. Unused credits were refunded." }],
  ["CANCELLED", { status: "cancelled", error: "The search was cancelled. Unused credits were refunded." }],
  ["TIMED_OUT", { status: "failed", error: "The search didn't finish in time. Unused credits were refunded." }],
]);

const MAX_RESULT_BYTES = 1_000_000;
const RESULT_TOO_LARGE: Outcome = { status: "failed", error: "The search found more than can be saved. Unused credits were refunded." };

async function isWebhookToken(token: string | null, secret: string | undefined): Promise<boolean> {
  if (!token || !secret) return false;
  const encoder = new TextEncoder();
  const [given, expected] = await Promise.all(
    [token, secret].map((text) => crypto.subtle.digest("SHA-256", encoder.encode(text))),
  );
  const expectedBytes = new Uint8Array(expected);
  return new Uint8Array(given).reduce((difference, byte, index) => difference | (byte ^ expectedBytes[index]), 0) === 0;
}

export async function POST(request: Request) {
  const params = new URL(request.url).searchParams;
  if (!(await isWebhookToken(params.get("token"), env.RUNPOD_WEBHOOK_SECRET))) return jsonError(401, "Bad webhook token.");

  const payload = ((await request.json().catch(() => null)) ?? {}) as RunpodWebhook;
  if (typeof payload.id !== "string") return jsonError(400, "The webhook has no RunPod job id.");
  const outcome = OUTCOMES.get(payload.status);
  if (outcome === undefined) return json({ settled: false });

  const job = await env.DB.prepare(
    "SELECT id, user_id, max_cost FROM jobs WHERE id = ?1 AND (runpod_id IS NULL OR runpod_id = ?2)",
  )
    .bind(params.get("job"), payload.id)
    .first<Pick<JobRow, "id" | "user_id" | "max_cost">>();
  if (job === null) return jsonError(404, "No such job.");

  const result = payload.output === undefined ? null : JSON.stringify(payload.output);
  const fits = result === null || new TextEncoder().encode(result).byteLength <= MAX_RESULT_BYTES;
  await settleJob(env.DB, job, {
    ...(fits ? outcome : RESULT_TOO_LARGE),
    costUnits: settledCostUnits(job.max_cost, payload.executionTime),
    result: fits ? result : null,
    runpodId: payload.id,
  });
  return json({ settled: true });
}
