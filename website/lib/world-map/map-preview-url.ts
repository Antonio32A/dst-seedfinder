import { GAME_BUILD } from "@/lib/catalog/world";
import type { Platform, Shard } from "@/lib/config/seedfinder-config";
import { encodeMapView, parseMapRoute, parseMapView } from "@/lib/world-map/map-route";
import type { LinkedView } from "@/lib/world-map/view/map-view";

export const MAP_PREVIEW_VERSION = 1;
export const MAP_PREVIEW_SIZE = { width: 1200, height: 630 };

const RENDER = `${GAME_BUILD}.${MAP_PREVIEW_VERSION}`;
const PREVIEW_PATH = /^\/og\/map\/([^/]+)\/(?:(caves)\/)?([^/]+)\.png$/;

export interface MapPreviewRequest {
    platform: Platform;
    shard: Shard;
    seed: number;
    view?: string;
    key: string;
    dumpKey: string;
}

export function mapPreviewPath(platform: Platform, seed: number, shard: Shard, view?: LinkedView) {
    const query = [view && `v=${encodeMapView(view)}`, `r=${RENDER}`].filter(Boolean).join("&");
    return `/og/map/${platform}/${shard === "caves" ? "caves/" : ""}${seed}.png?${query}`;
}

export function parseMapPreviewUrl(url: URL): MapPreviewRequest | { error: string } {
    const match = PREVIEW_PATH.exec(url.pathname);
    if (match === null) return { error: "There's no map preview here." };

    const [, platform, caves, seed] = match;
    const route = parseMapRoute(platform, seed, caves === undefined ? "forest" : "caves");
    if ("error" in route) return route;

    const linked = parseMapView(url.searchParams.get("v") ?? undefined);
    const view = linked && encodeMapView(linked);
    const world = `${route.platform}/${route.shard}/${route.seed}`;
    return {
        ...route,
        view,
        key: `previews/${RENDER}/${world}/${view ?? "full"}.png`,
        dumpKey: `dumps/${RENDER}/${world}.dstw`
    };
}
