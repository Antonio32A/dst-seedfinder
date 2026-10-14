import type { GameBuild } from "@/lib/config/game-builds";
import type { Platform, Shard } from "@/lib/config/seedfinder-config";
import { encodeMapView, type MapSeed, parseMapRoute, parseMapView } from "@/lib/world-map/map-route";
import type { LinkedView } from "@/lib/world-map/view/map-view";

export const MAP_PREVIEW_VERSION = 1;
export const MAP_PREVIEW_SIZE = { width: 1200, height: 630 };

const PREVIEW_PATH = /^\/og\/map\/([^/]+)\/(.+)\.png$/;

export interface MapPreviewRequest {
    platform: Platform;
    shard: Shard;
    build: GameBuild;
    seed: number;
    view?: string;
    key: string;
    dumpKey: string;
}

const renderOf = (build: GameBuild) => `${build}.${MAP_PREVIEW_VERSION}`;

/** A map's preview image lives at `/og/map/<platform>/[caves/]<build>/<seed>.png`, the map's route as a picture. */
export function mapPreviewPath({ platform, shard, build, seed }: MapSeed, view?: LinkedView) {
    const query = [view && `v=${encodeMapView(view)}`, `r=${renderOf(build)}`].filter(Boolean).join("&");
    return `/og/map/${platform}/${shard === "caves" ? "caves/" : ""}${build}/${seed}.png?${query}`;
}

export function parseMapPreviewUrl(url: URL): MapPreviewRequest | { error: string } {
    const match = PREVIEW_PATH.exec(url.pathname);
    if (match === null) return { error: "There's no map preview here." };

    const [, platform, segments] = match;
    const route = parseMapRoute(platform, segments.split("/"));
    if ("error" in route) return route;

    const linked = parseMapView(url.searchParams.get("v") ?? undefined);
    const view = linked && encodeMapView(linked);
    const render = renderOf(route.build);
    const world = `${route.platform}/${route.shard}/${route.seed}`;
    return {
        ...route,
        view,
        key: `previews/${render}/${world}/${view ?? "full"}.png`,
        dumpKey: `dumps/${render}/${world}.dstw`
    };
}
