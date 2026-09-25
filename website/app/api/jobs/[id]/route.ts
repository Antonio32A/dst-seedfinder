import { env } from "cloudflare:workers";
import { json, jsonError } from "@/lib/server/http";
import { toJobView, type JobRow } from "@/lib/server/jobs";
import { getCurrentUser } from "@/lib/server/session";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const user = await getCurrentUser();
  if (user === null) return jsonError(401, "Log in to see your searches.");
  const { id } = await params;
  const row = await env.DB.prepare("SELECT * FROM jobs WHERE id = ? AND user_id = ?").bind(id, user.id).first<JobRow>();
  if (row === null) return jsonError(404, "Search not found.");
  return json({ job: toJobView(row) });
}
