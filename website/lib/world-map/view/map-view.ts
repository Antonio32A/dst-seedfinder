import { WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";

const MIN_SCALE = 0.02;
const MAX_SCALE = 32;
const ROTATION_STEP = 45;

/** The camera heading the game starts at (cameras/followcamera.lua, `FollowCamera:SetDefault`). */
export const DEFAULT_HEADING = 45;

export interface MapView {
    centerX: number;
    centerZ: number;
    /** Screen pixels per world unit. */
    scale: number;
    /** The game's camera heading in degrees: world direction `(x, z) = (cos, sin)` of it points up the map. */
    heading: number;
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

/** The world units `tiles` covers, edge to edge (docs/world-dump.md, `TILE`). */
export const worldBounds = (tiles: Size): WorldBounds => ({
    left: -(tiles.width + 1) * WORLD_UNITS_PER_TILE / 2,
    top: -(tiles.height + 1) * WORLD_UNITS_PER_TILE / 2,
    width: tiles.width * WORLD_UNITS_PER_TILE,
    height: tiles.height * WORLD_UNITS_PER_TILE
});

const screenAngle = (heading: number) => (90 - heading) * Math.PI / 180;

export function fitView(tiles: Size, viewport: Size, heading = DEFAULT_HEADING): MapView {
    const bounds = worldBounds(tiles);
    const angle = screenAngle(heading);
    const cos = Math.abs(Math.cos(angle));
    const sin = Math.abs(Math.sin(angle));
    return {
        centerX: bounds.left + bounds.width / 2,
        centerZ: bounds.top + bounds.height / 2,
        scale: Math.min(
            viewport.width / (bounds.width * cos + bounds.height * sin),
            viewport.height / (bounds.width * sin + bounds.height * cos)
        ),
        heading
    };
}

/** In pixels from the viewport's top left. */
export function worldToScreen(view: MapView, viewport: Size, point: WorldPoint): ScreenPoint {
    const angle = screenAngle(view.heading);
    const dx = (point.x - view.centerX) * view.scale;
    const dz = (point.z - view.centerZ) * view.scale;
    return {
        x: viewport.width / 2 + dx * Math.cos(angle) - dz * Math.sin(angle),
        y: viewport.height / 2 - dx * Math.sin(angle) - dz * Math.cos(angle)
    };
}

export function screenToWorld(view: MapView, viewport: Size, point: ScreenPoint): WorldPoint {
    const angle = screenAngle(view.heading);
    const right = (point.x - viewport.width / 2) / view.scale;
    const up = (viewport.height / 2 - point.y) / view.scale;
    return {
        x: view.centerX + right * Math.cos(angle) + up * Math.sin(angle),
        z: view.centerZ - right * Math.sin(angle) + up * Math.cos(angle)
    };
}

/** Keeps the world point under `cursor` where it is on screen. */
export function zoomAt(view: MapView, viewport: Size, cursor: ScreenPoint, factor: number): MapView {
    const anchor = screenToWorld(view, viewport, cursor);
    const zoomed = { ...view, scale: Math.min(MAX_SCALE, Math.max(MIN_SCALE, view.scale * factor)) };
    const drift = screenToWorld(zoomed, viewport, cursor);
    return { ...zoomed, centerX: zoomed.centerX + anchor.x - drift.x, centerZ: zoomed.centerZ + anchor.z - drift.z };
}

export function panBy(view: MapView, dx: number, dy: number): MapView {
    const origin = screenToWorld(view, { width: 0, height: 0 }, { x: 0, y: 0 });
    const dragged = screenToWorld(view, { width: 0, height: 0 }, { x: dx, y: dy });
    return { ...view, centerX: view.centerX - dragged.x + origin.x, centerZ: view.centerZ - dragged.z + origin.z };
}

/** A positive step is the game's rotate right (E, `PlayerController:RotRight`), clockwise on screen. */
export const turnView = (view: MapView, steps: number): MapView => ({
    ...view,
    heading: view.heading + steps * ROTATION_STEP
});
