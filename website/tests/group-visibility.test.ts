import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MAP_GROUPS } from "../lib/world-map/entity-layer";
import { readGroupVisibility, storeGroupVisibility } from "../lib/world-map/group-visibility";

const memoryStorage = () => {
    const items = new Map<string, string>();
    return {
        getItem: (key: string) => items.get(key) ?? null,
        setItem: (key: string, value: string) => void items.set(key, value)
    };
};

const hiddenGroups = (visibility: Record<string, boolean>) =>
    MAP_GROUPS.filter(({ id }) => !visibility[id]).map(({ id }) => id);

describe("the entity groups a browser shows", () => {
    beforeEach(() => vi.stubGlobal("localStorage", memoryStorage()));
    afterEach(() => vi.unstubAllGlobals());

    it("starts with the common groups hidden and the rest shown", () => {
        expect(hiddenGroups(readGroupVisibility()))
            .toEqual(["trees", "rocks", "plants", "mobs & dens", "items", "other"]);
    });

    it("remembers the groups a browser toggled", () => {
        storeGroupVisibility({ ...readGroupVisibility(), trees: true, landmarks: false });
        expect(hiddenGroups(readGroupVisibility()))
            .toEqual(["landmarks", "rocks", "plants", "mobs & dens", "items", "other"]);
    });

    it("falls back to the defaults when the browser's storage fails or holds something else", () => {
        const defaults = readGroupVisibility();
        localStorage.setItem("dst-seedfinder:map-groups:v1", "not json");
        expect(readGroupVisibility()).toEqual(defaults);
        localStorage.setItem("dst-seedfinder:map-groups:v1", "[true]");
        expect(readGroupVisibility()).toEqual(defaults);
        const failing = () => {
            throw new DOMException("The storage is off.", "SecurityError");
        };
        vi.stubGlobal("localStorage", { getItem: failing, setItem: failing });
        expect(readGroupVisibility()).toEqual(defaults);
        expect(() => storeGroupVisibility(defaults)).not.toThrow();
    });
});
