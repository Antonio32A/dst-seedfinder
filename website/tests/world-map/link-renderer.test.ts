import { describe, expect, it } from "vitest";
import { createLinkRenderer } from "@/lib/world-map/canvas/link-renderer";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";
import { fakeGl } from "./fake-gl";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });
const VIEW = { centerX: 0, centerZ: 0, scale: 2, heading: 0 };
const VIEWPORT = { width: 800, height: 600 };

const linked = entityLayer({ prefabs: [prefab("wormhole", 0, 0, 800, -800)], links: new Uint32Array([0, 1]) });
const unlinked = entityLayer({ prefabs: [prefab("evergreen", 0, 0)], links: new Uint32Array(0) });

describe("the link renderer", () => {
    it("draws one instance per link, only once shown", () => {
        const { gl, names } = fakeGl();
        const renderer = createLinkRenderer(gl, linked);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toHaveLength(0);
        renderer.show(true);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced").map(([, , , , count]) => count)).toEqual([1]);
        renderer.show(false);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toHaveLength(1);
    });

    it("draws nothing without links", () => {
        const { gl, names } = fakeGl();
        const renderer = createLinkRenderer(gl, unlinked);
        renderer.show(true);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toHaveLength(0);
    });

    it("frees everything it created", () => {
        const { gl, names } = fakeGl();
        createLinkRenderer(gl, linked).dispose();
        for (const kind of ["Buffer", "VertexArray", "Program"]) {
            expect(names(`delete${kind}`).length).toBe(names(`create${kind}`).length);
        }
    });
});
