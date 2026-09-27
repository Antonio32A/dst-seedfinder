import { type EntityLayer, SPAWN } from "@/lib/world-map/legend/entity-layer";
import { instancesOf } from "@/lib/world-map/legend/prefab-search";
import type { WitnessShape } from "@/lib/world-map/search/witness-overlay";
import { createTerrainRenderer } from "@/lib/world-map/terrain/terrain-renderer";
import {
    fitView,
    type MapView,
    panBy,
    type Size,
    turnView,
    type WorldPoint,
    zoomAt
} from "@/lib/world-map/view/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import { createEntityRenderer } from "./entity-renderer";
import { createHighlightRenderer } from "./highlight-renderer";
import { createSetPieceRenderer } from "./set-piece-renderer";
import { createWitnessRenderer, type WitnessRenderer } from "./witness-renderer";

const ZOOM_PER_PIXEL = 0.002;
const PIXELS_PER_LINE = 16;
const TURN_MS = 180;
const TURN_KEYS: Record<string, number> = { q: -1, e: 1 };
const TYPING_TARGETS = "input:not([type=checkbox], [type=radio]), textarea, select, [contenteditable]";
const BACKGROUND = [22, 17, 14] as const;
const SPAWN_SCALE = 2;

export interface MapCanvas {
    /** Rejects with a readable error when the map art can't be downloaded. */
    terrain: Promise<void>;
    /** Animated 45 degree steps: positive is the game's rotate right (E). */
    turn: (steps: number) => void;
    show: (prefabs: ReadonlySet<string>) => void;
    showSetPieces: (layouts: ReadonlySet<string>) => void;
    highlightSetPieces: (indices: readonly number[]) => void;
    /** Rings `points`, interleaved world `x, z`, whichever prefabs are shown. */
    highlight: (points: Float32Array) => void;
    /** Zooms in to at least `scale` pixels per world unit. */
    centre: (point: WorldPoint, scale?: number) => void;
    /** Calls `listener` with the view now and after every redraw, until the returned function is called. */
    watch: (listener: (view: MapView, viewport: Size) => void) => () => void;
    witnesses: (shapes: WitnessShape[]) => void;
    dispose: () => void;
}

