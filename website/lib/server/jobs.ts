import { unitsToCredits } from "@/lib/credits";
import type { SeedfinderConfig } from "@/lib/seedfinder-config";
import { DAILY_CREDIT_UNITS } from "./users";

export type JobStatus = "queued" | "running" | "done" | "failed" | "cancelled";

export interface JobRow {
  id: string;
  user_id: string;
  status: JobStatus;
  config: string;
  wanted: number;
  max_cost: number;
  cost: number | null;
  created_at: number;
  updated_at: number;
  result: string | null;
  error: string | null;
  runpod_id: string | null;
}

export interface JobView {
  id: string;
  status: JobStatus;
  config: SeedfinderConfig;
  wanted: number;
  maxCost: number;
  cost: number | null;
  createdAt: string;
  updatedAt: string;
  result: unknown;
  error: string | null;
}

export interface JobSettlement {
  status: Extract<JobStatus, "done" | "failed" | "cancelled">;
  costUnits: number;
  result: string | null;
  error: string | null;
  runpodId?: string;
}

export function toJobView(row: JobRow): JobView {
  return {
    id: row.id,
    status: row.status,
    config: JSON.parse(row.config) as SeedfinderConfig,
    wanted: row.wanted,
    maxCost: unitsToCredits(row.max_cost),
    cost: row.cost === null ? null : unitsToCredits(row.cost),
    createdAt: new Date(row.created_at).toISOString(),
    updatedAt: new Date(row.updated_at).toISOString(),
    result: row.result === null ? null : JSON.parse(row.result),
    error: row.error,
  };
}

/**
 * Settles a job exactly once: refunds the unused part of its reservation (never above the daily grant) and records
 * the outcome, both only while the job is still unsettled (`cost IS NULL`). Runs as one D1 batch, so it is atomic and
 * a repeated call is a no-op.
 */
export async function settleJob(
  db: D1Database,
  job: Pick<JobRow, "id" | "user_id" | "max_cost">,
  settlement: JobSettlement,
): Promise<void> {
  await db.batch([
    db
      .prepare(
        "UPDATE users SET credit_units = MIN(?, credit_units + ?) WHERE id = ? AND EXISTS (SELECT 1 FROM jobs WHERE id = ? AND cost IS NULL)",
      )
      .bind(DAILY_CREDIT_UNITS, job.max_cost - settlement.costUnits, job.user_id, job.id),
    db
      .prepare(
        `UPDATE jobs SET status = ?, cost = ?, result = ?, error = ?, runpod_id = COALESCE(runpod_id, ?), updated_at = ?
         WHERE id = ? AND cost IS NULL`,
      )
      .bind(
        settlement.status,
        settlement.costUnits,
        settlement.result,
        settlement.error,
        settlement.runpodId ?? null,
        Date.now(),
        job.id,
      ),
  ]);
}
