const WASM_URL = "/wasm/seedfinder.wasm";

let compiled: Promise<WebAssembly.Module> | null = null;

/** Downloads and compiles the seedfinder once per page load; every run then instantiates the same module. */
export const compileSeedfinder = () => {
    compiled ??= fetch(WASM_URL)
        .then((response) => {
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return response.arrayBuffer();
        })
        .then((bytes) => WebAssembly.compile(bytes));
    compiled.catch(() => (compiled = null));
    return compiled;
};

/** The seedfinder needs threads, so shared memory, so a cross-origin isolated page. */
export const canRunSeedfinder = () =>
    typeof WebAssembly === "object" && typeof SharedArrayBuffer === "function" && globalThis.crossOriginIsolated === true;