/** Opens on the spawn portal, or fitted to the world without one, with every prefab and set piece hidden. Throws when the browser can't draw the map. */
export function mountMapCanvas(canvas: HTMLCanvasElement, world: GeneratedWorld, layer: EntityLayer): MapCanvas {
    const gl = canvas.getContext("webgl2", { alpha: true, antialias: false });
    if (gl === null) throw new Error("This browser can't draw the map: it needs WebGL2.");
    const terrain = createTerrainRenderer(gl, world, () => redraw());
    const setPieces = createSetPieceRenderer(gl, world.setPieces ?? []);
    const entities = createEntityRenderer(gl, layer);
    const highlights = createHighlightRenderer(gl);
    const watchers = new Set<(view: MapView, viewport: Size) => void>();
    let overlay: WitnessRenderer | null = null;
    let viewport: Size = { width: canvas.clientWidth, height: canvas.clientHeight };
    const [spawn] = instancesOf(world, { kind: "prefab", name: SPAWN });
    const fitted = fitView(world, viewport);
    let view: MapView = spawn === undefined
            ? fitted
            : { ...fitted, centerX: spawn.x, centerZ: spawn.z, scale: Math.max(fitted.scale, SPAWN_SCALE) };
    let frame = 0;
    let grab: { x: number; y: number } | null = null;
    let turning: { from: number; to: number; start: number } | null = null;

    const redraw = () => {
        frame ||= requestAnimationFrame((now) => {
            frame = 0;
            if (turning !== null) {
                const progress = Math.min(1, (now - turning.start) / TURN_MS);
                view = { ...view, heading: turning.from + (turning.to - turning.from) * (1 - (1 - progress) ** 3) };
                if (progress < 1) redraw();
                else turning = null;
            }
            gl.viewport(0, 0, canvas.width, canvas.height);
            const [red, green, blue] = BACKGROUND;
            gl.clearColor(red / 255, green / 255, blue / 255, 1);
            gl.clear(gl.COLOR_BUFFER_BIT);
            terrain.draw(view, viewport);
            setPieces.draw(view, viewport);
            entities.draw(view, viewport);
            overlay?.draw(view, viewport);
            highlights.draw(view, viewport);
            for (const watcher of watchers) watcher(view, viewport);
        });
    };
    const move = (next: MapView) => {
        view = next;
        redraw();
    };

    const resized = new ResizeObserver(() => {
        viewport = { width: canvas.clientWidth, height: canvas.clientHeight };
        canvas.width = Math.round(viewport.width * devicePixelRatio);
        canvas.height = Math.round(viewport.height * devicePixelRatio);
        redraw();
    });
    resized.observe(canvas);

    const listeners: { [K in keyof HTMLElementEventMap]?: (event: HTMLElementEventMap[K]) => void } = {
        pointerdown: (event) => {
            grab = { x: event.clientX, y: event.clientY };
            canvas.setPointerCapture(event.pointerId);
        },
        pointermove: (event) => {
            if (grab === null) return;
            move(panBy(view, event.clientX - grab.x, event.clientY - grab.y));
            grab = { x: event.clientX, y: event.clientY };
        },
        pointerup: () => (grab = null),
        pointercancel: () => (grab = null),
        wheel: (event) => {
            event.preventDefault();
            const box = canvas.getBoundingClientRect();
            const pixels = event.deltaY * (event.deltaMode === WheelEvent.DOM_DELTA_LINE ? PIXELS_PER_LINE : 1);
            move(zoomAt(view, viewport, {
                x: event.clientX - box.left,
                y: event.clientY - box.top
            }, Math.exp(-pixels * ZOOM_PER_PIXEL)));
        }
    };
    for (const [type, listener] of Object.entries(listeners)) canvas.addEventListener(type, listener as EventListener, { passive: false });

    const turn = (steps: number) => {
        const to = turnView({ ...view, heading: turning?.to ?? view.heading }, steps).heading;
        turning = { from: view.heading, to, start: performance.now() };
        redraw();
    };
    const pressed = (event: KeyboardEvent) => {
        const steps = TURN_KEYS[event.key.toLowerCase()];
        const typing = event.target instanceof HTMLElement && event.target.closest(TYPING_TARGETS) !== null;
        if (steps === undefined || typing || event.ctrlKey || event.metaKey || event.altKey) return;
        turn(steps);
    };
    addEventListener("keydown", pressed);

    return {
        terrain: terrain.built,
        turn,
        show: (shown) => {
            entities.show(shown);
            redraw();
        },
        showSetPieces: (shown) => {
            setPieces.show(shown);
            redraw();
        },
        highlightSetPieces: (indices) => {
            setPieces.highlight(indices);
            redraw();
        },
        highlight: (points) => {
            highlights.highlight(points);
            redraw();
        },
        centre: (point, scale = 0) => move({
            ...view,
            centerX: point.x,
            centerZ: point.z,
            scale: Math.max(view.scale, scale)
        }),
        watch: (listener) => {
            watchers.add(listener);
            listener(view, viewport);
            return () => watchers.delete(listener);
        },
        witnesses: (shapes) => {
            overlay?.dispose();
            overlay = createWitnessRenderer(gl, shapes);
            redraw();
        },
        dispose: () => {
            cancelAnimationFrame(frame);
            resized.disconnect();
            for (const [type, listener] of Object.entries(listeners)) canvas.removeEventListener(type, listener as EventListener);
            removeEventListener("keydown", pressed);
            terrain.dispose();
            setPieces.dispose();
            entities.dispose();
            highlights.dispose();
            overlay?.dispose();
        }
    };
}
