import MapRoutePage, { type MapPageProps, mapRouteMetadata } from "@/components/map/MapRoutePage";

export const generateMetadata = mapRouteMetadata;

export default function MapPage(props: MapPageProps) {
    return <MapRoutePage {...props}/>;
}
