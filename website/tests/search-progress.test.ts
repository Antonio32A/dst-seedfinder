import { describe, expect, it } from "vitest";
import { parseJobResult } from "../lib/jobs/job-result";
import { jobObject, parseOutputLine } from "../lib/jobs/runner-output";
import { parseSpeedLine, SpeedMeter } from "../lib/jobs/search-speed";
import { inRealTime, parseTimingsLine, sumTimings } from "../lib/jobs/search-timings";

const TIMINGS = 'timings {"elapsed_ms":41441,"seeds":65536,"prefilter_ms":12,"generation_ms":16789,"hits_ms":4413,"options":['
    + '{"prefilter_ms":12,"passed":32846,"worlds":223,"rules":[{"section":"distances","index":0,"ms":2895}]},'
    + '{"prefilter_ms":17,"passed":65536,"worlds":56,"rules":[{"section":"counts","index":0,"ms":4}]}]}';

describe("the finder's speed line", () => {
    it("reads both windows", () => {
        expect(parseSpeedLine("speed 30s: 2269/8.5/8.3 full: 1581/0.0/5.7")).toEqual({
            recent: { prefilter: 2269, generation: 8.5, total: 8.3 },
            full: { prefilter: 1581, generation: 0, total: 5.7 }
        });
        expect(parseOutputLine("speed 30s: 1/2/3 full: 4/5/6")?.kind).toBe("speed");
        expect(parseSpeedLine("speed 30s: 1/2 full: 4/5/6")).toBeNull();
    });

    it("leaves the progress lines readable, with the prefiltered seeds", () => {
        expect(parseOutputLine("scanned 65536/4294967296 matches 3 (4369066 seeds/s)")).toEqual({
            kind: "progress",
            progress: { scanned: 65536, hits: 3, prefiltered: 65536 }
        });
        const worldgen = parseOutputLine("search: scanned 240, levels 65536, worlds 222, generating 128 (kk 27, passes 867), "
            + "waiting 99, hits 96 (rounds 53, cpu 16179 ms, take 6 ms)");
        expect(worldgen).toEqual({
            kind: "progress",
            progress: { scanned: 240, hits: 96, prefiltered: 65536, worlds: { generated: 222, generating: 128 } }
        });
    });
});

describe("a speed meter", () => {
    it("measures the last 30 seconds from the sample at or before their start", () => {
        const meter = new SpeedMeter(0);
        meter.record(10_000, { prefiltered: 1000, generated: 10, decided: 100 });
        meter.record(40_000, { prefiltered: 4000, generated: 40, decided: 400 });
        meter.record(50_000, { prefiltered: 9000, generated: 50, decided: 500 });
        expect(meter.speeds()).toEqual({
            recent: { prefilter: 200, generation: 1, total: 10 },
            full: { prefilter: 180, generation: 1, total: 10 }
        });
    });
});

describe("the timings line", () => {
    const timings = parseTimingsLine(TIMINGS);

    it("is read", () => {
        expect(timings?.options.map(({ rules }) => rules.map(({ section, ms }) => `${section} ${ms}`))).toEqual([["distances 2895"], ["counts 4"]]);
        expect(parseOutputLine(TIMINGS)?.kind).toBe("timings");
        expect(parseTimingsLine("timings {nope")).toBeNull();
    });

    it("adds up over the browser's runs", () => {
        const twice = sumTimings([timings!, timings!]);
        expect(twice?.seeds).toBe(131072);
        expect(twice?.options[0]).toEqual({
            prefilter_ms: 24,
            passed: 65692,
            worlds: 446,
            rules: [{ section: "distances", index: 0, ms: 5790 }]
        });
        expect(sumTimings([])).toBeNull();
    });

    it("fits the threads' summed times into the real run time", () => {
        const real = inRealTime(sumTimings([timings!, timings!])!, 41441);
        expect(real).toMatchObject({ elapsed_ms: 41441, generation_ms: 16789, hits_ms: 4413 });
        expect(real.options[0].rules[0].ms).toBe(2895);
    });

    it("stays with the job's result", () => {
        const result = jobObject("linux", [], null, { startSeed: 0, progress: { scanned: 10, hits: 0, timings: timings! } });
        const parsed = parseJobResult(JSON.parse(JSON.stringify(result)));
        expect(parsed?.kind === "search" && parsed.search.timings?.generation_ms).toBe(16789);
    });
});
