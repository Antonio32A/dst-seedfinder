/** A JSON response that is never cached, since every API response is per user or per request. */
export function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

export function jsonError(status: number, error: string): Response {
  return json({ error }, status);
}

export function clientIp(request: Request): string | null {
  return request.headers.get("CF-Connecting-IP");
}

/** Whether a browser sent this request from a page on another origin, which state-changing routes refuse. */
export function isCrossOrigin(request: Request): boolean {
  const site = request.headers.get("Sec-Fetch-Site");
  return site !== null && site !== "same-origin";
}

/** Headers that make a page cross-origin isolated, which the browser search needs for WebAssembly threads. */
export const CROSS_ORIGIN_ISOLATION = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
};
