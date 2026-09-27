import { type EntityLayer, MAP_GROUPS } from "./entity-layer";
import { buildProgram, setViewUniforms, vertexBuffer, VIEW_TRANSFORM } from "./gl-program";
import type { GroupVisibility } from "./group-visibility";
import type { MapView, Size } from "./map-view";

const MIN_DOT_RADIUS = 2.5;
const MAX_DOT_RADIUS = 8;
const DOT_RADIUS_PER_WORLD_UNIT = 1;
const LINK_HALF_WIDTH = 1.25;

const unit = (channel: number) => channel / 255;

const TRANSFORM = `${VIEW_TRANSFORM}
uniform uint shown;

bool hidden(float group) {
    return ((shown >> uint(group)) & 1u) == 0u;
}`;

const DOT_VERTEX_SHADER = `#version 300 es
in vec2 position;
in float group;
uniform vec3 colours[${MAP_GROUPS.length}];
uniform float radius;
out vec3 fill;
${TRANSFORM}

void main() {
    fill = colours[int(group)];
    gl_PointSize = 2.0 * radius + 1.0;
    gl_Position = hidden(group) ? vec4(2.0, 2.0, 2.0, 1.0) : clipped(onScreen(position));
}`;

const DOT_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform float radius;
in vec3 fill;
out vec4 colour;

void main() {
    float fromCentre = length(gl_PointCoord - 0.5) * (2.0 * radius + 1.0);
    float outline = smoothstep(radius - 1.75, radius - 0.75, fromCentre);
    float coverage = 1.0 - smoothstep(radius - 0.5, radius + 0.5, fromCentre);
    if (coverage <= 0.0) discard;
    colour = vec4(mix(fill, fill * 0.3, outline), coverage);
}`;

const LINK_VERTEX_SHADER = `#version 300 es
in vec2 corner;
in vec4 ends;
uniform float group;
uniform float halfWidth;
${TRANSFORM}

void main() {
    vec2 entry = onScreen(ends.xy);
    vec2 exit = onScreen(ends.zw);
    vec2 along = exit - entry;
    vec2 across = length(along) > 0.0 ? normalize(vec2(-along.y, along.x)) : vec2(0.0);
    vec2 screen = entry + corner.x * along + corner.y * halfWidth * across;
    gl_Position = hidden(group) ? vec4(2.0, 2.0, 2.0, 1.0) : clipped(screen);
}`;

const LINK_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform vec3 fill;
out vec4 colour;

void main() {
    colour = vec4(fill, 0.85);
}`;

export interface EntityRenderer {
    /** Draws the shown groups' dots and wormhole links at `view`, over what's drawn already. */
    draw: (view: MapView, viewport: Size) => void;
    show: (visibility: GroupVisibility) => void;
    dispose: () => void;
}

/** Draws a world's entities as dots in their group colours, and its wormhole links as lines. */
export function createEntityRenderer(gl: WebGL2RenderingContext, layer: EntityLayer): EntityRenderer {
    const dotProgram = buildProgram(gl, DOT_VERTEX_SHADER, DOT_FRAGMENT_SHADER);
    const dotVertices = gl.createVertexArray();
    gl.bindVertexArray(dotVertices);
    const dotBuffers = [
        vertexBuffer(gl, dotProgram, "position", layer.positions, 2),
        vertexBuffer(gl, dotProgram, "group", Float32Array.from(layer.groups), 1)
    ];
    const [, largestPoint] = gl.getParameter(gl.ALIASED_POINT_SIZE_RANGE) as Float32Array;
    const maxRadius = Math.min(MAX_DOT_RADIUS, (largestPoint - 1) / 2);
    gl.useProgram(dotProgram);
    gl.uniform3fv(gl.getUniformLocation(dotProgram, "colours"), MAP_GROUPS.flatMap(({ colour }) => colour.map(unit)));

    const linkProgram = buildProgram(gl, LINK_VERTEX_SHADER, LINK_FRAGMENT_SHADER);
    const linkVertices = gl.createVertexArray();
    gl.bindVertexArray(linkVertices);
    const linkBuffers = [
        vertexBuffer(gl, linkProgram, "corner", new Float32Array([0, -1, 1, -1, 0, 1, 1, 1]), 2),
        vertexBuffer(gl, linkProgram, "ends", layer.links, 4, 1)
    ];
    gl.useProgram(linkProgram);
    gl.uniform1f(gl.getUniformLocation(linkProgram, "group"), layer.linkGroup);
    gl.uniform1f(gl.getUniformLocation(linkProgram, "halfWidth"), LINK_HALF_WIDTH);
    gl.uniform3fv(gl.getUniformLocation(linkProgram, "fill"), MAP_GROUPS[layer.linkGroup].colour.map(unit));

    let shown = 0;
    const programs = [linkProgram, dotProgram];

    return {
        draw: (view, viewport) => {
            for (const program of programs) {
                gl.useProgram(program);
                setViewUniforms(gl, program, view, viewport);
                gl.uniform1ui(gl.getUniformLocation(program, "shown"), shown);
            }
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.useProgram(linkProgram);
            gl.bindVertexArray(linkVertices);
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, layer.links.length / 4);
            gl.useProgram(dotProgram);
            gl.bindVertexArray(dotVertices);
            const radius = Math.min(maxRadius, Math.max(MIN_DOT_RADIUS, view.scale * DOT_RADIUS_PER_WORLD_UNIT));
            gl.uniform1f(gl.getUniformLocation(dotProgram, "radius"), radius);
            gl.drawArrays(gl.POINTS, 0, layer.groups.length);
            gl.disable(gl.BLEND);
        },
        show: (visibility) => {
            shown = MAP_GROUPS.reduce((mask, { id }, group) => (visibility[id] ? mask | 1 << group : mask), 0);
        },
        dispose: () => {
            for (const buffer of [...dotBuffers, ...linkBuffers]) gl.deleteBuffer(buffer);
            for (const vertices of [dotVertices, linkVertices]) gl.deleteVertexArray(vertices);
            for (const program of programs) gl.deleteProgram(program);
        }
    };
}
