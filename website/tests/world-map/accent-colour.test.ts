import { afterEach, describe, expect, it, vi } from "vitest";
import { readAccent } from "@/lib/world-map/canvas/accent-colour";

function withAccent(value: string) {
    vi.stubGlobal("getComputedStyle", () => ({ getPropertyValue: (name: string) => (name === "--highlight" ? value : "") }));
    return readAccent({} as Element);
}

describe("reading the site's highlight colour", () => {
    afterEach(() => vi.unstubAllGlobals());

    it("parses a six digit colour, ignoring the whitespace custom properties keep", () => {
        expect(withAccent(" #fc5821 ")).toEqual([252, 88, 33]);
    });

    it("expands a three digit colour", () => {
        expect(withAccent("#fc0")).toEqual([255, 204, 0]);
    });

    it("fails clearly when the variable is missing", () => {
        expect(() => withAccent("")).toThrow("--highlight is missing");
    });

    it("fails clearly on a colour it can't parse, naming it", () => {
        expect(() => withAccent("rgb(1, 2, 3)")).toThrow('"rgb(1, 2, 3)", not a #rgb or #rrggbb colour');
    });
});
