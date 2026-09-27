"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import type { MapRoute } from "@/lib/world-map/map-route";
import MapCorner from "./MapCorner";

const WorldMap = dynamic(() => import("./WorldMap"), {
    ssr: false,
    loading: () => <p className="hint map-screen__notice" role="status">Loading the map...</p>
});

export default function MapScreen({ route, share }: { route: MapRoute; share?: string }) {
    return (
            <main className="map-screen">
                <header className="map-bar map-screen__header">
                    <div className="brand">
                        <a href="https://antonio32a.com" className="logo">
                            antonio32a.com
                        </a>
                        <Link href="/" className="brand__site">
                            seedfinder
                        </Link>
                    </div>
                    <Link href="/" className="link-button">back to search</Link>
                </header>
                {"error" in route ? (
                        <>
                            <p className="notice notice--error map-screen__notice" role="alert">{route.error}</p>
                            <MapCorner/>
                        </>
                ) : (
                        <WorldMap platform={route.platform} seed={route.seed} share={share}/>
                )}
            </main>
    );
}
