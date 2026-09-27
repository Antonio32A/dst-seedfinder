import MapScreen from "@/components/map/MapScreen";
import { parseMapRoute } from "@/lib/world-map/map-route";

export default async function MapPage({ params, searchParams }: {
    params: Promise<{ platform: string; seed: string }>;
    searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
    const { platform, seed } = await params;
    const { c: share } = await searchParams;
    return <MapScreen route={parseMapRoute(platform, seed)} share={typeof share === "string" ? share : undefined}/>;
}
