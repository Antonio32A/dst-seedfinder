import { describe, expect, it } from "vitest";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { decodeShareParam, encodeShareParam } from "@/lib/criteria/search-state";
import { mapPath, parseMapConfig, parseMapRoute } from "@/lib/world-map/map-route";

const CONFIG: SeedfinderConfig = {
    version: 1,
    platform: "windows",
    criteria: [{ distances: [{ from: "multiplayer_portal", to: "pigking", max: 400 }] }]
};

describe("the map route", () => {
    it("links a seed's map on its platform", () => {
        expect(mapPath("linux", 1234)).toBe("/map/linux/1234");
        expect(parseMapRoute("linux", "1234")).toEqual({ platform: "linux", seed: 1234 });
        expect(parseMapRoute("windows", "4294967295")).toEqual({ platform: "windows", seed: 4294967295 });
    });

    it("carries a search's config in the link", () => {
        const link = new URL(mapPath("windows", 7, CONFIG), "https://example.com");
        expect(link.pathname).toBe("/map/windows/7");
        expect(decodeShareParam(link.searchParams.get("c")!)).toEqual(CONFIG);
    });

    it("evaluates a linked config on the map's platform", () => {
        expect(parseMapConfig(encodeShareParam(CONFIG), "linux")).toEqual({ config: { ...CONFIG, platform: "linux" } });
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
});
