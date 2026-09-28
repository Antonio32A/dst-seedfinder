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
    vi.stubGlobal("createImageBitmap", vi.fn(async () => ({ close })));
    return close;
};

afterEach(() => vi.unstubAllGlobals());

describe("the icon renderer", () => {
    it("draws nothing until the sheet has downloaded, then one instance per icon", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const onBuilt = vi.fn();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, layer.names.indexOf("multiplayer_portal"), onBuilt);
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toHaveLength(0);
        await renderer.built;
        expect(onBuilt).toHaveBeenCalledOnce();
        renderer.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toEqual([["drawArraysInstanced", "TRIANGLE_STRIP", 0, 4, 3]]);
    });

    it("samples the sheet trilinearly with edge clamping on its own texture unit, from mipmaps", async () => {
        const close = serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, 0, () => undefined);
        await renderer.built;
        const parameters = names("texParameteri").map(([, , parameter, value]) => [parameter, value]);
        expect(parameters).toEqual(expect.arrayContaining([
            ["TEXTURE_MIN_FILTER", "LINEAR_MIPMAP_LINEAR"],
            ["TEXTURE_MAG_FILTER", "LINEAR"],
            ["TEXTURE_WRAP_S", "CLAMP_TO_EDGE"],
            ["TEXTURE_WRAP_T", "CLAMP_TO_EDGE"]
        ]));
        expect(names("generateMipmap")).toHaveLength(1);
        expect(names("activeTexture")[0][1]).toBe(FIRST_UNIT + 3);
        expect(close).toHaveBeenCalledOnce();
    });

    it("blends the premultiplied sheet by its alpha and leaves the canvas alpha alone", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, 0, () => undefined);
        await renderer.built;
        renderer.draw(VIEW, VIEWPORT);
        expect(names("blendFuncSeparate")).toEqual([["blendFuncSeparate", "SRC_ALPHA", "ONE_MINUS_SRC_ALPHA", "ZERO", "ONE"]]);
    });

    it("looks its uniforms up once and sorts the icons again only when the heading changes", async () => {
        serveSheet();
        const { gl, names } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, 0, () => undefined);
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
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, 0, () => undefined);
        await renderer.built;
        const brightness = () => names("uniform1f")
            .filter(([, location]) => (location as { uniform: string }).uniform === "brightness").map(([, , value]) => value);
        renderer.draw(VIEW, VIEWPORT);
        renderer.darken(false);
        renderer.draw(VIEW, VIEWPORT);
        expect(brightness()).toEqual([0.7, 1]);
    });

    it("rejects when the sheet can't be downloaded", async () => {
        vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 404 })));
        const { gl } = fakeGl();
        const renderer = createIconRenderer(gl, icons, {} as WebGLTexture, 0, () => undefined);
        await expect(renderer.built).rejects.toThrow(`${MAP_TEXTURES.iconSheet.url} answered 404`);
    });
});
