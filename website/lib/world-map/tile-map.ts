import { fitView, type MapView, panBy, type Size, zoomAt } from "./map-view";
import { createTileRenderer } from "./tile-renderer";
import type { GeneratedWorld } from "./world-dump";

const ZOOM_PER_PIXEL = 0.002;
const PIXELS_PER_LINE = 16;

export interface TileMap {
    fit: () => void;
    dispose: () => void;
}

/**
 * Draws the world's tiles on the canvas, sized to the canvas's CSS box, and pans on drag and zooms to the cursor on
 * wheel. Throws when the browser can't draw it.
 */
export function mountTileMap(canvas: HTMLCanvasElement, world: GeneratedWorld): TileMap {
    const renderer = createTileRenderer(canvas, world);
    if (renderer === null) throw new Error("This browser can't draw the map: it needs WebGL2.");
    let viewport: Size = { width: canvas.clientWidth, height: canvas.clientHeight };
    let view: MapView = fitView(world, viewport);
    let frame = 0;
    let grab: { x: number; y: number } | null = null;

    const redraw = () => {
        frame ||= requestAnimationFrame(() => {
            frame = 0;
            renderer.draw(view, viewport);
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

    return {
        fit: () => move(fitView(world, viewport)),
        dispose: () => {
            cancelAnimationFrame(frame);
            resized.disconnect();
            for (const [type, listener] of Object.entries(listeners)) canvas.removeEventListener(type, listener as EventListener);
            renderer.dispose();
        }
    };
}
