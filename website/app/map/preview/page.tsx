import type { Metadata } from "next";
import MapPreview from "@/components/map/MapPreview";

export const metadata: Metadata = { robots: { index: false } };

export default function MapPreviewPage() {
    return <MapPreview/>;
}
