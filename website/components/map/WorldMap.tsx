"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Toast, { type ToastMessage } from "@/components/ui/Toast";
import { copyText } from "@/lib/client/clipboard";
import type { Platform, Shard } from "@/lib/config/seedfinder-config";
import { entityLayer, MAP_GROUPS, mapWorld } from "@/lib/world-map/legend/entity-layer";
import { loadWorld, type WorldLoad } from "@/lib/world-map/world/load-world";
import { type MapCanvas, mountMapCanvas } from "@/lib/world-map/canvas/map-canvas";
import { createMapProbe, type Probe } from "@/lib/world-map/view/map-probe";
import { mapPath, parseMapConfig } from "@/lib/world-map/map-route";
import { mapPreviewPath } from "@/lib/world-map/map-preview-url";
import type { MapTarget } from "@/lib/world-map/legend/prefab-search";
import { allPrefabs, defaultShown, mapLegend } from "@/lib/world-map/legend/prefab-visibility";
import { defaultShownSetPieces, setPieceLegend } from "@/lib/world-map/legend/set-pieces";
import type { LinkedView } from "@/lib/world-map/view/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import GroupsPanel from "./GroupsPanel";
import MapCorner from "./MapCorner";
import MapDetails from "./MapDetails";
import MapPointer from "./MapPointer";
import PrefabSearch from "./PrefabSearch";
import WitnessPanel from "./WitnessPanel";

const LINK_LABELS: Record<Shard, string> = { forest: "Wormhole Connections", caves: "Tentacle Pillar Connections" };

const NOTICES: Record<Exclude<WorldLoad["status"], "ready" | "failed">, string> = {
    loading: "Generating the world in your browser...",
    "gave-up": "This seed's world generation gave up, so there's no world to show.",
    crashed: "This seed crashes the game's world generation, so there's no world to show.",
    unsupported: "This browser can't run the seedfinder: it needs WebAssembly threads."
};

