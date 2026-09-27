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
