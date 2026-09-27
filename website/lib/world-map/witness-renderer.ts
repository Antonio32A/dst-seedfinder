import { PREFAB_BY_ID } from "@/lib/catalog/world";
import { MAP_GROUPS } from "./entity-layer";
import { buildProgram, setViewUniforms, vertexBuffer, VIEW_TRANSFORM } from "./gl-program";
import type { MapView, Size } from "./map-view";
import type { WitnessShape } from "./witness-overlay";

const MARK_RADIUS = 9;
const MARK_DOT_RADIUS = 4.5;
const LINE_HALF_WIDTH = 1.5;
const LINE_EDGE = 1.5;
const DASH = 12;
const DASH_GAP = 6;
const OK: [number, number, number] = [1, 1, 1];
const FAILED: [number, number, number] = [1, 0.3, 0.25];
const EDGE: [number, number, number] = [0.08, 0.08, 0.08];

const COLOURS = `
uniform vec3 okColour;
uniform vec3 failedColour;
uniform vec3 edgeColour;`;

const LINE_VERTEX_SHADER = `#version 300 es
in vec2 corner;
in vec4 ends;
in vec2 style;
uniform float halfWidth;
out float along;
out vec2 look;
${VIEW_TRANSFORM}

void main() {
    vec2 start = onScreen(ends.xy);
    vec2 line = onScreen(ends.zw) - start;
    vec2 across = length(line) > 0.0 ? normalize(vec2(-line.y, line.x)) : vec2(0.0);
    along = corner.x * length(line);
    look = style;
    gl_Position = clipped(start + corner.x * line + corner.y * halfWidth * across);
}`;

const LINE_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform bool edge;
${COLOURS}
in float along;
in vec2 look;
out vec4 colour;

void main() {
    if (look.y > 0.5 && mod(along, ${DASH + DASH_GAP}.0) > ${DASH}.0) discard;
    colour = vec4(edge ? edgeColour : mix(failedColour, okColour, look.x), 1.0);
}`;

const MARK_VERTEX_SHADER = `#version 300 es
in vec2 position;
in vec3 fill;
in float ok;
uniform float radius;
out vec3 inner;
out float good;
${VIEW_TRANSFORM}

void main() {
    inner = fill;
    good = ok;
    gl_PointSize = 2.0 * radius + 1.0;
    gl_Position = clipped(onScreen(position));
}`;

const MARK_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform float radius;
uniform float dotRadius;
${COLOURS}
in vec3 inner;
in float good;
out vec4 colour;

float inside(float fromCentre, float limit) {
    return 1.0 - smoothstep(limit - 0.5, limit + 0.5, fromCentre);
}

void main() {
    float fromCentre = length(gl_PointCoord - 0.5) * (2.0 * radius + 1.0);
    float ring = inside(fromCentre, radius) - inside(fromCentre, radius - 4.5);
    float ringFill = inside(fromCentre, radius - 1.0) - inside(fromCentre, radius - 3.5);
    float coverage = max(ring, inside(fromCentre, dotRadius));
    if (coverage <= 0.0) discard;
    vec3 shade = mix(edgeColour, mix(failedColour, okColour, good), ringFill);
    colour = vec4(mix(shade, inner, inside(fromCentre, dotRadius - 1.0)), coverage);
}`;

export interface WitnessRenderer {
    /** Draws the witnesses at `view`, over what's drawn already. */
    draw: (view: MapView, viewport: Size) => void;
    dispose: () => void;
}

const groupColour = (prefab: string) => {
    const group = PREFAB_BY_ID.get(prefab)?.group ?? "other";
    return (MAP_GROUPS.find(({ id }) => id === group) ?? MAP_GROUPS[MAP_GROUPS.length - 1]).colour.map((channel) => channel / 255);
};

/**
 * Draws witness shapes: each mark as a ring around a dot in its entity group's colour, each segment as a line, dashed
 * for a wormhole jump. Failed witnesses draw in the failure colour.
 */
export function createWitnessRenderer(gl: WebGL2RenderingContext, shapes: WitnessShape[]): WitnessRenderer {
    const marks = shapes.flatMap((shape) => shape.marks);
    const segments = shapes.flatMap((shape) => shape.segments);
    const ends = Float32Array.from(segments.flatMap(({ from, to }) => [from.x, from.z, to.x, to.z]));
    const styles = Float32Array.from(segments.flatMap(({ ok, jump }) => [Number(ok), Number(jump)]));

    const lineProgram = buildProgram(gl, LINE_VERTEX_SHADER, LINE_FRAGMENT_SHADER);
    const lineVertices = gl.createVertexArray();
    gl.bindVertexArray(lineVertices);
    const lineBuffers = [
        vertexBuffer(gl, lineProgram, "corner", new Float32Array([0, -1, 1, -1, 0, 1, 1, 1]), 2),
        vertexBuffer(gl, lineProgram, "ends", ends, 4, 1),
        vertexBuffer(gl, lineProgram, "style", styles, 2, 1)
    ];

    const markProgram = buildProgram(gl, MARK_VERTEX_SHADER, MARK_FRAGMENT_SHADER);
    const markVertices = gl.createVertexArray();
    gl.bindVertexArray(markVertices);
    const markBuffers = [
        vertexBuffer(gl, markProgram, "position", Float32Array.from(marks.flatMap(({ at }) => [at.x, at.z])), 2),
        vertexBuffer(gl, markProgram, "fill", Float32Array.from(marks.flatMap(({ prefab }) => groupColour(prefab))), 3),
        vertexBuffer(gl, markProgram, "ok", Float32Array.from(marks, ({ ok }) => Number(ok)), 1)
    ];
    const [, largestPoint] = gl.getParameter(gl.ALIASED_POINT_SIZE_RANGE) as Float32Array;
    const radius = Math.min(MARK_RADIUS, (largestPoint - 1) / 2);

    const programs = [lineProgram, markProgram];
    for (const program of programs) {
        gl.useProgram(program);
        gl.uniform3fv(gl.getUniformLocation(program, "okColour"), OK);
        gl.uniform3fv(gl.getUniformLocation(program, "failedColour"), FAILED);
        gl.uniform3fv(gl.getUniformLocation(program, "edgeColour"), EDGE);
    }
    gl.uniform1f(gl.getUniformLocation(markProgram, "radius"), radius);
    gl.uniform1f(gl.getUniformLocation(markProgram, "dotRadius"), Math.min(MARK_DOT_RADIUS, radius / 2));

    return {
        draw: (view, viewport) => {
            for (const program of programs) {
                gl.useProgram(program);
                setViewUniforms(gl, program, view, viewport);
            }
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.useProgram(lineProgram);
            gl.bindVertexArray(lineVertices);
            for (const [edge, halfWidth] of [[true, LINE_HALF_WIDTH + LINE_EDGE], [false, LINE_HALF_WIDTH]] as const) {
                gl.uniform1i(gl.getUniformLocation(lineProgram, "edge"), Number(edge));
                gl.uniform1f(gl.getUniformLocation(lineProgram, "halfWidth"), halfWidth);
                gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, segments.length);
            }
            gl.useProgram(markProgram);
            gl.bindVertexArray(markVertices);
            gl.drawArrays(gl.POINTS, 0, marks.length);
            gl.disable(gl.BLEND);
        },
        dispose: () => {
            for (const buffer of [...lineBuffers, ...markBuffers]) gl.deleteBuffer(buffer);
            for (const vertices of [lineVertices, markVertices]) gl.deleteVertexArray(vertices);
            for (const program of programs) gl.deleteProgram(program);
        }
    };
}
