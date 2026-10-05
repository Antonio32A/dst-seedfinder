import type { TurfBridge } from "@/lib/world-map/legend/turf-bridges";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import { buildProgram, unitColour, vertexBuffer, viewUniforms, VIEW_TRANSFORM } from "./gl-program";

export const BRIDGE_COLOUR = [255, 95, 120] as const;
const EDGE_COLOUR = [0.08, 0.08, 0.08];
const STRAY_HALF_WIDTH = 1.75;
const NORMAL_HALF_WIDTH = 1.1;
const FEATHER = 1;
const ROOM_RADIUS = 3.5;
const ROOM_EDGE = 1;

const LINE_VERTEX_SHADER = `#version 300 es
in vec2 corner;
in vec4 ends;
in float stray;
out float across;
out float halfWidth;
out float strayness;
${VIEW_TRANSFORM}

void main() {
    vec2 start = onScreen(ends.xy);
    vec2 line = onScreen(ends.zw) - start;
    vec2 normal = length(line) > 0.0 ? normalize(vec2(-line.y, line.x)) : vec2(0.0);
    halfWidth = mix(${NORMAL_HALF_WIDTH.toFixed(2)}, ${STRAY_HALF_WIDTH.toFixed(2)}, stray);
    strayness = stray;
    across = corner.y * (halfWidth + ${FEATHER.toFixed(1)});
    gl_Position = clipped(start + corner.x * line + across * normal);
}`;

const LINE_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform vec3 fill;
in float across;
in float halfWidth;
in float strayness;
out vec4 colour;

void main() {
    float coverage = clamp((halfWidth - abs(across)) / fwidth(across) + 0.5, 0.0, 1.0);
    if (coverage <= 0.0) discard;
    colour = vec4(fill, mix(0.4, 0.9, strayness) * coverage);
}`;

const ROOM_VERTEX_SHADER = `#version 300 es
in vec2 position;
in float stray;
out float strayness;
${VIEW_TRANSFORM}

void main() {
    strayness = stray;
    gl_PointSize = ${(2 * (ROOM_RADIUS + ROOM_EDGE) + 1).toFixed(1)};
    gl_Position = clipped(onScreen(position));
}`;

const ROOM_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform vec3 fill;
uniform vec3 edgeColour;
in float strayness;
out vec4 colour;

float inside(float fromCentre, float limit) {
    return 1.0 - smoothstep(limit - 0.5, limit + 0.5, fromCentre);
}

void main() {
    float fromCentre = length(gl_PointCoord - 0.5) * ${(2 * (ROOM_RADIUS + ROOM_EDGE) + 1).toFixed(1)};
    float coverage = inside(fromCentre, ${(ROOM_RADIUS + ROOM_EDGE).toFixed(1)});
    if (coverage <= 0.0) discard;
    vec3 shade = mix(edgeColour, fill, inside(fromCentre, ${ROOM_RADIUS.toFixed(1)}));
    colour = vec4(shade, mix(0.55, 1.0, strayness) * coverage);
}`;

export interface BridgeRenderer {
    draw: (view: MapView, viewport: Size) => void;
    show: (on: boolean) => void;
    dispose: () => void;
}

function bridgeRooms(bridges: readonly TurfBridge[]) {
    const rooms = new Map<string, { x: number; z: number; stray: boolean }>();
    for (const { from, to, stray } of bridges) {
        for (const { id, xk, zk } of [from, to]) {
            rooms.set(id, { x: xk / 100, z: zk / 100, stray: stray || (rooms.get(id)?.stray ?? false) });
        }
    }
    return [...rooms.values()].sort((a, b) => Number(a.stray) - Number(b.stray));
}

export function createBridgeRenderer(gl: WebGL2RenderingContext, bridges: readonly TurfBridge[]): BridgeRenderer {
    const lines = [...bridges].sort((a, b) => Number(a.stray) - Number(b.stray));
    const rooms = bridgeRooms(bridges);

    const lineProgram = buildProgram(gl, LINE_VERTEX_SHADER, LINE_FRAGMENT_SHADER);
    const lineVertices = gl.createVertexArray();
    gl.bindVertexArray(lineVertices);
    const lineBuffers = [
        vertexBuffer(gl, lineProgram, "corner", new Float32Array([0, -1, 1, -1, 0, 1, 1, 1]), 2),
        vertexBuffer(gl, lineProgram, "ends", Float32Array.from(lines.flatMap(({ from, to }) => [from.xk, from.zk, to.xk, to.zk]), (centi) => centi / 100), 4, 1),
        vertexBuffer(gl, lineProgram, "stray", Float32Array.from(lines, ({ stray }) => Number(stray)), 1, 1)
    ];

    const roomProgram = buildProgram(gl, ROOM_VERTEX_SHADER, ROOM_FRAGMENT_SHADER);
    const roomVertices = gl.createVertexArray();
    gl.bindVertexArray(roomVertices);
    const roomBuffers = [
        vertexBuffer(gl, roomProgram, "position", Float32Array.from(rooms.flatMap(({ x, z }) => [x, z])), 2),
        vertexBuffer(gl, roomProgram, "stray", Float32Array.from(rooms, ({ stray }) => Number(stray)), 1)
    ];

    const programs = [lineProgram, roomProgram];
    for (const program of programs) {
        gl.useProgram(program);
        gl.uniform3fv(gl.getUniformLocation(program, "fill"), unitColour(BRIDGE_COLOUR));
    }
    gl.uniform3fv(gl.getUniformLocation(roomProgram, "edgeColour"), EDGE_COLOUR);
    const setViews = programs.map((program) => viewUniforms(gl, program));
    let shown = false;

    return {
        draw: (view, viewport) => {
            if (!shown || lines.length === 0) return;
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.useProgram(lineProgram);
            gl.bindVertexArray(lineVertices);
            setViews[0](view, viewport);
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, lines.length);
            gl.useProgram(roomProgram);
            gl.bindVertexArray(roomVertices);
            setViews[1](view, viewport);
            gl.drawArrays(gl.POINTS, 0, rooms.length);
            gl.disable(gl.BLEND);
        },
        show: (on) => (shown = on),
        dispose: () => {
            for (const buffer of [...lineBuffers, ...roomBuffers]) gl.deleteBuffer(buffer);
            for (const vertices of [lineVertices, roomVertices]) gl.deleteVertexArray(vertices);
            for (const program of programs) gl.deleteProgram(program);
        }
    };
}
