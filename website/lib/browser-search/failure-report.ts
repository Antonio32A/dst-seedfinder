import type { SpeedCounts } from "@/lib/jobs/search-speed";

export const STDERR_TAIL = 50;

export const LOAD_FAILURE = "The seedfinder couldn't load in this browser.";

export interface WorkerErrorDetails {
    message: string;
    filename: string;
    lineno: number;
    colno: number;
}

export interface HeapUsage {
    usedMb: number;
    totalMb: number;
    limitMb: number;
}

export interface BrowserEnvironment {
    userAgent: string;
    cores: number;
    deviceMemoryGb: number | null;
    crossOriginIsolated: boolean;
    heap: HeapUsage | null;
}

export interface FailureReport {
    error: string;
    time: string;
    elapsedMs: number;
    event: WorkerErrorDetails | null;
    exit: { code: number; error: string | null } | null;
    chunk: { from: number; to: number } | null;
    stderr: readonly string[];
    counts: SpeedCounts & { hits: number };
    request: { threads: number; wanted: number; startSeed: number; timings: boolean; config: string };
    environment: BrowserEnvironment;
}

interface HeapMemory {
    usedJSHeapSize: number;
    totalJSHeapSize: number;
    jsHeapSizeLimit: number;
}

/** Keeps the last `max` lines of `tail`, appending `line`. */
export function appendTail(tail: string[], line: string, max = STDERR_TAIL): void {
    tail.push(line);
    if (tail.length > max) tail.splice(0, tail.length - max);
}

/** Reads a worker's `error` event, which is a plain `Event` with no details when the worker script failed to load. */
export function workerErrorDetails(event: Event): WorkerErrorDetails {
    const { message = "", filename = "", lineno = 0, colno = 0 } = event as Partial<ErrorEvent>;
    return { message: String(message), filename, lineno, colno };
}

const informative = (text: string | null | undefined): text is string =>
    typeof text === "string" && text.trim() !== "" && !text.includes("[object ");

/**
 * A worker error before any worker said anything means the seedfinder never loaded; after that, it crashed, and the
 * event's message or else the last stderr line says why.
 */
export function workerErrorMessage(event: WorkerErrorDetails, ran: boolean, lastStderr: string | null): string {
    if (!ran) return LOAD_FAILURE;
    const detail = [event.message, lastStderr].find(informative) ?? "a worker failed without saying why";
    return `The seedfinder stopped unexpectedly: ${detail}`;
}

const megabytes = (bytes: number) => Math.round(bytes / (1024 * 1024));

export function browserEnvironment(): BrowserEnvironment {
    const browser = navigator as Navigator & { deviceMemory?: number };
    const memory = (performance as Performance & { memory?: HeapMemory }).memory;
    return {
        userAgent: browser.userAgent,
        cores: browser.hardwareConcurrency,
        deviceMemoryGb: browser.deviceMemory ?? null,
        crossOriginIsolated: globalThis.crossOriginIsolated,
        heap: memory
            ? {
                usedMb: megabytes(memory.usedJSHeapSize),
                totalMb: megabytes(memory.totalJSHeapSize),
                limitMb: megabytes(memory.jsHeapSizeLimit)
            }
            : null
    };
}

function eventLines(event: WorkerErrorDetails | null): string[] {
    if (event === null) return [];
    if (event.message === "" && event.filename === "") return ["Worker error: an error event with no details"];
    return [`Worker error: ${JSON.stringify(event.message)} at ${event.filename}:${event.lineno}:${event.colno}`];
}

function exitLines(exit: FailureReport["exit"]): string[] {
    if (exit === null) return [];
    return [`Exit: code ${exit.code}${exit.error === null ? "" : `, ${JSON.stringify(exit.error)}`}`];
}

function environmentLines({ userAgent, cores, deviceMemoryGb, crossOriginIsolated, heap }: BrowserEnvironment) {
    const heapText = heap ? `${heap.usedMb} MB used, ${heap.totalMb} MB total, ${heap.limitMb} MB limit` : "unknown";
    const memoryText = deviceMemoryGb === null ? "unknown" : `${deviceMemoryGb} GB`;
    return [
        `Browser: ${userAgent}`,
        `Cores: ${cores}, device memory: ${memoryText}, cross-origin isolated: ${crossOriginIsolated ? "yes" : "no"}`,
        `JS heap: ${heapText}`
    ];
}

/** The plain-text report a user pastes to the developer when a browser search fails. */
export function formatFailureReport(report: FailureReport): string {
    const { counts, request, chunk, stderr } = report;
    return [
        "DST seedfinder browser search error",
        `Error: ${report.error}`,
        `Time: ${report.time} (${(report.elapsedMs / 1000).toFixed(1)} s after the start)`,
        ...eventLines(report.event),
        ...exitLines(report.exit),
        `Chunk: ${chunk ? `seeds ${chunk.from} to ${chunk.to}` : "none"}`,
        `Progress: decided ${counts.decided}, prefiltered ${counts.prefiltered}, worlds generated ${counts.generated}, hits ${counts.hits}`,
        `Request: threads ${request.threads}, wanted ${request.wanted}, start seed ${request.startSeed}, timings ${request.timings ? "on" : "off"}`,
        ...environmentLines(report.environment),
        `Config: ${request.config}`,
        `Last stderr lines (${stderr.length}):`,
        ...stderr
    ].join("\n");
}
