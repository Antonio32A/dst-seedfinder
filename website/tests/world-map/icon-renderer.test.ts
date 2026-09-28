import { afterEach, describe, expect, it, vi } from "vitest";
import { MAP_TEXTURES } from "@/lib/catalog/world";
import { createIconRenderer } from "@/lib/world-map/canvas/icon-renderer";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";
import { iconLayer } from "@/lib/world-map/legend/icon-layer";
import { FORGOTTEN_BRIGHTNESS } from "@/lib/world-map/terrain/terrain-renderer";
import { fakeGl } from "./fake-gl";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const icons = iconLayer(entityLayer({
    prefabs: [prefab("evergreen", 100, 0, 200, 0), prefab("amulet", 900, 900), prefab("multiplayer_portal", 0, 0)],
    links: new Uint32Array(0)
}));
const VIEW = { centerX: 0, centerZ: 0, scale: 2, heading: 0 };
const VIEWPORT = { width: 800, height: 600 };
const ACCENT = [252, 88, 33];

const serveSheet = () => {
    const close = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, blob: async () => new Blob() })));
    const createImageBitmap = vi.fn(async () => ({ close }));
    vi.stubGlobal("createImageBitmap", createImageBitmap);
    return { close, createImageBitmap };
};

const renderer = (onBuilt = () => undefined) => {
    const fake = fakeGl();
    return { ...fake, icons: createIconRenderer(fake.gl, icons, {} as WebGLTexture, ACCENT, onBuilt) };
};

afterEach(() => vi.unstubAllGlobals());

describe("the icon renderer", () => {
    it("draws nothing until the sheet has downloaded, then every icon plain, then again for the outlined ones", async () => {
        serveSheet();
        const onBuilt = vi.fn();
        const { icons: sheet, names, uniformValues } = renderer(onBuilt);
        sheet.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced")).toHaveLength(0);
        await sheet.built;
        expect(onBuilt).toHaveBeenCalledOnce();
        sheet.draw(VIEW, VIEWPORT);
        expect(names("drawArraysInstanced").map(([, , , , count]) => count)).toEqual([3, 3]);
        expect(uniformValues("lifted", "uniform1f")).toEqual([[0], [1]]);
    });

    it("uploads each of the sheet's own mip levels, without generating any, and frees the bitmaps", async () => {
        const { close, createImageBitmap } = serveSheet();
        const { icons: sheet, names } = renderer();
        await sheet.built;
        const levels = MAP_TEXTURES.iconSheet.levels;
        expect(createImageBitmap.mock.calls.map(([, ...region]) => region.slice(0, 4)))
            .toEqual(levels.map(({ x, y, width, height }) => [x, y, width, height]));
        expect(names("texImage2D").map(([, , level]) => level)).toEqual(levels.map((_, mip) => mip));
        expect(names("generateMipmap")).toHaveLength(0);
        expect(close).toHaveBeenCalledTimes(levels.length);
    });

    it("frees the downloaded levels instead of uploading them when disposed first", async () => {
        const { close } = serveSheet();
        const { icons: sheet, names } = renderer();
        sheet.dispose();
        await sheet.built;
        expect(names("texImage2D")).toHaveLength(0);
        expect(close).toHaveBeenCalledTimes(MAP_TEXTURES.iconSheet.levels.length);
    });

    it("sorts the icons again only when the heading changes", async () => {
        serveSheet();
        const { icons: sheet, names } = renderer();
        await sheet.built;
        sheet.draw(VIEW, VIEWPORT);
        sheet.draw({ ...VIEW, scale: 4 }, VIEWPORT);
        sheet.draw({ ...VIEW, heading: 45 }, VIEWPORT);
        expect(names("bufferData").filter(([, , , usage]) => usage === "DYNAMIC_DRAW")).toHaveLength(2);
    });

    it("dims with the fog until it's lifted", async () => {
        serveSheet();
        const { icons: sheet, uniformValues } = renderer();
        await sheet.built;
        sheet.draw(VIEW, VIEWPORT);
        sheet.darken(false);
        sheet.draw(VIEW, VIEWPORT);
        expect(uniformValues("brightness", "uniform1f")).toEqual([[FORGOTTEN_BRIGHTNESS], [1]]);
    });

    it("passes the hovered entity to the shader on every draw, and none by default", async () => {
        serveSheet();
        const { icons: sheet, uniformValues } = renderer();
        await sheet.built;
        sheet.draw(VIEW, VIEWPORT);
        sheet.hover({ prefab: 1, x: 9, z: 9 });
        sheet.draw(VIEW, VIEWPORT);
        expect(uniformValues("hovered", "uniform3f")).toEqual([[-1, 0, 0], [1, 9, 9]]);
    });

    it("rejects when the sheet can't be downloaded", async () => {
        vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 404 })));
        const { icons: sheet } = renderer();
        await expect(sheet.built).rejects.toThrow(`${MAP_TEXTURES.iconSheet.url} answered 404`);
    });
});
