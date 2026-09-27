const TILE_SIZE = 4;
const MIN_SCALE = 0.02;
const MAX_SCALE = 32;

/** North-up for now: world x grows to the right, world z grows down the screen. */
export interface MapView {
    centerX: number;
    centerZ: number;
    /** Screen pixels per world unit. */
    scale: number;
}

export interface Size {
    width: number;
    height: number;
}

export interface ScreenPoint {
    x: number;
    y: number;
}

export interface WorldPoint {
    x: number;
    z: number;
}

export interface WorldBounds extends Size {
    left: number;
    top: number;
}

/** The world units a map of `width × height` tiles covers, edge to edge (docs/world-dump.md, `TILE`). */
export const worldBounds = (tiles: Size): WorldBounds => ({
    left: -(tiles.width + 1) * TILE_SIZE / 2,
    top: -(tiles.height + 1) * TILE_SIZE / 2,
    width: tiles.width * TILE_SIZE,
    height: tiles.height * TILE_SIZE
});

/** The view that shows the whole world, centred. */
export function fitView(tiles: Size, viewport: Size): MapView {
    const bounds = worldBounds(tiles);
    return {
        centerX: bounds.left + bounds.width / 2,
        centerZ: bounds.top + bounds.height / 2,
        scale: Math.min(viewport.width / bounds.width, viewport.height / bounds.height)
    };
}

export const worldToScreen = (view: MapView, viewport: Size, point: WorldPoint): ScreenPoint => ({
    x: (point.x - view.centerX) * view.scale + viewport.width / 2,
    y: (point.z - view.centerZ) * view.scale + viewport.height / 2
});

export const screenToWorld = (view: MapView, viewport: Size, point: ScreenPoint): WorldPoint => ({
    x: (point.x - viewport.width / 2) / view.scale + view.centerX,
    z: (point.y - viewport.height / 2) / view.scale + view.centerZ
});

/** Zooms by `factor`, keeping the world point under `cursor` where it is on screen. */
export function zoomAt(view: MapView, viewport: Size, cursor: ScreenPoint, factor: number): MapView {
    const anchor = screenToWorld(view, viewport, cursor);
    const scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, view.scale * factor));
    return {
        centerX: anchor.x - (cursor.x - viewport.width / 2) / scale,
        centerZ: anchor.z - (cursor.y - viewport.height / 2) / scale,
        scale
    };
}

/** Moves the world by a pointer drag of `dx, dy` screen pixels. */
export const panBy = (view: MapView, dx: number, dy: number): MapView => ({
    ...view,
    centerX: view.centerX - dx / view.scale,
    centerZ: view.centerZ - dy / view.scale
});
