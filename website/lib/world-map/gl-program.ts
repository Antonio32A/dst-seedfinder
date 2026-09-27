import { type MapView, type Size, worldToScreen } from "./map-view";

/** The GLSL that places a world point `(x, z)` on screen, from the uniforms {@link setViewUniforms} sets. */
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

/** Compiles and links a map shader program. Throws with the driver's log when it doesn't build. */
export function buildProgram(gl: WebGL2RenderingContext, vertexShader: string, fragmentShader: string): WebGLProgram {
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, vertexShader));
    gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, fragmentShader));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`The map shader didn't link: ${gl.getProgramInfoLog(program)}`);
    return program;
}

/** Binds a new buffer holding `data` to `attribute` of the bound vertex array; `divisor` 1 makes it per instance. */
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

/** Sets the {@link VIEW_TRANSFORM} uniforms of `program`, the program in use, to draw at `view` from {@link worldToScreen}. */
export function setViewUniforms(gl: WebGL2RenderingContext, program: WebGLProgram, view: MapView, viewport: Size): void {
    const origin = worldToScreen(view, viewport, { x: 0, z: 0 });
    const unitX = worldToScreen(view, viewport, { x: 1, z: 0 });
    const unitZ = worldToScreen(view, viewport, { x: 0, z: 1 });
    const uniform = (name: string) => gl.getUniformLocation(program, name);
    gl.uniform2f(uniform("origin"), origin.x, origin.y);
    gl.uniform2f(uniform("alongX"), unitX.x - origin.x, unitX.y - origin.y);
    gl.uniform2f(uniform("alongZ"), unitZ.x - origin.x, unitZ.y - origin.y);
    gl.uniform2f(uniform("viewport"), viewport.width, viewport.height);
}
