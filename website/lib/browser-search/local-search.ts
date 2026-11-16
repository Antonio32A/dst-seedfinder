import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import type { JobStatus } from "@/lib/jobs/job-events";
import type { SearchOutput } from "@/lib/jobs/job-result";
import { type DoneSummary, exitKind, type OutputLine, parseOutputLine } from "@/lib/jobs/runner-output";
import { type SearchSpeeds, SpeedMeter } from "@/lib/jobs/search-speed";
import { inRealTime, type SearchTimings } from "@/lib/jobs/search-timings";
import {
    appendTail,
    browserEnvironment,
    type FailureReport,
    formatFailureReport,
    workerErrorDetails,
    workerErrorMessage
} from "./failure-report";
import { type Chunk, LocalScan } from "./local-scan";
import { compileSeedfinder } from "./seedfinder-wasm";

/** The search thread plus its share of the layout helper threads. */
export const CORES_PER_THREAD = 1.35;
export const MEMORY_PER_THREAD_MB = 300;

export const SEARCH_TARGETS = ["browser", "cloud"] as const;
export type SearchTarget = (typeof SEARCH_TARGETS)[number];
export const DEFAULT_SEARCH_TARGET: SearchTarget = "browser";

const UPDATE_MS = 200;

export interface LocalRun {
    module: WebAssembly.Module;
    from: number;
    to: number;
    limit: number;
    config: string;
    timings: boolean;
}

/** `code` is -1 when the worker crashed or failed to load. */
export type WorkerMessage = { type: "line"; line: string; stderr: boolean } | {
    type: "exit";
    code: number;
    error: string | null;
};

export interface LocalSearchRequest {
    config: SeedfinderConfig;
    wanted: number;
    startSeed: number;
    threads: number;
    /** Runs every chunk with `--verbose-timings`. */
    timings: boolean;
}

export interface LocalSearchState {
    request: LocalSearchRequest;
    status: Extract<JobStatus, "starting" | "running" | "done" | "failed" | "cancelled">;
    search: SearchOutput;
    speeds: SearchSpeeds | null;
    timings: SearchTimings | null;
    generatesWorlds: boolean;
    error: string | null;
    errorReport: string | null;
}

type Failure = Pick<FailureReport, "error" | "event" | "exit">;

interface Slot {
    worker: Worker;
    chunk: Chunk | null;
    startedAt: number;
    summary: DoneSummary | null;
    configError: string | null;
    lastError: string | null;
    stderr: string[];
    heard: boolean;
}

/**
 * `onChange` fires at most every `UPDATE_MS` and once at the end. The returned function stops the search, keeping its
 * hits.
 */
