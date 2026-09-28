import { describe, expect, it } from "vitest";
import {
    createEntityRenderer,
    NO_HOVER,
    VISIBILITY_HIGHLIGHTED,
    VISIBILITY_SHOWN
} from "@/lib/world-map/canvas/entity-renderer";
import { entityLayer } from "@/lib/world-map/legend/entity-layer";
import { fakeGl } from "./fake-gl";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });
const layer = entityLayer({
    prefabs: [prefab("evergreen", 100, 0), prefab("amulet", 900, 900), prefab("pigking", 0, 0)],
    links: new Uint32Array(0)
});
const ACCENT = [252, 88, 33];
const VIEW = { centerX: 0, centerZ: 0, scale: 2, heading: 0 };
const VIEWPORT = { width: 800, height: 600 };
const iconedEvergreen = Uint8Array.from([1, 0, 0]);

function renderer() {
    const fake = fakeGl();
    const uploads = () => fake.names("texSubImage2D").map(([, , , , , , , , , texels]) => Array.from(texels as Uint8Array));
    return { ...fake, entities: createEntityRenderer(fake.gl, layer, iconedEvergreen, ACCENT), uploads };
}

describe("the entity renderer's visibility texture", () => {
    it("holds hidden, shown and highlighted per prefab in red, and whether it has an icon in green", () => {
        const { entities, uploads } = renderer();
        entities.show(new Set(["evergreen", "amulet"]));
        entities.highlight(new Set(["amulet", "pigking"]));
        const [shown, highlighted] = uploads();
        expect(shown.slice(0, 6)).toEqual([VISIBILITY_SHOWN, 255, VISIBILITY_SHOWN, 0, 0, 0]);
        expect(highlighted.slice(0, 6)).toEqual([VISIBILITY_SHOWN, 255, VISIBILITY_HIGHLIGHTED, 0, VISIBILITY_HIGHLIGHTED, 0]);
    });

    it("shows a highlighted prefab even when it isn't shown, and keeps both across each other's updates", () => {
        const { entities, uploads } = renderer();
        entities.highlight(new Set(["pigking"]));
        entities.show(new Set(["evergreen"]));
        entities.highlight(new Set());
        const [onlyHighlighted, both, onlyShown] = uploads().map((texels) => texels.filter((_, at) => at % 2 === 0).slice(0, 3));
        expect(onlyHighlighted).toEqual([0, 0, VISIBILITY_HIGHLIGHTED]);
        expect(both).toEqual([VISIBILITY_SHOWN, 0, VISIBILITY_HIGHLIGHTED]);
        expect(onlyShown).toEqual([VISIBILITY_SHOWN, 0, 0]);
    });
});

describe("the entity renderer's hover", () => {
    it("hands the shader the hovered entity on every draw, none by default", () => {
        const { entities, uniformValues } = renderer();
        entities.draw(VIEW, VIEWPORT);
        entities.hover({ prefab: 2, x: 0, z: 0 });
        entities.draw(VIEW, VIEWPORT);
        entities.hover(NO_HOVER);
        entities.draw(VIEW, VIEWPORT);
        expect(uniformValues("hovered", "uniform3f")).toEqual([[-1, 0, 0], [2, 0, 0], [-1, 0, 0]]);
    });
});
