import { type MapView, type Size, worldToScreen } from "@/lib/world-map/view/map-view";

/** GLSL placing a world point `(x, z)` on screen, from the uniforms {@link setViewUniforms} sets. */
export const VIEW_TRANSFORM = `
uniform vec2 origin;
uniform vec2 alongX;
uniform vec2 alongZ;
uniform vec2 viewport;

vec2 onScreen(vec2 world) {
    return origin + world.x * alongX + world.y * alongZ;
}

vec4 clipped(vec2 screen) {
    return vec4(2.0 * screen.x / viewport.x - 1.0, 1.0 - 2.0 * screen.y / viewport.y, 0.0, 1.0);
}`;

function compile(gl: WebGL2RenderingContext, type: GLenum, source: string) {
    const shader = gl.createShader(type)!;
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(`The map shader didn't compile: ${gl.getShaderInfoLog(shader)}`);
    return shader;
}

/** Throws with the driver's log when the program doesn't build. */
export function buildProgram(gl: WebGL2RenderingContext, vertexShader: string, fragmentShader: string): WebGLProgram {
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, vertexShader));
    gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, fragmentShader));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`The map shader didn't link: ${gl.getProgramInfoLog(program)}`);
    return program;
}

/** On the bound vertex array; `divisor` 1 makes it per instance. */
export function vertexBuffer(
    gl: WebGL2RenderingContext,
    program: WebGLProgram,
    attribute: string,
    data: Float32Array,
    size: number,
    divisor = 0
): WebGLBuffer {
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    const location = gl.getAttribLocation(program, attribute);
    gl.enableVertexAttribArray(location);
    gl.vertexAttribPointer(location, size, gl.FLOAT, false, 0, 0);
    gl.vertexAttribDivisor(location, divisor);
    return buffer;
}

/** A setter of the {@link VIEW_TRANSFORM} uniforms of `program`, looked up once; the program must be in use when it's called. */
export function viewUniforms(gl: WebGL2RenderingContext, program: WebGLProgram): (view: MapView, viewport: Size) => void {
    const origin = gl.getUniformLocation(program, "origin");
    const alongX = gl.getUniformLocation(program, "alongX");
    const alongZ = gl.getUniformLocation(program, "alongZ");
    const viewportSize = gl.getUniformLocation(program, "viewport");
    return (view, viewport) => {
        const zero = worldToScreen(view, viewport, { x: 0, z: 0 });
        const unitX = worldToScreen(view, viewport, { x: 1, z: 0 });
        const unitZ = worldToScreen(view, viewport, { x: 0, z: 1 });
        gl.uniform2f(origin, zero.x, zero.y);
        gl.uniform2f(alongX, unitX.x - zero.x, unitX.y - zero.y);
        gl.uniform2f(alongZ, unitZ.x - zero.x, unitZ.y - zero.y);
        gl.uniform2f(viewportSize, viewport.width, viewport.height);
    };
}

/** Sets the {@link VIEW_TRANSFORM} uniforms of `program`, which must be in use. */
export function setViewUniforms(gl: WebGL2RenderingContext, program: WebGLProgram, view: MapView, viewport: Size): void {
    viewUniforms(gl, program)(view, viewport);
}

const RAW_TEXELS = { premultiplyAlpha: "none", colorSpaceConversion: "none" } as const;

async function download(url: string): Promise<Blob> {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`The map art couldn't be downloaded: ${url} answered ${response.status}.`);
    return response.blob();
}

/** Downloads `url` as raw texels: no colour conversion and no alpha premultiplication, whatever the file holds is uploaded. */
export async function fetchTexels(url: string): Promise<ImageBitmap> {
    return createImageBitmap(await download(url), RAW_TEXELS);
}

export interface TexelRegion {
    x: number;
    y: number;
    width: number;
    height: number;
}

/** Downloads `url` once and cuts `regions` out of it as raw texels, like {@link fetchTexels}. */
export async function fetchTexelRegions(url: string, regions: readonly TexelRegion[]): Promise<ImageBitmap[]> {
    const image = await download(url);
    return Promise.all(regions.map(({ x, y, width, height }) => createImageBitmap(image, x, y, width, height, RAW_TEXELS)));
}
