import { describe, expect, it } from "vitest";
import {
    estimateApplicableSeeds,
    formatApplicableSeeds,
    formatShare,
    mergeOdds,
    parseOddsLine,
    sampleRanges,
    sampleSize
} from "@/lib/prefilter/odds";

const line = (body: object) => `odds ${JSON.stringify(body)}`;

describe("parseOddsLine", () => {
    it("reads the seedfinder's odds line", () => {
        const odds = parseOddsLine(
            line({ seeds: 10, candidates: 4, tasks: { Badlands: 5 }, setpieces: { MooseNest: 7 } })
        );
        expect(odds).toEqual({ seeds: 10, candidates: 4, tasks: { Badlands: 5 }, setpieces: { MooseNest: 7 } });
    });

    it.each([
        ["another line", "scanned 1/2 matches 0 (5 seeds/s)"],
        ["bad JSON", "odds {nope"],
        ["a missing field", line({ seeds: 1, tasks: {}, setpieces: {} })],
        ["a negative count", line({ seeds: 1, candidates: 0, tasks: { a: -1 }, setpieces: {} })],
        ["a fractional count", line({ seeds: 1, candidates: 0, tasks: {}, setpieces: { a: 0.5 } })]
    ])("rejects %s", (_, text) => expect(parseOddsLine(text)).toBeNull());
});

describe("mergeOdds", () => {
    it("adds up seeds, candidates and every name's count", () => {
        const merged = mergeOdds([
            { seeds: 5, candidates: 1, tasks: { a: 2 }, setpieces: { x: 1 } },
            { seeds: 5, candidates: 2, tasks: { a: 1, b: 4 }, setpieces: {} }
        ]);
        expect(merged).toEqual({ seeds: 10, candidates: 3, tasks: { a: 3, b: 4 }, setpieces: { x: 1 } });
    });
});

describe("sampleRanges", () => {
    it.each([1, 3, 7, 24])("covers the sample once with %i slices", (slices) => {
        const ranges = sampleRanges(sampleSize("forest"), slices);
        expect(ranges).toHaveLength(slices);
        expect(ranges[0].from).toBe(0);
        expect(ranges.at(-1)?.to).toBe(sampleSize("forest") - 1);
        ranges.slice(1).forEach((range, index) => expect(range.from).toBe(ranges[index].to + 1));
    });
});

describe("shares", () => {
    it("shows two decimals and a percent sign", () => {
        expect(formatShare(1, 3)).toBe("33.33%");
        expect(formatShare(0, 0)).toBe("0.00%");
    });

    it("scales the candidates' share up to every seed", () => {
        expect(estimateApplicableSeeds({ candidates: 1, seeds: 4 })).toBe(2 ** 30);
        expect(formatApplicableSeeds({ candidates: 1, seeds: 4 })).toBe("1,073,741,824 (25.00%)");
    });
});
