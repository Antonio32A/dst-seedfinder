"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useEffect, useState } from "react";
import Brand from "@/components/shell/Brand";
import { lastMapOrigin, type MapOrigin } from "@/lib/client/map-origin";
import type { MapRoute } from "@/lib/world-map/map-route";
import MapCorner from "./MapCorner";

const WorldMap = dynamic(() => import("./WorldMap"), {
    ssr: false,
    loading: () => <p className="hint map-screen__notice" role="status">Loading the map...</p>
});

export default function MapScreen({ route, share }: { route: MapRoute; share?: string }) {
    const [back, setBack] = useState<MapOrigin>("/");

    useEffect(() => setBack(lastMapOrigin()), []);

    return (
            <main className="map-screen">
                <header className="map-bar map-screen__header">
                    <Brand/>
                    <Link href={back} className="link-button">back</Link>
                </header>
                <p className="map-credit">
                    <span>Game art © Klei Entertainment</span>
                    <span>Not affiliated with Klei</span>
                </p>
                {"error" in route ? (
                        <>
                            <p className="notice notice--error map-screen__notice" role="alert">{route.error}</p>
                            <MapCorner/>
                        </>
                ) : (
                        <WorldMap platform={route.platform} shard={route.shard} seed={route.seed} share={share}/>
                )}
            </main>
    );
}
