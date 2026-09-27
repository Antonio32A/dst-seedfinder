"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Platform } from "@/lib/config/seedfinder-config";
import { entityLayer, mapWorld } from "@/lib/world-map/entity-layer";
import { loadWorld, type WorldLoad } from "@/lib/world-map/load-world";
import { type MapCanvas, mountMapCanvas } from "@/lib/world-map/map-canvas";
import { createMapProbe, type Probe } from "@/lib/world-map/map-probe";
import { parseMapConfig } from "@/lib/world-map/map-route";
import type { MapTarget } from "@/lib/world-map/prefab-search";
import { defaultShown, mapLegend } from "@/lib/world-map/prefab-visibility";
import { defaultShownSetPieces, setPieceLegend } from "@/lib/world-map/set-pieces";
import type { GeneratedWorld } from "@/lib/world-map/world-dump";
import GroupsPanel from "./GroupsPanel";
import MapCorner from "./MapCorner";
import MapDetails from "./MapDetails";
import MapPointer from "./MapPointer";
import PrefabSearch from "./PrefabSearch";
import WitnessPanel from "./WitnessPanel";

const NOTICES: Record<Exclude<WorldLoad["status"], "ready" | "failed">, string> = {
    loading: "Generating the world in your browser...",
    "gave-up": "This seed's world generation gave up, so there's no world to show.",
    unsupported: "This browser can't run the seedfinder: it needs WebAssembly threads."
};

function WorldCanvas({ world: generated, bytes, platform, seed, share }: {
    world: GeneratedWorld;
    bytes: Uint8Array;
    platform: Platform;
    seed: number;
    share?: string;
}) {
    const canvas = useRef<HTMLCanvasElement>(null);
    const world = useMemo(() => mapWorld(generated), [generated]);
    const [map, setMap] = useState<MapCanvas | null>(null);
    const [error, setError] = useState<string | null>(null);
    const layer = useMemo(() => entityLayer(world), [world]);
    const legend = useMemo(() => mapLegend(world), [world]);
    const setPieces = useMemo(() => setPieceLegend(world), [world]);
    const probe = useMemo(() => createMapProbe(world), [world]);
    const shared = useMemo(() => (share === undefined ? null : parseMapConfig(share, platform)), [share, platform]);
    const search = shared && "config" in shared ? shared.config : undefined;
    const [shownPrefabs, setShownPrefabs] = useState<ReadonlySet<string>>(() => defaultShown(search));
    const [shownSetPieces, setShownSetPieces] = useState<ReadonlySet<string>>(() => defaultShownSetPieces(search));
    const shown = useMemo(() => ({ prefabs: shownPrefabs, setPieces: shownSetPieces }), [shownPrefabs, shownSetPieces]);
    const [searched, setSearched] = useState<MapTarget | null>(null);
    const [picked, setPicked] = useState<Probe | null>(null);
    const close = useCallback(() => setPicked(null), []);
    const openSetPiece = useCallback((index: number) => setPicked(probe.setPiece(index)), [probe]);
    const highlighted = useMemo(() => {
        const found = (world.setPieces ?? []).flatMap(({ name }, index) =>
                (searched?.kind === "set piece" && name === searched.name ? [index] : []));
        return picked?.setPiece ? [...found, picked.setPiece.index] : found;
    }, [world, searched, picked]);

    useEffect(() => {
        let mounted: MapCanvas | null = null;
        try {
            mounted = mountMapCanvas(canvas.current!, world, layer);
            setMap(mounted);
        } catch (caught) {
            setError(caught instanceof Error ? caught.message : String(caught));
        }
        return () => {
            mounted?.dispose();
            setMap(null);
        };
    }, [world, layer]);

    useEffect(() => {
        map?.show(shownPrefabs);
    }, [map, shownPrefabs]);

    useEffect(() => {
        map?.showSetPieces(shownSetPieces);
    }, [map, shownSetPieces]);

    useEffect(() => {
        map?.highlightSetPieces(highlighted);
    }, [map, highlighted]);

    return (
            <>
                <canvas ref={canvas} className="map__canvas" aria-label="World map"/>
                {error && <p className="notice notice--error map-screen__notice" role="alert">{error}</p>}
                <MapPointer probe={probe} map={map} canvas={canvas} shown={shown} searched={searched}
                            onPick={setPicked}/>
                <GroupsPanel legend={legend} shown={shownPrefabs} onChange={setShownPrefabs} setPieces={setPieces}
                             shownSetPieces={shownSetPieces} onSetPiecesChange={setShownSetPieces}/>
                <MapCorner seed={seed} map={map}/>
                <div className="map-side">
                    <div className="map-bar">
                        <PrefabSearch world={world} map={map} onChange={setSearched}/>
                    </div>
                    {picked && <MapDetails probe={picked} onClose={close} onOpenSetPiece={openSetPiece}/>}
                    {shared && <WitnessPanel shared={shared} world={generated} bytes={bytes} map={map}/>}
                </div>
            </>
    );
}

export default function WorldMap({ platform, seed, share }: { platform: Platform; seed: number; share?: string }) {
    const [load, setLoad] = useState<WorldLoad>({ status: "loading" });

    useEffect(() => {
        const controller = new AbortController();
        setLoad({ status: "loading" });
        void loadWorld(seed, platform, controller.signal).then((result) => {
            if (!controller.signal.aborted) setLoad(result);
        });
        return () => controller.abort();
    }, [platform, seed]);

    if (load.status === "ready") {
        return (
                <WorldCanvas key={share} world={load.world} bytes={load.bytes} platform={platform} seed={seed}
                             share={share}/>
        );
    }
    const tone = load.status === "loading" ? "hint" : "notice notice--warning";
    return (
            <>
                {load.status === "failed" ? (
                        <p className="notice notice--error map-screen__notice" role="alert">{load.error}</p>
                ) : (
                        <p className={`${tone} map-screen__notice`} role="status">{NOTICES[load.status]}</p>
                )}
                <MapCorner seed={seed}/>
            </>
    );
}
