import { describe, expect, it } from "vitest";
import { mapPath, parseMapRoute } from "../lib/world-map/map-route";

describe("the map route", () => {
    it("links a seed's map on its platform", () => {
        expect(mapPath("linux", 1234)).toBe("/map/linux/1234");
        expect(parseMapRoute("linux", "1234")).toEqual({ platform: "linux", seed: 1234 });
        expect(parseMapRoute("windows", "4294967295")).toEqual({ platform: "windows", seed: 4294967295 });
    });

    it.each(["mac", "Windows", ""])("refuses the platform %j", (platform) => {
        expect(parseMapRoute(platform, "1")).toEqual({ error: expect.stringMatching(/platform/) });
    });

    it.each(["-1", "4294967296", "1.5", "1e3", "abc", " 1", ""])("refuses the seed %j", (seed) => {
        expect(parseMapRoute("windows", seed)).toEqual({ error: expect.stringMatching(/seed/) });
    });
});
