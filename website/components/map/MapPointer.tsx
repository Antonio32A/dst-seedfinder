"use client";

import { type RefObject, useEffect, useRef, useState } from "react";
import type { MapCanvas } from "@/lib/world-map/canvas/map-canvas";
import type { MapProbe, MapShown, Probe } from "@/lib/world-map/view/map-probe";
import type { MapView, ScreenPoint, Size } from "@/lib/world-map/view/map-view";
import type { MapTarget } from "@/lib/world-map/legend/prefab-search";

const OFFSET = 14;
const FLIP_WITHIN = 240;
const CLICK_SLOP = 5;

interface MapPointerProps {
    probe: MapProbe;
    map: MapCanvas | null;
    canvas: RefObject<HTMLCanvasElement | null>;
    shown: MapShown;
    searched: MapTarget | null;
    /** Called with what a click or tap without a drag landed on, or `null` off the map. */
    onPick: (probe: Probe | null) => void;
}

const clientPoint = (event: PointerEvent): ScreenPoint => ({ x: event.clientX, y: event.clientY });

export default function MapPointer({ probe, map, canvas, shown, searched, onPick }: MapPointerProps) {
    const [hovered, setHovered] = useState<{ cursor: ScreenPoint; name: string } | null>(null);
    const cursor = useRef<ScreenPoint | null>(null);
    const drawn = useRef<{ view: MapView; viewport: Size } | null>(null);
    const filter = useRef<[MapShown, MapTarget | null]>([shown, searched]);
    const pick = useRef(onPick);

    useEffect(() => {
        filter.current = [shown, searched];
        pick.current = onPick;
    }, [shown, searched, onPick]);

    useEffect(() => {
        const element = canvas.current;
        if (map === null || element === null) return;
        let pressed: ScreenPoint | null = null;
        const down = new Set<number>();
        const probeAt = (client: ScreenPoint, { view, viewport }: { view: MapView; viewport: Size }) => {
            const box = element.getBoundingClientRect();
            return probe.under(view, viewport, { x: client.x - box.left, y: client.y - box.top }, ...filter.current);
        };
        const update = () => {
            if (cursor.current === null || drawn.current === null) return;
            const { entity, setPiece } = probeAt(cursor.current, drawn.current);
            map.hover(entity);
            const name = entity?.displayName ?? setPiece?.name;
            setHovered(name === undefined ? null : { cursor: cursor.current, name });
        };
        const listeners: { [K in keyof HTMLElementEventMap]?: (event: HTMLElementEventMap[K]) => void } = {
            pointermove: (event) => {
                if (event.pointerType === "touch") return;
                cursor.current = clientPoint(event);
                update();
            },
            pointerleave: () => {
                cursor.current = null;
                map.hover(null);
                setHovered(null);
            },
            pointerdown: (event) => {
                down.add(event.pointerId);
                pressed = down.size === 1 ? clientPoint(event) : null;
            },
            pointercancel: (event) => {
                down.delete(event.pointerId);
                pressed = null;
            },
            pointerup: (event) => {
                down.delete(event.pointerId);
                const at = clientPoint(event);
                const click = pressed !== null && Math.hypot(at.x - pressed.x, at.y - pressed.y) <= CLICK_SLOP;
                pressed = null;
                if (!click || drawn.current === null) return;
                const found = probeAt(at, drawn.current);
                pick.current(found.entity === null && found.setPiece === null && found.tile === null ? null : found);
            }
        };
        const unwatch = map.watch((view, viewport) => {
            drawn.current = { view, viewport };
            update();
        });
        for (const [type, listener] of Object.entries(listeners)) {
            element.addEventListener(type, listener as EventListener);
        }
        return () => {
            unwatch();
            map.hover(null);
            for (const [type, listener] of Object.entries(listeners)) {
                element.removeEventListener(type, listener as EventListener);
            }
        };
    }, [map, canvas, probe]);

    if (hovered === null) return null;
    const flip = hovered.cursor.x > innerWidth - FLIP_WITHIN;
    return (
            <div className="map__label" role="tooltip" style={{
                left: hovered.cursor.x + (flip ? -OFFSET : OFFSET),
                top: hovered.cursor.y + OFFSET,
                transform: flip ? "translateX(-100%)" : undefined
            }}>
                {hovered.name}
            </div>
    );
}
