import { describe, expect, it } from "vitest";
import {
    createEntityRenderer,
    HOVER_MATCH,
    NO_HOVER,
    VISIBILITY_HIGHLIGHTED,
    VISIBILITY_SHOWN
} from "@/lib/world-map/canvas/entity-renderer";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";

type Call = [name: string, ...args: unknown[]];

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });
const layer = entityLayer({
    prefabs: [prefab("evergreen", 100, 0), prefab("amulet", 900, 900), prefab("pigking", 0, 0)],
    links: new Uint32Array(0)
});
const ACCENT = [252, 88, 33];
const VIEW = { centerX: 0, centerZ: 0, scale: 2, heading: 0 };
const VIEWPORT = { width: 800, height: 600 };

function fakeGl() {
    const calls: Call[] = [];
    const gl = new Proxy({}, {
        get: (_, property: string) => {
            if (property === "TEXTURE0") return 0;
            if (property === property.toUpperCase()) return property;
            return (...args: unknown[]) => {
                calls.push([property, ...args]);
                if (property === "getUniformLocation") return { uniform: args[1] };
                if (property === "getAttribLocation") return 0;
                if (property === "getParameter") return new Float32Array([1, 64]);
                return { created: property };
            };
        }
    }) as unknown as WebGL2RenderingContext;
    const names = (name: string) => calls.filter(([call]) => call === name);
    const uploaded = () => names("texSubImage2D").map(([, , , , , , , , , texels]) => Array.from(texels as Uint8Array));
    return { gl, calls, names, uploaded };
}

const iconedEvergreen = Uint8Array.from([1, 0, 0]);

describe("the entity renderer's visibility texture", () => {
    it("holds hidden, shown and highlighted per prefab in red, and whether it has an icon in green", () => {
        const { gl, uploaded } = fakeGl();
        const renderer = createEntityRenderer(gl, layer, iconedEvergreen, ACCENT);
        renderer.show(new Set(["evergreen", "amulet"]));
        renderer.highlight(new Set(["amulet", "pigking"]));
        const [shown, highlighted] = uploaded();
        expect(shown.slice(0, 6)).toEqual([VISIBILITY_SHOWN, 255, VISIBILITY_SHOWN, 0, 0, 0]);
        expect(highlighted.slice(0, 6)).toEqual([VISIBILITY_SHOWN, 255, VISIBILITY_HIGHLIGHTED, 0, VISIBILITY_HIGHLIGHTED, 0]);
    });

    it("shows a highlighted prefab even when it isn't shown, and keeps both across each other's updates", () => {
        const { gl, uploaded } = fakeGl();
        const renderer = createEntityRenderer(gl, layer, iconedEvergreen, ACCENT);
        renderer.highlight(new Set(["pigking"]));
        renderer.show(new Set(["evergreen"]));
        renderer.highlight(new Set());
        const [onlyHighlighted, both, onlyShown] = uploaded().map((texels) => texels.filter((_, at) => at % 2 === 0).slice(0, 3));
        expect(onlyHighlighted).toEqual([0, 0, VISIBILITY_HIGHLIGHTED]);
        expect(both).toEqual([VISIBILITY_SHOWN, 0, VISIBILITY_HIGHLIGHTED]);
        expect(onlyShown).toEqual([VISIBILITY_SHOWN, 0, 0]);
    });

    it("tells the shaders' three states apart by thresholds between the encoded values", () => {
        expect(VISIBILITY_SHOWN / 255).toBeGreaterThan(0.25);
        expect(VISIBILITY_SHOWN / 255).toBeLessThan(0.75);
        expect(VISIBILITY_HIGHLIGHTED / 255).toBeGreaterThan(0.75);
    });
});

describe("the entity renderer's highlight", () => {
    it("rings dots in the accent it was given, as unit floats", () => {
        const { gl, names } = fakeGl();
        createEntityRenderer(gl, layer, iconedEvergreen, ACCENT);
        const accent = names("uniform3fv").filter(([, location]) => (location as { uniform: string }).uniform === "accent");
        expect(accent).toEqual([["uniform3fv", { uniform: "accent" }, ACCENT.map((channel) => channel / 255)]]);
    });

    it("hands the shader the hovered entity on every draw, none by default", () => {
        const { gl, names } = fakeGl();
        const renderer = createEntityRenderer(gl, layer, iconedEvergreen, ACCENT);
        const hovered = () => names("uniform3f")
            .filter(([, location]) => (location as { uniform: string }).uniform === "hovered").map(([, , ...value]) => value);
        renderer.draw(VIEW, VIEWPORT);
        renderer.hover({ prefab: 2, x: 0, z: 0 });
        renderer.draw(VIEW, VIEWPORT);
        renderer.hover(NO_HOVER);
        renderer.draw(VIEW, VIEWPORT);
        expect(hovered()).toEqual([[-1, 0, 0], [2, 0, 0], [-1, 0, 0]]);
    });

    it("matches the hovered entity by prefab and position in the shader, within a tolerance smaller than any two entities' spacing", () => {
        const { gl, calls } = fakeGl();
        createEntityRenderer(gl, layer, iconedEvergreen, ACCENT);
        const [vertex] = calls.filter(([name]) => name === "shaderSource").map(([, , source]) => String(source));
        expect(vertex).toContain(`prefab == hovered.x && distance(position, hovered.yz) < ${HOVER_MATCH}`);
        expect(vertex).toContain("ring = lit(prefab, position)");
    });

    it("only tints a dot with the accent when it's ringed, so no other dot gets an orange fringe", () => {
        const { gl, calls } = fakeGl();
        createEntityRenderer(gl, layer, iconedEvergreen, ACCENT);
        const [, fragment] = calls.filter(([name]) => name === "shaderSource").map(([, , source]) => String(source));
        expect(fragment).toContain("ring > 0.0 ? mix(accent, dot, disc) : dot");
    });
});
