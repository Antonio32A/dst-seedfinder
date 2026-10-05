import { type EntityLayer, SPAWN } from "@/lib/world-map/legend/entity-layer";
import { instancesOf } from "@/lib/world-map/legend/prefab-search";
import type { WitnessShape } from "@/lib/world-map/search/witness-overlay";
import {
    fitView,
    type LinkedView,
    linkView,
    type MapView,
    openLinkedView,
    panBy,
    type ScreenPoint,
    type Size,
    turnView,
    type WorldPoint,
    zoomAt
} from "@/lib/world-map/view/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import { readAccent } from "./accent-colour";
import { NO_HOVER } from "./entity-renderer";
import { createMapScene } from "./map-scene";
import { createWitnessRenderer, type WitnessRenderer } from "./witness-renderer";

const ZOOM_PER_PIXEL = 0.002;
const PIXELS_PER_LINE = 16;
const TURN_MS = 180;
const TURN_KEYS: Record<string, number> = { q: -1, e: 1 };
const TYPING_TARGETS = "input:not([type=checkbox], [type=radio]), textarea, select, [contenteditable]";
const SPAWN_SCALE = 2;

export interface MapCanvas {
    /** Rejects with a readable error when the map art can't be downloaded. */
    terrain: Promise<void>;
    /** Animated 45 degree steps: positive is the game's rotate right (E). */
    turn: (steps: number) => void;
    /** Opens darkened, like the game's fog over explored ground. */
    darken: (on: boolean) => void;
    show: (prefabs: ReadonlySet<string>) => void;
    showSetPieces: (layouts: ReadonlySet<string>) => void;
    /** Shows or hides the wormhole connection lines, drawn over the icons. They start shown. */
    showLinks: (on: boolean) => void;
    /** Shows or hides the turf bridges, drawn over the roads. They start hidden. */
    showBridges: (on: boolean) => void;
    /** Shows or hides the roads, drawn over the terrain. They start shown. */
    showRoads: (on: boolean) => void;
    highlightSetPieces: (indices: readonly number[]) => void;
    /** Outlines every instance of `prefabs` in the site's highlight orange, showing them even when they're not in {@link show}. */
    highlight: (prefabs: ReadonlySet<string>) => void;
    /** Outlines the entity of `prefab` at world `(x, z)`, on top of {@link highlight}, or none for `null`. */
    hover: (entity: { prefab: string; x: number; z: number } | null) => void;
    /** Zooms in to at least `scale` pixels per world unit. */
    centre: (point: WorldPoint, scale?: number) => void;
    /** The view now, as a link opens it on any screen, at the heading a turn is heading to. */
    linkedView: () => LinkedView;
    /** Calls `listener` with the view now and after every redraw, until the returned function is called. */
    watch: (listener: (view: MapView, viewport: Size) => void) => () => void;
    witnesses: (shapes: WitnessShape[]) => void;
    dispose: () => void;
}

/**
 * Opens on `linked`, else on the spawn portal, or fitted to the world without one, with every prefab and set piece
 * hidden. Throws when the browser can't draw the map or the page has no `--highlight` colour to highlight with.
 */
