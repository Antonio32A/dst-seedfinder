import MapScreen from "@/components/map/MapScreen";
import type { Shard } from "@/lib/config/seedfinder-config";
import { parseMapRoute, parseMapView } from "@/lib/world-map/map-route";

export interface MapPageProps {
    params: Promise<{ platform: string; seed: string }>;
    searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function MapRoutePage({ shard, params, searchParams }: MapPageProps & { shard: Shard }) {
    const { platform, seed } = await params;
    const { c: share, v: view } = await searchParams;
    return <MapScreen route={parseMapRoute(platform, seed, shard)} share={typeof share === "string" ? share : undefined}
                      view={parseMapView(view)}/>;
}
