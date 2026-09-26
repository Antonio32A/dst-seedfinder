import type { LocalRun, WorkerMessage } from "./local-search";

interface SeedfinderModule {
  FS: { mkdirTree: (path: string) => void; writeFile: (path: string, data: string) => void };
}

type Factory = (options: object) => Promise<unknown>;

const post = (message: WorkerMessage) => postMessage(message);

const factory = import(/* @vite-ignore */ new URL("/wasm/seedfinder.mjs", self.location.origin).href).then(
  (loaded: { default: Factory }) => loaded.default,
);

onmessage = async ({ data: { module, from, to, limit, config } }: MessageEvent<LocalRun>) => {
  let exited = false;
  const exit = (code: number, error: unknown) => {
    if (exited) return;
    exited = true;
    post({ type: "exit", code, error: error === null ? null : String(error) });
  };
  const args = ["--threads", "1", "--", "world", "find", String(from), String(to), "--limit", String(limit), "--config", "/config.json"];
  try {
    const seedfinder = await factory;
    await seedfinder({
      arguments: args,
      instantiateWasm: (imports: WebAssembly.Imports, receive: (instance: WebAssembly.Instance, module: WebAssembly.Module) => void) => {
        WebAssembly.instantiate(module, imports).then(
          (instance) => receive(instance, module),
          (error: unknown) => exit(-1, error),
        );
        return {};
      },
      preRun: [
        (runtime: SeedfinderModule) => {
          runtime.FS.mkdirTree("/proc/self");
          runtime.FS.writeFile("/proc/self/cmdline", ["seedfinder", ...args].map((arg) => `${arg}\0`).join(""));
          runtime.FS.writeFile("/config.json", config);
        },
      ],
      print: (line: string) => post({ type: "line", line, stderr: false }),
      printErr: (line: string) => post({ type: "line", line, stderr: true }),
      onExit: (code: number) => exit(code, null),
      onAbort: (reason: unknown) => exit(-1, reason),
    });
  } catch (error) {
    exit(-1, error);
  }
};
