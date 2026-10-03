import MapRoutePage, { type MapPageProps, mapRouteMetadata } from "@/components/map/MapRoutePage";

export const generateMetadata = (props: MapPageProps) => mapRouteMetadata("caves", props);

export default function MapPage(props: MapPageProps) {
    return <MapRoutePage shard="caves" {...props}/>;
}
