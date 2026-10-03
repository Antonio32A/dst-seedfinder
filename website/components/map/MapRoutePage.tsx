import type { Metadata } from "next";
import MapScreen from "@/components/map/MapScreen";
import { PLATFORM_LABELS, type Shard, SHARD_LABELS } from "@/lib/config/seedfinder-config";
import { siteName } from "@/lib/site-metadata";
import { MAP_PREVIEW_SIZE, mapPreviewPath } from "@/lib/world-map/map-preview-url";
import { parseMapRoute, parseMapView } from "@/lib/world-map/map-route";

export interface MapPageProps {
    params: Promise<{ platform: string; seed: string }>;
    searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export async function mapRouteMetadata(shard: Shard, { params, searchParams }: MapPageProps): Promise<Metadata> {
    const { platform, seed } = await params;
    const route = parseMapRoute(platform, seed, shard);
    if ("error" in route) return {};
    const title = `Seed ${route.seed} (${PLATFORM_LABELS[route.platform]} ${SHARD_LABELS[shard].toLowerCase()})`;
    const image = mapPreviewPath(route.platform, route.seed, shard, parseMapView((await searchParams).v));
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

export default async function MapRoutePage({ shard, params, searchParams }: MapPageProps & { shard: Shard }) {
    const { platform, seed } = await params;
    const { c: share, v: view } = await searchParams;
    return <MapScreen route={parseMapRoute(platform, seed, shard)} share={typeof share === "string" ? share : undefined}
                      view={parseMapView(view)}/>;
}
