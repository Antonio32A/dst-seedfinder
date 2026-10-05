import { env } from "cloudflare:workers";
import type { NextRequest } from "next/server";
import { getCurrentUser, SESSION_COOKIE, sessionUserId } from "@/lib/server/auth/session";
import { jsonError } from "@/lib/server/http";
import { jobRoomStub } from "@/lib/server/jobs/dispatcher";
import { closedEventStream, finishedEvents } from "@/lib/server/jobs/job-stream";
import { loadUserJob } from "@/lib/server/jobs/jobs";

const SESSION_CHECK_MS = 60_000;

function whileSignedIn(events: ReadableStream<Uint8Array>, token: string): ReadableStream<Uint8Array> {
    const reader = events.getReader();
    const timer = setInterval(() => {
        void sessionUserId(token)
            .then((userId) => userId !== null, () => true)
            .then((signedIn) => (signedIn ? undefined : reader.cancel()))
            .catch(() => undefined);
    }, Number(env.EVENTS_SESSION_CHECK_MS) || SESSION_CHECK_MS);
    return new ReadableStream<Uint8Array>({
        async pull(controller) {
            const { done, value } = await reader.read();
            if (!done) return controller.enqueue(value);
            clearInterval(timer);
            controller.close();
        },
        cancel(reason) {
            clearInterval(timer);
            return reader.cancel(reason);
        }
    });
}

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = await getCurrentUser();
    if (user === null) return jsonError(401, "Log in to see your searches.");
    const { id } = await params;
    const row = await loadUserJob(env.DB, id, user.id);
    if (row === null) return jsonError(404, "Search not found.");
    if (row.cost !== null) return closedEventStream(finishedEvents(row));
    const live = await jobRoomStub(env, id).events();
    if (live.body === null) return live;
    return new Response(whileSignedIn(live.body, request.cookies.get(SESSION_COOKIE)?.value ?? ""), live);
}
