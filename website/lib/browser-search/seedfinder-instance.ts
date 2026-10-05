export interface SeedfinderFS {
    mkdirTree: (path: string) => void;
    writeFile: (path: string, data: string | Uint8Array) => void;
    readFile: (path: string) => Uint8Array<ArrayBuffer>;
}

export interface SeedfinderRun {
    module: WebAssembly.Module;
    /** The runtime's arguments, then `--`, then the seedfinder's own. */
    args: string[];
    files?: Record<string, string | Uint8Array>;
    print?: (line: string) => void;
    printErr?: (line: string) => void;
}

/** `code` is -1 when the instance failed to load or aborted. `fs` is the instance's filesystem, still readable. */
export interface SeedfinderExit {
    code: number;
    error: string | null;
    fs: SeedfinderFS | null;
}

type Factory = (options: object) => Promise<unknown>;

const factory = import(/* @vite-ignore */ new URL("/wasm/seedfinder.mjs", self.location.origin).href).then(
    (loaded: { default: Factory }) => loaded.default
);

/** Runs the seedfinder once, in a fresh instance of the compiled `module`, with `files` in its in-memory filesystem. */
export function runSeedfinder({ module, args, files = {}, print, printErr }: SeedfinderRun): Promise<SeedfinderExit> {
    return new Promise((resolve) => {
        let fs: SeedfinderFS | null = null;
        const exit = (code: number, error: unknown) => resolve({
            code,
            error: error === null ? null : String(error),
            fs
        });
        factory.then((seedfinder) => seedfinder({
            arguments: args,
            instantiateWasm: (
                imports: WebAssembly.Imports,
                receive: (instance: WebAssembly.Instance, module: WebAssembly.Module) => void
            ) => {
                WebAssembly.instantiate(module, imports).then(
                    (instance) => receive(instance, module),
                    (error: unknown) => exit(-1, error)
                );
                return {};
            },
            preRun: [
                (runtime: { FS: SeedfinderFS }) => {
                    fs = runtime.FS;
                    fs.mkdirTree("/proc/self");
                    fs.writeFile("/proc/self/cmdline", ["seedfinder", ...args].map((arg) => `${arg}\0`).join(""));
                    for (const [path, data] of Object.entries(files)) fs.writeFile(path, data);
                }
            ],
            print: print ?? (() => {
            }),
            printErr: printErr ?? (() => {
            }),
            onExit: (code: number) => exit(code, null),
            onAbort: (reason: unknown) => exit(-1, reason)
        })).catch((error: unknown) => exit(-1, error));
    });
}
