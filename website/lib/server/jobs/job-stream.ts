import type { JobEvent } from "@/lib/jobs/job-events";
import { parseJobResult } from "@/lib/jobs/job-result";
import { type JobRow, toJobView } from "./jobs";

export const SSE_HEADERS = {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Accel-Buffering": "no"
};

const encoder = new TextEncoder();

export function sseFrame(event: JobEvent): Uint8Array {
    return encoder.encode(`data: ${JSON.stringify(event)}\n\n`);
}

export const SSE_HEARTBEAT = encoder.encode(": ping\n\n");

export function finishedEvents(row: JobRow): JobEvent[] {
    const job = toJobView(row);
    const parsed = parseJobResult(job.result);
    const hits = parsed?.kind === "search" ? parsed.search.hits : [];
    return [
        { type: "status", status: job.status, queuePosition: null, machine: job.machine, attempt: null },
        ...hits.map((hit): JobEvent => ({ type: "hit", hit })),
        { type: "end", job }
    ];
}

export function closedEventStream(events: JobEvent[]): Response {
    const body = new ReadableStream<Uint8Array>({
        start(controller) {
            events.forEach((event) => controller.enqueue(sseFrame(event)));
            controller.close();
        }
    });
    return new Response(body, { headers: SSE_HEADERS });
}
