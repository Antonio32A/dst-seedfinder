import { entityLayer, mapWorld } from "@/lib/world-map/legend/entity-layer";
import { defaultShown } from "@/lib/world-map/legend/prefab-visibility";
import { fitView, type LinkedView, openLinkedView, type Size } from "@/lib/world-map/view/map-view";
import { parseWorldDump } from "@/lib/world-map/world/world-dump";
import { readAccent } from "./accent-colour";
import { createMapScene } from "./map-scene";

export interface PreviewImage {
    size: Size;
    /** The whole world, fitted at the game's default heading, without one. */
    view?: LinkedView;
    /** An image type `canvas.toBlob` encodes, PNG by default. */
    type?: string;
    /** From 0 to 1, for the lossy types. */
    quality?: number;
}

/**
 * Draws the world of `dump` once into `canvas`, resized to the image's size, with what the map shows by default (the
 * icons the game's map draws and the roads), and encodes it. Throws when the dump has no world or the browser can't draw
 * the map.
 */
export async function renderMapPreview(
    canvas: HTMLCanvasElement,
    dump: Uint8Array,
    { size, view, type, quality }: PreviewImage
): Promise<Blob> {
    const parsed = parseWorldDump(dump);
    if (parsed.status !== "generated") throw new Error("This seed's world generation gave up, so there's no world to show.");
    const world = mapWorld(parsed);
    canvas.width = size.width;
    canvas.height = size.height;
    const gl = canvas.getContext("webgl2", { alpha: true, antialias: false, preserveDrawingBuffer: true });
    if (gl === null) throw new Error("This browser can't draw the map: it needs WebGL2.");
    const scene = createMapScene(gl, world, entityLayer(world), readAccent(canvas), () => undefined);
    try {
        scene.entities.show(defaultShown(undefined, world.shard));
        await scene.built;
        scene.draw(view === undefined ? fitView(world, size) : openLinkedView(view, size), size);
        return await new Promise<Blob>((resolve, reject) => canvas.toBlob(
                (image) => (image === null ? reject(new Error("The map preview couldn't be encoded.")) : resolve(image)),
                type,
                quality
        ));
    } finally {
        scene.dispose();
    }
}
