import { afterEach, describe, expect, it, vi } from "vitest";
import { MAP_TEXTURES } from "@/lib/catalog/world";
import { createIconRenderer } from "@/lib/world-map/canvas/icon-renderer";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";
import { iconLayer } from "@/lib/world-map/legend/icon-layer";

type Call = [name: string, ...args: unknown[]];

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const layer = entityLayer({
    prefabs: [prefab("evergreen", 100, 0, 200, 0), prefab("amulet", 900, 900), prefab("multiplayer_portal", 0, 0)],
    links: new Uint32Array(0)
});
const icons = iconLayer(layer);
const FIRST_UNIT = 33984;
const VIEW = { centerX: 0, centerZ: 0, scale: 2, heading: 0 };
const VIEWPORT = { width: 800, height: 600 };
const ACCENT = [252, 88, 33];

function fakeGl() {
    const calls: Call[] = [];
    let locations = 0;
    const gl = new Proxy({}, {
        get: (_, property: string) => {
            if (property === "TEXTURE0") return FIRST_UNIT;
            if (property === property.toUpperCase()) return property;
            return (...args: unknown[]) => {
                calls.push([property, ...args]);
                if (property === "getUniformLocation") return { uniform: args[1] };
                if (property === "getAttribLocation") return locations++;
                if (property.startsWith("get") && property.endsWith("Parameter")) return true;
                return { created: property };
            };
        }
    }) as unknown as WebGL2RenderingContext;
    const names = (name: string) => calls.filter(([call]) => call === name);
    return { gl, calls, names };
}

const serveSheet = () => {
    const close = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, blob: async () => new Blob() })));
    const createImageBitmap = vi.fn(async () => ({ close }));
    vi.stubGlobal("createImageBitmap", createImageBitmap);
    return { close, createImageBitmap };
};

afterEach(() => vi.unstubAllGlobals());

describe("the icon renderer", () => {
    it("draws nothing until the sheet has downloaded, then one instance per icon, and again for the outlined ones", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const onBuilt = vi.fn();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, onBuilt);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toHaveLength(0);
        await renderer.built;
        expect(onBuilt).toHaveBeenCalledOnce();
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toEqual([
            ["drawArraysInstanced", "TRIANGLE_STRIP", 0, 4, 3],
            ["drawArraysInstanced", "TRIANGLE_STRIP", 0, 4, 3]
        ]);
    });

    it("samples the sheet trilinearly with edge clamping on its own texture unit, from the game's own mip levels", async () => {
        const { close, createImageBitmap } = serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        await renderer.built;
        const parameters = names("texParameteri").map(([, , parameter, value]) => [parameter, value]);
        expect(parameters).toEqual(expect.arrayContaining([
            ["TEXTURE_MIN_FILTER", "LINEAR_MIPMAP_LINEAR"],
            ["TEXTURE_MAG_FILTER", "LINEAR"],
            ["TEXTURE_WRAP_S", "CLAMP_TO_EDGE"],
            ["TEXTURE_WRAP_T", "CLAMP_TO_EDGE"]
        ]));
        const levels = MAP_TEXTURES.iconSheet.levels;
        expect(names("generateMipmap")).toHaveLength(0);
        expect(parameters).toContainEqual(["TEXTURE_MAX_LEVEL", levels.length - 1]);
        expect(createImageBitmap.mock.calls.map(([, ...region]) => region.slice(0, 4)))
            .toEqual(levels.map(({ x, y, width, height }) => [x, y, width, height]));
        expect(names("texImage2D").map(([, , level]) => level)).toEqual(levels.map((_, mip) => mip));
        expect(names("activeTexture")[0][1]).toBe(FIRST_UNIT + 3);
        expect(close).toHaveBeenCalledTimes(levels.length);
    });

    it("blends the premultiplied sheet by its alpha and leaves the canvas alpha alone", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        await renderer.built;
        renderer.draw(VIEW, VIEWPORT);
        expect(names("blendFuncSeparate")).toEqual([["blendFuncSeparate", "SRC_ALPHA", "ONE_MINUS_SRC_ALPHA", "ZERO", "ONE"]]);
    });

    it("looks its uniforms up once and sorts the icons again only when the heading changes", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        await renderer.built;
        const lookups = names("getUniformLocation").length;
        renderer.draw(VIEW, VIEWPORT);
        renderer.draw({ ...VIEW, scale: 4 }, VIEWPORT);
        renderer.draw({ ...VIEW, heading: 45 }, VIEWPORT);
        expect(names("getUniformLocation")).toHaveLength(lookups);
        expect(names("bufferData").filter(([, , , usage]) => usage === "DYNAMIC_DRAW")).toHaveLength(2);
    });

    it("dims with the fog until it's lifted", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        await renderer.built;
        const brightness = () => names("uniform1f")
            .filter(([, location]) => (location as { uniform: string }).uniform === "brightness").map(([, , value]) => value);
        renderer.draw(VIEW, VIEWPORT);
        renderer.darken(false);
        renderer.draw(VIEW, VIEWPORT);
        expect(brightness()).toEqual([0.7, 1]);
    });

    const uniformValues = (names: (name: string) => Call[], name: string, kind: string) => names(kind)
        .filter(([, location]) => (location as { uniform: string }).uniform === name).map(([, , ...value]) => value);

    it("draws the plain icons, then the highlighted and hovered ones on top", async () => {
        serveSheet();
        const { gl, calls } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        await renderer.built;
        renderer.draw(VIEW, VIEWPORT);
        const sequence = calls
            .filter(([name, location]) => name === "drawArraysInstanced"
                || (name === "uniform1f" && (location as { uniform: string }).uniform === "lifted"))
            .map(([name, ...args]) => (name === "uniform1f" ? `lifted ${args[1]}` : "draw"));
        expect(sequence).toEqual(["lifted 0", "draw", "lifted 1", "draw"]);
    });

    it("outlines in the accent it was given, as unit floats", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        expect(uniformValues(names, "accent", "uniform3fv")).toEqual([[ACCENT.map((channel) => channel / 255)]]);
    });

    it("passes the hovered entity to the shader on every draw, and none by default", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        await renderer.built;
        renderer.draw(VIEW, VIEWPORT);
        renderer.hover({ prefab: 1, x: 9, z: 9 });
        renderer.draw(VIEW, VIEWPORT);
        expect(uniformValues(names, "hovered", "uniform3f")).toEqual([[-1, 0, 0], [1, 9, 9]]);
    });

    it("dilates the icon's alpha in one pass, by screen pixels, within the icon's own cell", () => {
        serveSheet();
        const { gl, calls } = fakeGl();
        createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        const [vertex, fragment] = calls.filter(([name]) => name === "shaderSource").map(([, , source]) => String(source));
        expect(fragment).toContain("for (int ring = 0; ring < 2; ring++)");
        expect(fragment).toContain("for (int direction = 0; direction < 8; direction++)");
        expect(fragment).toContain("texelsPerPixel");
        expect(fragment).toContain("step(bounds.xy, at) * step(at, bounds.xy + bounds.zw)");
        expect(fragment).toContain("outlined > 0.5 ? mix(accent, fill, own.a) : fill");
        expect(vertex).toContain("highlight ? 3.0 : 0.0");
        expect(vertex).toContain("highlight != (lifted > 0.5)");
    });

    it("rejects when the sheet can't be downloaded", async () => {
        vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 404 })));
        const { gl } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, ACCENT, () => undefined);
        await expect(renderer.built).rejects.toThrow(`${MAP_TEXTURES.iconSheet.url} answered 404`);
    });
});
