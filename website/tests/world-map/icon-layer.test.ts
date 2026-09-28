import { describe, expect, it } from "vitest";
import { PREFABS } from "@/lib/catalog/world";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";
import { drawOrder, ICON_STRIDE, type IconLayer, iconLayer } from "@/lib/world-map/legend/icon-layer";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

describe("the icon layer", () => {
    const ICONED = PREFABS.find(({ icon }) => icon)!;
    const layer = entityLayer({
        prefabs: [prefab(ICONED.id, 500, 0, 100, 0), prefab("a_prefab_from_a_newer_game", 300, 300)],
        links: new Uint32Array(0)
    });
    const icons = iconLayer(layer);

    it("has an icon for each entity of a prefab with one and none for a prefab without", () => {
        expect(icons.iconed).toEqual(Uint8Array.of(1, 0));
        expect(icons.priorities).toHaveLength(2);
    });

    it("puts each icon at its entity, on its prefab's sheet rect", () => {
        const { x, y, w, h } = ICONED.icon!;
        expect([...icons.instances.subarray(0, ICON_STRIDE)]).toEqual([5, 0, x, y, w, h, 0]);
    });
});

describe("the icon draw order", () => {
    const at = (prefab: number, x: number) => [x, 0, 0, 0, 0, 0, prefab];
    const icons: IconLayer = {
        instances: Float32Array.from([at(0, 1), at(1, 5), at(2, 3), at(3, 2)].flat()),
        priorities: Int8Array.of(0, 0, 1, -1),
        iconed: Uint8Array.of(1, 1, 1, 1)
    };
    const drawn = (heading: number) => {
        const sorted = drawOrder(icons, heading);
        return Array.from({ length: sorted.length / ICON_STRIDE }, (_, index) => sorted[ICON_STRIDE * index + 6]);
    };

    it("draws the lowest priority first, then from the top of the view down", () => {
        expect(drawn(0)).toEqual([3, 1, 0, 2]);
    });

    it("follows the heading: what was at the bottom of the view is at the top after a half turn", () => {
        expect(drawn(180)).toEqual([3, 0, 1, 2]);
    });
});
