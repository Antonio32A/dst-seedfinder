import { type EntityLayer, MAP_GROUPS, SPAWN } from "@/lib/world-map/legend/entity-layer";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import { buildProgram, setViewUniforms, vertexBuffer, VIEW_TRANSFORM } from "./gl-program";

const MIN_DOT_RADIUS = 2.5;
const MAX_DOT_RADIUS = 8;
const DOT_RADIUS_PER_WORLD_UNIT = 1;
const SPAWN_RADIUS_SCALE = 2.5;
const LINK_HALF_WIDTH = 0.625;
const LINK_FEATHER = 1;
const VISIBILITY_ROW = 256;
const VISIBILITY_UNIT = 2;

const unit = (channel: number) => channel / 255;

const TRANSFORM = `${VIEW_TRANSFORM}
uniform sampler2D shown;

bool hidden(float prefab) {
    int at = int(prefab);
    return texelFetch(shown, ivec2(at % ${VISIBILITY_ROW}, at / ${VISIBILITY_ROW}), 0).r < 0.5;
}`;

const DOT_VERTEX_SHADER = `#version 300 es
in vec2 position;
in float group;
in float prefab;
uniform vec3 colours[${MAP_GROUPS.length}];
uniform float radius;
uniform float spawn;
uniform float spawnRadius;
out vec3 fill;
flat out float dotRadius;
${TRANSFORM}

void main() {
    fill = colours[int(group)];
    dotRadius = prefab == spawn ? spawnRadius : radius;
    gl_PointSize = 2.0 * dotRadius + 1.0;
    gl_Position = hidden(prefab) ? vec4(2.0, 2.0, 2.0, 1.0) : clipped(onScreen(position));
}`;

const DOT_FRAGMENT_SHADER = `#version 300 es
precision highp float;
in vec3 fill;
flat in float dotRadius;
out vec4 colour;

void main() {
    float fromCentre = length(gl_PointCoord - 0.5) * (2.0 * dotRadius + 1.0);
    float outline = smoothstep(dotRadius - 1.75, dotRadius - 0.75, fromCentre);
    float coverage = 1.0 - smoothstep(dotRadius - 0.5, dotRadius + 0.5, fromCentre);
    if (coverage <= 0.0) discard;
    colour = vec4(mix(fill, fill * 0.3, outline), coverage);
}`;

const LINK_VERTEX_SHADER = `#version 300 es
in vec2 corner;
in vec4 ends;
uniform float prefab;
uniform float halfWidth;
out float across;
${TRANSFORM}

void main() {
    vec2 entry = onScreen(ends.xy);
    vec2 exit = onScreen(ends.zw);
    vec2 along = exit - entry;
    vec2 normal = length(along) > 0.0 ? normalize(vec2(-along.y, along.x)) : vec2(0.0);
    across = corner.y * (halfWidth + ${LINK_FEATHER.toFixed(1)});
    vec2 screen = entry + corner.x * along + across * normal;
    gl_Position = hidden(prefab) ? vec4(2.0, 2.0, 2.0, 1.0) : clipped(screen);
}`;

const LINK_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform vec3 fill;
uniform float halfWidth;
in float across;
out vec4 colour;

