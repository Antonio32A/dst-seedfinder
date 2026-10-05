import type { EntityLayer } from "@/lib/world-map/legend/entity-layer";
import { iconLayer } from "@/lib/world-map/legend/icon-layer";
import { turfBridges } from "@/lib/world-map/legend/turf-bridges";
import { createTerrainRenderer, type TerrainRenderer } from "@/lib/world-map/terrain/terrain-renderer";
import type { MapView, Size } from "@/lib/world-map/view/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import { type BridgeRenderer, createBridgeRenderer } from "./bridge-renderer";
import { createEntityRenderer, type EntityRenderer } from "./entity-renderer";
import { createIconRenderer, type IconRenderer } from "./icon-renderer";
import { createLinkRenderer, type LinkRenderer } from "./link-renderer";
import { createRoadRenderer, type RoadRenderer } from "./road-renderer";
import { createSetPieceRenderer, type SetPieceRenderer } from "./set-piece-renderer";

const BACKGROUND = [22, 17, 14] as const;

export interface MapScene {
    terrain: TerrainRenderer;
    roads: RoadRenderer;
    bridges: BridgeRenderer;
    setPieces: SetPieceRenderer;
    entities: EntityRenderer;
    icons: IconRenderer;
    links: LinkRenderer;
    /**
     * Settles once every downloaded texture is uploaded, and rejects with a readable error when the map art can't be
     * downloaded.
     */
    built: Promise<void>;
    /** Clears the whole canvas to the map's background and draws every layer, bottom to top. */
    draw: (view: MapView, viewport: Size) => void;
    /** Darkens or clears the fog over the terrain, roads and icons, which open darkened. */
    darken: (on: boolean) => void;
    dispose: () => void;
}

/**
 * Every layer of the world map on `gl`, from the terrain to the wormhole links, in their initial state: darkened, roads
 * shown, every prefab, set piece, turf bridge and link hidden. `onBuilt` is called as each downloaded texture arrives.
 * `accent` is the highlight colour, `[r, g, b]` in 0-255.
 */
export function createMapScene(
    gl: WebGL2RenderingContext,
    world: GeneratedWorld,
    layer: EntityLayer,
    accent: readonly number[],
    onBuilt: () => void
): MapScene {
    const terrain = createTerrainRenderer(gl, world, onBuilt);
    const roads = createRoadRenderer(gl, world.roads ?? [], onBuilt);
    const bridges = createBridgeRenderer(gl, turfBridges(world));
    const setPieces = createSetPieceRenderer(gl, world.setPieces ?? []);
    const icons = iconLayer(layer);
    const entities = createEntityRenderer(gl, layer, icons.iconed, accent);
    const iconRenderer = createIconRenderer(gl, icons, entities.visibility, accent, onBuilt);
    const links = createLinkRenderer(gl, layer);
    const layers = [terrain, roads, bridges, setPieces, entities, iconRenderer, links];
    const fogged = [terrain, roads, iconRenderer];

    return {
        terrain,
        roads,
        bridges,
        setPieces,
        entities,
        icons: iconRenderer,
        links,
        built: Promise.all([terrain.built, roads.built, iconRenderer.built]).then(() => undefined),
        draw: (view, viewport) => {
            gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
            const [red, green, blue] = BACKGROUND;
            gl.clearColor(red / 255, green / 255, blue / 255, 1);
            gl.clear(gl.COLOR_BUFFER_BIT);
            for (const drawn of layers) drawn.draw(view, viewport);
        },
        darken: (on) => {
            for (const dimmed of fogged) dimmed.darken(on);
        },
        dispose: () => {
            for (const drawn of layers) drawn.dispose();
        }
    };
}
