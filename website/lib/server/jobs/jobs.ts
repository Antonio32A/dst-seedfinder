import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { unitsToCredits } from "@/lib/jobs/credits";
import {
    ACTIVE_JOB_STATUSES,
    type ActiveJobStatus,
    type FinishedJobStatus,
    type JobStatus,
    type JobView,
    type Machine,
    MAX_ACTIVE_SEARCHES
} from "@/lib/jobs/job-events";

export const ACTIVE_STATUS_SQL = ACTIVE_JOB_STATUSES.map((status) => `'${status}'`).join(", ");

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
    instance_id: string | null;
    machine: string | null;
    started_at: number | null;
    finished_at: number | null;
}

export interface JobSettlement {
    status: FinishedJobStatus;
    costUnits: number;
    result: string | null;
    error: string | null;
}

export interface ActiveJobUpdate {
    status: ActiveJobStatus;
    instanceId?: string;
    machine?: Machine;
    startedAt?: number;
}

const isoOrNull = (ms: number | null) => (ms === null ? null : new Date(ms).toISOString());

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
        startedAt: isoOrNull(row.started_at),
        machine: row.machine === null ? null : (JSON.parse(row.machine) as Machine),
        result: row.result === null ? null : JSON.parse(row.result),
        error: row.error
    };
}

export async function loadJob(db: D1Database, id: string): Promise<JobRow | null> {
    return db.prepare("SELECT * FROM jobs WHERE id = ?").bind(id).first<JobRow>();
}

/** Records a search moving between its active statuses. A no-op once the search is settled. */
export async function updateActiveJob(db: D1Database, id: string, update: ActiveJobUpdate): Promise<void> {
    await db
        .prepare(
            `UPDATE jobs SET status = ?, instance_id = COALESCE(?, instance_id), machine = COALESCE(?, machine),
         started_at = COALESCE(?, started_at), updated_at = ?
       WHERE id = ? AND cost IS NULL`
        )
        .bind(
            update.status,
            update.instanceId ?? null,
            update.machine ? JSON.stringify(update.machine) : null,
            update.startedAt ?? null,
            Date.now(),
            id
        )
        .run();
}

/**
 * Settles a job exactly once: refunds the unused part of its reservation and records
 * the outcome, both only while the job is still unsettled (`cost IS NULL`), then deletes the user's settled searches
 * other than the `MAX_ACTIVE_SEARCHES` last finished ones. Runs as one D1 batch, so it is atomic and a repeated call is
 * a no-op.
 */
export async function settleJob(
    db: D1Database,
    job: Pick<JobRow, "id" | "user_id" | "max_cost">,
    settlement: JobSettlement
): Promise<void> {
    const now = Date.now();
    await db.batch([
        db
            .prepare(
                "UPDATE users SET credit_units = credit_units + ? WHERE id = ? AND EXISTS (SELECT 1 FROM jobs WHERE id = ? AND cost IS NULL)"
            )
            .bind(job.max_cost - settlement.costUnits, job.user_id, job.id),
        db
            .prepare(
                "UPDATE jobs SET status = ?, cost = ?, result = ?, error = ?, updated_at = ?, finished_at = ? WHERE id = ? AND cost IS NULL"
            )
            .bind(settlement.status, settlement.costUnits, settlement.result, settlement.error, now, now, job.id),
        db
            .prepare(
                `DELETE FROM jobs WHERE user_id = ?1 AND cost IS NOT NULL AND id NOT IN (
           SELECT id FROM jobs WHERE user_id = ?1 AND cost IS NOT NULL ORDER BY finished_at DESC LIMIT ?2
         )`
            )
            .bind(job.user_id, MAX_ACTIVE_SEARCHES)
    ]);
}
