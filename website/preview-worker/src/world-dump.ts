import createSeedfinder from "../../../build/wasm-single/seedfinder.mjs";
import seedfinder from "../../../build/wasm-single/seedfinder.wasm";
import type { Platform, Shard } from "@/lib/config/seedfinder-config";
import { CRASHED_LINE, DUMP_PATH, dumpArgs } from "@/lib/world-map/world/world-dump";

export type GeneratedDump = { status: "dumped"; bytes: Uint8Array } | { status: "crashed" };

interface SeedfinderRuntime {
    FS: { readFile: (path: string) => Uint8Array };
}

let running: Promise<unknown> = Promise.resolve();

export function generateDump(seed: number, platform: Platform, shard: Shard): Promise<GeneratedDump> {
    const dump = running.then(() => runDump(seed, platform, shard));
    running = dump.catch(() => undefined);
    return dump;
}

function runDump(seed: number, platform: Platform, shard: Shard): Promise<GeneratedDump> {
    return new Promise((resolve, reject) => {
        let runtime: SeedfinderRuntime | null = null;
        let crashed = false;
        const errors: string[] = [];
        const exit = (code: number) => {
            if (crashed) return resolve({ status: "crashed" });
            if (code !== 0 || runtime === null) return reject(new Error(`world dump exited with ${code}: ${errors.at(-1) ?? "no error"}`));
            resolve({ status: "dumped", bytes: runtime.FS.readFile(DUMP_PATH) });
        };
        createSeedfinder({
            arguments: ["--", ...dumpArgs(seed, platform, shard)],
            instantiateWasm: (imports: WebAssembly.Imports, receive: (instance: WebAssembly.Instance, module: WebAssembly.Module) => void) => {
                WebAssembly.instantiate(seedfinder, imports).then((instance) => receive(instance, seedfinder), reject);
                return {};
            },
            preRun: [(loaded: SeedfinderRuntime) => {
                runtime = loaded;
            }],
            print: (line: string) => {
                crashed ||= CRASHED_LINE.test(line);
            },
            printErr: (line: string) => errors.push(line),
            onExit: exit,
            onAbort: (reason: unknown) => reject(new Error(`world dump aborted: ${reason}`))
        }).catch(reject);
    });
}
