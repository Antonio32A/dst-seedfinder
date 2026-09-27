import { compileSeedfinder } from "@/lib/browser-search/seedfinder-wasm";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import type { WorldEval } from "./world-eval";

export interface EvalRequest {
    module: WebAssembly.Module;
    bytes: Uint8Array;
    config: string;
}

export type EvalReply = { type: "evaluated"; evaluation: WorldEval } | { type: "failed"; error: string };

export type EvalLoad = { status: "loading" } | { status: "ready"; evaluation: WorldEval } | { status: "failed"; error: string };

/**
 * Evaluates `config` on a world dump's bytes in a worker, like `seedfinder world eval`. Aborting the signal stops the
 * worker; the result is then meaningless.
 */
export async function evaluateWorld(bytes: Uint8Array, config: SeedfinderConfig, signal: AbortSignal): Promise<EvalLoad> {
    try {
        const module = await compileSeedfinder();
        signal.throwIfAborted();
        const worker = new Worker(new URL("./world-eval.worker.ts", import.meta.url), { type: "module" });
        signal.addEventListener("abort", () => worker.terminate());
        const reply = await new Promise<EvalReply>((resolve) => {
            worker.onmessage = ({ data }: MessageEvent<EvalReply>) => resolve(data);
            worker.onerror = (event) => {
                event.preventDefault();
                resolve({ type: "failed", error: "the seedfinder couldn't load in this browser" });
            };
            const request: EvalRequest = { module, bytes, config: JSON.stringify(config) };
            worker.postMessage(request);
        });
        worker.terminate();
        if (reply.type === "failed") throw new Error(reply.error);
        return { status: "ready", evaluation: reply.evaluation };
    } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        return { status: "failed", error: `The search couldn't be checked on this world: ${reason}` };
    }
}
