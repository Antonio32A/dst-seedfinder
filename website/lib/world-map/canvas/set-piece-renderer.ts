import { SET_PIECE_COLOUR } from "@/lib/world-map/legend/set-pieces";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import type { DumpSetPiece } from "@/lib/world-map/world/world-dump";
import { buildProgram, setViewUniforms, vertexBuffer, VIEW_TRANSFORM } from "./gl-program";

const HIDDEN = 0;
const SHOWN = 1;
const HIGHLIGHTED = 2;
const FEATHER = 1;
const EDGE: [number, number, number] = [0.08, 0.08, 0.08];
const HIGHLIGHT: [number, number, number] = [1, 1, 1];
const PASSES = [
    { state: SHOWN, halfWidth: 1.5, colour: EDGE },
    { state: SHOWN, halfWidth: 0.75, colour: SET_PIECE_COLOUR.map((channel) => channel / 255) },
    { state: HIGHLIGHTED, halfWidth: 2.5, colour: EDGE },
    { state: HIGHLIGHTED, halfWidth: 1.25, colour: HIGHLIGHT }
];

const VERTEX_SHADER = `#version 300 es
in vec2 corner;
in vec4 ends;
in float state;
uniform float drawn;
uniform float halfWidth;
out float across;
${VIEW_TRANSFORM}

void main() {
    vec2 start = onScreen(ends.xy);
    vec2 line = onScreen(ends.zw) - start;
    vec2 along = length(line) > 0.0 ? normalize(line) : vec2(0.0);
    across = corner.y * (halfWidth + ${FEATHER.toFixed(1)});
    vec2 capped = start - halfWidth * along + corner.x * (line + 2.0 * halfWidth * along);
    vec2 screen = capped + across * vec2(-along.y, along.x);
    gl_Position = state == drawn ? clipped(screen) : vec4(2.0, 2.0, 2.0, 1.0);
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
    colour = vec4(fill, coverage);
}`;

export interface SetPieceRenderer {
    draw: (view: MapView, viewport: Size) => void;
    /** `shown` holds layout names. */
    show: (shown: ReadonlySet<string>) => void;
    /** Outlines the set pieces at `indices` brighter and thicker, shown or not. */
    highlight: (indices: readonly number[]) => void;
    dispose: () => void;
}

export function createSetPieceRenderer(
    gl: WebGL2RenderingContext,
    setPieces: readonly DumpSetPiece[]
): SetPieceRenderer {
    const ends = Float32Array.from(setPieces.flatMap(({ bounds }) => {
        const [x0, z0, x1, z1] = [...bounds].map((centi) => centi / 100);
        return [x0, z0, x1, z0, x1, z0, x1, z1, x1, z1, x0, z1, x0, z1, x0, z0];
    }));
    const states = new Float32Array(ends.length / 4);
    const program = buildProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
    const uniform = (name: string) => gl.getUniformLocation(program, name);
    const vertices = gl.createVertexArray();
    gl.bindVertexArray(vertices);
    const buffers = [
        vertexBuffer(gl, program, "corner", new Float32Array([0, -1, 1, -1, 0, 1, 1, 1]), 2),
        vertexBuffer(gl, program, "ends", ends, 4, 1)
    ];
    const stateBuffer = vertexBuffer(gl, program, "state", states, 1, 1);
    let shown: ReadonlySet<string> = new Set();
    let highlighted: ReadonlySet<number> = new Set();
    let drawn = new Set<number>();

    const upload = () => {
        setPieces.forEach(({ name }, piece) => {
            const state = highlighted.has(piece) ? HIGHLIGHTED : shown.has(name) ? SHOWN : HIDDEN;
            states.fill(state, 4 * piece, 4 * piece + 4);
        });
        drawn = new Set(states);
        gl.bindBuffer(gl.ARRAY_BUFFER, stateBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, states, gl.DYNAMIC_DRAW);
    };

    return {
        draw: (view, viewport) => {
            const passes = PASSES.filter(({ state }) => drawn.has(state));
            if (passes.length === 0) return;
            gl.useProgram(program);
            gl.bindVertexArray(vertices);
            setViewUniforms(gl, program, view, viewport);
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            for (const { state, halfWidth, colour } of passes) {
                gl.uniform1f(uniform("drawn"), state);
                gl.uniform1f(uniform("halfWidth"), halfWidth);
                gl.uniform3fv(uniform("fill"), colour);
                gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, states.length);
            }
            gl.disable(gl.BLEND);
        },
        show: (names) => {
            shown = names;
            upload();
        },
        highlight: (indices) => {
            highlighted = new Set(indices);
            upload();
        },
        dispose: () => {
            for (const buffer of [...buffers, stateBuffer]) gl.deleteBuffer(buffer);
            gl.deleteVertexArray(vertices);
            gl.deleteProgram(program);
        }
    };
}
