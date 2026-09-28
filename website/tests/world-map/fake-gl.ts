export type GlCall = [name: string, ...args: unknown[]];

/** A WebGL2 context that records every call, answering with harmless stand-ins. */
export function fakeGl() {
    const calls: GlCall[] = [];
    let attributes = 0;
    const gl = new Proxy({}, {
        get: (_, property: string) => {
            if (property === "TEXTURE0") return 0;
            if (property === property.toUpperCase()) return property;
            return (...args: unknown[]) => {
                calls.push([property, ...args]);
                if (property === "getUniformLocation") return { uniform: args[1] };
                if (property === "getAttribLocation") return attributes++;
                if (property === "getParameter") return new Float32Array([1, 64]);
                if (property.startsWith("get") && property.endsWith("Parameter")) return true;
                return { created: property };
            };
        }
    }) as unknown as WebGL2RenderingContext;
    const names = (name: string) => calls.filter(([call]) => call === name);
    const uniformValues = (uniform: string, call: string) => names(call)
        .filter(([, location]) => (location as { uniform: string }).uniform === uniform)
        .map(([, , ...value]) => value);
    return { gl, calls, names, uniformValues };
}
