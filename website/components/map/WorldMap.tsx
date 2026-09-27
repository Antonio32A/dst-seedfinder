"use client";

import { useEffect, useRef, useState } from "react";
import type { Platform } from "@/lib/config/seedfinder-config";
import { loadWorld, type WorldLoad } from "@/lib/world-map/load-world";
import { mountTileMap, type TileMap } from "@/lib/world-map/tile-map";
import type { GeneratedWorld } from "@/lib/world-map/world-dump";

const NOTICES: Record<Exclude<WorldLoad["status"], "ready" | "failed">, string> = {
    loading: "Generating the world in your browser...",
    "gave-up": "This seed's world generation gave up, so there's no world to show.",
    unsupported: "This browser can't run the seedfinder: it needs WebAssembly threads."
};

function TileCanvas({ world }: { world: GeneratedWorld }) {
    const canvas = useRef<HTMLCanvasElement>(null);
    const map = useRef<TileMap | null>(null);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        try {
            map.current = mountTileMap(canvas.current!, world);
        } catch (caught) {
            setError(caught instanceof Error ? caught.message : String(caught));
        }
        return () => {
            map.current?.dispose();
            map.current = null;
        };
    }, [world]);

    return (
            <div className="map">
                {error && <p className="notice notice--error" role="alert">{error}</p>}
                <canvas ref={canvas} className="map__canvas" aria-label="World map"/>
                <div className="map__controls">
                    <button type="button" className="link-button" onClick={() => map.current?.fit()}>
                        fit to world
                    </button>
                    <button type="button" className="link-button" onClick={() => map.current?.turn(-1)}>
                        rotate left (Q)
                    </button>
                    <button type="button" className="link-button" onClick={() => map.current?.turn(1)}>
                        rotate right (E)
                    </button>
                    <span className="hint">Drag to pan, scroll to zoom, Q/E to rotate.</span>
                </div>
            </div>
    );
}

export default function WorldMap({ platform, seed }: { platform: Platform; seed: number }) {
    const [load, setLoad] = useState<WorldLoad>({ status: "loading" });

    useEffect(() => {
        const controller = new AbortController();
        setLoad({ status: "loading" });
        void loadWorld(seed, platform, controller.signal).then((result) => {
            if (!controller.signal.aborted) setLoad(result);
        });
        return () => controller.abort();
    }, [platform, seed]);

    if (load.status === "ready") return <TileCanvas world={load.world}/>;
    if (load.status === "failed") return <p className="notice notice--error" role="alert">{load.error}</p>;
    return <p className={load.status === "loading" ? "hint" : "notice notice--warning"} role="status">{NOTICES[load.status]}</p>;
}
