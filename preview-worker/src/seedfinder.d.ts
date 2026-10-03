declare module "*.wasm" {
    const module: WebAssembly.Module;
    export default module;
}

declare module "*/seedfinder.mjs" {
    const createSeedfinder: (options: object) => Promise<unknown>;
    export default createSeedfinder;
}
