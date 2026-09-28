import { type EntityLayer, MAP_GROUPS } from "@/lib/world-map/legend/entity-layer";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import { buildProgram, vertexBuffer, viewUniforms, VIEW_TRANSFORM } from "./gl-program";

const MIN_DOT_RADIUS = 2.5;
const MAX_DOT_RADIUS = 8;
const DOT_RADIUS_PER_WORLD_UNIT = 1;
const VISIBILITY_ROW = 256;
export const VISIBILITY_UNIT = 2;

const unit = (channel: number) => channel / 255;

/** GLSL for the visibility texture: per prefab, red is whether it shows and green whether it has an icon. */
export const VISIBILITY_TRANSFORM = `${VIEW_TRANSFORM}
uniform sampler2D shown;

vec2 status(float prefab) {
    int at = int(prefab);
    return texelFetch(shown, ivec2(at % ${VISIBILITY_ROW}, at / ${VISIBILITY_ROW}), 0).rg;
}

bool hidden(float prefab) {
    return status(prefab).r < 0.5;
}

bool iconed(float prefab) {
    return status(prefab).g > 0.5;
}`;

const DOT_VERTEX_SHADER = `#version 300 es
in vec2 position;
in float group;
in float prefab;
uniform vec3 colours[${MAP_GROUPS.length}];
uniform float radius;
out vec3 fill;
flat out float dotRadius;
${VISIBILITY_TRANSFORM}

void main() {
    fill = colours[int(group)];
    dotRadius = radius;
    gl_PointSize = 2.0 * dotRadius + 1.0;
    gl_Position = hidden(prefab) || iconed(prefab) ? vec4(2.0, 2.0, 2.0, 1.0) : clipped(onScreen(position));
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

export interface EntityRenderer {
    /** Bound to {@link VISIBILITY_UNIT} by {@link draw}. */
    visibility: WebGLTexture;
    draw: (view: MapView, viewport: Size) => void;
    show: (shown: ReadonlySet<string>) => void;
    dispose: () => void;
}

/**
 * Which prefabs show is a texture the shaders look each dot's prefab up in, so a toggle uploads a few bytes per prefab.
 * The prefabs `iconed` marks draw no dot: the icon renderer draws them.
 */
export function createEntityRenderer(gl: WebGL2RenderingContext, layer: EntityLayer, iconed: Uint8Array): EntityRenderer {
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
    gl.uniform3fv(gl.getUniformLocation(dotProgram, "colours"), MAP_GROUPS.flatMap(({ colour }) => colour.map(unit)));

    const visibilityRows = Math.max(1, Math.ceil(layer.names.length / VISIBILITY_ROW));
    const visibility = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0 + VISIBILITY_UNIT);
    gl.bindTexture(gl.TEXTURE_2D, visibility);
    for (const parameter of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.NEAREST);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RG8, VISIBILITY_ROW, visibilityRows, 0, gl.RG, gl.UNSIGNED_BYTE, null);
    gl.useProgram(dotProgram);
    gl.uniform1i(gl.getUniformLocation(dotProgram, "shown"), VISIBILITY_UNIT);

    const radiusUniform = gl.getUniformLocation(dotProgram, "radius");
    const setView = viewUniforms(gl, dotProgram);

    return {
        visibility,
        draw: (view, viewport) => {
            gl.useProgram(dotProgram);
            setView(view, viewport);
            gl.activeTexture(gl.TEXTURE0 + VISIBILITY_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, visibility);
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.bindVertexArray(dotVertices);
            const radius = Math.min(MAX_DOT_RADIUS, Math.max(MIN_DOT_RADIUS, view.scale * DOT_RADIUS_PER_WORLD_UNIT));
            gl.uniform1f(radiusUniform, Math.min(largestRadius, radius));
            gl.drawArrays(gl.POINTS, 0, layer.groups.length);
            gl.disable(gl.BLEND);
        },
        show: (shown) => {
            const texels = new Uint8Array(2 * VISIBILITY_ROW * visibilityRows);
            layer.names.forEach((name, prefab) => {
                texels[2 * prefab] = shown.has(name) ? 255 : 0;
                texels[2 * prefab + 1] = iconed[prefab] * 255;
            });
            gl.activeTexture(gl.TEXTURE0 + VISIBILITY_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, visibility);
            gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
            gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, VISIBILITY_ROW, visibilityRows, gl.RG, gl.UNSIGNED_BYTE, texels);
        },
        dispose: () => {
            for (const buffer of dotBuffers) gl.deleteBuffer(buffer);
            gl.deleteVertexArray(dotVertices);
            gl.deleteProgram(dotProgram);
            gl.deleteTexture(visibility);
        }
    };
}
