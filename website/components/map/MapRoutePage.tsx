import type { Metadata } from "next";
import MapScreen from "@/components/map/MapScreen";
import { LATEST_BUILD } from "@/lib/config/game-builds";
import { PLATFORM_LABELS, SHARD_LABELS } from "@/lib/config/seedfinder-config";
import { siteName } from "@/lib/site-metadata";
import { MAP_PREVIEW_SIZE, mapPreviewPath } from "@/lib/world-map/map-preview-url";
import { parseMapRoute, parseMapView } from "@/lib/world-map/map-route";

export interface MapPageProps {
    params: Promise<{ platform: string; rest: string[] }>;
    searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export async function mapRouteMetadata({ params, searchParams }: MapPageProps): Promise<Metadata> {
    const { platform, rest } = await params;
    const route = parseMapRoute(platform, rest);
    if ("error" in route) return {};
    const build = route.build === LATEST_BUILD ? "" : `, build ${route.build}`;
    const title = `Seed ${route.seed} (${PLATFORM_LABELS[route.platform]} ${SHARD_LABELS[route.shard].toLowerCase()}${build})`;
    const image = mapPreviewPath(route, parseMapView((await searchParams).v));
    return {
        description: null,
        openGraph: {
            type: "website",
            siteName: siteName(),
            title,
            images: [{ url: image, ...MAP_PREVIEW_SIZE }]
        },
        twitter: { card: "summary_large_image", title, description: null, images: [image] }
    };
}

export default async function MapRoutePage({ params, searchParams }: MapPageProps) {
    const { platform, rest } = await params;
    const { c: share, v: view } = await searchParams;
    return <MapScreen route={parseMapRoute(platform, rest)} share={typeof share === "string" ? share : undefined}
                      view={parseMapView(view)}/>;
}
