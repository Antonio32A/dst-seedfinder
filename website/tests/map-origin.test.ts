import { afterEach, describe, expect, it, vi } from "vitest";
import { lastMapOrigin, rememberMapOrigin } from "@/lib/client/map-origin";

const memoryStorage = () => {
    const values = new Map<string, string>();
    return {
        getItem: (key: string) => values.get(key) ?? null,
        setItem: (key: string, value: string) => void values.set(key, value)
    };
};

const brokenStorage = {
    getItem: () => {
        throw new Error("blocked");
    },
    setItem: () => {
        throw new Error("blocked");
    }
};

afterEach(() => {
    vi.unstubAllGlobals();
});

describe("the map viewer's back link", () => {
    it("returns to the search page when nothing was visited first", () => {
        vi.stubGlobal("sessionStorage", memoryStorage());
        expect(lastMapOrigin()).toBe("/");
    });

    it("returns to whichever page was visited last", () => {
        vi.stubGlobal("sessionStorage", memoryStorage());
        rememberMapOrigin("/map");
        expect(lastMapOrigin()).toBe("/map");
        rememberMapOrigin("/");
        expect(lastMapOrigin()).toBe("/");
    });

    it("ignores a stored page that isn't an origin", () => {
        const storage = memoryStorage();
        storage.setItem("mapOrigin", "https://example.com");
        vi.stubGlobal("sessionStorage", storage);
        expect(lastMapOrigin()).toBe("/");
    });

    it("returns to the search page when the storage is blocked", () => {
        vi.stubGlobal("sessionStorage", brokenStorage);
        expect(() => rememberMapOrigin("/map")).not.toThrow();
        expect(lastMapOrigin()).toBe("/");
    });
});
