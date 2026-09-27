import type { MapView, Size } from "@/lib/world-map/view/map-view";
import { buildProgram, setViewUniforms, vertexBuffer, VIEW_TRANSFORM } from "./gl-program";

const MIN_RING_RADIUS = 6.5;
const MAX_RING_RADIUS = 12;
const RING_RADIUS_PER_WORLD_UNIT = 1;
const RING_OUTSIDE_DOT = 4;

const VERTEX_SHADER = `#version 300 es
in vec2 position;
uniform float radius;
${VIEW_TRANSFORM}

void main() {
    gl_PointSize = 2.0 * radius + 1.0;
    gl_Position = clipped(onScreen(position));
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
    draw: (view: MapView, viewport: Size) => void;
    /** `points` are interleaved world `x, z`. */
    highlight: (points: Float32Array) => void;
    dispose: () => void;
}

export function createHighlightRenderer(gl: WebGL2RenderingContext): HighlightRenderer {
    const program = buildProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
    const vertices = gl.createVertexArray();
    gl.bindVertexArray(vertices);
    const buffer = vertexBuffer(gl, program, "position", new Float32Array(0), 2);
    const [, largestPoint] = gl.getParameter(gl.ALIASED_POINT_SIZE_RANGE) as Float32Array;
    const maxRadius = Math.min(MAX_RING_RADIUS, (largestPoint - 1) / 2);
    let count = 0;

    return {
        draw: (view, viewport) => {
            if (count === 0) return;
            gl.useProgram(program);
            gl.bindVertexArray(vertices);
            setViewUniforms(gl, program, view, viewport);
            const radius = view.scale * RING_RADIUS_PER_WORLD_UNIT + RING_OUTSIDE_DOT;
            gl.uniform1f(gl.getUniformLocation(program, "radius"), Math.min(maxRadius, Math.max(MIN_RING_RADIUS, radius)));
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
