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
    return site !== null && site !== "same-origin";
}

/** Needed for WebAssembly threads in the browser search. */
export const CROSS_ORIGIN_ISOLATION = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp"
};
