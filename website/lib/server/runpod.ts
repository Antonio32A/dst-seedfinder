import { creditsToSeconds } from "@/lib/credits";
import { DEFAULT_START_SEED, type JobRequest, type SeedfinderConfig } from "@/lib/seedfinder-config";

export const EXECUTION_GRACE_MS = 10_000;

interface RunpodRunBody {
  input: { config: SeedfinderConfig; limit: number; time_limit: number; start_seed: number };
  policy: { executionTimeout: number };
  webhook: string;
}

/** The webhook RunPod calls when a job ends, carrying our job id and the shared secret. */
export function webhookUrl(origin: string, jobId: string, secret: string): string {
  const url = new URL("/api/runpod/webhook", origin);
  url.searchParams.set("job", jobId);
  url.searchParams.set("token", secret);
  return url.toString();
}

/**
 * The `/run` body for a search: the binary's `--limit`, `--time-limit` (seconds) and `--start-seed` as `limit`,
 * `time_limit` and `start_seed`, and a hard RunPod execution timeout of the time limit plus a fixed grace, so billing can't run past the max cost.
 */
export function runpodRunBody({ config, wanted, maxCost, startSeed }: JobRequest, webhook: string): RunpodRunBody {
  const timeLimit = creditsToSeconds(maxCost);
  return {
    input: { config, limit: wanted, time_limit: timeLimit, start_seed: startSeed ?? DEFAULT_START_SEED },
    policy: { executionTimeout: Math.round(timeLimit * 1000) + EXECUTION_GRACE_MS },
    webhook,
  };
}

/** Queues a seed search on the RunPod serverless endpoint and returns RunPod's job id. Throws on failure. */
export async function dispatchToRunpod({ endpointId, apiKey }: { endpointId: string; apiKey: string }, body: RunpodRunBody): Promise<string> {
  const response = await fetch(`https://api.runpod.ai/v2/${encodeURIComponent(endpointId)}/run`, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`RunPod responded ${response.status}`);
  const { id } = (await response.json()) as { id?: unknown };
  if (typeof id !== "string") throw new Error("RunPod response had no job id");
  return id;
}
