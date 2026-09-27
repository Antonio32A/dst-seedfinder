"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Toggle from "@/components/ui/Toggle";
import type { Platform } from "@/lib/config/seedfinder-config";
import { entityLayer, MAP_GROUPS, type MapGroupId } from "@/lib/world-map/entity-layer";
import { type GroupVisibility, readGroupVisibility, storeGroupVisibility } from "@/lib/world-map/group-visibility";
import { loadWorld, type WorldLoad } from "@/lib/world-map/load-world";
import { type MapCanvas, mountMapCanvas } from "@/lib/world-map/map-canvas";
import type { GeneratedWorld } from "@/lib/world-map/world-dump";
import MapTooltip from "./MapTooltip";
import PrefabSearch from "./PrefabSearch";

const NOTICES: Record<Exclude<WorldLoad["status"], "ready" | "failed">, string> = {
    loading: "Generating the world in your browser...",
    "gave-up": "This seed's world generation gave up, so there's no world to show.",
    unsupported: "This browser can't run the seedfinder: it needs WebAssembly threads."
};

function WorldCanvas({ world }: { world: GeneratedWorld }) {
    const canvas = useRef<HTMLCanvasElement>(null);
    const map = useRef<MapCanvas | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [visibility, setVisibility] = useState<GroupVisibility>(readGroupVisibility);
    const layer = useMemo(() => entityLayer(world), [world]);
    const [mounted, setMounted] = useState<MapCanvas | null>(null);
    const [searched, setSearched] = useState<string | null>(null);

    useEffect(() => {
        try {
            map.current = mountMapCanvas(canvas.current!, world, layer);
            setMounted(map.current);
        } catch (caught) {
            setError(caught instanceof Error ? caught.message : String(caught));
        }
        return () => {
            map.current?.dispose();
            map.current = null;
            setMounted(null);
        };
    }, [world, layer]);

    useEffect(() => {
        map.current?.show(visibility);
    }, [visibility, layer]);

    const toggle = (group: MapGroupId, shown: boolean) => {
        const next = { ...visibility, [group]: shown };
        setVisibility(next);
        storeGroupVisibility(next);
    };

    return (
            <div className="map">
                {error && <p className="notice notice--error" role="alert">{error}</p>}
                <canvas ref={canvas} className="map__canvas" aria-label="World map"/>
                <MapTooltip world={world} map={mounted} canvas={canvas} visibility={visibility} highlighted={searched}/>
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
                <PrefabSearch world={world} map={mounted} onChange={setSearched}/>
                <div className="map__layers" role="group" aria-label="Entity groups">
                    {MAP_GROUPS.map(({ id, name, colour }, group) => layer.counts[group] > 0 && (
                            <Toggle key={id} checked={visibility[id]} onChange={(shown) => toggle(id, shown)}>
                                <span className="map__swatch" style={{ background: `rgb(${colour.join()})` }}/>
                                {name} <span className="map__count">{layer.counts[group].toLocaleString("en-US")}</span>
                            </Toggle>
                    ))}
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

    if (load.status === "ready") return <WorldCanvas world={load.world}/>;
    if (load.status === "failed") return <p className="notice notice--error" role="alert">{load.error}</p>;
    return <p className={load.status === "loading" ? "hint" : "notice notice--warning"} role="status">{NOTICES[load.status]}</p>;
}
