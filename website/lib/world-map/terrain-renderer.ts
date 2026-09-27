import { TILES } from "@/lib/catalog/world";
import { buildProgram, setViewUniforms, vertexBuffer, VIEW_TRANSFORM } from "./gl-program";
import { landLayers } from "./land-layers";
import type { MapView, Size } from "./map-view";
import type { GeneratedWorld } from "./world-dump";

const MAP_EDGE = "/world-map/map_edge.png";
const PIXELS_PER_TILE = 4;
const TERRAIN_CLEAR = [21, 24, 31] as const;
const QUAD_COMPONENTS = 3;
const QUAD_CORNERS = [0, 0, 1, 0, 0, 1, 1, 1];
const TERRAIN_UNIT = 0;
const MAP_EDGE_UNIT = 0;
const NOISE_UNIT = 1;

const LAND_VERTEX_SHADER = `#version 300 es
in vec2 corner;
in uvec3 quad;
uniform vec2 terrainSize;
flat out ivec3 drawn;

const float TILE_PIXELS = ${PIXELS_PER_TILE}.0;

void main() {
    vec2 pixel = (vec2(quad.xy) + corner) * TILE_PIXELS - TILE_PIXELS / 2.0;
    gl_Position = vec4(2.0 * pixel / terrainSize - 1.0, 0.0, 1.0);
    drawn = ivec3(quad);
}`;

const LAND_FRAGMENT_SHADER = `#version 300 es
precision highp float;
precision highp int;
uniform sampler2D mapEdge;
uniform sampler2D noise;
uniform ivec2 worldOrigin;
flat in ivec3 drawn;
out vec4 colour;

const int TILE_PIXELS = ${PIXELS_PER_TILE};
const int ATLAS_SLOTS = 8;
const int SLOT_TEXELS = 128;
const int SLOT_GUTTER = 4;
const int CELL_TEXELS_PER_PIXEL = 30;
const float NOISE_REPEAT = 64.0;

vec2 nearestTexelTowardOrigin(vec2 texelCoordinate) {
    return mix(floor(texelCoordinate), ceil(texelCoordinate) - 1.0, step(0.0, texelCoordinate));
}

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    ivec2 inTile = pixel - drawn.xy * TILE_PIXELS + TILE_PIXELS / 2;
    int slot = drawn.z - 1;
    ivec2 cell = SLOT_GUTTER + SLOT_TEXELS * ivec2(slot % ATLAS_SLOTS, ATLAS_SLOTS - 1 - slot / ATLAS_SLOTS);
    vec4 edge = texelFetch(mapEdge, cell + CELL_TEXELS_PER_PIXEL / 2 + CELL_TEXELS_PER_PIXEL * inTile.yx, 0);
    vec2 size = vec2(textureSize(noise, 0));
    vec2 texel = nearestTexelTowardOrigin((vec2(pixel - worldOrigin) + 0.5) * size / NOISE_REPEAT);
    colour = vec4(edge.rgb * texelFetch(noise, ivec2(mod(texel, size)), 0).rgb, edge.a);
}`;

const SCREEN_VERTEX_SHADER = `#version 300 es
in vec2 corner;
uniform vec4 bounds;
out vec2 uv;
${VIEW_TRANSFORM}

void main() {
    gl_Position = clipped(onScreen(bounds.xy + corner * bounds.zw));
    uv = corner;
}`;

const SCREEN_FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform sampler2D terrain;
in vec2 uv;
out vec4 colour;

void main() {
    colour = vec4(texture(terrain, uv).rgb, 0.0);
}`;

export interface TerrainRenderer {
    /** Settles once the terrain is built, or disposed of first, and rejects when the map art can't be downloaded. */
    built: Promise<void>;
    /** Adds the terrain onto the frame at `view`, a view in CSS pixels, on a canvas of `viewport` CSS pixels. */
    draw: (view: MapView, viewport: Size) => void;
    dispose: () => void;
}

async function loadTexture(gl: WebGL2RenderingContext, url: string) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`The map art couldn't be downloaded: ${url} answered ${response.status}.`);
    const image = await createImageBitmap(await response.blob(), { premultiplyAlpha: "none", colorSpaceConversion: "none" });
    const texture = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0 + NOISE_UNIT);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, image);
    image.close();
    return texture;
}

/**
 * Draws a world's terrain the way the game's map screen does. The terrain is rendered once, into a texture of
 * {@link PIXELS_PER_TILE} pixels per tile, from the game's map_edge atlas times each land tile's minimap noise: every
 * layer's own tiles first, then every layer's edges on its lower ranked neighbours. Each frame adds it onto the map's
 * background, filtered smoothly. Until the art has downloaded, it draws nothing, and it calls `onBuilt` once it can.
 */
