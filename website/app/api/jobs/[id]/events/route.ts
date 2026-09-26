import { env } from "cloudflare:workers";
import { getCurrentUser } from "@/lib/server/auth/session";
import { jsonError } from "@/lib/server/http";
import { jobRoomStub } from "@/lib/server/jobs/dispatcher";
import { closedEventStream, finishedEvents } from "@/lib/server/jobs/job-stream";
import { loadUserJob } from "@/lib/server/jobs/jobs";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
    const user = await getCurrentUser();
    if (user === null) return jsonError(401, "Log in to see your searches.");
    const { id } = await params;
    const row = await loadUserJob(env.DB, id, user.id);
    if (row === null) return jsonError(404, "Search not found.");
    if (row.cost !== null) return closedEventStream(finishedEvents(row));
    return jobRoomStub(env, id).events();
}
