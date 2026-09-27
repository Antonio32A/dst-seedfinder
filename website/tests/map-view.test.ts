import { describe, expect, it } from "vitest";
import { fitView, panBy, screenToWorld, turnView, worldToScreen, zoomAt } from "../lib/world-map/map-view";

const WORLD = { width: 425, height: 400 };
const VIEWPORT = { width: 800, height: 600 };
const TILE = 4;

const edges = {
    left: -2 * WORLD.width - 2,
    right: 2 * WORLD.width - 2,
    top: -2 * WORLD.height - 2,
    bottom: 2 * WORLD.height - 2
};

describe("the map view", () => {
    it.each([45, 90, 180, 315])("fits the whole world in the viewport, filling one side, at heading %i", (heading) => {
        const view = fitView(WORLD, VIEWPORT, heading);
        const corners = [
            worldToScreen(view, VIEWPORT, { x: edges.left, z: edges.top }),
            worldToScreen(view, VIEWPORT, { x: edges.right, z: edges.top }),
            worldToScreen(view, VIEWPORT, { x: edges.left, z: edges.bottom }),
            worldToScreen(view, VIEWPORT, { x: edges.right, z: edges.bottom })
        ];
        const xs = corners.map((corner) => corner.x);
        const ys = corners.map((corner) => corner.y);
        expect(Math.min(...xs)).toBeGreaterThanOrEqual(-1e-9);
        expect(Math.max(...xs)).toBeLessThanOrEqual(VIEWPORT.width + 1e-9);
        expect(Math.min(...ys)).toBeCloseTo(0);
        expect(Math.max(...ys)).toBeCloseTo(VIEWPORT.height);
    });

    it("opens like the game's map at the default camera heading: world +x up and right, +z up and left", () => {
        const view = fitView(WORLD, VIEWPORT);
        const center = worldToScreen(view, VIEWPORT, { x: view.centerX, z: view.centerZ });
        const east = worldToScreen(view, VIEWPORT, { x: view.centerX + TILE, z: view.centerZ });
        const south = worldToScreen(view, VIEWPORT, { x: view.centerX, z: view.centerZ + TILE });
        expect(east.x - center.x).toBeCloseTo(center.y - east.y);
        expect(east.x).toBeGreaterThan(center.x);
        expect(center.x - south.x).toBeCloseTo(center.y - south.y);
        expect(south.x).toBeLessThan(center.x);
    });

    const HALF = Math.SQRT1_2;
    it.each([
        { heading: 45, east: { x: HALF, y: -HALF }, south: { x: -HALF, y: -HALF } },
        { heading: 90, east: { x: 1, y: 0 }, south: { x: 0, y: -1 } },
        { heading: 135, east: { x: HALF, y: HALF }, south: { x: HALF, y: -HALF } },
        { heading: 225, east: { x: -HALF, y: HALF }, south: { x: HALF, y: HALF } },
        { heading: 0, east: { x: 0, y: -1 }, south: { x: -1, y: 0 } }
    ])("draws world +x and +z along the game's map axes at heading $heading", ({ heading, east, south }) => {
        const view = { centerX: 30, centerZ: -50, scale: 2, heading };
        const center = worldToScreen(view, VIEWPORT, { x: 30, z: -50 });
        const eastward = worldToScreen(view, VIEWPORT, { x: 31, z: -50 });
        const southward = worldToScreen(view, VIEWPORT, { x: 30, z: -49 });
        expect(center).toEqual({ x: VIEWPORT.width / 2, y: VIEWPORT.height / 2 });
        expect((eastward.x - center.x) / 2).toBeCloseTo(east.x);
        expect((eastward.y - center.y) / 2).toBeCloseTo(east.y);
        expect((southward.x - center.x) / 2).toBeCloseTo(south.x);
        expect((southward.y - center.y) / 2).toBeCloseTo(south.y);
    });

    it.each([0, 45, 90, 180, 315])("finds the world point under a screen point at heading %i", (heading) => {
        const view = { centerX: 12, centerZ: 7, scale: 0.8, heading };
        const world = screenToWorld(view, VIEWPORT, { x: 123, y: 456 });
        const screen = worldToScreen(view, VIEWPORT, world);
        expect(screen.x).toBeCloseTo(123);
        expect(screen.y).toBeCloseTo(456);
    });

    it("turns the map a 45 degree step about the viewport centre, clockwise on screen for E and back for Q", () => {
        const view = fitView(WORLD, VIEWPORT);
        const above = screenToWorld(view, VIEWPORT, { x: VIEWPORT.width / 2, y: VIEWPORT.height / 2 - 100 });
        const afterE = worldToScreen(turnView(view, 1), VIEWPORT, above);
        expect(afterE.x).toBeCloseTo(VIEWPORT.width / 2 + 100 * Math.SQRT1_2);
        expect(afterE.y).toBeCloseTo(VIEWPORT.height / 2 - 100 * Math.SQRT1_2);
        const afterQ = worldToScreen(turnView(view, -1), VIEWPORT, above);
        expect(afterQ.x).toBeCloseTo(VIEWPORT.width / 2 - 100 * Math.SQRT1_2);
        expect(afterQ.y).toBeCloseTo(VIEWPORT.height / 2 - 100 * Math.SQRT1_2);
    });

    it.each([0, 45, 180])("zooms around the cursor, keeping the world point under it, at heading %i", (heading) => {
        const view = fitView(WORLD, VIEWPORT, heading);
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
        expect(zoomAt(view, VIEWPORT, { x: 0, y: 0 }, 1e6).scale).toBe(zoomAt(view, VIEWPORT, {
            x: 0,
            y: 0
        }, 1e7).scale);
        expect(zoomAt(view, VIEWPORT, { x: 0, y: 0 }, 1e-6).scale).toBe(zoomAt(view, VIEWPORT, {
            x: 0,
            y: 0
        }, 1e-7).scale);
    });

    it.each([0, 45, 180])("drags the world along with the pointer at heading %i", (heading) => {
        const view = fitView(WORLD, VIEWPORT, heading);
        const grabbed = screenToWorld(view, VIEWPORT, { x: 300, y: 200 });
        const moved = worldToScreen(panBy(view, 40, -25), VIEWPORT, grabbed);
        expect(moved.x).toBeCloseTo(340);
        expect(moved.y).toBeCloseTo(175);
    });
});
