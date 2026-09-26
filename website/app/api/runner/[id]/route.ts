import { env } from "cloudflare:workers";
import { MAX_CHUNK_BYTES } from "@/lib/jobs/runner-output";
import { text } from "@/lib/server/http";
import { jobRoomStub } from "@/lib/server/jobs/dispatcher";

const RUNNER_AUTHORIZATION = /^Bearer [0-9a-f]{64}$/;

async function readChunk(request: Request): Promise<Uint8Array | Response> {
    if (request.body === null) return new Uint8Array();
    const reader = request.body.getReader();
    const parts: Uint8Array[] = [];
    let size = 0;
    for (; ;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_CHUNK_BYTES) {
            await reader.cancel().catch(() => undefined);
            return text(413, "Chunk too large.");
        }
        parts.push(value);
    }
    const body = new Uint8Array(size);
    let at = 0;
    for (const part of parts) {
        body.set(part, at);
        at += part.byteLength;
    }
    return body;
}

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
    const { id } = await params;
    const authorization = request.headers.get("Authorization");
    if (!RUNNER_AUTHORIZATION.test(authorization ?? "")) return text(401, "Bad token.");
    return jobRoomStub(env, id).runnerConfig(authorization);
}

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
    const { id } = await params;
    const authorization = request.headers.get("Authorization");
    if (!RUNNER_AUTHORIZATION.test(authorization ?? "")) return text(401, "Bad token.");
    if (Number(request.headers.get("Content-Length")) > MAX_CHUNK_BYTES) return text(413, "Chunk too large.");
    const body = await readChunk(request).catch(() => text(400, "Unreadable body."));
    if (body instanceof Response) return body;
    return jobRoomStub(env, id).runnerOutput(authorization, request.headers.get("X-Offset"), request.headers.get("X-Exit"), body);
}
