import { prefabName } from "@/lib/catalog/prefab-sets";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { TILES } from "@/lib/catalog/world";
import { WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import { ICON_WORLD_UNIT_PIXELS } from "@/lib/world-map/legend/icon-layer";
import type { MapTarget } from "@/lib/world-map/legend/prefab-search";
import { type SetPieceDetails, setPieceDetails } from "@/lib/world-map/legend/set-pieces";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import {
    type MapView,
    type ScreenPoint,
    screenToWorld,
    type Size,
    worldBounds,
    type WorldPoint,
    worldToScreen
} from "./map-view";

const CELL_SIZE = 16;

/** In screen pixels: the least an entity can be picked from, whatever its size. */
export const PICK_RADIUS = 8;

const DOT_RANK = -Infinity;

interface Pick {
    /** The icon's priority, or {@link DOT_RANK} for a dot, which every icon is drawn over. */
    rank: number;
    y: number;
    distance: number;
}

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
    /**
     * The entity under `cursor`, in screen space at any heading: an icon is picked from the rectangle it's drawn in
     * (grown to at least {@link PICK_RADIUS} around its position), a dot from within {@link PICK_RADIUS}. Where several
     * are under the cursor the top-most drawn wins: icons over dots, then the highest priority, then the lowest on
     * screen, and among dots the nearest. Set pieces are as in {@link at}, at the world point under the cursor.
     */
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
        return { name, displayName: Object.hasOwn(TILES, name) ? TILES[name].displayName : name };
    };

    const pieces = world.setPieces ?? [];
    const owners = world.prefabs.map(({ positions }) => new Int32Array(positions.length / 2).fill(-1));
    pieces.forEach(({ members }, piece) => {
        for (let at = 0; at < members.length; at += 2) {
            const owner = owners[members[at]];
            if (owner[members[at + 1]] === -1) owner[members[at + 1]] = piece;
        }
    });

    const shownIn = (searched: MapTarget | null | undefined) =>
        (kind: MapTarget["kind"], name: string, names: ReadonlySet<string>) =>
            names.has(name) || (searched?.kind === kind && searched.name === name);

    const near = (point: WorldPoint, radius: number, visit: (candidate: number) => void) => {
        const low = cellOf(point.x - radius, point.z - radius);
        const high = cellOf(point.x + radius, point.z + radius);
        for (let row = low.row; row <= high.row; row++) {
            const end = cellStarts[row * columns + high.column + 1];
            for (let slot = cellStarts[row * columns + low.column]; slot < end; slot++) visit(byCell[slot]);
        }
    };

    const probeOf = (
        point: WorldPoint,
        found: number | null,
        shown: MapShown,
        searched: MapTarget | null | undefined
    ): Probe => {
        if (found === null) {
            const isShown = shownIn(searched);
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
                displayName: prefabName(prefab, world.shard),
                index: indices[found],
                x: xs[found],
                z: zs[found],
                setPiece: owner === -1 ? null : { index: owner, name: pieces[owner].name }
            },
            setPiece: null
        };
    };

    const at: MapProbe["at"] = (point, radius, shown, searched = null) => {
        const isShown = shownIn(searched);
        let found: number | null = null;
        let closest = radius * radius;
        near(point, radius, (candidate) => {
            const distance = (xs[candidate] - point.x) ** 2 + (zs[candidate] - point.z) ** 2;
            const { name } = world.prefabs[prefabs[candidate]];
            if (distance > closest || !isShown("prefab", name, shown.prefabs)) return;
            closest = distance;
            found = candidate;
        });
        return probeOf(point, found, shown, searched);
    };

    const icons = world.prefabs.map(({ name }) => {
        const icon = shardCatalog(world.shard).byId.get(name)?.icon;
        if (icon === undefined) return null;
        return {
            halfWidth: icon.w / 2 / ICON_WORLD_UNIT_PIXELS,
            halfHeight: icon.h / 2 / ICON_WORLD_UNIT_PIXELS,
            priority: icon.priority ?? 0
        };
    });
    const largestIconHalfExtent = Math.max(
        0,
        ...icons.map((icon) => (icon === null ? 0 : Math.max(icon.halfWidth, icon.halfHeight)))
    );

    const covers = (prefab: number, dx: number, dy: number, scale: number) => {
        const icon = icons[prefab];
        if (icon === null) return dx * dx + dy * dy <= PICK_RADIUS * PICK_RADIUS;
        return Math.abs(dx) <= Math.max(icon.halfWidth * scale, PICK_RADIUS)
            && Math.abs(dy) <= Math.max(icon.halfHeight * scale, PICK_RADIUS);
    };

    const drawnAbove = (a: Pick, b: Pick) => {
        if (a.rank !== b.rank) return a.rank > b.rank;
        return a.rank === DOT_RANK ? a.distance < b.distance : a.y > b.y;
    };

    const under: MapProbe["under"] = (view, viewport, cursor, shown, searched = null) => {
        const isShown = shownIn(searched);
        const point = screenToWorld(view, viewport, cursor);
        const reachPixels = Math.max(PICK_RADIUS, largestIconHalfExtent * view.scale);
        let found: number | null = null;
        let best: Pick = { rank: -Infinity, y: -Infinity, distance: Infinity };
        near(point, Math.SQRT2 * reachPixels / view.scale, (candidate) => {
            const prefab = prefabs[candidate];
            if (!isShown("prefab", world.prefabs[prefab].name, shown.prefabs)) return;
            const there = worldToScreen(view, viewport, { x: xs[candidate], z: zs[candidate] });
            const [dx, dy] = [there.x - cursor.x, there.y - cursor.y];
            if (!covers(prefab, dx, dy, view.scale)) return;
            const pick = { rank: icons[prefab]?.priority ?? DOT_RANK, y: there.y, distance: dx * dx + dy * dy };
            if (!drawnAbove(pick, best)) return;
            best = pick;
            found = candidate;
        });
        return probeOf(point, found, shown, searched);
    };

    return {
        at,
        under,
        setPiece: (index) => {
            const details = setPieceDetails(world, index);
            return { tile: tileAt(details), entity: null, setPiece: details };
        }
    };
}
