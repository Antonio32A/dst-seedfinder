import { type EntityLayer, MAP_GROUPS } from "@/lib/world-map/legend/entity-layer";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import { buildProgram, unitColour, vertexBuffer, viewUniforms, VIEW_TRANSFORM } from "./gl-program";

const HALF_WIDTH = 0.625;
const FEATHER = 1;

const VERTEX_SHADER = `#version 300 es
in vec2 corner;
in vec4 ends;
uniform float halfWidth;
out float across;
${VIEW_TRANSFORM}

void main() {
    vec2 entry = onScreen(ends.xy);
    vec2 exit = onScreen(ends.zw);
    vec2 along = exit - entry;
    vec2 normal = length(along) > 0.0 ? normalize(vec2(-along.y, along.x)) : vec2(0.0);
    across = corner.y * (halfWidth + ${FEATHER.toFixed(1)});
    gl_Position = clipped(entry + corner.x * along + across * normal);
}`;

const FRAGMENT_SHADER = `#version 300 es
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

export interface LinkRenderer {
    draw: (view: MapView, viewport: Size) => void;
    /** Shows or hides every link, whichever prefabs are shown. Links start hidden. */
    show: (on: boolean) => void;
    dispose: () => void;
}

/** Draws a line between the two ends of each wormhole link. */
export function createLinkRenderer(gl: WebGL2RenderingContext, layer: EntityLayer): LinkRenderer {
    const program = buildProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
    const vertices = gl.createVertexArray();
    gl.bindVertexArray(vertices);
    const buffers = [
        vertexBuffer(gl, program, "corner", new Float32Array([0, -1, 1, -1, 0, 1, 1, 1]), 2),
        vertexBuffer(gl, program, "ends", layer.links, 4, 1)
    ];
    gl.useProgram(program);
    gl.uniform1f(gl.getUniformLocation(program, "halfWidth"), HALF_WIDTH);
    gl.uniform3fv(gl.getUniformLocation(program, "fill"), unitColour(MAP_GROUPS[layer.linkGroup].colour));
    const setView = viewUniforms(gl, program);
    let shown = false;

    return {
        draw: (view, viewport) => {
            if (!shown || layer.links.length === 0) return;
            gl.useProgram(program);
            gl.bindVertexArray(vertices);
            setView(view, viewport);
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, layer.links.length / 4);
            gl.disable(gl.BLEND);
        },
        show: (on) => (shown = on),
        dispose: () => {
            for (const buffer of buffers) gl.deleteBuffer(buffer);
            gl.deleteVertexArray(vertices);
            gl.deleteProgram(program);
        }
    };
}
