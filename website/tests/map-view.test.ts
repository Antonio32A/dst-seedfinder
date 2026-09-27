import { describe, expect, it } from "vitest";
import { fitView, panBy, screenToWorld, worldToScreen, zoomAt } from "../lib/world-map/map-view";

const WORLD = { width: 425, height: 400 };
const VIEWPORT = { width: 800, height: 600 };
const TILE = 4;

const edges = { left: -2 * WORLD.width - 2, right: 2 * WORLD.width - 2, top: -2 * WORLD.height - 2, bottom: 2 * WORLD.height - 2 };

describe("the map view", () => {
    it("fits the whole world in the viewport, filling it along one side", () => {
        const view = fitView(WORLD, VIEWPORT);
        const topLeft = worldToScreen(view, VIEWPORT, { x: edges.left, z: edges.top });
        const bottomRight = worldToScreen(view, VIEWPORT, { x: edges.right, z: edges.bottom });
        expect(topLeft.x).toBeGreaterThanOrEqual(-1e-9);
        expect(bottomRight.x).toBeLessThanOrEqual(VIEWPORT.width + 1e-9);
        expect(topLeft.y).toBeCloseTo(0);
        expect(bottomRight.y).toBeCloseTo(VIEWPORT.height);
    });

    it("puts tile (0, 0) at the top left and x to the right", () => {
        const view = fitView(WORLD, VIEWPORT);
        const origin = worldToScreen(view, VIEWPORT, { x: -2 * WORLD.width, z: -2 * WORLD.height });
        const east = worldToScreen(view, VIEWPORT, { x: -2 * WORLD.width + TILE, z: -2 * WORLD.height });
        expect(origin.y).toBeLessThan(VIEWPORT.height / 2);
        expect(east.x).toBeGreaterThan(origin.x);
    });

    it("zooms around the cursor, keeping the world point under it", () => {
        const view = fitView(WORLD, VIEWPORT);
        const cursor = { x: 610, y: 95 };
        const zoomed = zoomAt(view, VIEWPORT, cursor, 3);
        expect(zoomed.scale).toBeCloseTo(3 * view.scale);
        const before = screenToWorld(view, VIEWPORT, cursor);
        const after = screenToWorld(zoomed, VIEWPORT, cursor);
        expect(after.x).toBeCloseTo(before.x);
        expect(after.z).toBeCloseTo(before.z);
    });

    it("stops zooming in at a few screen pixels per world unit and out at a speck", () => {
        const view = fitView(WORLD, VIEWPORT);
        expect(zoomAt(view, VIEWPORT, { x: 0, y: 0 }, 1e6).scale).toBe(zoomAt(view, VIEWPORT, { x: 0, y: 0 }, 1e7).scale);
        expect(zoomAt(view, VIEWPORT, { x: 0, y: 0 }, 1e-6).scale).toBe(zoomAt(view, VIEWPORT, { x: 0, y: 0 }, 1e-7).scale);
    });

    it("drags the world along with the pointer", () => {
        const view = fitView(WORLD, VIEWPORT);
        const grabbed = screenToWorld(view, VIEWPORT, { x: 300, y: 200 });
        const moved = worldToScreen(panBy(view, 40, -25), VIEWPORT, grabbed);
        expect(moved.x).toBeCloseTo(340);
        expect(moved.y).toBeCloseTo(175);
    });
});
