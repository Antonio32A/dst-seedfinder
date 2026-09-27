import type { EntityLayer } from "./entity-layer";
import { createEntityRenderer } from "./entity-renderer";
import type { GroupVisibility } from "./group-visibility";
import { createHighlightRenderer } from "./highlight-renderer";
import { fitView, type MapView, panBy, type Size, turnView, type WorldPoint, zoomAt } from "./map-view";
import { createTileRenderer } from "./tile-renderer";
import type { WitnessShape } from "./witness-overlay";
import { createWitnessRenderer, type WitnessRenderer } from "./witness-renderer";
import type { GeneratedWorld } from "./world-dump";

const ZOOM_PER_PIXEL = 0.002;
const PIXELS_PER_LINE = 16;
const TURN_MS = 180;
const TURN_KEYS: Record<string, number> = { q: -1, e: 1 };
const TYPING_TARGETS = "input:not([type=checkbox], [type=radio]), textarea, select, [contenteditable]";

export interface MapCanvas {
    fit: () => void;
    /** Turns the map by `steps` of 45 degrees, animated: positive is the game's rotate right (E). */
    turn: (steps: number) => void;
    /** Draws the entities of the groups `visibility` shows, and hides the rest. */
    show: (visibility: GroupVisibility) => void;
    /** Rings `points`, interleaved world `x, z`, over the entities, whichever groups are shown. */
    highlight: (points: Float32Array) => void;
    /** Centres the map on `point`, zooming in to at least `scale` pixels per world unit when given. */
    centre: (point: WorldPoint, scale?: number) => void;
    /** Calls `listener` with the view now and after every redraw, until the returned function is called. */
    watch: (listener: (view: MapView, viewport: Size) => void) => () => void;
    /** Draws `shapes` over the entities, whatever groups are shown, in place of the witnesses drawn before. */
    witnesses: (shapes: WitnessShape[]) => void;
    dispose: () => void;
}

/**
 * Draws the world's tiles and its entity layer on the canvas, sized to the canvas's CSS box, and pans on drag, zooms
 * to the cursor on wheel and turns on Q/E like the game. It starts with every entity group hidden. Throws when the
 * browser can't draw it.
 */
export function mountMapCanvas(canvas: HTMLCanvasElement, world: GeneratedWorld, layer: EntityLayer): MapCanvas {
    const gl = canvas.getContext("webgl2", { alpha: true, antialias: false });
    if (gl === null) throw new Error("This browser can't draw the map: it needs WebGL2.");
    const tiles = createTileRenderer(gl, world);
    const entities = createEntityRenderer(gl, layer);
    const highlights = createHighlightRenderer(gl);
    const watchers = new Set<(view: MapView, viewport: Size) => void>();
    let overlay: WitnessRenderer | null = null;
    let viewport: Size = { width: canvas.clientWidth, height: canvas.clientHeight };
    let view: MapView = fitView(world, viewport);
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
            gl.clearColor(0, 0, 0, 0);
            gl.clear(gl.COLOR_BUFFER_BIT);
            tiles.draw(view, viewport);
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
            move(zoomAt(view, viewport, { x: event.clientX - box.left, y: event.clientY - box.top }, Math.exp(-pixels * ZOOM_PER_PIXEL)));
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
        fit: () => move(fitView(world, viewport, turning?.to ?? view.heading)),
        turn,
        show: (visibility) => {
            entities.show(visibility);
            redraw();
        },
        highlight: (points) => {
            highlights.highlight(points);
            redraw();
        },
        centre: (point, scale = 0) => move({ ...view, centerX: point.x, centerZ: point.z, scale: Math.max(view.scale, scale) }),
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
            tiles.dispose();
            entities.dispose();
            highlights.dispose();
            overlay?.dispose();
        }
    };
}