export function startLocalSearch(request: LocalSearchRequest, onChange: (state: LocalSearchState) => void): () => void {
    const scan = new LocalScan(request.startSeed, request.wanted);
    const config = JSON.stringify(request.config);
    const slots: Slot[] = [];
    const startedAt = performance.now();
    let module: WebAssembly.Module | null = null;
    let status: LocalSearchState["status"] = "starting";
    let error: string | null = null;
    let errorReport: string | null = null;
    let meter: SpeedMeter | null = null;
    let generatesWorlds = false;
    let updateTimer = 0;

    const state = (): LocalSearchState => {
        const now = performance.now();
        meter?.record(now, scan.counts());
        const summed = scan.timings();
        const timings = summed && meter ? inRealTime(summed, now - meter.startedAt) : summed;
        return {
            request,
            status,
            search: timings ? { ...scan.output(), timings } : scan.output(),
            speeds: meter?.speeds() ?? null,
            timings,
            generatesWorlds,
            error,
            errorReport
        };
    };

    const flush = () => {
        window.clearTimeout(updateTimer);
        updateTimer = 0;
        onChange(state());
    };

    const update = () => {
        if (updateTimer === 0) updateTimer = window.setTimeout(flush, UPDATE_MS);
    };

    const end = (next: LocalSearchState["status"], reason: string | null = null, report: string | null = null) => {
        if (status !== "starting" && status !== "running") return;
        status = next;
        error = reason;
        errorReport = report;
        for (const slot of slots) slot.worker.terminate();
        flush();
    };

    const fail = (slot: Slot | null, failure: Failure) => end("failed", failure.error, formatFailureReport({
        ...failure,
        time: new Date().toISOString(),
        elapsedMs: performance.now() - startedAt,
        chunk: slot?.chunk ? { from: slot.chunk.from, to: slot.chunk.to } : null,
        stderr: slot?.stderr ?? [],
        counts: { ...scan.counts(), hits: scan.output().hits.length },
        request: { ...request, config },
        environment: browserEnvironment()
    }));

    const assign = (slot: Slot) => {
        const chunk = scan.claim();
        Object.assign(slot, { chunk, startedAt: performance.now(), summary: null, configError: null, lastError: null });
        if (chunk === null || module === null) return;
        const { from, to } = chunk;
        const run: LocalRun = { module, from, to, limit: request.wanted, config, timings: request.timings };
        slot.worker.postMessage(run);
    };

    const progressed = (chunk: Chunk, { progress }: Extract<OutputLine, { kind: "progress" }>) => {
        Object.assign(chunk, {
            scanned: progress.scanned,
            prefiltered: progress.prefiltered,
            generated: progress.worlds?.generated ?? 0
        });
        generatesWorlds ||= progress.worlds !== undefined;
    };

    const readLine = (slot: Slot, chunk: Chunk, { line, stderr }: Extract<WorkerMessage, { type: "line" }>) => {
        const parsed = parseOutputLine(line);
        if (parsed?.kind === "hit") chunk.hits.push(parsed.hit);
        if (parsed?.kind === "progress") progressed(chunk, parsed);
        if (parsed?.kind === "timings") chunk.timings = parsed.timings;
        if (parsed?.kind === "done") slot.summary = parsed.summary;
        if (parsed?.kind === "error") slot.configError = parsed.error;
        if (stderr && parsed === null) slot.lastError = line;
    };

    const exited = (slot: Slot, chunk: Chunk, { code, error: crash }: Extract<WorkerMessage, { type: "exit" }>) => {
        const kind = exitKind(code, slot.summary, slot.configError);
        const exit = { code, error: crash };
        if (kind === "config-error") return fail(slot, { error: `The search couldn't run: ${slot.configError}`, event: null, exit });
        if (kind === "crash" || slot.summary === null) {
            const error = `The seedfinder stopped unexpectedly: ${crash ?? slot.lastError ?? `exit ${code}`}`;
            return fail(slot, { error, event: null, exit });
        }
        scan.finish(chunk, slot.summary.scanned, performance.now() - slot.startedAt);
        if (scan.stopReason() !== null) return end("done");
        assign(slot);
    };

    const listen = (slot: Slot) => {
        slot.worker.onmessage = ({ data }: MessageEvent<WorkerMessage>) => {
            slot.heard = true;
            if (data.type === "line" && data.stderr) appendTail(slot.stderr, data.line);
            const chunk = slot.chunk;
            if (chunk === null || (status !== "running" && status !== "starting")) return;
            if (data.type === "line") readLine(slot, chunk, data);
            else exited(slot, chunk, data);
            update();
        };
        slot.worker.onerror = (event) => {
            event.preventDefault();
            const details = workerErrorDetails(event);
            const ran = slots.some((each) => each.heard);
            fail(slot, { error: workerErrorMessage(details, ran, slot.lastError), event: details, exit: null });
        };
    };

    compileSeedfinder().then(
        (loaded) => {
            if (status !== "starting") return;
            module = loaded;
            status = "running";
            meter = new SpeedMeter(performance.now());
            for (let index = 0; index < request.threads; index++) {
                const slot: Slot = {
                    worker: new Worker(new URL("./local-search.worker.ts", import.meta.url), { type: "module" }),
                    chunk: null,
                    startedAt: 0,
                    summary: null,
                    configError: null,
                    lastError: null,
                    stderr: [],
                    heard: false
                };
                slots.push(slot);
                listen(slot);
                assign(slot);
            }
            flush();
        },
        (caught: unknown) => fail(null, {
            error: `The seedfinder couldn't be downloaded: ${caught instanceof Error ? caught.message : String(caught)}`,
            event: null,
            exit: null
        })
    );
    flush();

    return () => end("cancelled");
}
