import { env } from "cloudflare:workers";
import { getCurrentUser } from "@/lib/server/auth/session";
import { json, jsonError } from "@/lib/server/http";
import { type JobRow, toJobView } from "@/lib/server/jobs/jobs";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
    const user = await getCurrentUser();
    if (user === null) return jsonError(401, "Log in to see your searches.");
    const { id } = await params;
    const row = await env.DB.prepare("SELECT * FROM jobs WHERE id = ? AND user_id = ?").bind(id, user.id).first<JobRow>();
    if (row === null) return jsonError(404, "Search not found.");
    return json({ job: toJobView(row) });
}
