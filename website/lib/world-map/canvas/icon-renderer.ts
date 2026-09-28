import { MAP_TEXTURES } from "@/lib/catalog/world";
import { drawOrder, ICON_STRIDE, type IconLayer } from "@/lib/world-map/legend/icon-layer";
import { FORGOTTEN_BRIGHTNESS } from "@/lib/world-map/terrain/terrain-renderer";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import { type HoveredEntity, NO_HOVER, VISIBILITY_TRANSFORM, VISIBILITY_UNIT } from "./entity-renderer";
import { buildProgram, fetchTexelRegions, viewUniforms } from "./gl-program";

const SHEET_UNIT = 3;
const WORLD_UNIT_PIXELS = 6.4;
const FLOAT_BYTES = 4;
const OUTLINE_PIXELS = 2;
const OUTLINE_SLACK = 1;
const OUTLINE_ANGLES = 8;

const DIRECTIONS = Array.from({ length: OUTLINE_ANGLES }, (_, step) => {
    const angle = 2 * Math.PI * step / OUTLINE_ANGLES;
    return `vec2(${Math.cos(angle).toFixed(4)}, ${Math.sin(angle).toFixed(4)})`;
});
const OUTLINE_RINGS = Array.from({ length: OUTLINE_PIXELS }, (_, ring) => (ring + 1).toFixed(1));

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
uniform float lifted;
out vec2 texel;
flat out vec4 bounds;
flat out vec2 texelsPerPixel;
flat out float outlined;
${VISIBILITY_TRANSFORM}

void main() {
    vec2 size = rect.zw * scale / ${WORLD_UNIT_PIXELS.toFixed(1)};
    bool highlight = lit(prefab, position);
    vec2 grown = size + 2.0 * (highlight ? ${OUTLINE_PIXELS + OUTLINE_SLACK}.0 : 0.0);
    texelsPerPixel = rect.zw / size;
    texel = rect.xy + 0.5 * rect.zw + (corner - 0.5) * grown * texelsPerPixel;
    bounds = rect;
    outlined = highlight ? 1.0 : 0.0;
    bool skipped = hidden(prefab) || highlight != (lifted > 0.5);
    gl_Position = skipped ? vec4(2.0, 2.0, 2.0, 1.0) : clipped(onScreen(position) + (corner - 0.5) * grown);
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform sampler2D icons;
uniform vec2 sheetSize;
uniform float brightness;
uniform vec3 accent;
in vec2 texel;
flat in vec4 bounds;
flat in vec2 texelsPerPixel;
flat in float outlined;
out vec4 colour;

const vec2 DIRECTIONS[${OUTLINE_ANGLES}] = vec2[${OUTLINE_ANGLES}](${DIRECTIONS.join(", ")});
const float RINGS[${OUTLINE_PIXELS}] = float[${OUTLINE_PIXELS}](${OUTLINE_RINGS.join(", ")});

vec4 iconAt(vec2 at, vec2 across, vec2 down) {
    vec2 inside = step(bounds.xy, at) * step(at, bounds.xy + bounds.zw);
    return inside.x * inside.y * textureGrad(icons, at / sheetSize, across / sheetSize, down / sheetSize);
}

void main() {
    vec2 across = dFdx(texel);
    vec2 down = dFdy(texel);
    vec4 own = iconAt(texel, across, down);
    float halo = 0.0;
    if (outlined > 0.5) {
        for (int ring = 0; ring < ${OUTLINE_PIXELS}; ring++) {
            for (int direction = 0; direction < ${OUTLINE_ANGLES}; direction++) {
                halo = max(halo, iconAt(texel + DIRECTIONS[direction] * RINGS[ring] * texelsPerPixel, across, down).a);
            }
        }
    }
    float alpha = max(own.a, halo);
    if (alpha <= 0.0) discard;
    vec3 fill = own.rgb * brightness;
    colour = vec4(outlined > 0.5 ? mix(accent, fill, own.a) : fill, alpha);
}`;

export interface IconRenderer {
    /** Settles once the sprite sheet is uploaded or disposed of, and rejects when it can't be downloaded. */
    built: Promise<void>;
    draw: (view: MapView, viewport: Size) => void;
    /** Dims the icons to the terrain's fog brightness, as it opens. */
    darken: (on: boolean) => void;
    /** Outlines the icon at `entity`'s position, or none. */
    hover: (entity: HoveredEntity) => void;
    dispose: () => void;
}

/**
 * Draws each icon of the game's sprite sheet as a billboard of constant world size, like the game's minimap: the
 * premultiplied sheet blended by its alpha, sampled trilinearly from the game's own mip chain, the lowest priority and the top of the view first.
 * It draws what `visibility` shows, after the entity dots, and nothing until the sheet has downloaded.
 *
 * Highlighted and hovered icons are drawn again on top of the rest, in the same order, each grown by an outline
 * of `accent` (`[r, g, b]` in 0-255): the icon's alpha dilated by {@link OUTLINE_PIXELS} screen pixels in one pass.
 */
export function createIconRenderer(
    gl: WebGL2RenderingContext,
    icons: IconLayer,
    visibility: WebGLTexture,
    accent: readonly number[],
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
    const liftedUniform = gl.getUniformLocation(program, "lifted");
    const hoveredUniform = gl.getUniformLocation(program, "hovered");
    gl.uniform3fv(gl.getUniformLocation(program, "accent"), accent.map((channel) => channel / 255));
    gl.uniform2f(gl.getUniformLocation(program, "sheetSize"), MAP_TEXTURES.iconSheet.width, MAP_TEXTURES.iconSheet.height);
    gl.uniform1i(gl.getUniformLocation(program, "shown"), VISIBILITY_UNIT);
    gl.uniform1i(gl.getUniformLocation(program, "icons"), SHEET_UNIT);

    let sheet: WebGLTexture | null = null;
    let disposed = false;
    let darkened = true;
    let arrangedFor: number | null = null;
    let hovered = NO_HOVER;

    const built = fetchTexelRegions(MAP_TEXTURES.iconSheet.url, MAP_TEXTURES.iconSheet.levels).then((levels) => {
        if (disposed) return levels.forEach((level) => level.close());
        sheet = gl.createTexture();
        gl.activeTexture(gl.TEXTURE0 + SHEET_UNIT);
        gl.bindTexture(gl.TEXTURE_2D, sheet);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        for (const parameter of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, levels.length - 1);
        levels.forEach((level, mip) => {
            gl.texImage2D(gl.TEXTURE_2D, mip, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, level);
            level.close();
        });
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
            gl.uniform3f(hoveredUniform, hovered.prefab, hovered.x, hovered.z);
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ZERO, gl.ONE);
            for (const lifted of [0, 1]) {
                gl.uniform1f(liftedUniform, lifted);
                gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, icons.priorities.length);
            }
            gl.disable(gl.BLEND);
        },
        darken: (on) => (darkened = on),
        hover: (entity) => (hovered = entity),
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
