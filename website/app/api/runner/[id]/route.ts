import { env } from "cloudflare:workers";
import type { JobStatus } from "@/lib/jobs/job-events";
import { MAX_CHUNK_BYTES } from "@/lib/jobs/runner-output";
import { readBody, text } from "@/lib/server/http";
import { jobRoomStub } from "@/lib/server/jobs/dispatcher";
import { RUNNER_GET_STATUSES, RUNNER_POST_STATUSES } from "@/lib/server/jobs/job-room";
import { JOB_ID } from "@/lib/server/jobs/jobs";

const RUNNER_AUTHORIZATION = /^Bearer [0-9a-f]{64}$/;

const RUNNER_STATUSES = new Set<JobStatus>([...RUNNER_GET_STATUSES, ...RUNNER_POST_STATUSES]);

async function refusal(request: Request, id: string): Promise<Response | null> {
    if (!RUNNER_AUTHORIZATION.test(request.headers.get("Authorization") ?? "")) return text(401, "Bad token.");
    if (!JOB_ID.test(id)) return text(410, "Gone.");
    const row = await env.DB.prepare("SELECT status FROM jobs WHERE id = ?").bind(id).first<{ status: JobStatus }>();
    return row !== null && RUNNER_STATUSES.has(row.status) ? null : text(410, "Gone.");
}

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
    const { id } = await params;
    const refused = await refusal(request, id);
    if (refused !== null) return refused;
    return jobRoomStub(env, id).runnerConfig(request.headers.get("Authorization"));
}

export function HEAD() {
    return text(405, "Method not allowed.", { Allow: "GET, OPTIONS, POST" });
}

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
    const { id } = await params;
    const refused = await refusal(request, id);
    if (refused !== null) return refused;
    const body = await readBody(request, MAX_CHUNK_BYTES).catch(() => text(400, "Unreadable body."));
    if (body === null) return text(413, "Chunk too large.");
    if (body instanceof Response) return body;
    const { headers } = request;
    return jobRoomStub(env, id).runnerOutput(headers.get("Authorization"), headers.get("X-Offset"), headers.get("X-Exit"), body);
}