export function createTerrainRenderer(
        gl: WebGL2RenderingContext,
        world: GeneratedWorld,
        onBuilt: () => void
): TerrainRenderer {
    const art = (tile: number) => {
        const name = world.tileNames.get(tile) ?? "";
        return Object.hasOwn(TILES, name) && TILES[name].minimapNoise !== undefined ? TILES[name] : undefined;
    };
    const size = { width: PIXELS_PER_TILE * world.width, height: PIXELS_PER_TILE * world.height };
    const program = buildProgram(gl, SCREEN_VERTEX_SHADER, SCREEN_FRAGMENT_SHADER);
    gl.useProgram(program);
    gl.uniform1i(gl.getUniformLocation(program, "terrain"), TERRAIN_UNIT);
    gl.uniform4f(gl.getUniformLocation(program, "bounds"), -size.width / 2, -size.height / 2, size.width, size.height);
    const vertices = gl.createVertexArray();
    gl.bindVertexArray(vertices);
    const corners = vertexBuffer(gl, program, "corner", new Float32Array(QUAD_CORNERS), 2);
    let terrain: WebGLTexture | null = null;
    let disposed = false;

    const build = (mapEdge: WebGLTexture, noises: Map<string, WebGLTexture>) => {
        const layers = landLayers(world, (tile) => art(tile)?.minimapRank);
        const land = buildProgram(gl, LAND_VERTEX_SHADER, LAND_FRAGMENT_SHADER);
        gl.useProgram(land);
        gl.uniform1i(gl.getUniformLocation(land, "mapEdge"), MAP_EDGE_UNIT);
        gl.uniform1i(gl.getUniformLocation(land, "noise"), NOISE_UNIT);
        gl.uniform2f(gl.getUniformLocation(land, "terrainSize"), size.width, size.height);
        gl.uniform2i(gl.getUniformLocation(land, "worldOrigin"), size.width / 2, size.height / 2);
        const landVertices = gl.createVertexArray();
        gl.bindVertexArray(landVertices);
        const landCorners = vertexBuffer(gl, land, "corner", new Float32Array(QUAD_CORNERS), 2);
        const draws = [
            ...layers.map(({ tile, fills }) => ({ tile, quads: fills })),
            ...layers.map(({ tile, edges }) => ({ tile, quads: edges }))
        ];
        const quadBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, quadBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, new Uint16Array(draws.flatMap(({ quads }) => [...quads])), gl.STATIC_DRAW);
        const quadLocation = gl.getAttribLocation(land, "quad");
        gl.enableVertexAttribArray(quadLocation);
        gl.vertexAttribDivisor(quadLocation, 1);

        terrain = gl.createTexture();
        gl.activeTexture(gl.TEXTURE0 + TERRAIN_UNIT);
        gl.bindTexture(gl.TEXTURE_2D, terrain);
        for (const parameter of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.LINEAR);
        for (const parameter of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, parameter, gl.CLAMP_TO_EDGE);
        gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, size.width, size.height);
        const framebuffer = gl.createFramebuffer();
        gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, terrain, 0);
        gl.viewport(0, 0, size.width, size.height);
        const [red, green, blue] = TERRAIN_CLEAR;
        gl.clearColor(red / 255, green / 255, blue / 255, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.activeTexture(gl.TEXTURE0 + MAP_EDGE_UNIT);
        gl.bindTexture(gl.TEXTURE_2D, mapEdge);
        gl.activeTexture(gl.TEXTURE0 + NOISE_UNIT);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        let first = 0;
        for (const { tile, quads } of draws) {
            gl.bindTexture(gl.TEXTURE_2D, noises.get(art(tile)!.minimapNoise!)!);
            gl.vertexAttribIPointer(quadLocation, QUAD_COMPONENTS, gl.UNSIGNED_SHORT, 0, first * Uint16Array.BYTES_PER_ELEMENT);
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, quads.length / QUAD_COMPONENTS);
            first += quads.length;
        }
        gl.disable(gl.BLEND);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.deleteFramebuffer(framebuffer);
        for (const buffer of [landCorners, quadBuffer]) gl.deleteBuffer(buffer);
        gl.deleteVertexArray(landVertices);
        gl.deleteProgram(land);
    };

    const urls = [...new Set([...world.tileNames.keys()].flatMap((tile) => art(tile)?.minimapNoise ?? []))];
    const loads = [MAP_EDGE, ...urls].map((url) => loadTexture(gl, url));
    const built = Promise.all(loads)
            .then(([mapEdge, ...noises]) => {
                if (disposed) return;
                build(mapEdge, new Map(urls.map((url, index) => [url, noises[index]])));
                onBuilt();
            })
            .finally(() => loads.forEach((load) => load.then((texture) => gl.deleteTexture(texture), () => undefined)));

    return {
        built,
        draw: (view, viewport) => {
            if (terrain === null) return;
            gl.useProgram(program);
            gl.bindVertexArray(vertices);
            gl.activeTexture(gl.TEXTURE0 + TERRAIN_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, terrain);
            setViewUniforms(gl, program, view, viewport);
            gl.enable(gl.BLEND);
            gl.blendFunc(gl.ONE, gl.ONE);
            gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
            gl.disable(gl.BLEND);
        },
        dispose: () => {
            disposed = true;
            gl.deleteTexture(terrain);
            gl.deleteBuffer(corners);
            gl.deleteVertexArray(vertices);
            gl.deleteProgram(program);
        }
    };
}