void main() {
    float coverage = clamp((halfWidth - abs(across)) / fwidth(across) + 0.5, 0.0, 1.0);
    if (coverage <= 0.0) discard;
    colour = vec4(fill, 0.85 * coverage);
}`;

export interface EntityRenderer {
    draw: (view: MapView, viewport: Size) => void;
    show: (shown: ReadonlySet<string>) => void;
    dispose: () => void;
}

/** Which prefabs show is a texture the shaders look each dot's prefab up in, so a toggle uploads one byte per prefab. */
export function createEntityRenderer(gl: WebGL2RenderingContext, layer: EntityLayer): EntityRenderer {
    const dotProgram = buildProgram(gl, DOT_VERTEX_SHADER, DOT_FRAGMENT_SHADER);
    const dotVertices = gl.createVertexArray();
    gl.bindVertexArray(dotVertices);
    const dotBuffers = [
        vertexBuffer(gl, dotProgram, "position", layer.positions, 2),
        vertexBuffer(gl, dotProgram, "group", Float32Array.from(layer.groups), 1),
        vertexBuffer(gl, dotProgram, "prefab", Float32Array.from(layer.prefabs), 1)
    ];
    const [, largestPoint] = gl.getParameter(gl.ALIASED_POINT_SIZE_RANGE) as Float32Array;
    const largestRadius = (largestPoint - 1) / 2;
    gl.useProgram(dotProgram);
    gl.uniform1f(gl.getUniformLocation(dotProgram, "spawn"), layer.names.indexOf(SPAWN));
    gl.uniform3fv(gl.getUniformLocation(dotProgram, "colours"), MAP_GROUPS.flatMap(({ colour }) => colour.map(unit)));

    const linkProgram = buildProgram(gl, LINK_VERTEX_SHADER, LINK_FRAGMENT_SHADER);
    const linkVertices = gl.createVertexArray();
    gl.bindVertexArray(linkVertices);
    const linkBuffers = [
        vertexBuffer(gl, linkProgram, "corner", new Float32Array([0, -1, 1, -1, 0, 1, 1, 1]), 2),
        vertexBuffer(gl, linkProgram, "ends", layer.links, 4, 1)
    ];
    gl.useProgram(linkProgram);
    gl.uniform1f(gl.getUniformLocation(linkProgram, "prefab"), Math.max(0, layer.linkPrefab));
    gl.uniform1f(gl.getUniformLocation(linkProgram, "halfWidth"), LINK_HALF_WIDTH);
    gl.uniform3fv(gl.getUniformLocation(linkProgram, "fill"), MAP_GROUPS[layer.linkGroup].colour.map(unit));

    const programs = [linkProgram, dotProgram];
    const visibilityRows = Math.max(1, Math.ceil(layer.names.length / VISIBILITY_ROW));
    const visibility = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0 + VISIBILITY_UNIT);
    gl.bindTexture(gl.TEXTURE_2D, visibility);
    for (const parameter of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.NEAREST);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, VISIBILITY_ROW, visibilityRows, 0, gl.RED, gl.UNSIGNED_BYTE, null);
    for (const program of programs) {
        gl.useProgram(program);
        gl.uniform1i(gl.getUniformLocation(program, "shown"), VISIBILITY_UNIT);
    }

    return {
        draw: (view, viewport) => {
            for (const program of programs) {
                gl.useProgram(program);
                setViewUniforms(gl, program, view, viewport);
            }
            gl.activeTexture(gl.TEXTURE0 + VISIBILITY_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, visibility);
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.useProgram(linkProgram);
            gl.bindVertexArray(linkVertices);
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, layer.links.length / 4);
            gl.useProgram(dotProgram);
            gl.bindVertexArray(dotVertices);
            const radius = Math.min(MAX_DOT_RADIUS, Math.max(MIN_DOT_RADIUS, view.scale * DOT_RADIUS_PER_WORLD_UNIT));
            gl.uniform1f(gl.getUniformLocation(dotProgram, "radius"), Math.min(largestRadius, radius));
            const spawnRadius = Math.min(largestRadius, SPAWN_RADIUS_SCALE * radius);
            gl.uniform1f(gl.getUniformLocation(dotProgram, "spawnRadius"), spawnRadius);
            gl.drawArrays(gl.POINTS, 0, layer.groups.length);
            gl.disable(gl.BLEND);
        },
        show: (shown) => {
            const texels = new Uint8Array(VISIBILITY_ROW * visibilityRows);
            layer.names.forEach((name, prefab) => (texels[prefab] = shown.has(name) ? 255 : 0));
            gl.activeTexture(gl.TEXTURE0 + VISIBILITY_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, visibility);
            gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
            gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, VISIBILITY_ROW, visibilityRows, gl.RED, gl.UNSIGNED_BYTE, texels);
        },
        dispose: () => {
            for (const buffer of [...dotBuffers, ...linkBuffers]) gl.deleteBuffer(buffer);
            for (const vertices of [dotVertices, linkVertices]) gl.deleteVertexArray(vertices);
            for (const program of programs) gl.deleteProgram(program);
            gl.deleteTexture(visibility);
        }
    };
}
