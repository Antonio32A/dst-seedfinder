import { mapPreviewPath } from "@/lib/world-map/map-preview-url";
import { parseMapRoute, parseMapView } from "@/lib/world-map/map-route";

const MAP_PAGE = /^\/map\/([^/]+)\/(.+)$/;
const UNFURL_CRAWLER =
    /Discordbot|Slackbot|Twitterbot|facebookexternalhit|meta-externalagent|TelegramBot|WhatsApp|LinkedInBot|redditbot|Mastodon|Bluesky|Iframely|Embedly|SkypeUriPreview|vkShare|Pinterest/i;

export const isMapPreviewPath = (url: URL) => url.pathname.startsWith("/og/");

export function prewarmMapPreview(request: Request, env: Cloudflare.Env, ctx: ExecutionContext) {
    if (request.method !== "GET" || !UNFURL_CRAWLER.test(request.headers.get("User-Agent") ?? "")) return;
    const url = new URL(request.url);
    const page = MAP_PAGE.exec(url.pathname);
    if (page === null) return;

    const [, platform, segments] = page;
    const route = parseMapRoute(platform, segments.split("/"));
    if ("error" in route) return;

    const preview = new URL(mapPreviewPath(route, parseMapView(url.searchParams.get("v") ?? undefined)), url);
    const client = request.headers.get("CF-Connecting-IP");
    ctx.waitUntil(
        env.MAP_PREVIEW.fetch(preview, { headers: client === null ? {} : { "CF-Connecting-IP": client } })
            .then((response) => response.body?.cancel())
            .catch((error: unknown) => console.warn(`The map preview ${preview.pathname} couldn't be pre-warmed: ${error}`))
    );
}
