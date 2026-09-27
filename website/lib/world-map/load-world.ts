import { canRunSeedfinder, compileSeedfinder } from "@/lib/browser-search/seedfinder-wasm";
import type { Platform } from "@/lib/config/seedfinder-config";
import { type GeneratedWorld, parseWorldDump } from "./world-dump";

export interface DumpRequest {
    module: WebAssembly.Module;
    seed: number;
    platform: Platform;
}

export type DumpReply = { type: "dump"; bytes: Uint8Array<ArrayBuffer> } | { type: "failed"; error: string };

export type WorldLoad =
    | { status: "loading" }
    | { status: "ready"; world: GeneratedWorld; bytes: Uint8Array }
    | { status: "gave-up" }
    | { status: "unsupported" }
    | { status: "failed"; error: string };

const message = (error: unknown) => (error instanceof Error ? error.message : String(error));

/**
 * Generates the seed's world in a worker and reads its dump. Aborting the signal stops the worker; the result is then
 * meaningless (a failure, or a promise that never settles).
 */
export async function loadWorld(seed: number, platform: Platform, signal: AbortSignal): Promise<WorldLoad> {
    if (!canRunSeedfinder()) return { status: "unsupported" };
    try {
        const module = await compileSeedfinder().catch((error: unknown) => {
            throw new Error(`The seedfinder couldn't be downloaded: ${message(error)}`);
        });
        signal.throwIfAborted();
        const worker = new Worker(new URL("./world-map.worker.ts", import.meta.url), { type: "module" });
        signal.addEventListener("abort", () => worker.terminate());
        const reply = await new Promise<DumpReply>((resolve) => {
            worker.onmessage = ({ data }: MessageEvent<DumpReply>) => resolve(data);
            worker.onerror = (event) => {
                event.preventDefault();
                resolve({ type: "failed", error: "the seedfinder couldn't load in this browser" });
            };
            const request: DumpRequest = { module, seed, platform };
            worker.postMessage(request);
        });
        worker.terminate();
        if (reply.type === "failed") throw new Error(`The world generation stopped unexpectedly: ${reply.error}`);
        const dump = parseWorldDump(reply.bytes);
        return dump.status === "generated" ? {
            status: "ready",
            world: dump,
            bytes: reply.bytes
        } : { status: "gave-up" };
    } catch (error) {
        return { status: "failed", error: message(error) };
    }
}
