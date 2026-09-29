import MapRoutePage, { type MapPageProps } from "@/components/map/MapRoutePage";

export default function MapPage(props: MapPageProps) {
    return <MapRoutePage shard="forest" {...props}/>;
}
