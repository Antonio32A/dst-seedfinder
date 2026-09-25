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

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

const FRIENDLY_ERRORS: Record<number, string> = {
  401: "You've been logged out. Log in again to search.",
  402: "Not enough credits for this max cost. Credits refill at 00:00 UTC.",
  429: "Too many requests. Wait a bit and try again.",
};

async function request<T extends object>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, { credentials: "same-origin", ...init }).catch(() => {
    throw new ApiError("Couldn't reach the server. Check your connection and try again.", 0);
  });
  const parsed: unknown = await response.json().catch(() => null);
  const body = typeof parsed === "object" && parsed !== null ? (parsed as T & { error?: unknown }) : null;
  if (response.ok && body !== null) return body;
  const message = typeof body?.error === "string" ? body.error : FRIENDLY_ERRORS[response.status];
  throw new ApiError(message ?? `Something went wrong (error ${response.status}). Try again.`, response.status);
}

/** The Discord login URL; navigate to it rather than fetching it. */
export function loginUrl(returnTo = "/"): string {
  return `/api/auth/login?return=${encodeURIComponent(returnTo)}`;
}

export async function fetchMe(): Promise<SessionUser | null> {
  return (await request<{ user: SessionUser | null }>("/api/me")).user;
}

export async function fetchJobs(): Promise<JobView[]> {
  return (await request<{ jobs: JobView[] }>("/api/jobs")).jobs;
}

export async function createJob(job: JobRequest): Promise<{ job: JobView | null }> {
  return request<{ job: JobView | null }>("/api/jobs", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(job),
  });
}

export async function logout(): Promise<void> {
  await request<object>("/api/auth/logout", { method: "POST" });
}