function WorldCanvas({ world: generated, bytes, platform, shard, seed, share, view }: {
    world: GeneratedWorld;
    bytes: Uint8Array;
    platform: Platform;
    shard: Shard;
    seed: number;
    share?: string;
    view?: LinkedView;
}) {
    const canvas = useRef<HTMLCanvasElement>(null);
    const world = useMemo(() => mapWorld(generated), [generated]);
    const [map, setMap] = useState<MapCanvas | null>(null);
    const [error, setError] = useState<string | null>(null);
    const layer = useMemo(() => entityLayer(world), [world]);
    const legend = useMemo(() => mapLegend(world), [world]);
    const setPieces = useMemo(() => setPieceLegend(world), [world]);
    const probe = useMemo(() => createMapProbe(world), [world]);
    const shared = useMemo(() => (share === undefined ? null : parseMapConfig(share, platform, shard)), [share, platform, shard]);
    const search = shared && "config" in shared ? shared.config : undefined;
    const [shownPrefabs, setShownPrefabs] = useState<ReadonlySet<string>>(() => defaultShown(search, shard));
    const [shownSetPieces, setShownSetPieces] = useState<ReadonlySet<string>>(() => defaultShownSetPieces(search));
    const [shownLinks, setShownLinks] = useState(false);
    const links = useMemo(() => layer.links.length === 0 ? null : {
        label: LINK_LABELS[shard],
        shown: shownLinks,
        colour: MAP_GROUPS[layer.linkGroup].colour,
        onChange: setShownLinks
    }, [layer, shard, shownLinks]);
    const [shownRoads, setShownRoads] = useState(true);
    const roads = useMemo(() => (world.roads?.length ? { shown: shownRoads, onChange: setShownRoads } : null), [world, shownRoads]);
    const select = useCallback((selection: "all" | "none" | "reset") => {
        setShownPrefabs(selection === "all" ? allPrefabs(legend) : selection === "none" ? new Set() : defaultShown(search, shard));
        setShownSetPieces(selection === "all" ? (setPieces ? allPrefabs([setPieces]) : new Set<string>())
                : selection === "none" ? new Set() : defaultShownSetPieces(search));
        setShownLinks(selection === "all");
        setShownRoads(selection !== "none");
    }, [legend, setPieces, search, shard]);
    const [searched, setSearched] = useState<MapTarget | null>(null);
    const [previewed, setPreviewed] = useState<readonly string[]>([]);
    const highlightedPrefabs = useMemo<ReadonlySet<string>>(
            () => new Set(searched?.kind === "prefab" ? [...previewed, searched.name] : previewed),
            [previewed, searched]
    );
    const shown = useMemo(() => ({
        prefabs: new Set([...shownPrefabs, ...highlightedPrefabs]),
        setPieces: shownSetPieces
    }), [shownPrefabs, highlightedPrefabs, shownSetPieces]);
    const [picked, setPicked] = useState<Probe | null>(null);
    const close = useCallback(() => setPicked(null), []);
    const openSetPiece = useCallback((index: number) => setPicked(probe.setPiece(index)), [probe]);
    const highlighted = useMemo(() => {
        const found = (world.setPieces ?? []).flatMap(({ name }, index) =>
                (searched?.kind === "set piece" && name === searched.name ? [index] : []));
        return picked?.setPiece ? [...found, picked.setPiece.index] : found;
    }, [world, searched, picked]);

    const [toast, setToast] = useState<ToastMessage | null>(null);
    const dismissToast = useCallback(() => setToast(null), []);
    const copyLink = useCallback(async () => {
        const view = map?.linkedView();
        const link = new URL(mapPath(platform, seed, search, shard, view), window.location.origin).href;
        void fetch(mapPreviewPath(platform, seed, shard, view), { method: "HEAD", keepalive: true }).catch(() => undefined);
        setToast({ id: Date.now(), text: (await copyText(link)) ? "Link copied." : `Couldn't copy. The link is ${link}` });
    }, [map, platform, seed, search, shard]);

    useEffect(() => {
        let mounted: MapCanvas | null = null;
        try {
            mounted = mountMapCanvas(canvas.current!, world, layer, view);
            mounted.terrain.catch((caught: unknown) => setError(caught instanceof Error ? caught.message : String(caught)));
            setMap(mounted);
        } catch (caught) {
            setError(caught instanceof Error ? caught.message : String(caught));
        }
        return () => {
            mounted?.dispose();
            setMap(null);
        };
    }, [world, layer, view]);

    useEffect(() => {
        map?.show(shownPrefabs);
    }, [map, shownPrefabs]);

    useEffect(() => {
        map?.highlight(highlightedPrefabs);
    }, [map, highlightedPrefabs]);

    useEffect(() => {
        map?.showSetPieces(shownSetPieces);
    }, [map, shownSetPieces]);

    useEffect(() => {
        map?.showLinks(shownLinks);
    }, [map, shownLinks]);

    useEffect(() => {
        map?.showRoads(shownRoads);
    }, [map, shownRoads]);

    useEffect(() => {
        map?.highlightSetPieces(highlighted);
    }, [map, highlighted]);

    return (
            <>
                <canvas ref={canvas} className="map__canvas" aria-label="World map"/>
                {error && <p className="notice notice--error map-screen__notice" role="alert">{error}</p>}
                <MapPointer probe={probe} map={map} canvas={canvas} shown={shown} searched={searched}
                            onPick={setPicked}/>
                <GroupsPanel legend={legend} shown={shownPrefabs} onChange={setShownPrefabs} onHighlight={setPreviewed}
                             setPieces={setPieces}
                             shownSetPieces={shownSetPieces} onSetPiecesChange={setShownSetPieces} links={links} roads={roads}
                             onSelect={select}/>
                <MapCorner seed={seed} map={map} onCopyLink={() => void copyLink()}/>
                <Toast message={toast} onDismiss={dismissToast}/>
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

export default function WorldMap({ platform, shard, seed, share, view }: {
    platform: Platform;
    shard: Shard;
    seed: number;
    share?: string;
    view?: LinkedView;
}) {
    const [load, setLoad] = useState<WorldLoad>({ status: "loading" });

    useEffect(() => {
        const controller = new AbortController();
        setLoad({ status: "loading" });
        void loadWorld(seed, platform, shard, controller.signal).then((result) => {
            if (!controller.signal.aborted) setLoad(result);
        });
        return () => controller.abort();
    }, [platform, shard, seed]);

    if (load.status === "ready") {
        return (
                <WorldCanvas key={share} world={load.world} bytes={load.bytes} platform={platform} shard={shard} seed={seed}
                             share={share} view={view}/>
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
