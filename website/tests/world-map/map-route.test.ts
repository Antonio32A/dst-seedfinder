import { describe, expect, it } from "vitest";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { decodeShareParam, encodeShareParam } from "@/lib/criteria/search-state";
import { mapPath, parseMapConfig, parseMapRoute, pickedMapPath } from "@/lib/world-map/map-route";

const CONFIG: SeedfinderConfig = {
    version: 1,
    platform: "windows",
    criteria: [{ distances: [{ from: "multiplayer_portal", to: "pigking", max: 400 }] }]
};

describe("the map route", () => {
    it("links a seed's map on its platform", () => {
        expect(mapPath("linux", 1234)).toBe("/map/linux/1234");
        expect(parseMapRoute("linux", "1234")).toEqual({ platform: "linux", shard: "forest", seed: 1234 });
        expect(parseMapRoute("windows", "4294967295")).toEqual({ platform: "windows", shard: "forest", seed: 4294967295 });
    });

    it("links the forest map at both of its routes and the caves map at its own", () => {
        expect(mapPath("linux", 1234, undefined, "forest")).toBe("/map/linux/1234");
        expect(mapPath("linux", 1234, undefined, "caves")).toBe("/map/linux/caves/1234");
        expect(parseMapRoute("linux", "1234", "forest")).toEqual(parseMapRoute("linux", "1234"));
        expect(parseMapRoute("linux", "1234", "caves")).toEqual({ platform: "linux", shard: "caves", seed: 1234 });
    });

    it("links a search result to the route of its shard", () => {
        const link = new URL(mapPath("linux", 7, { ...CONFIG, shard: "caves" }), "https://example.com");
        expect(link.pathname).toBe("/map/linux/caves/7");
        expect(decodeShareParam(link.searchParams.get("c")!)).toEqual({ ...CONFIG, shard: "caves" });
    });

    it("carries a search's config in the link", () => {
        const link = new URL(mapPath("windows", 7, CONFIG), "https://example.com");
        expect(link.pathname).toBe("/map/windows/7");
        expect(decodeShareParam(link.searchParams.get("c")!)).toEqual(CONFIG);
    });

    it("evaluates a linked config on the map's platform", () => {
        expect(parseMapConfig(encodeShareParam(CONFIG), "linux")).toEqual({ config: { ...CONFIG, shard: "forest", platform: "linux" } });
    });

    it("evaluates a linked config on the map's shard", () => {
        expect(parseMapConfig(encodeShareParam(CONFIG), "linux", "caves")).toEqual({ config: { ...CONFIG, shard: "caves", platform: "linux" } });
    });

    it.each([
        ["isn't a share param", "not base64!"],
        ["isn't a config", encodeShareParam({ ...CONFIG, criteria: "none" } as unknown as SeedfinderConfig)]
    ])("refuses a linked config that %s", (_, share) => {
        expect(parseMapConfig(share, "linux")).toEqual({ error: expect.stringMatching(/\S/) });
    });

    it.each(["mac", "Windows", ""])("refuses the platform %j", (platform) => {
        expect(parseMapRoute(platform, "1")).toEqual({ error: expect.stringMatching(/platform/) });
    });

    it.each(["-1", "4294967296", "1.5", "1e3", "abc", " 1", ""])("refuses the seed %j", (seed) => {
        expect(parseMapRoute("windows", seed)).toEqual({ error: expect.stringMatching(/seed/) });
    });

    it.each([
        ["windows", "forest", "1234", "/map/windows/1234"],
        ["linux", "caves", "1234", "/map/linux/caves/1234"],
        ["linux", "forest", " 42 ", "/map/linux/42"],
        ["windows", "caves", "0007", "/map/windows/caves/7"],
        ["windows", "forest", "4294967295", "/map/windows/4294967295"]
    ] as const)("opens the picked %s %s seed %j at its map", (platform, shard, seed, path) => {
        expect(pickedMapPath(platform, seed, shard)).toEqual({ path });
    });

    it.each(["", "-1", "4294967296", "1.5", "12 34", "abc"])("refuses to open the picked seed %j", (seed) => {
        expect(pickedMapPath("windows", seed, "forest")).toEqual({ error: expect.stringMatching(/seed/) });
    });
});
