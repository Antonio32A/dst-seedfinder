import { env } from "cloudflare:workers";

/** Never cached: every API response is per user or per request. */
export function json(body: unknown, status = 200): Response {
    return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

export function jsonError(status: number, error: string): Response {
    return json({ error }, status);
}

export function text(status: number, body: string, headers: Record<string, string> = {}): Response {
    return new Response(body, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

export function clientIp(request: Request): string | null {
    return request.headers.get("CF-Connecting-IP");
}

export function isCrossOrigin(request: Request): boolean {
    const site = request.headers.get("Sec-Fetch-Site");
    const origin = request.headers.get("Origin");
    const ours = [new URL(request.url).origin, env.PUBLIC_ORIGIN];
    return (site !== null && site !== "same-origin") || (origin !== null && !ours.includes(origin));
}

export async function readBody(request: Request, maxBytes: number): Promise<Uint8Array<ArrayBuffer> | null> {
    if (Number(request.headers.get("Content-Length")) > maxBytes) return null;
    if (request.body === null) return new Uint8Array();
    const reader = request.body.getReader();
    const parts: Uint8Array<ArrayBuffer>[] = [];
    let size = 0;
    for (; ;) {
        const { done, value } = await reader.read();
        if (done) return new Uint8Array(await new Blob(parts).arrayBuffer());
        size += value.byteLength;
        if (size > maxBytes) {
            await reader.cancel().catch(() => undefined);
            return null;
        }
        parts.push(value);
    }
}
