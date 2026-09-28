import { PREFAB_BY_ID } from "@/lib/catalog/world";
import { screenAngle } from "@/lib/world-map/view/map-view";
import type { EntityLayer } from "./entity-layer";

/** Floats per icon in {@link IconLayer.instances}: world `x, z`, the sheet rect `x, y, w, h`, and the prefab. */
export const ICON_STRIDE = 7;

/** Sheet pixels per world unit: the size an icon is drawn at. */
export const ICON_WORLD_UNIT_PIXELS = 6.4;

/** Wide enough that a priority outranks any position. */
const PRIORITY_SPAN = 1e6;

export interface IconLayer {
    /** {@link ICON_STRIDE} floats per icon, the prefab as its index in the entity layer's names. */
    instances: Float32Array;
    priorities: Int8Array;
    /** Per prefab in the entity layer's names: 1 when it has an icon, 0 when it's a dot. */
    iconed: Uint8Array;
}

export function iconLayer(layer: EntityLayer): IconLayer {
    const iconed = Uint8Array.from(layer.names, (name) => (PREFAB_BY_ID.get(name)?.icon === undefined ? 0 : 1));
    const dots = Array.from(layer.prefabs.keys()).filter((dot) => iconed[layer.prefabs[dot]] === 1);
    const instances = new Float32Array(ICON_STRIDE * dots.length);
    const priorities = new Int8Array(dots.length);
    dots.forEach((dot, at) => {
        const prefab = layer.prefabs[dot];
        const { x, y, w, h, priority = 0 } = PREFAB_BY_ID.get(layer.names[prefab])!.icon!;
        instances.set([layer.positions[2 * dot], layer.positions[2 * dot + 1], x, y, w, h, prefab], ICON_STRIDE * at);
        priorities[at] = priority;
    });
    return { instances, priorities, iconed };
}

/**
 * `icons.instances` in the game's draw order at `heading`: priority ascending, then screen y ascending, the top of the
 * rotated view first. Equal icons keep their place.
 */
export function drawOrder(icons: IconLayer, heading: number): Float32Array {
    const angle = screenAngle(heading);
    const [sin, cos] = [Math.sin(angle), Math.cos(angle)];
    const { instances, priorities } = icons;
    const keys = Float64Array.from(priorities, (priority, at) => {
        const up = instances[ICON_STRIDE * at] * sin + instances[ICON_STRIDE * at + 1] * cos;
        return priority * PRIORITY_SPAN - up;
    });
    const order = Uint32Array.from(priorities.keys()).sort((a, b) => keys[a] - keys[b]);
    const sorted = new Float32Array(instances.length);
    order.forEach((from, at) => sorted.set(instances.subarray(ICON_STRIDE * from, ICON_STRIDE * (from + 1)), ICON_STRIDE * at));
    return sorted;
}
