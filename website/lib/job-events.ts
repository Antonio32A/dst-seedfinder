import type { SearchHit } from "@/lib/job-result";
import type { JobView } from "@/lib/server/jobs";

export const ACTIVE_JOB_STATUSES = ["queued", "starting", "running"] as const;
export const FINISHED_JOB_STATUSES = ["done", "failed", "cancelled"] as const;

/** How many searches one user may have queued, starting or running at once, and how many of their searches are kept. */
export const MAX_ACTIVE_SEARCHES = 3;

export type ActiveJobStatus = (typeof ACTIVE_JOB_STATUSES)[number];
export type FinishedJobStatus = (typeof FINISHED_JOB_STATUSES)[number];
export type JobStatus = ActiveJobStatus | FinishedJobStatus;

/** The vast.ai machine a search runs on. */
export interface Machine {
  cpuName: string;
  cores: number;
  ghz: number;
  dollarsPerHour: number;
}

/**
 * How far a world-filter search is: seeds through the cheap level-table scan (`null` from finders that don't print it),
 * worlds fully generated so far, and worlds being generated right now.
 */
export interface WorldProgress {
  levels: number | null;
  generated: number;
  generating: number;
}

export interface JobProgress {
  scanned: number;
  hits: number;
  seedsPerSecond: number;
  worlds?: WorldProgress;
}

/**
 * One message of `GET /api/jobs/<id>/events`, sent as `data: <JSON>\n\n`. `status` has the 1-based queue position
 * (1 = next in line) while queued, and the machine and attempt (1 to 3) once one is picked; `end` carries the settled
 * job and closes the stream.
 */
export type JobEvent =
  | { type: "status"; status: JobStatus; queuePosition: number | null; machine: Machine | null; attempt: number | null }
  | { type: "progress"; progress: JobProgress }
  | { type: "hit"; hit: SearchHit }
  | { type: "end"; job: JobView };

/** Whether a search is still waiting, booting or running. */
export function isActiveStatus(status: JobStatus): status is ActiveJobStatus {
  return (ACTIVE_JOB_STATUSES as readonly JobStatus[]).includes(status);
}
