import { describe, expect, it } from "vitest";
import { PREFAB_BY_ID } from "@/lib/catalog/world";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";
import { drawOrder, ICON_STRIDE, iconLayer } from "@/lib/world-map/legend/icon-layer";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const WORLD = {
    prefabs: [
        prefab("evergreen", 500, 0, 100, 0),
        prefab("berrybush", 300, 0, 200, 0),
        prefab("pigking", 0, 0),
        prefab("amulet", 900, 900),
        prefab("a_prefab_from_a_newer_game", 300, 300),
        prefab("multiplayer_portal", 700, 0)
    ],
    links: new Uint32Array(0)
};

const layer = entityLayer(WORLD);
const icons = iconLayer(layer);

const ordered = (heading: number) => {
    const sorted = drawOrder(icons, heading);
    return Array.from({ length: sorted.length / ICON_STRIDE }, (_, at) => {
        const [x, z, , , , , prefabIndex] = sorted.subarray(ICON_STRIDE * at, ICON_STRIDE * (at + 1));
        return [layer.names[prefabIndex], x, z];
    });
};

describe("the icon layer", () => {
    it("has an icon for each entity of a prefab with one and none for the dot-only prefabs", () => {
        expect(icons.priorities).toHaveLength(6);
        expect(layer.names.map((name, prefab) => [name, icons.iconed[prefab]])).toEqual([
            ["evergreen", 1],
            ["berrybush", 1],
            ["pigking", 1],
            ["amulet", 0],
            ["a_prefab_from_a_newer_game", 0],
            ["multiplayer_portal", 1]
        ]);
    });

    it("puts each icon at its entity, on its prefab's sheet rect", () => {
        const spawn = layer.names.indexOf("multiplayer_portal");
        const { x, y, w, h } = PREFAB_BY_ID.get("multiplayer_portal")!.icon!;
        const at = Array.from({ length: icons.priorities.length }, (_, index) => index)
            .find((index) => icons.instances[ICON_STRIDE * index + 6] === spawn)!;
        expect([...icons.instances.subarray(ICON_STRIDE * at, ICON_STRIDE * (at + 1))]).toEqual([7, 0, x, y, w, h, spawn]);
    });

    it("draws the lowest priority first, then from the top of the view down", () => {
        expect(ordered(0)).toEqual([
            ["evergreen", 5, 0],
            ["evergreen", 1, 0],
            ["multiplayer_portal", 7, 0],
            ["berrybush", 3, 0],
            ["berrybush", 2, 0],
            ["pigking", 0, 0]
        ]);
    });

    it("follows the heading: the icons that were at the bottom of the view are at the top after a half turn", () => {
        expect(ordered(180)).toEqual([
            ["evergreen", 1, 0],
            ["evergreen", 5, 0],
            ["berrybush", 2, 0],
            ["berrybush", 3, 0],
            ["multiplayer_portal", 7, 0],
            ["pigking", 0, 0]
        ]);
    });
});
