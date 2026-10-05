import { afterEach, describe, expect, it, vi } from "vitest";
import { MAP_TEXTURES } from "@/lib/catalog/world";
import { createRoadRenderer } from "@/lib/world-map/canvas/road-renderer";
import { FORGOTTEN_BRIGHTNESS } from "@/lib/world-map/terrain/terrain-renderer";
import { fakeGl } from "./fake-gl";

const VIEW = { centerX: 0, centerZ: 0, scale: 2, heading: 0 };
const VIEWPORT = { width: 800, height: 600 };
const PAVED = { weight: 3, points: new Int32Array([0, 0, 1000, 0, 1000, 1000]) };
const DIRT = { weight: 1, points: new Int32Array([0, 0, -1000, 500, -1000, 1000]) };

const serveTextures = () => {
    const close = vi.fn();
    const fetch = vi.fn(async (_url: string) => ({ ok: true, blob: async () => new Blob() }));
    vi.stubGlobal("fetch", fetch);
    vi.stubGlobal("createImageBitmap", vi.fn(async () => ({ close })));
    return { close, fetch };
};

afterEach(() => vi.unstubAllGlobals());

describe("the road renderer", () => {
    it("draws nothing until the textures have downloaded, then every strip of each kind of road", async () => {
        serveTextures();
        const onBuilt = vi.fn();
        const { gl, names } = fakeGl();
        const roads = createRoadRenderer(gl, [PAVED, DIRT], onBuilt);
        roads.draw(VIEW, VIEWPORT);
        expect(names("drawArrays")).toHaveLength(0);
        await roads.built;
        expect(onBuilt).toHaveBeenCalledOnce();
        roads.draw(VIEW, VIEWPORT);
        expect(names("drawArrays")).toHaveLength(7);
    });

    it("downloads only the textures the roads use, and frees the bitmaps", async () => {
        const { close, fetch } = serveTextures();
        const { gl } = fakeGl();
        await createRoadRenderer(gl, [DIRT], () => undefined).built;
        const { pathnoise, roadcorner, roadedge, roadendcap } = MAP_TEXTURES.road;
        expect(fetch.mock.calls.map(([url]) => url).sort())
            .toEqual([pathnoise, roadcorner, roadedge, roadendcap].sort());
        expect(close).toHaveBeenCalledTimes(4);
    });

    it("dims to the fog brightness, and back", async () => {
        serveTextures();
        const { gl, uniformValues } = fakeGl();
        const roads = createRoadRenderer(gl, [PAVED], () => undefined);
        await roads.built;
        roads.draw(VIEW, VIEWPORT);
        roads.darken(false);
        roads.draw(VIEW, VIEWPORT);
        expect(uniformValues("brightness", "uniform1f")).toEqual([[FORGOTTEN_BRIGHTNESS], [1]]);
    });

    it("draws nothing while hidden or without roads", async () => {
        serveTextures();
        const { gl, names } = fakeGl();
        const roads = createRoadRenderer(gl, [PAVED], () => undefined);
        await roads.built;
        roads.show(false);
        roads.draw(VIEW, VIEWPORT);
        const bare = createRoadRenderer(gl, [], () => undefined);
        await bare.built;
        bare.draw(VIEW, VIEWPORT);
        expect(names("drawArrays")).toHaveLength(0);
    });

    it("frees the downloaded bitmaps instead of uploading them when disposed first", async () => {
        const { close } = serveTextures();
        const { gl, names } = fakeGl();
        const roads = createRoadRenderer(gl, [PAVED], () => undefined);
        roads.dispose();
        await roads.built;
        expect(close).toHaveBeenCalledTimes(5);
        expect(names("texImage2D")).toHaveLength(0);
    });

    it("frees everything it created", async () => {
        serveTextures();
        const { gl, names } = fakeGl();
        const roads = createRoadRenderer(gl, [PAVED, DIRT], () => undefined);
        await roads.built;
        roads.dispose();
        for (const kind of ["Buffer", "VertexArray", "Program", "Texture"]) {
            expect(names(`delete${kind}`).length).toBe(names(`create${kind}`).length);
        }
    });
});
