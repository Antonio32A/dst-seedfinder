import { buildProgram, setViewUniforms, vertexBuffer, VIEW_TRANSFORM } from "./gl-program";
import { type MapView, type Size, worldBounds } from "./map-view";
import { tilePalette } from "./tile-palette";
import type { GeneratedWorld } from "./world-dump";

const PALETTE_ROW = 256;

const VERTEX_SHADER = `#version 300 es
in vec2 corner;
uniform vec2 gridSize;
uniform vec4 bounds;
out vec2 grid;
${VIEW_TRANSFORM}

void main() {
    gl_Position = clipped(onScreen(bounds.xy + corner * bounds.zw));
    grid = corner * gridSize;
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
precision highp usampler2D;
uniform usampler2D tiles;
uniform sampler2D palette;
in vec2 grid;
out vec4 colour;

void main() {
    ivec2 cell = clamp(ivec2(floor(grid)), ivec2(0), textureSize(tiles, 0) - 1);
    uint id = texelFetch(tiles, cell, 0).r;
    colour = texelFetch(palette, ivec2(int(id % ${PALETTE_ROW}u), int(id / ${PALETTE_ROW}u)), 0);
}`;

export interface TileRenderer {
    /** Draws the world at `view`, a view in CSS pixels, on a canvas of `viewport` CSS pixels. */
    draw: (view: MapView, viewport: Size) => void;
    dispose: () => void;
}

function texture(gl: WebGL2RenderingContext, unit: number, upload: () => void) {
    const created = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_2D, created);
    for (const parameter of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.NEAREST);
    for (const parameter of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.CLAMP_TO_EDGE);
    upload();
    return created;
}

/** Draws a world's tiles as one quad: the tile ids as a texture, coloured through the catalog's tile palette. */
export function createTileRenderer(gl: WebGL2RenderingContext, world: GeneratedWorld): TileRenderer {
    const program = buildProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
    gl.useProgram(program);
    const uniform = (name: string) => gl.getUniformLocation(program, name);

    const vertices = gl.createVertexArray();
    gl.bindVertexArray(vertices);
    const corners = vertexBuffer(gl, program, "corner", new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), 2);

    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    const colours = tilePalette(world.tileNames, world.tiles);
    const paletteRows = Math.ceil(colours.length / 4 / PALETTE_ROW);
    const palette = new Uint8Array(4 * PALETTE_ROW * paletteRows);
    palette.set(colours);
    const textures = [
        texture(gl, 0, () =>
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.R16UI, world.width, world.height, 0, gl.RED_INTEGER, gl.UNSIGNED_SHORT, world.tiles)),
        texture(gl, 1, () =>
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, PALETTE_ROW, paletteRows, 0, gl.RGBA, gl.UNSIGNED_BYTE, palette))
    ];
    gl.uniform1i(uniform("tiles"), 0);
    gl.uniform1i(uniform("palette"), 1);

    const bounds = worldBounds(world);
    gl.uniform2f(uniform("gridSize"), world.width, world.height);
    gl.uniform4f(uniform("bounds"), bounds.left, bounds.top, bounds.width, bounds.height);

    return {
        draw: (view, viewport) => {
            gl.useProgram(program);
            gl.bindVertexArray(vertices);
            setViewUniforms(gl, program, view, viewport);
            gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        },
        dispose: () => {
            for (const created of textures) gl.deleteTexture(created);
            gl.deleteBuffer(corners);
            gl.deleteVertexArray(vertices);
            gl.deleteProgram(program);
        }
    };
}