export function mountMapCanvas(canvas: HTMLCanvasElement, world: GeneratedWorld, layer: EntityLayer, linked?: LinkedView): MapCanvas {
    const gl = canvas.getContext("webgl2", { alpha: true, antialias: false });
    if (gl === null) throw new Error("This browser can't draw the map: it needs WebGL2.");
    const scene = createMapScene(gl, world, layer, readAccent(canvas), () => redraw());
    const { roads, bridges, setPieces, entities, icons, links } = scene;
    const watchers = new Set<(view: MapView, viewport: Size) => void>();
    let overlay: WitnessRenderer | null = null;
    let viewport: Size = { width: canvas.clientWidth, height: canvas.clientHeight };
    const [spawn] = instancesOf(world, { kind: "prefab", name: SPAWN });
    const fitted = fitView(world, viewport);
    const opening: MapView = spawn === undefined
            ? fitted
            : { ...fitted, centerX: spawn.x, centerZ: spawn.z, scale: Math.max(fitted.scale, SPAWN_SCALE) };
    let view = linked === undefined ? opening : openLinkedView(linked, viewport);
    let frame = 0;
    const pointers = new Map<number, ScreenPoint>();
    let turning: { from: number; to: number; start: number } | null = null;
    let hovered = NO_HOVER;

    const render = (now: number) => {
        cancelAnimationFrame(frame);
        frame = 0;
        if (turning !== null) {
            const progress = Math.min(1, (now - turning.start) / TURN_MS);
            view = { ...view, heading: turning.from + (turning.to - turning.from) * (1 - (1 - progress) ** 3) };
            if (progress < 1) redraw();
            else turning = null;
        }
        scene.draw(view, viewport);
        overlay?.draw(view, viewport);
        for (const watcher of watchers) watcher(view, viewport);
    };
    const redraw = () => {
        frame ||= requestAnimationFrame(render);
    };
    const move = (next: MapView) => {
        view = next;
        redraw();
    };

    // Resizing the canvas clears it, so it's drawn again before the browser paints it, not a frame later.
    const resized = new ResizeObserver(([entry]) => {
        viewport = { width: entry.contentRect.width, height: entry.contentRect.height };
        const [pixels] = entry.devicePixelContentBoxSize ?? [];
        const width = pixels?.inlineSize ?? Math.round(viewport.width * devicePixelRatio);
        const height = pixels?.blockSize ?? Math.round(viewport.height * devicePixelRatio);
        if (canvas.width !== width) canvas.width = width;
        if (canvas.height !== height) canvas.height = height;
        render(performance.now());
    });
    try {
        resized.observe(canvas, { box: "device-pixel-content-box" });
    } catch {
        resized.observe(canvas);
    }

    const gesture = () => {
        const points = [...pointers.values()];
        const [first, second] = points;
        return {
            x: points.reduce((sum, { x }) => sum + x, 0) / points.length,
            y: points.reduce((sum, { y }) => sum + y, 0) / points.length,
            spread: second === undefined ? 0 : Math.hypot(first.x - second.x, first.y - second.y)
        };
    };
    const listeners: { [K in keyof HTMLElementEventMap]?: (event: HTMLElementEventMap[K]) => void } = {
        pointerdown: (event) => {
            pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
            canvas.setPointerCapture(event.pointerId);
        },
        pointermove: (event) => {
            if (!pointers.has(event.pointerId)) return;
            const before = gesture();
            pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
            const after = gesture();
            const panned = panBy(view, after.x - before.x, after.y - before.y);
            const box = canvas.getBoundingClientRect();
            move(before.spread === 0 || after.spread === 0 ? panned
                    : zoomAt(panned, viewport, { x: after.x - box.left, y: after.y - box.top }, after.spread / before.spread));
        },
        pointerup: (event) => pointers.delete(event.pointerId),
        pointercancel: (event) => pointers.delete(event.pointerId),
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
        terrain: scene.built,
        turn,
        darken: (on) => {
            scene.darken(on);
            redraw();
        },
        show: (shown) => {
            entities.show(shown);
            redraw();
        },
        showSetPieces: (shown) => {
            setPieces.show(shown);
            redraw();
        },
        showLinks: (on) => {
            links.show(on);
            redraw();
        },
        showBridges: (on) => {
            bridges.show(on);
            redraw();
        },
        showRoads: (on) => {
            roads.show(on);
            redraw();
        },
        highlightSetPieces: (indices) => {
            setPieces.highlight(indices);
            redraw();
        },
        highlight: (prefabs) => {
            entities.highlight(prefabs);
            redraw();
        },
        hover: (entity) => {
            const prefab = entity === null ? -1 : layer.names.indexOf(entity.prefab);
            const next = entity === null || prefab === -1 ? NO_HOVER : { prefab, x: entity.x, z: entity.z };
            if (next.prefab === hovered.prefab && next.x === hovered.x && next.z === hovered.z) return;
            hovered = next;
            entities.hover(next);
            icons.hover(next);
            redraw();
        },
        centre: (point, scale = 0) => move({
            ...view,
            centerX: point.x,
            centerZ: point.z,
            scale: Math.max(view.scale, scale)
        }),
        linkedView: () => linkView({ ...view, heading: turning?.to ?? view.heading }, viewport),
        watch: (listener) => {
            watchers.add(listener);
            listener(view, viewport);
            return () => watchers.delete(listener);
        },
        witnesses: (shapes) => {
            overlay?.dispose();
            overlay = createWitnessRenderer(gl, shapes, world.shard);
            redraw();
        },
        dispose: () => {
            cancelAnimationFrame(frame);
            resized.disconnect();
            for (const [type, listener] of Object.entries(listeners)) canvas.removeEventListener(type, listener as EventListener);
            removeEventListener("keydown", pressed);
            scene.dispose();
            overlay?.dispose();
        }
    };
}
