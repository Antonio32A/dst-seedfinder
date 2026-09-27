import { buildProgram, vertexBuffer } from "./gl-program";
import { type MapView, type Size, worldToScreen } from "./map-view";

const MIN_RING_RADIUS = 6.5;
const MAX_RING_RADIUS = 12;
const RING_RADIUS_PER_WORLD_UNIT = 1;
const RING_OUTSIDE_DOT = 4;

const VERTEX_SHADER = `#version 300 es
in vec2 position;
uniform vec2 origin;
uniform vec2 alongX;
uniform vec2 alongZ;
uniform vec2 viewport;
uniform float radius;

void main() {
    vec2 screen = origin + position.x * alongX + position.y * alongZ;
    gl_PointSize = 2.0 * radius + 1.0;
    gl_Position = vec4(2.0 * screen.x / viewport.x - 1.0, 1.0 - 2.0 * screen.y / viewport.y, 0.0, 1.0);
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform float radius;
out vec4 colour;

void main() {
    float fromCentre = length(gl_PointCoord - 0.5) * (2.0 * radius + 1.0);
    float inner = radius - ${RING_OUTSIDE_DOT.toFixed(1)};
    float outside = smoothstep(inner - 0.5, inner + 0.5, fromCentre);
    float coverage = outside * (1.0 - smoothstep(radius - 0.5, radius + 0.5, fromCentre));
    if (coverage <= 0.0) discard;
    float band = smoothstep(inner + 0.5, inner + 1.5, fromCentre) * (1.0 - smoothstep(radius - 1.5, radius - 0.5, fromCentre));
    colour = vec4(mix(vec3(0.05), vec3(1.0), band), coverage);
}`;

export interface HighlightRenderer {
    /** Rings the highlighted points at `view`, over what's drawn already. */
    draw: (view: MapView, viewport: Size) => void;
    /** Rings `points`, interleaved world `x, z`, from the next draw on, instead of the ones before. */
    highlight: (points: Float32Array) => void;
    dispose: () => void;
}

/** Draws rings around world points, a size bigger than the entity dots they surround. */
export function createHighlightRenderer(gl: WebGL2RenderingContext): HighlightRenderer {
    const program = buildProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
    const uniform = (name: string) => gl.getUniformLocation(program, name);
    const vertices = gl.createVertexArray();
    gl.bindVertexArray(vertices);
    const buffer = vertexBuffer(gl, program, "position", new Float32Array(0), 2);
    const [, largestPoint] = gl.getParameter(gl.ALIASED_POINT_SIZE_RANGE) as Float32Array;
    const maxRadius = Math.min(MAX_RING_RADIUS, (largestPoint - 1) / 2);
    let count = 0;

    return {
        draw: (view, viewport) => {
            if (count === 0) return;
            const origin = worldToScreen(view, viewport, { x: 0, z: 0 });
            const unitX = worldToScreen(view, viewport, { x: 1, z: 0 });
            const unitZ = worldToScreen(view, viewport, { x: 0, z: 1 });
            gl.useProgram(program);
            gl.bindVertexArray(vertices);
            gl.uniform2f(uniform("origin"), origin.x, origin.y);
            gl.uniform2f(uniform("alongX"), unitX.x - origin.x, unitX.y - origin.y);
            gl.uniform2f(uniform("alongZ"), unitZ.x - origin.x, unitZ.y - origin.y);
            gl.uniform2f(uniform("viewport"), viewport.width, viewport.height);
            const radius = view.scale * RING_RADIUS_PER_WORLD_UNIT + RING_OUTSIDE_DOT;
            gl.uniform1f(uniform("radius"), Math.min(maxRadius, Math.max(MIN_RING_RADIUS, radius)));
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.drawArrays(gl.POINTS, 0, count);
            gl.disable(gl.BLEND);
        },
        highlight: (points) => {
            gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
            gl.bufferData(gl.ARRAY_BUFFER, points, gl.STATIC_DRAW);
            count = points.length / 2;
        },
        dispose: () => {
            gl.deleteBuffer(buffer);
            gl.deleteVertexArray(vertices);
            gl.deleteProgram(program);
        }
    };
}
