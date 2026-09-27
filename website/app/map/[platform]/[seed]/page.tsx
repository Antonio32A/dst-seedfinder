import MapScreen from "@/components/map/MapScreen";
import { parseMapRoute } from "@/lib/world-map/map-route";

export default async function MapPage({ params }: { params: Promise<{ platform: string; seed: string }> }) {
    const { platform, seed } = await params;
    return <MapScreen route={parseMapRoute(platform, seed)}/>;
}
