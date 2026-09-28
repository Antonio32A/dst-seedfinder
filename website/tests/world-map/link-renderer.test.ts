import { describe, expect, it } from "vitest";
import { createLinkRenderer } from "@/lib/world-map/canvas/link-renderer";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";

type Call = [name: string, ...args: unknown[]];

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });
const VIEW = { centerX: 0, centerZ: 0, scale: 2, heading: 0 };
const VIEWPORT = { width: 800, height: 600 };

function fakeGl() {
    const calls: Call[] = [];
    const gl = new Proxy({}, {
        get: (_, property: string) => {
            if (property === property.toUpperCase()) return property;
            return (...args: unknown[]) => {
                calls.push([property, ...args]);
                if (property === "getUniformLocation") return { uniform: args[1] };
                if (property === "getAttribLocation") return 0;
                return { created: property };
            };
        }
    }) as unknown as WebGL2RenderingContext;
    const names = (name: string) => calls.filter(([call]) => call === name);
    return { gl, names };
}

const linked = entityLayer({ prefabs: [prefab("wormhole", 0, 0, 800, -800)], links: new Uint32Array([0, 1]) });
const unlinked = entityLayer({ prefabs: [prefab("evergreen", 0, 0)], links: new Uint32Array(0) });

describe("the link renderer", () => {
    it("draws one line per link, blended, whichever prefabs are shown", () => {
        const { gl, names } = fakeGl();
        const renderer = createLinkRenderer(gl, linked);
        renderer.show(true);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toEqual([["drawArraysInstanced", "TRIANGLE_STRIP", 0, 4, 1]]);
        expect(names("enable")).toEqual([["enable", "BLEND"]]);
    });

    it("draws nothing until shown, and again after being hidden and shown", () => {
        const { gl, names } = fakeGl();
        const renderer = createLinkRenderer(gl, linked);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toHaveLength(0);
        renderer.show(true);
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

    it("frees what it created", () => {
        const { gl, names } = fakeGl();
        createLinkRenderer(gl, linked).dispose();
        expect(names("deleteBuffer")).toHaveLength(2);
        expect(names("deleteVertexArray")).toHaveLength(1);
        expect(names("deleteProgram")).toHaveLength(1);
    });
});
