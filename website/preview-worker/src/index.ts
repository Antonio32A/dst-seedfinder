import { type MapPreviewRequest, parseMapPreviewUrl } from "@/lib/world-map/map-preview-url";
import type { RenderOutcome } from "./map-renderer";

export { MapRenderer } from "./map-renderer";

const RENDERERS = 4;
const IMAGE_CACHE = "public, max-age=31536000, immutable";
const NO_MAP_CACHE = "public, max-age=86400";

const image = (body: BodyInit) => new Response(body, {
    headers: {
        "Content-Type": "image/png",
        "Cache-Control": IMAGE_CACHE
    }
});

const failure = (status: number, reason: string, cacheControl = "no-store", retryAfter?: number) => new Response(reason, {
    status,
    headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": cacheControl,
        "X-Map-Preview-Error": reason.replace(/[^\x20-\x7e]/g, " ").slice(0, 300),
        ...(retryAfter === undefined ? {} : { "Retry-After": String(retryAfter) })
    }
});

const fnv1a = (text: string) =>
    [...text].reduce((hash, char) => Math.imul(hash ^ char.charCodeAt(0), 16777619) >>> 0, 2166136261);

function outcomeResponse(outcome: RenderOutcome): Response {
    switch (outcome.status) {
        case "rendered":
            return image(outcome.image);
        case "no-map":
            return failure(404, outcome.reason, NO_MAP_CACHE);
        case "limited":
            return failure(429, "Too many new map previews from here. Try again in a minute.", "no-store", 60);
        case "busy":
            return failure(503, "Too many map previews are being drawn. Try again shortly.", "no-store", 10);
        case "failed":
            return failure(503, outcome.reason, "no-store", 30);
    }
}

async function previewResponse(env: Env, preview: MapPreviewRequest, client: string): Promise<Response> {
    const stored = await env.PREVIEWS.get(preview.key);
    if (stored !== null) return image(stored.body);
    const renderer = env.MAP_RENDERER.getByName(`renderer-${fnv1a(preview.key) % RENDERERS}`);
    const outcome = await renderer.render(preview, client).catch((error: unknown): RenderOutcome => ({
        status: "failed",
        reason: String(error)
    }));
    return outcomeResponse(outcome);
}

export default {
    async fetch(request, env, ctx) {
        if (request.method !== "GET" && request.method !== "HEAD") {
            return new Response(null, {
                status: 405,
                headers: { Allow: "GET, HEAD" }
            });
        }

        const url = new URL(request.url);
        const preview = parseMapPreviewUrl(url);
        if ("error" in preview) return failure(404, preview.error, NO_MAP_CACHE);

        const cacheKey = new Request(new URL(`/og/${preview.key}`, url));
        const cached = await caches.default.match(cacheKey);
        if (cached !== undefined) return cached;

        const response = await previewResponse(env, preview, request.headers.get("CF-Connecting-IP") ?? "unknown");
        if (response.headers.get("Cache-Control") !== "no-store") ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
        return response;
    }
} satisfies ExportedHandler<Env>;
