import { prefabName } from "@/lib/catalog/prefab-sets";
import { TILES } from "@/lib/catalog/world";
import { groupOf, MAP_GROUPS, type MapGroupId } from "./entity-layer";
import type { GroupVisibility } from "./group-visibility";
import { type MapView, type ScreenPoint, screenToWorld, type Size, worldBounds, type WorldPoint } from "./map-view";
import type { GeneratedWorld } from "./world-dump";

const TILE_SIZE = 4;
const CELL_SIZE = 16;

/** How far from a dot, in screen pixels, the cursor still points at it. */
export const PICK_RADIUS = 8;

export interface ProbedTile {
    name: string;
    displayName: string;
}

export interface ProbedEntity {
    prefab: string;
    displayName: string;
    /** The instance's index in its prefab's savedata list, from 0. */
    index: number;
    x: number;
    z: number;
}

export interface Probe {
    tile: ProbedTile | null;
    entity: ProbedEntity | null;
}

export interface MapProbe {
    /**
     * What the map shows at `point`: its tile, and the entity nearest it within `radius` world units among the groups
     * `visibility` shows and the `highlighted` prefab's instances.
     */
    at: (point: WorldPoint, radius: number, visibility: GroupVisibility, highlighted?: string | null) => Probe;
    /** What the map shows under `cursor` at `view`: {@link at} the world point there, within {@link PICK_RADIUS}. */
    under: (
            view: MapView,
            viewport: Size,
            cursor: ScreenPoint,
            visibility: GroupVisibility,
            highlighted?: string | null
    ) => Probe;
}

/** Finds what's under a point of a world's map, through a grid of its entities. */
export function createMapProbe(world: GeneratedWorld): MapProbe {
    const bounds = worldBounds(world);
    const columns = Math.ceil(bounds.width / CELL_SIZE);
    const rows = Math.ceil(bounds.height / CELL_SIZE);
    const cellOf = (x: number, z: number) => {
        const column = Math.min(columns - 1, Math.max(0, Math.floor((x - bounds.left) / CELL_SIZE)));
        const row = Math.min(rows - 1, Math.max(0, Math.floor((z - bounds.top) / CELL_SIZE)));
        return { column, row };
    };

    const groups: MapGroupId[] = world.prefabs.map(({ name }) => MAP_GROUPS[groupOf(name)].id);
    const total = world.prefabs.reduce((sum, { positions }) => sum + positions.length / 2, 0);
    const prefabs = new Uint16Array(total);
    const indices = new Uint32Array(total);
    const xs = new Float64Array(total);
    const zs = new Float64Array(total);
    const cells = new Uint32Array(total);
    const cellStarts = new Uint32Array(columns * rows + 1);
    let entity = 0;
    world.prefabs.forEach(({ positions }, prefab) => {
        for (let index = 0; index < positions.length / 2; index++, entity++) {
            prefabs[entity] = prefab;
            indices[entity] = index;
            xs[entity] = positions[2 * index] / 100;
            zs[entity] = positions[2 * index + 1] / 100;
            const { column, row } = cellOf(xs[entity], zs[entity]);
            cells[entity] = row * columns + column;
            cellStarts[cells[entity] + 1]++;
        }
    });
    for (let cell = 0; cell < columns * rows; cell++) cellStarts[cell + 1] += cellStarts[cell];
    const filled = cellStarts.slice(0, -1);
    const byCell = new Uint32Array(total);
    for (let at = 0; at < total; at++) byCell[filled[cells[at]]++] = at;

    const nearest = (point: WorldPoint, radius: number, shown: (prefab: number) => boolean) => {
        const low = cellOf(point.x - radius, point.z - radius);
        const high = cellOf(point.x + radius, point.z + radius);
        let found: number | null = null;
        let closest = radius * radius;
        for (let row = low.row; row <= high.row; row++) {
            const end = cellStarts[row * columns + high.column + 1];
            for (let slot = cellStarts[row * columns + low.column]; slot < end; slot++) {
                const at = byCell[slot];
                const distance = (xs[at] - point.x) ** 2 + (zs[at] - point.z) ** 2;
                if (distance > closest || !shown(prefabs[at])) continue;
                closest = distance;
                found = at;
            }
        }
        return found;
    };

    const tileAt = ({ x, z }: WorldPoint): ProbedTile | null => {
        const column = Math.fround(Math.fround(x + TILE_SIZE / 2 + TILE_SIZE / 2 * world.width) / TILE_SIZE);
        const row = Math.fround(Math.fround(z + TILE_SIZE / 2 + TILE_SIZE / 2 * world.height) / TILE_SIZE);
        if (!(column >= 0 && column < world.width && row >= 0 && row < world.height)) return null;
        const name = world.tileNames.get(world.tiles[Math.trunc(row) * world.width + Math.trunc(column)]) ?? "";
        return { name, displayName: TILES[name]?.displayName ?? name };
    };

    const at: MapProbe["at"] = (point, radius, visibility, highlighted = null) => {
        const shown = (prefab: number) => visibility[groups[prefab]] || world.prefabs[prefab].name === highlighted;
        const found = nearest(point, radius, shown);
        const prefab = found === null ? "" : world.prefabs[prefabs[found]].name;
        return {
            tile: tileAt(point),
            entity: found === null ? null : {
                prefab,
                displayName: prefabName(prefab),
                index: indices[found],
                x: xs[found],
                z: zs[found]
            }
        };
    };
    return {
        at,
        under: (view, viewport, cursor, visibility, highlighted) =>
            at(screenToWorld(view, viewport, cursor), PICK_RADIUS / view.scale, visibility, highlighted)
    };
}
