import { describe, expect, it } from "vitest";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { decodeShareParam, encodeShareParam } from "@/lib/criteria/search-state";
import { mapPath, type MapSeed, parseMapConfig, parseMapRoute, pickedMapPath } from "@/lib/world-map/map-route";

const CONFIG: SeedfinderConfig = {
    version: 3,
    build: 756039,
    platform: "windows",
    filters: [{ distances: [{ from: "multiplayer_portal", to: "pigking", max: 400 }] }]
};

const route = (path: string) => {
    const [platform, ...segments] = path.split("/");
    return parseMapRoute(platform, segments);
};

const world = (map: Partial<MapSeed>): MapSeed => ({ platform: "linux", shard: "forest", build: 756039, seed: 1234, ...map });

describe("the map route", () => {
    it.each([
        ["linux/1234", world({})],
        ["windows/4294967295", world({ platform: "windows", seed: 4294967295 })],
        ["linux/forest/1234", world({})],
        ["linux/caves/1234", world({ shard: "caves" })],
        ["linux/756039/1234", world({})],
        ["linux/forest/756039/1234", world({})],
        ["linux/caves/756039/1234", world({ shard: "caves" })],
        ["linux/757748/1234", world({ build: 757748 })],
        ["linux/forest/757748/0007", world({ build: 757748, seed: 7 })],
        ["linux/caves/757748/1234", world({ shard: "caves", build: 757748 })]
    ])("opens %s", (path, expected) => {
        expect(route(path)).toEqual(expected);
    });

    it("reads a number after the shard as the seed, and two as the build and the seed", () => {
        expect(route("linux/caves/123")).toEqual(world({ shard: "caves", seed: 123 }));
        expect(route("linux/caves/756039/123")).toEqual(world({ shard: "caves", seed: 123 }));
        expect(route("linux/caves/756039")).toEqual(world({ shard: "caves", seed: 756039 }));
    });

    it.each(["linux/123/1234", "linux/caves/1/1234", "linux/abc/1234", "linux/forest/-1/1234", "linux/forest/caves/1"])("refuses the unknown build of %s", (path) => {
        expect(route(path)).toEqual({ error: expect.stringMatching(/^There's no build "[^"]+"\. Use 756039 or 757748\.$/) });
    });

    it.each(["linux/caves", "linux/756039/1234/5", "linux/caves/756039/1/2"])("refuses %s, which isn't a map", (path) => {
        expect(route(path)).toEqual({ error: expect.stringMatching(/no map/) });
    });

    it.each(["mac", "Windows", ""])("refuses the platform %j", (platform) => {
        expect(parseMapRoute(platform, ["1"])).toEqual({ error: expect.stringMatching(/platform/) });
    });

    it.each(["-1", "4294967296", "1.5", "1e3", "abc", " 1", ""])("refuses the seed %j", (seed) => {
        expect(parseMapRoute("windows", [seed])).toEqual({ error: expect.stringMatching(/seed/) });
        expect(parseMapRoute("windows", ["caves", "756039", seed])).toEqual({ error: expect.stringMatching(/seed/) });
    });

    it("links a map with its build, the caves with their shard word", () => {
        expect(mapPath(world({}))).toBe("/map/linux/756039/1234");
        expect(mapPath(world({ shard: "caves" }))).toBe("/map/linux/caves/756039/1234");
        expect(mapPath(world({ build: 757748, platform: "windows", seed: 7 }))).toBe("/map/windows/757748/7");
    });

    it.each([
        world({}),
        world({ shard: "caves", seed: 0 }),
        world({ build: 757748, platform: "windows", seed: 4294967295 })
    ])("reads back the link of %j", (map) => {
        expect(route(mapPath(map).replace(/^\/map\//, ""))).toEqual(map);
    });

    it("links a search result to the route of its shard and build", () => {
        const link = new URL(mapPath(world({ shard: "caves", seed: 7 }), { ...CONFIG, shard: "caves" }), "https://example.com");
        expect(link.pathname).toBe("/map/linux/caves/756039/7");
        expect(decodeShareParam(link.searchParams.get("c")!)).toEqual({ ...CONFIG, shard: "caves" });
    });

    it("evaluates a linked config on the map's platform, shard and build", () => {
        expect(parseMapConfig(encodeShareParam(CONFIG), { platform: "linux", shard: "forest", build: 756039 }))
            .toEqual({ config: { ...CONFIG, shard: "forest", platform: "linux" } });
        expect(parseMapConfig(encodeShareParam(CONFIG), { platform: "linux", shard: "caves", build: 757748 }))
            .toEqual({ config: { ...CONFIG, shard: "caves", platform: "linux", build: 757748 } });
    });

    it("evaluates a v1 link's criteria as generation and filters, for the build it was written for", () => {
        const old = { version: 1, criteria: [{ distances: [{ from: "multiplayer_portal", to: "pigking", max: 400 }] }] };
        expect(parseMapConfig(encodeShareParam(old as unknown as SeedfinderConfig), { platform: "windows", shard: "forest", build: 756039 }))
            .toEqual({ config: { ...CONFIG, shard: "forest" } });
    });

    it.each([
        ["isn't a share param", "not base64!"],
        ["isn't a config", encodeShareParam({ ...CONFIG, filters: "none" } as unknown as SeedfinderConfig)]
    ])("refuses a linked config that %s", (_, share) => {
        expect(parseMapConfig(share, { platform: "linux", shard: "forest", build: 756039 })).toEqual({ error: expect.stringMatching(/\S/) });
    });

    it.each([
        ["windows", "forest", 756039, "1234", "/map/windows/756039/1234"],
        ["linux", "caves", 756039, "1234", "/map/linux/caves/756039/1234"],
        ["linux", "forest", 756039, " 42 ", "/map/linux/756039/42"],
        ["windows", "caves", 756039, "0007", "/map/windows/caves/756039/7"],
        ["windows", "forest", 757748, "4294967295", "/map/windows/757748/4294967295"],
        ["windows", "caves", 757748, "1", "/map/windows/caves/757748/1"]
    ] as const)("opens the picked %s %s %s seed %j at its map", (platform, shard, build, seed, path) => {
        expect(pickedMapPath(platform, seed, shard, build)).toEqual({ path });
    });

    it.each(["", "-1", "4294967296", "1.5", "12 34", "abc"])("refuses to open the picked seed %j", (seed) => {
        expect(pickedMapPath("windows", seed, "forest", 756039)).toEqual({ error: expect.stringMatching(/seed/) });
    });
});
