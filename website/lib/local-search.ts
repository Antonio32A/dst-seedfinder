import type { JobStatus } from "./job-events";
import type { SearchOutput } from "./job-result";
import { LocalScan, type Chunk } from "./local-scan";
import type { SeedfinderConfig } from "./seedfinder-config";
import { exitKind, parseOutputLine, type DoneSummary } from "./server/runner-output";

/** Cores one finder instance keeps busy: its search thread plus the layout helper threads. */
export const CORES_PER_THREAD = 1.35;
export const MEMORY_PER_THREAD_MB = 300;

export const SEARCH_TARGETS = ["cloud", "browser"] as const;
export type SearchTarget = (typeof SEARCH_TARGETS)[number];
export const DEFAULT_SEARCH_TARGET: SearchTarget = "cloud";

const WASM_URL = "/wasm/seedfinder.wasm";
const UPDATE_MS = 200;

/** One finder run a worker is asked to do. */
export interface LocalRun {
  module: WebAssembly.Module;
  from: number;
  to: number;
  limit: number;
  config: string;
}

/** What a worker reports about its run: each output line, then how it exited (`-1` when it crashed or failed to load). */
export type WorkerMessage = { type: "line"; line: string; stderr: boolean } | { type: "exit"; code: number; error: string | null };

export interface LocalSearchRequest {
  config: SeedfinderConfig;
  wanted: number;
  startSeed: number;
  threads: number;
}

/** A browser search as the page shows it. `search` is the finder's job object so far. */
export interface LocalSearchState {
  request: LocalSearchRequest;
  status: Extract<JobStatus, "starting" | "running" | "done" | "failed" | "cancelled">;
  search: SearchOutput;
  seedsPerSecond: number;
  error: string | null;
}

interface Slot {
  worker: Worker;
  chunk: Chunk | null;
  startedAt: number;
  summary: DoneSummary | null;
  configError: string | null;
  lastError: string | null;
}

let compiled: Promise<WebAssembly.Module> | null = null;

const compileSeedfinder = () => {
  compiled ??= fetch(WASM_URL)
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.arrayBuffer();
    })
    .then((bytes) => WebAssembly.compile(bytes));
  compiled.catch(() => (compiled = null));
  return compiled;
};

/** Whether this page can run the finder: WebAssembly with threads, which needs a cross-origin isolated page. */
export function canSearchLocally(): boolean {
  return typeof WebAssembly === "object" && typeof SharedArrayBuffer === "function" && globalThis.crossOriginIsolated === true;
}

/** The CPU threads to search with by default: as many instances as the logical cores keep busy, at least one. */
export function defaultThreads(cores: number): number {
  return Math.max(1, Math.floor(cores / CORES_PER_THREAD));
}

/**
 * Runs a search in this browser with one finder instance per thread, each in its own worker on its own seed chunk, and
 * reports every change through `onChange` (at most every `UPDATE_MS`, and at once when it ends). Returns a function that
 * stops the search, keeping what was found.
 */
export function startLocalSearch(request: LocalSearchRequest, onChange: (state: LocalSearchState) => void): () => void {
  const scan = new LocalScan(request.startSeed, request.wanted);
  const config = JSON.stringify(request.config);
  const slots: Slot[] = [];
  let module: WebAssembly.Module | null = null;
  let status: LocalSearchState["status"] = "starting";
  let error: string | null = null;
  let runningSince = 0;
  let updateTimer = 0;

  const state = (): LocalSearchState => {
    const seconds = runningSince === 0 ? 0 : (performance.now() - runningSince) / 1000;
    return { request, status, search: scan.output(), seedsPerSecond: seconds > 0 ? scan.totalScanned() / seconds : 0, error };
  };

  const flush = () => {
    window.clearTimeout(updateTimer);
    updateTimer = 0;
    onChange(state());
  };

  const update = () => {
    if (updateTimer === 0) updateTimer = window.setTimeout(flush, UPDATE_MS);
  };

  const end = (next: LocalSearchState["status"], reason: string | null = null) => {
    if (status !== "starting" && status !== "running") return;
    status = next;
    error = reason;
    for (const slot of slots) slot.worker.terminate();
    flush();
  };

  const assign = (slot: Slot) => {
    const chunk = scan.claim();
    Object.assign(slot, { chunk, startedAt: performance.now(), summary: null, configError: null, lastError: null });
    if (chunk === null || module === null) return;
    const run: LocalRun = { module, from: chunk.from, to: chunk.to, limit: request.wanted, config };
    slot.worker.postMessage(run);
  };

  const readLine = (slot: Slot, chunk: Chunk, { line, stderr }: Extract<WorkerMessage, { type: "line" }>) => {
    const parsed = parseOutputLine(line);
    if (parsed?.kind === "hit") chunk.hits.push(parsed.hit);
    if (parsed?.kind === "progress") chunk.scanned = parsed.progress.scanned;
    if (parsed?.kind === "done") slot.summary = parsed.summary;
    if (parsed?.kind === "error") slot.configError = parsed.error;
    if (stderr && parsed === null) slot.lastError = line;
  };

  const exited = (slot: Slot, chunk: Chunk, { code, error: crash }: Extract<WorkerMessage, { type: "exit" }>) => {
    const kind = exitKind(code, slot.summary, slot.configError);
    if (kind === "config-error") return end("failed", `The search couldn't run: ${slot.configError}`);
    if (kind === "crash" || slot.summary === null) return end("failed", `The seedfinder stopped unexpectedly: ${crash ?? slot.lastError ?? `exit ${code}`}`);
    scan.finish(chunk, slot.summary.scanned, performance.now() - slot.startedAt);
    if (scan.stopReason() !== null) return end("done");
    assign(slot);
  };

  const listen = (slot: Slot) => {
    slot.worker.onmessage = ({ data }: MessageEvent<WorkerMessage>) => {
      const chunk = slot.chunk;
      if (chunk === null || (status !== "running" && status !== "starting")) return;
      if (data.type === "line") readLine(slot, chunk, data);
      else exited(slot, chunk, data);
      update();
    };
    slot.worker.onerror = (event) => {
      event.preventDefault();
      end("failed", "The seedfinder couldn't load in this browser.");
    };
  };

  compileSeedfinder().then(
    (loaded) => {
      if (status !== "starting") return;
      module = loaded;
      status = "running";
      runningSince = performance.now();
      for (let index = 0; index < request.threads; index++) {
        const slot: Slot = {
          worker: new Worker(new URL("./local-search.worker.ts", import.meta.url), { type: "module" }),
          chunk: null,
          startedAt: 0,
          summary: null,
          configError: null,
          lastError: null,
        };
        slots.push(slot);
        listen(slot);
        assign(slot);
      }
      flush();
    },
    (caught: unknown) => end("failed", `The seedfinder couldn't be downloaded: ${caught instanceof Error ? caught.message : String(caught)}`),
  );
  flush();

  return () => end("cancelled");
}
