import { MAX_ACTIVE_SEARCHES } from "./job-events";
import type { JobRequest } from "./seedfinder-config";
import type { JobView } from "./server/jobs";

export interface SessionUser {
    id: string;
    username: string;
    globalName: string | null;
    avatarUrl: string | null;
    credits: number;
    dailyCredits: number;
    resetsAt: string;
}

export type { JobView };

/** A failed API call; `jobId` names a search that is already going when a new one is refused (409). */
export class ApiError extends Error {
    constructor(
        message: string,
        readonly status: number,
        readonly jobId: string | null = null
    ) {
        super(message);
    }
}

const FRIENDLY_ERRORS: Record<number, string> = {
    401: "You've been logged out. Log in again to search.",
    402: "Not enough credits for this max cost. Credits refill at 00:00 UTC.",
    409: `You already have ${MAX_ACTIVE_SEARCHES} searches going.`,
    429: "Too many requests. Wait a bit and try again."
};

async function request<T extends object>(path: string, init?: RequestInit): Promise<T> {
    const response = await fetch(path, { credentials: "same-origin", ...init }).catch(() => {
        throw new ApiError("Couldn't reach the server. Check your connection and try again.", 0);
    });
    const parsed: unknown = await response.json().catch(() => null);
    const body = typeof parsed === "object" && parsed !== null ? (parsed as T & {
        error?: unknown;
        jobId?: unknown
    }) : null;
    if (response.ok && body !== null) return body;
    const message = typeof body?.error === "string" ? body.error : FRIENDLY_ERRORS[response.status];
    const jobId = typeof body?.jobId === "string" ? body.jobId : null;
    throw new ApiError(message ?? `Something went wrong (error ${response.status}). Try again.`, response.status, jobId);
}

/** The Discord login URL; navigate to it rather than fetching it. */
export function loginUrl(returnTo = "/"): string {
    return `/api/auth/login?return=${encodeURIComponent(returnTo)}`;
}

/** The live event stream of a search, for an `EventSource`. */
export function jobEventsUrl(jobId: string): string {
    return `/api/jobs/${encodeURIComponent(jobId)}/events`;
}

export async function fetchMe(): Promise<SessionUser | null> {
    return (await request<{ user: SessionUser | null }>("/api/me")).user;
}

export async function fetchJobs(): Promise<JobView[]> {
    return (await request<{ jobs: JobView[] }>("/api/jobs")).jobs;
}

/** Starts a search. Throws an `ApiError` with status 409 when `MAX_ACTIVE_SEARCHES` searches are already going. */
export async function createJob(job: JobRequest): Promise<JobView> {
    const created = await request<{ job: JobView }>("/api/jobs", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(job)
    });
    return created.job;
}

export async function cancelJob(jobId: string): Promise<JobView> {
    return (await request<{ job: JobView }>(`/api/jobs/${encodeURIComponent(jobId)}/cancel`, { method: "POST" })).job;
}

export async function logout(): Promise<void> {
    await request<object>("/api/auth/logout", { method: "POST" });
}
