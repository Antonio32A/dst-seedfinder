"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import type { MapRoute } from "@/lib/world-map/map-route";

const PLATFORM_NAMES = { windows: "Windows", linux: "Linux" } as const;

const WorldMap = dynamic(() => import("./WorldMap"), {
    ssr: false,
    loading: () => <p className="hint" role="status">Loading the map...</p>
});

export default function MapScreen({ route, share }: { route: MapRoute; share?: string }) {
    return (
            <main className="content">
                <header className="header">
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
                        <p className="notice notice--error" role="alert">{route.error}</p>
                ) : (
                        <section className="section" aria-labelledby="map-title">
                            <h2 id="map-title" className="section-title">
                                Seed {route.seed} on {PLATFORM_NAMES[route.platform]}
                            </h2>
                            <WorldMap platform={route.platform} seed={route.seed} share={share}/>
                        </section>
                )}
            </main>
    );
}
