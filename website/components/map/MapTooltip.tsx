"use client";

import { type RefObject, useEffect, useMemo, useRef, useState } from "react";
import type { GroupVisibility } from "@/lib/world-map/group-visibility";
import type { MapCanvas } from "@/lib/world-map/map-canvas";
import { createMapProbe, type Probe } from "@/lib/world-map/map-probe";
import type { MapView, ScreenPoint, Size } from "@/lib/world-map/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world-dump";

const OFFSET = 14;
const FLIP_WITHIN = 280;

interface MapTooltipProps {
    world: GeneratedWorld;
    map: MapCanvas | null;
    canvas: RefObject<HTMLCanvasElement | null>;
    visibility: GroupVisibility;
    highlighted: string | null;
}

const coordinate = (value: number) => value.toFixed(2);

export default function MapTooltip({ world, map, canvas, visibility, highlighted }: MapTooltipProps) {
    const probe = useMemo(() => createMapProbe(world), [world]);
    const [shown, setShown] = useState<{ cursor: ScreenPoint; probe: Probe } | null>(null);
    const cursor = useRef<ScreenPoint | null>(null);
    const drawn = useRef<{ view: MapView; viewport: Size } | null>(null);
    const filter = useRef<[GroupVisibility, string | null]>([visibility, highlighted]);

    useEffect(() => {
        filter.current = [visibility, highlighted];
    }, [visibility, highlighted]);

    useEffect(() => {
        const element = canvas.current;
        if (map === null || element === null) return;
        const update = () => {
            if (cursor.current === null || drawn.current === null) return;
            const box = element.getBoundingClientRect();
            const { view, viewport } = drawn.current;
            const at = { x: cursor.current.x - box.left, y: cursor.current.y - box.top };
            setShown({ cursor: cursor.current, probe: probe.under(view, viewport, at, ...filter.current) });
        };
        const point = (event: PointerEvent) => {
            cursor.current = { x: event.clientX, y: event.clientY };
            update();
        };
        const leave = (event: PointerEvent) => {
            if (event.pointerType === "touch") return;
            cursor.current = null;
            setShown(null);
        };
        const unwatch = map.watch((view, viewport) => {
            drawn.current = { view, viewport };
            update();
        });
        element.addEventListener("pointermove", point);
        element.addEventListener("pointerdown", point);
        element.addEventListener("pointerleave", leave);
        return () => {
            unwatch();
            element.removeEventListener("pointermove", point);
            element.removeEventListener("pointerdown", point);
            element.removeEventListener("pointerleave", leave);
        };
    }, [map, canvas, probe]);

    if (shown === null || shown.probe.tile === null && shown.probe.entity === null) return null;
    const { entity, tile } = shown.probe;
    const flip = shown.cursor.x > innerWidth - FLIP_WITHIN;
    return (
            <div className="map__tooltip" role="tooltip" style={{
                left: shown.cursor.x + (flip ? -OFFSET : OFFSET),
                top: shown.cursor.y + OFFSET,
                transform: flip ? "translateX(-100%)" : undefined
            }}>
                {entity && (
                        <>
                            <div>
                                <strong>{entity.displayName}</strong> <code>{entity.prefab}</code>
                                <span className="map__count"> index {entity.index}</span>
                            </div>
                            <div>x {coordinate(entity.x)}, z {coordinate(entity.z)}</div>
                        </>
                )}
                {tile && <div>{tile.displayName} <code>{tile.name}</code></div>}
            </div>
    );
}
