import { canRunSeedfinder, compileSeedfinder } from "@/lib/browser-search/seedfinder-wasm";
import type { MapSeed } from "@/lib/world-map/map-route";
import { type WorkerFailure, workerReply } from "./worker-reply";
import { type GeneratedWorld, parseWorldDump } from "./world-dump";

export interface DumpRequest extends MapSeed {
    module: WebAssembly.Module;
}

export type DumpReply = { type: "dump"; bytes: Uint8Array<ArrayBuffer> } | { type: "crashed" } | WorkerFailure;

export type WorldLoad =
    | { status: "loading" }
    | { status: "ready"; world: GeneratedWorld; bytes: Uint8Array }
    | { status: "gave-up" }
    | { status: "crashed" }
    | { status: "unsupported" }
    | { status: "failed"; error: string };

const message = (error: unknown) => (error instanceof Error ? error.message : String(error));

/** Generates the seed's world in a worker. Aborting the signal stops the worker, and the result is then meaningless. */
export async function loadWorld(world: MapSeed, signal: AbortSignal): Promise<WorldLoad> {
    if (!canRunSeedfinder()) return { status: "unsupported" };
    try {
        const module = await compileSeedfinder().catch((error: unknown) => {
            throw new Error(`The seedfinder couldn't be downloaded: ${message(error)}`);
        });
        signal.throwIfAborted();
        const worker = new Worker(new URL("./world-dump.worker.ts", import.meta.url), { type: "module" });
        const reply = await workerReply<DumpRequest, DumpReply>(worker, { module, ...world }, signal);
        if (reply.type === "failed") throw new Error(`The world generation stopped unexpectedly: ${reply.error}`);
        if (reply.type === "crashed") return { status: "crashed" };
        const dump = parseWorldDump(reply.bytes);
        if (dump.status === "gave-up") return { status: "gave-up" };
        return { status: "ready", world: dump, bytes: reply.bytes };
    } catch (error) {
        return { status: "failed", error: message(error) };
    }
}
