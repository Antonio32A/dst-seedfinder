import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import type { SearchHit } from "./job-result";

export const ACTIVE_JOB_STATUSES = ["queued", "starting", "running"] as const;
export const FINISHED_JOB_STATUSES = ["done", "failed", "cancelled"] as const;

/** Caps both a user's active searches and the finished searches kept for them. */
export const MAX_ACTIVE_SEARCHES = 3;

export type ActiveJobStatus = (typeof ACTIVE_JOB_STATUSES)[number];
export type FinishedJobStatus = (typeof FINISHED_JOB_STATUSES)[number];
export type JobStatus = ActiveJobStatus | FinishedJobStatus;

export interface Machine {
    cpuName: string;
    cores: number;
    ghz: number;
    dollarsPerHour: number;
}

export interface WorldProgress {
    generated: number;
    generating: number;
}

export interface JobProgress {
    scanned: number;
    hits: number;
    seedsPerSecond: number;
    worlds?: WorldProgress;
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
    startedAt: string | null;
    machine: Machine | null;
    result: unknown;
    error: string | null;
}

/** Sent as `data: <JSON>\n\n`. `queuePosition` and `attempt` are 1-based, and `end` closes the stream. */
export type JobEvent =
    | {
    type: "status";
    status: JobStatus;
    queuePosition: number | null;
    machine: Machine | null;
    attempt: number | null
}
    | { type: "progress"; progress: JobProgress }
    | { type: "hit"; hit: SearchHit }
    | { type: "end"; job: JobView };

export function isActiveStatus(status: JobStatus): status is ActiveJobStatus {
    return (ACTIVE_JOB_STATUSES as readonly JobStatus[]).includes(status);
}
