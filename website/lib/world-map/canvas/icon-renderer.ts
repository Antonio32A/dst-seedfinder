import { MAP_TEXTURES } from "@/lib/catalog/world";
import { drawOrder, ICON_STRIDE, type IconLayer } from "@/lib/world-map/legend/icon-layer";
import { FORGOTTEN_BRIGHTNESS } from "@/lib/world-map/terrain/terrain-renderer";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import { VISIBILITY_TRANSFORM, VISIBILITY_UNIT } from "./entity-renderer";
import { buildProgram, fetchTexels, viewUniforms } from "./gl-program";

const SHEET_UNIT = 3;
const WORLD_UNIT_PIXELS = 6.4;
const SPAWN_MINIMUM_SIZE = 20;
const FLOAT_BYTES = 4;

const INSTANCE_ATTRIBUTES = [
    { name: "position", size: 2 },
    { name: "rect", size: 4 },
    { name: "prefab", size: 1 }
];

const VERTEX_SHADER = `#version 300 es
in vec2 corner;
in vec2 position;
in vec4 rect;
in float prefab;
uniform vec2 sheetSize;
uniform float scale;
uniform float spawn;
uniform float spawnMinimum;
out vec2 uv;
${VISIBILITY_TRANSFORM}

void main() {
    vec2 size = rect.zw * scale / ${WORLD_UNIT_PIXELS.toFixed(1)};
    if (prefab == spawn) size *= max(1.0, spawnMinimum / max(size.x, size.y));
    uv = (rect.xy + corner * rect.zw) / sheetSize;
    gl_Position = hidden(prefab) ? vec4(2.0, 2.0, 2.0, 1.0) : clipped(onScreen(position) + (corner - 0.5) * size);
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform sampler2D icons;
uniform float brightness;
in vec2 uv;
out vec4 colour;

void main() {
    vec4 texel = texture(icons, uv);
    if (texel.a <= 0.0) discard;
    colour = vec4(texel.rgb * brightness, texel.a);
}`;

export interface IconRenderer {
    /** Settles once the sprite sheet is uploaded or disposed of, and rejects when it can't be downloaded. */
    built: Promise<void>;
    draw: (view: MapView, viewport: Size) => void;
    /** Dims the icons to the terrain's fog brightness, as it opens. */
    darken: (on: boolean) => void;
    dispose: () => void;
}

/**
 * Draws each icon of the game's sprite sheet as a billboard of constant world size, like the game's minimap: the
 * premultiplied sheet blended by its alpha, sampled trilinearly, the lowest priority and the top of the view first.
 * It draws what `visibility` shows, after the entity dots, and nothing until the sheet has downloaded.
 */
export function createIconRenderer(
    gl: WebGL2RenderingContext,
    icons: IconLayer,
    visibility: WebGLTexture,
    spawn: number,
    onBuilt: () => void
): IconRenderer {
    const program = buildProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
    const vertices = gl.createVertexArray();
    gl.bindVertexArray(vertices);
    const corners = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, corners);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), gl.STATIC_DRAW);
    const cornerLocation = gl.getAttribLocation(program, "corner");
    gl.enableVertexAttribArray(cornerLocation);
    gl.vertexAttribPointer(cornerLocation, 2, gl.FLOAT, false, 0, 0);
    const instances = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, instances);
    let offset = 0;
    for (const { name, size } of INSTANCE_ATTRIBUTES) {
        const location = gl.getAttribLocation(program, name);
        gl.enableVertexAttribArray(location);
        gl.vertexAttribPointer(location, size, gl.FLOAT, false, ICON_STRIDE * FLOAT_BYTES, offset * FLOAT_BYTES);
        gl.vertexAttribDivisor(location, 1);
        offset += size;
    }

    gl.useProgram(program);
    const setView = viewUniforms(gl, program);
    const scaleUniform = gl.getUniformLocation(program, "scale");
    const brightnessUniform = gl.getUniformLocation(program, "brightness");
    gl.uniform1f(gl.getUniformLocation(program, "spawn"), spawn);
    gl.uniform1f(gl.getUniformLocation(program, "spawnMinimum"), SPAWN_MINIMUM_SIZE);
    gl.uniform2f(gl.getUniformLocation(program, "sheetSize"), MAP_TEXTURES.iconSheet.width, MAP_TEXTURES.iconSheet.height);
    gl.uniform1i(gl.getUniformLocation(program, "shown"), VISIBILITY_UNIT);
    gl.uniform1i(gl.getUniformLocation(program, "icons"), SHEET_UNIT);

    let sheet: WebGLTexture | null = null;
    let disposed = false;
    let darkened = true;
    let arrangedFor: number | null = null;

    const built = fetchTexels(MAP_TEXTURES.iconSheet.url).then((image) => {
        if (disposed) return image.close();
        sheet = gl.createTexture();
        gl.activeTexture(gl.TEXTURE0 + SHEET_UNIT);
        gl.bindTexture(gl.TEXTURE_2D, sheet);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        for (const parameter of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.CLAMP_TO_EDGE);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, image);
        image.close();
        gl.generateMipmap(gl.TEXTURE_2D);
        onBuilt();
    });

    return {
        built,
        draw: (view, viewport) => {
            if (sheet === null || icons.priorities.length === 0) return;
            gl.useProgram(program);
            gl.bindVertexArray(vertices);
            setView(view, viewport);
            gl.uniform1f(scaleUniform, view.scale);
            gl.uniform1f(brightnessUniform, darkened ? FORGOTTEN_BRIGHTNESS : 1);
            gl.activeTexture(gl.TEXTURE0 + SHEET_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, sheet);
            gl.activeTexture(gl.TEXTURE0 + VISIBILITY_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, visibility);
            if (arrangedFor !== view.heading) {
                gl.bindBuffer(gl.ARRAY_BUFFER, instances);
                gl.bufferData(gl.ARRAY_BUFFER, drawOrder(icons, view.heading), gl.DYNAMIC_DRAW);
                arrangedFor = view.heading;
            }
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ZERO, gl.ONE);
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, icons.priorities.length);
            gl.disable(gl.BLEND);
        },
        darken: (on) => (darkened = on),
        dispose: () => {
            disposed = true;
            gl.deleteTexture(sheet);
            gl.deleteBuffer(corners);
            gl.deleteBuffer(instances);
            gl.deleteVertexArray(vertices);
            gl.deleteProgram(program);
        }
    };
}
