import { MAP_TEXTURES } from "@/lib/catalog/world";
import { FORGOTTEN_BRIGHTNESS } from "@/lib/world-map/terrain/terrain-renderer";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import type { DumpRoad } from "@/lib/world-map/world/world-dump";
import { buildProgram, fetchTexels, vertexBuffer, VIEW_TRANSFORM, viewUniforms } from "./gl-program";
import { PAVED_WEIGHT, ROAD_STRIPS, ROAD_VERTEX_FLOATS, roadMesh, type RoadStrip } from "./road-geometry";

const BASE_UNIT = 0;
const NOISE_UNIT = 1;
const GROUND_REPEAT = 16;

const STRIP_TEXTURES: Record<RoadStrip, keyof typeof MAP_TEXTURES.road> = {
    corners: "roadcorner",
    ends: "roadendcap",
    edges: "roadedge",
    center: "square"
};
const NOISE_TEXTURES = { paved: "roadnoise", dirt: "pathnoise" } as const;
type RoadKind = keyof typeof NOISE_TEXTURES;
const KINDS = Object.keys(NOISE_TEXTURES) as RoadKind[];

const VERTEX_SHADER = `#version 300 es
in vec4 vertex;
out vec2 uv;
out vec2 ground;
${VIEW_TRANSFORM}

void main() {
    uv = vertex.zw;
    ground = vertex.xy;
    gl_Position = clipped(onScreen(vertex.xy));
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform sampler2D base;
uniform sampler2D noise;
uniform float brightness;
in vec2 uv;
in vec2 ground;
out vec4 colour;

const float GROUND_REPEAT = ${GROUND_REPEAT}.0;

void main() {
    vec4 grain = texture(noise, ground / GROUND_REPEAT);
    vec4 paint = texture(base, uv);
    float alpha = grain.a * paint.a;
    if (alpha <= 0.0) discard;
    colour = vec4(paint.rgb / paint.a * grain.rgb * brightness * alpha, alpha);
}`;

export interface RoadRenderer {
    /** Settles once the road textures are uploaded or disposed of, and rejects when they can't be downloaded. */
    built: Promise<void>;
    draw: (view: MapView, viewport: Size) => void;
    /** Dims the roads to the terrain's fog brightness, as it opens. */
    darken: (on: boolean) => void;
    /** Shows or hides every road. They start shown. */
    show: (on: boolean) => void;
    dispose: () => void;
}

interface Batch {
    kind: RoadKind;
    strip: RoadStrip;
    vertices: WebGLVertexArrayObject;
    buffer: WebGLBuffer;
    count: number;
}

const kindOf = (weight: number): RoadKind => (weight === PAVED_WEIGHT ? "paved" : "dirt");

/**
 * Draws the roads as the game's road shader does: each strip of the road's mesh is its own texture (edge, corner, end
 * cap or the plain centre) times a noise texture sampled by ground position, blended by the product of their alphas.
 * The paved road takes the cobble noise and any other weight the dirt path's. Nothing is drawn until the textures have
 * downloaded.
 */
export function createRoadRenderer(
    gl: WebGL2RenderingContext,
    roads: readonly DumpRoad[],
    onBuilt: () => void
): RoadRenderer {
    const program = buildProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
    gl.useProgram(program);
    gl.uniform1i(gl.getUniformLocation(program, "base"), BASE_UNIT);
    gl.uniform1i(gl.getUniformLocation(program, "noise"), NOISE_UNIT);
    const setView = viewUniforms(gl, program);
    const brightnessUniform = gl.getUniformLocation(program, "brightness");

    const meshes = roads.map(({ points, weight }) => ({ kind: kindOf(weight), mesh: roadMesh(points, weight) }));
    const batches: Batch[] = ROAD_STRIPS.flatMap((strip) => KINDS.flatMap((kind) => {
        const parts = meshes.filter((road) => road.kind === kind).map(({ mesh }) => mesh[strip]);
        const data = new Float32Array(parts.reduce((size, part) => size + part.length, 0));
        parts.reduce((at, part) => (data.set(part, at), at + part.length), 0);
        if (data.length === 0) return [];
        const vertices = gl.createVertexArray();
        gl.bindVertexArray(vertices);
        const buffer = vertexBuffer(gl, program, "vertex", data, ROAD_VERTEX_FLOATS);
        return [{ kind, strip, vertices, buffer, count: data.length / ROAD_VERTEX_FLOATS }];
    }));

    let textures: Map<string, WebGLTexture> | null = null;
    let shown = true;
    let darkened = true;
    let disposed = false;

    const names = [...new Set([
        ...batches.map(({ strip }) => STRIP_TEXTURES[strip]),
        ...batches.map(({ kind }) => NOISE_TEXTURES[kind])
    ])];
    const built = Promise.all(names.map((name) => fetchTexels(MAP_TEXTURES.road[name]))).then((images) => {
        if (disposed) return images.forEach((image) => image.close());
        textures = new Map(names.map((name, index) => {
            const texture = gl.createTexture();
            gl.activeTexture(gl.TEXTURE0 + BASE_UNIT);
            gl.bindTexture(gl.TEXTURE_2D, texture);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
            const ground = Object.values<string>(NOISE_TEXTURES).includes(name);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, ground ? gl.REPEAT : gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, ground || name === "roadedge" ? gl.REPEAT : gl.CLAMP_TO_EDGE);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, images[index]);
            gl.generateMipmap(gl.TEXTURE_2D);
            images[index].close();
            return [name, texture] as const;
        }));
        onBuilt();
    });

    return {
        built,
        draw: (view, viewport) => {
            if (textures === null || !shown || batches.length === 0) return;
            gl.useProgram(program);
            setView(view, viewport);
            gl.uniform1f(brightnessUniform, darkened ? FORGOTTEN_BRIGHTNESS : 1);
            gl.enable(gl.BLEND);
            gl.blendFuncSeparate(gl.ONE, gl.ONE_MINUS_SRC_ALPHA, gl.ZERO, gl.ONE);
            for (const batch of batches) {
                gl.activeTexture(gl.TEXTURE0 + BASE_UNIT);
                gl.bindTexture(gl.TEXTURE_2D, textures.get(STRIP_TEXTURES[batch.strip])!);
                gl.activeTexture(gl.TEXTURE0 + NOISE_UNIT);
                gl.bindTexture(gl.TEXTURE_2D, textures.get(NOISE_TEXTURES[batch.kind])!);
                gl.bindVertexArray(batch.vertices);
                gl.drawArrays(gl.TRIANGLES, 0, batch.count);
            }
            gl.disable(gl.BLEND);
        },
        darken: (on) => (darkened = on),
        show: (on) => (shown = on),
        dispose: () => {
            disposed = true;
            for (const texture of textures?.values() ?? []) gl.deleteTexture(texture);
            for (const { vertices, buffer } of batches) {
                gl.deleteBuffer(buffer);
                gl.deleteVertexArray(vertices);
            }
            gl.deleteProgram(program);
        }
    };
}
