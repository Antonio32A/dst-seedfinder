import { describe, expect, it } from "vitest";
import {
    appendTail,
    browserEnvironment,
    type FailureReport,
    formatFailureReport,
    LOAD_FAILURE,
    workerErrorDetails,
    workerErrorMessage
} from "../lib/browser-search/failure-report";

const GLUE_LINE = "worker sent an error! https://seeds.example/wasm/seedfinder.mjs:1:9000: Uncaught RuntimeError: unreachable";

const REPORT: FailureReport = {
    error: `The seedfinder stopped unexpectedly: ${GLUE_LINE}`,
    time: "2026-11-16T12:00:00.000Z",
    elapsedMs: 12_345,
    event: {
        message: "Uncaught [object ErrorEvent]",
        filename: "https://seeds.example/assets/local-search.worker.js",
        lineno: 1,
        colno: 42
    },
    exit: null,
    chunk: { from: 1024, to: 2047 },
    stderr: ["warning: slow start", GLUE_LINE],
    counts: { decided: 640, prefiltered: 900, generated: 12, hits: 1 },
    request: { threads: 4, wanted: 10, startSeed: 0, timings: false, config: '{"build":756039}' },
    environment: {
        userAgent: "Mozilla/5.0 Test",
        cores: 8,
        deviceMemoryGb: null,
        crossOriginIsolated: true,
        heap: { usedMb: 120, totalMb: 200, limitMb: 4096 }
    }
};

describe("the browser search's stderr tail", () => {
    it("keeps only the last lines", () => {
        const tail: string[] = [];
        for (let line = 0; line < 5; line++) appendTail(tail, String(line), 3);
        expect(tail).toEqual(["2", "3", "4"]);
    });
});

describe("a worker's error event", () => {
    it("reads an ErrorEvent's details", () => {
        const event = Object.assign(new Event("error"), {
            message: "Uncaught RuntimeError: unreachable",
            filename: "seedfinder.mjs",
            lineno: 3,
            colno: 7
        });
        expect(workerErrorDetails(event)).toEqual({
            message: "Uncaught RuntimeError: unreachable",
            filename: "seedfinder.mjs",
            lineno: 3,
            colno: 7
        });
    });

    it("reads a plain Event as having no details", () => {
        expect(workerErrorDetails(new Event("error"))).toEqual({ message: "", filename: "", lineno: 0, colno: 0 });
    });
});

describe("the message for a worker error", () => {
    const empty = { message: "", filename: "", lineno: 0, colno: 0 };

    it("says the seedfinder couldn't load when no worker had said anything", () => {
        expect(workerErrorMessage({ ...empty, message: "Uncaught SyntaxError" }, false, null)).toBe(LOAD_FAILURE);
    });

    it("says the seedfinder stopped, with the event's message, once it ran", () => {
        expect(workerErrorMessage({ ...empty, message: "Uncaught RuntimeError: unreachable" }, true, GLUE_LINE))
            .toBe("The seedfinder stopped unexpectedly: Uncaught RuntimeError: unreachable");
    });

    it("falls back to the last stderr line when the event's message says nothing", () => {
        const expected = `The seedfinder stopped unexpectedly: ${GLUE_LINE}`;
        expect(workerErrorMessage({ ...empty, message: "Uncaught [object ErrorEvent]" }, true, GLUE_LINE)).toBe(expected);
        expect(workerErrorMessage(empty, true, GLUE_LINE)).toBe(expected);
    });

    it("still says it stopped when nothing says why", () => {
        expect(workerErrorMessage(empty, true, null))
            .toBe("The seedfinder stopped unexpectedly: a worker failed without saying why");
    });
});

describe("the failure report", () => {
    it("lays out everything the developer needs", () => {
        expect(formatFailureReport(REPORT)).toBe([
            "DST seedfinder browser search error",
            `Error: The seedfinder stopped unexpectedly: ${GLUE_LINE}`,
            "Time: 2026-11-16T12:00:00.000Z (12.3 s after the start)",
            'Worker error: "Uncaught [object ErrorEvent]" at https://seeds.example/assets/local-search.worker.js:1:42',
            "Chunk: seeds 1024 to 2047",
            "Progress: decided 640, prefiltered 900, worlds generated 12, hits 1",
            "Request: threads 4, wanted 10, start seed 0, timings off",
            "Browser: Mozilla/5.0 Test",
            "Cores: 8, device memory: unknown, cross-origin isolated: yes",
            "JS heap: 120 MB used, 200 MB total, 4096 MB limit",
            'Config: {"build":756039}',
            "Last stderr lines (2):",
            "warning: slow start",
            GLUE_LINE
        ].join("\n"));
    });

    it("shows an exit, an empty error event and a missing chunk", () => {
        const text = formatFailureReport({
            ...REPORT,
            event: { message: "", filename: "", lineno: 0, colno: 0 },
            exit: { code: -1, error: "RuntimeError: memory access out of bounds" },
            chunk: null,
            stderr: [],
            environment: { ...REPORT.environment, heap: null, crossOriginIsolated: false }
        });
        expect(text).toContain("\nWorker error: an error event with no details\n");
        expect(text).toContain('\nExit: code -1, "RuntimeError: memory access out of bounds"\n');
        expect(text).toContain("\nChunk: none\n");
        expect(text).toContain("cross-origin isolated: no\nJS heap: unknown\n");
        expect(text.endsWith("Last stderr lines (0):")).toBe(true);
    });

    it("reads the environment without browser-only APIs", () => {
        const environment = browserEnvironment();
        expect(environment.userAgent).toBe(navigator.userAgent);
        expect(environment.deviceMemoryGb).toBeNull();
    });
});
