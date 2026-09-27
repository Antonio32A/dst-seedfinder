import { compileSeedfinder } from "@/lib/browser-search/seedfinder-wasm";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { workerReply, type WorkerFailure } from "@/lib/world-map/world/worker-reply";
import type { WorldEval } from "./world-eval";

export interface EvalRequest {
    module: WebAssembly.Module;
    bytes: Uint8Array;
    config: string;
}

export type EvalReply = { type: "evaluated"; evaluation: WorldEval } | WorkerFailure;

export type EvalLoad =
    | { status: "loading" }
    | { status: "ready"; evaluation: WorldEval }
    | { status: "failed"; error: string };

/** Runs `world eval` in a worker. Aborting the signal stops the worker, and the result is then meaningless. */
export async function evaluateWorld(bytes: Uint8Array, config: SeedfinderConfig, signal: AbortSignal): Promise<EvalLoad> {
    try {
        const module = await compileSeedfinder();
        signal.throwIfAborted();
        const worker = new Worker(new URL("./world-eval.worker.ts", import.meta.url), { type: "module" });
        const request = { module, bytes, config: JSON.stringify(config) };
        const reply = await workerReply<EvalRequest, EvalReply>(worker, request, signal);
        if (reply.type === "failed") throw new Error(reply.error);
        return { status: "ready", evaluation: reply.evaluation };
    } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        return { status: "failed", error: `The search couldn't be checked on this world: ${reason}` };
    }
}
