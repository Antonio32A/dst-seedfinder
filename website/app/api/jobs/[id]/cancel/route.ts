import { env } from "cloudflare:workers";
import { isActiveStatus } from "@/lib/job-events";
import { jobRoomStub } from "@/lib/server/dispatcher";
import { isCrossOrigin, json, jsonError } from "@/lib/server/http";
import { loadJob, toJobView, type JobRow } from "@/lib/server/jobs";
import { getCurrentUser } from "@/lib/server/session";

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  if (isCrossOrigin(request)) return jsonError(403, "Requests from other sites aren't allowed.");
  const user = await getCurrentUser();
  if (user === null) return jsonError(401, "Log in to cancel a search.");
  const { id } = await params;
  const row = await env.DB.prepare("SELECT * FROM jobs WHERE id = ? AND user_id = ?").bind(id, user.id).first<JobRow>();
  if (row === null) return jsonError(404, "Search not found.");
  if (isActiveStatus(row.status)) {
    const cancelled = await jobRoomStub(env, id).cancel().then(
      () => true,
      () => false,
    );
    if (!cancelled) return jsonError(502, "Couldn't cancel the search. Try again.");
  }
  const settled = await loadJob(env.DB, id);
  return json({ job: toJobView(settled ?? row) });
}
