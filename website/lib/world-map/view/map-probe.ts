import { prefabName } from "@/lib/catalog/prefab-sets";
import { TILES } from "@/lib/catalog/world";
import { WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import type { MapTarget } from "@/lib/world-map/legend/prefab-search";
import { type SetPieceDetails, setPieceDetails } from "@/lib/world-map/legend/set-pieces";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import { type MapView, type ScreenPoint, screenToWorld, type Size, worldBounds, type WorldPoint } from "./map-view";

const CELL_SIZE = 16;

/** In screen pixels. */
export const PICK_RADIUS = 8;

export interface ProbedTile {
    name: string;
    displayName: string;
}

export interface ProbedEntity {
    prefab: string;
    displayName: string;
    /** In its prefab's savedata list. */
    index: number;
    x: number;
    z: number;
    setPiece: { index: number; name: string } | null;
}

export interface Probe {
    /** The tile under the entity, or under the point without one. */
    tile: ProbedTile | null;
    entity: ProbedEntity | null;
    /** The set piece at the point, when there's no entity. */
    setPiece: SetPieceDetails | null;
}

/** The prefabs by id and the set pieces by layout name. */
export interface MapShown {
    prefabs: ReadonlySet<string>;
    setPieces: ReadonlySet<string>;
}

export interface MapProbe {
    /**
     * The entity nearest `point` within `radius` world units, among the `shown` and `searched` prefabs' instances.
     * Without one, the smallest of the `shown` and `searched` set pieces whose bounds hold the point.
     */
    at: (point: WorldPoint, radius: number, shown: MapShown, searched?: MapTarget | null) => Probe;
    /** {@link at} the world point under `cursor`, within {@link PICK_RADIUS}. */
    under: (view: MapView, viewport: Size, cursor: ScreenPoint, shown: MapShown, searched?: MapTarget | null) => Probe;
    /** With the tile at the set piece's centre. */
    setPiece: (index: number) => Probe;
}

export function createMapProbe(world: GeneratedWorld): MapProbe {
    const bounds = worldBounds(world);
    const columns = Math.ceil(bounds.width / CELL_SIZE);
    const rows = Math.ceil(bounds.height / CELL_SIZE);
    const cellOf = (x: number, z: number) => {
        const column = Math.min(columns - 1, Math.max(0, Math.floor((x - bounds.left) / CELL_SIZE)));
        const row = Math.min(rows - 1, Math.max(0, Math.floor((z - bounds.top) / CELL_SIZE)));
        return { column, row };
    };

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

    const tileAt = ({ x, z }: WorldPoint): ProbedTile | null => {
        const half = WORLD_UNITS_PER_TILE / 2;
        const column = Math.fround(Math.fround(x + half + half * world.width) / WORLD_UNITS_PER_TILE);
        const row = Math.fround(Math.fround(z + half + half * world.height) / WORLD_UNITS_PER_TILE);
        if (!(column >= 0 && column < world.width && row >= 0 && row < world.height)) return null;
        const name = world.tileNames.get(world.tiles[Math.trunc(row) * world.width + Math.trunc(column)]) ?? "";
        return { name, displayName: TILES[name]?.displayName ?? name };
    };

    const pieces = world.setPieces ?? [];
    const owners = world.prefabs.map(({ positions }) => new Int32Array(positions.length / 2).fill(-1));
    pieces.forEach(({ members }, piece) => {
        for (let at = 0; at < members.length; at += 2) {
            const owner = owners[members[at]];
            if (owner[members[at + 1]] === -1) owner[members[at + 1]] = piece;
        }
    });

    const at: MapProbe["at"] = (point, radius, shown, searched = null) => {
        const isShown = (kind: MapTarget["kind"], name: string, names: ReadonlySet<string>) =>
            names.has(name) || (searched?.kind === kind && searched.name === name);
        const low = cellOf(point.x - radius, point.z - radius);
        const high = cellOf(point.x + radius, point.z + radius);
        let found: number | null = null;
        let closest = radius * radius;
        for (let row = low.row; row <= high.row; row++) {
            const end = cellStarts[row * columns + high.column + 1];
            for (let slot = cellStarts[row * columns + low.column]; slot < end; slot++) {
                const candidate = byCell[slot];
                const distance = (xs[candidate] - point.x) ** 2 + (zs[candidate] - point.z) ** 2;
                const { name } = world.prefabs[prefabs[candidate]];
                if (distance > closest || !isShown("prefab", name, shown.prefabs)) continue;
                closest = distance;
                found = candidate;
            }
        }
        if (found === null) {
            let piece: number | null = null;
            let smallest = Infinity;
            const [x, z] = [100 * point.x, 100 * point.z];
            for (const [index, { name, bounds: [x0, z0, x1, z1] }] of pieces.entries()) {
                const area = (x1 - x0) * (z1 - z0);
                const inside = x0 <= x && x <= x1 && z0 <= z && z <= z1;
                if (!inside || area >= smallest || !isShown("set piece", name, shown.setPieces)) continue;
                smallest = area;
                piece = index;
            }
            const setPiece = piece === null ? null : setPieceDetails(world, piece);
            return { tile: tileAt(point), entity: null, setPiece };
        }
        const prefab = world.prefabs[prefabs[found]].name;
        const owner = owners[prefabs[found]][indices[found]];
        return {
            tile: tileAt({ x: xs[found], z: zs[found] }),
            entity: {
                prefab,
                displayName: prefabName(prefab),
                index: indices[found],
                x: xs[found],
                z: zs[found],
                setPiece: owner === -1 ? null : { index: owner, name: pieces[owner].name }
            },
            setPiece: null
        };
    };
    return {
        at,
        under: (view, viewport, cursor, shown, searched) =>
            at(screenToWorld(view, viewport, cursor), PICK_RADIUS / view.scale, shown, searched),
        setPiece: (index) => {
            const details = setPieceDetails(world, index);
            return { tile: tileAt(details), entity: null, setPiece: details };
        }
    };
}
