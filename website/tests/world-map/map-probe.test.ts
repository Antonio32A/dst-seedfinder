import { describe, expect, it } from "vitest";
import { prefabName } from "@/lib/catalog/prefab-sets";
import { PREFABS, TILES } from "@/lib/catalog/world";
import { ICON_WORLD_UNIT_PIXELS } from "@/lib/world-map/legend/icon-layer";
import { createMapProbe, PICK_RADIUS } from "@/lib/world-map/view/map-probe";
import { type MapView, worldToScreen } from "@/lib/world-map/view/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });
const HEADINGS = [0, 45, 135, 270];
const VIEWPORT = { width: 800, height: 600 };

const WORLD: GeneratedWorld = {
    status: "generated",
    seed: 1,
    platform: "linux",
    shard: "forest",
    gameBuild: 756039,
    width: 3,
    height: 2,
    tileNames: new Map([[1, "IMPASSABLE"], [6, "GRASS"], [7, "FOREST"], [99, "A_NEWER_TURF"]]),
    tiles: new Uint16Array([6, 7, 99, 1, 6, 6]),
    prefabs: [],
    links: new Uint32Array(0),
    pillarLinks: new Uint32Array(0)
};

const GRASSLAND: GeneratedWorld = {
    ...WORLD,
    width: 100,
    height: 100,
    tiles: new Uint16Array(100 * 100).fill(6),
    prefabs: [
        prefab("evergreen", 150, -400, -1, 25, 3000, 3000),
        prefab("pigking", 1000, 2000)
    ]
};

const DOT = "a_prefab_from_a_newer_game";
const ICONED = PREFABS.filter(({ id, icon }) => icon && id !== "multiplayer_portal")
    .sort((a, b) => (a.icon!.priority ?? 0) - (b.icon!.priority ?? 0));
const [LOW, HIGH] = [ICONED[0], ICONED.at(-1)!];
const tile = (name: string) => ({ name, displayName: TILES[name].displayName });

const NO_SET_PIECES: ReadonlySet<string> = new Set();
const ALL_SHOWN = {
    prefabs: new Set(["evergreen", "pigking", DOT]),
    setPieces: NO_SET_PIECES
};
const NO_TREES = { prefabs: new Set(["pigking"]), setPieces: NO_SET_PIECES };

describe("the map probe", () => {
    it("names the tile under a point", () => {
        const probe = createMapProbe(WORLD);
        expect(probe.at({ x: -3, z: -3 }, 1, ALL_SHOWN).tile).toEqual(tile("FOREST"));
        expect(probe.at({ x: -8, z: 1.5 }, 1, ALL_SHOWN).tile).toEqual(tile("IMPASSABLE"));
        expect(probe.at({ x: 3.9, z: -5.9 }, 1, ALL_SHOWN).tile).toEqual({
            name: "A_NEWER_TURF",
            displayName: "A_NEWER_TURF"
        });
    });

    it.each([
        { x: -8.01, z: 0 },
        { x: 4, z: 0 },
        { x: 0, z: -6.01 },
        { x: 0, z: 2 }
    ])("has no tile off the map's edge, at $x, $z", (point) => {
        expect(createMapProbe(WORLD).at(point, 1, ALL_SHOWN).tile).toBeNull();
    });

    it("picks the entity nearest the point within the radius, with its name, savedata index and position", () => {
        const probe = createMapProbe(GRASSLAND);
        expect(probe.at({ x: 0.2, z: 0.1 }, 2, ALL_SHOWN).entity).toEqual({
            prefab: "evergreen",
            displayName: prefabName("evergreen"),
            index: 1,
            x: -0.01,
            z: 0.25,
            setPiece: null
        });
        expect(probe.at({ x: 9, z: 19 }, 2, ALL_SHOWN).entity).toMatchObject({
            prefab: "pigking",
            index: 0,
            x: 10,
            z: 20
        });
    });

    it("names the tile under the entity it picks, rather than the one under the point", () => {
        const tiles = GRASSLAND.tiles.slice();
        tiles[55 * 100 + 53] = 7;
        const probe = createMapProbe({ ...GRASSLAND, tiles });
        expect(probe.at({ x: 9, z: 19 }, 0.1, ALL_SHOWN).tile).toEqual(tile("GRASS"));
        expect(probe.at({ x: 9, z: 19 }, 2, ALL_SHOWN)).toMatchObject({
            entity: { prefab: "pigking" },
            tile: tile("FOREST")
        });
    });

    it("picks no entity when none is within the radius, and still names the tile", () => {
        expect(createMapProbe(GRASSLAND).at({ x: 3, z: 3 }, 2, ALL_SHOWN)).toEqual({
            tile: tile("GRASS"),
            entity: null,
            setPiece: null
        });
    });

    it("never picks an entity of a hidden prefab, and picks the nearest shown one instead", () => {
        const probe = createMapProbe(GRASSLAND);
        expect(probe.at({ x: 0, z: 0 }, 2, NO_TREES).entity).toBeNull();
        expect(probe.at({ x: 3, z: 8 }, 20, ALL_SHOWN).entity).toMatchObject({ prefab: "evergreen", index: 1 });
        expect(probe.at({ x: 3, z: 8 }, 20, NO_TREES).entity).toMatchObject({ prefab: "pigking" });
    });

    it("picks the instances of the prefab searched for even when it's hidden", () => {
        const probe = createMapProbe(GRASSLAND);
        expect(probe.at({ x: 0, z: 0 }, 2, NO_TREES, {
            kind: "prefab",
            name: "evergreen"
        }).entity).toMatchObject({ prefab: "evergreen", index: 1 });
        expect(probe.at({ x: 0, z: 0 }, 2, NO_TREES, { kind: "prefab", name: "pigking" }).entity).toBeNull();
    });

    it.each(HEADINGS.flatMap((heading) => [0.05, 1, 12].map((scale) => ({ heading, scale }))))(
        "picks the dot under the cursor at $scale px per unit and heading $heading",
        ({ heading, scale }) => {
            const probe = createMapProbe({ ...GRASSLAND, prefabs: [prefab(DOT, 1000, 2000)] });
            const view = { centerX: 3, centerZ: 3, scale, heading };
            const dot = worldToScreen(view, VIEWPORT, { x: 10, z: 20 });
            const off = (pixels: number, angle: number) => ({
                x: dot.x + pixels * Math.cos(angle),
                y: dot.y + pixels * Math.sin(angle)
            });
            for (const angle of [0, 1, 2.5, 4]) {
                expect(probe.under(view, VIEWPORT, off(PICK_RADIUS - 0.5, angle), ALL_SHOWN).entity).toMatchObject({ prefab: DOT });
                expect(probe.under(view, VIEWPORT, off(PICK_RADIUS + 0.5, angle), ALL_SHOWN).entity).toBeNull();
            }
        }
    );

    it("picks the nearest entity anywhere on the map or past its edge, like checking every one of them", () => {
        let state = 7;
        const random = () => (state = (state * 1103515245 + 12345) % 2 ** 31) / 2 ** 31;
        const scatter = (count: number) => Array.from({ length: 2 * count }, () => Math.round((random() - 0.5) * 50000));
        const names = ["evergreen", "pigking", "flower", DOT];
        const world = { ...GRASSLAND, prefabs: names.map((name) => prefab(name, ...scatter(300))) };
        const probe = createMapProbe(world);
        const visibility = { prefabs: new Set(names.filter((name) => name !== "pigking")), setPieces: NO_SET_PIECES };
        for (let trial = 0; trial < 500; trial++) {
            const point = { x: (random() - 0.5) * 520, z: (random() - 0.5) * 520 };
            const radius = random() * 60;
            const expected = world.prefabs
                .filter(({ name }) => name !== "pigking")
                .flatMap(({ name, positions }) => Array.from({ length: positions.length / 2 }, (_, index) => ({
                    prefab: name,
                    index,
                    distance: Math.hypot(positions[2 * index] / 100 - point.x, positions[2 * index + 1] / 100 - point.z)
                })))
                .filter(({ distance }) => distance <= radius)
                .sort((a, b) => a.distance - b.distance)[0];
            const entity = probe.at(point, radius, visibility).entity;
            const picked = (found: { prefab: string; index: number } | null | undefined) =>
                found ? { prefab: found.prefab, index: found.index } : null;
            expect(picked(entity)).toEqual(picked(expected));
        }
    });
});

describe("picking icons under the cursor", () => {
    const ICON_HALF_PIXELS = LOW.icon!.w / 2 / ICON_WORLD_UNIT_PIXELS;
    const at = (view: MapView, x: number, z: number, dx = 0, dy = 0) => {
        const screen = worldToScreen(view, VIEWPORT, { x, z });
        return { x: screen.x + dx, y: screen.y + dy };
    };
    const [low, high] = [LOW.id, HIGH.id];
    const iconWorld = (...prefabs: ReturnType<typeof prefab>[]) => createMapProbe({ ...GRASSLAND, prefabs });
    const shown = (...names: string[]) => ({ prefabs: new Set(names), setPieces: NO_SET_PIECES });

    it.each(HEADINGS.flatMap((heading) => [0.05, 1, 4, 12].map((scale) => ({ heading, scale }))))(
        "picks an icon from the upright rectangle it's drawn in, at $scale px per unit and heading $heading",
        ({ heading, scale }) => {
            const view = { centerX: 3, centerZ: 3, scale, heading };
            const probe = iconWorld(prefab(low, 1000, 2000));
            const half = Math.max(PICK_RADIUS, ICON_HALF_PIXELS * scale);
            for (const [dx, dy] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
                const inside = at(view, 10, 20, dx * (half - 0.5), dy * (half - 0.5));
                expect(probe.under(view, VIEWPORT, inside, shown(low)).entity).toMatchObject({ prefab: low });
                for (const outside of [at(view, 10, 20, dx * (half + 0.5)), at(view, 10, 20, 0, dy * (half + 0.5))]) {
                    expect(probe.under(view, VIEWPORT, outside, shown(low)).entity).toBeNull();
                }
            }
        }
    );

    it("keeps at least the dot's pick radius around a small icon, at any angle", () => {
        const view = { centerX: 3, centerZ: 3, scale: 0.05, heading: 45 };
        const probe = iconWorld(prefab(low, 1000, 2000));
        for (const angle of [0, 1, 2.5, 4]) {
            const cursor = at(view, 10, 20, (PICK_RADIUS - 0.1) * Math.cos(angle), (PICK_RADIUS - 0.1) * Math.sin(angle));
            expect(probe.under(view, VIEWPORT, cursor, shown(low)).entity).toMatchObject({ prefab: low });
        }
    });

    it.each(HEADINGS)("picks the icon with the higher priority whichever is lower on screen, at heading %d", (heading) => {
        const view = { centerX: 0, centerZ: 0, scale: 12, heading };
        const cursor = at(view, 0, 0);
        for (const prefabs of [
            [prefab(low, 0, 0), prefab(high, 0, 0)],
            [prefab(high, 0, 0), prefab(low, 0, 0)],
            [prefab(high, 30, 30), prefab(low, -30, -30)],
            [prefab(high, -30, -30), prefab(low, 30, 30)]
        ]) {
            const found = iconWorld(...prefabs).under(view, VIEWPORT, cursor, shown(low, high));
            expect(found.entity).toMatchObject({ prefab: high });
        }
    });

    it.each(HEADINGS)("picks the one lower on screen among equal icons, at heading %d", (heading) => {
        const view = { centerX: 0, centerZ: 0, scale: 12, heading };
        const probe = iconWorld(prefab(low, 0, 0, 40, 40, -40, -40));
        const cursor = at(view, 0, 0, 0, 0);
        const lowest = [[0, 0], [0.4, 0.4], [-0.4, -0.4]]
            .map(([x, z], index) => ({ index, y: worldToScreen(view, VIEWPORT, { x, z }).y }))
            .sort((a, b) => b.y - a.y)[0].index;
        expect(probe.under(view, VIEWPORT, cursor, shown(low)).entity).toMatchObject({ index: lowest });
    });

    it("picks an icon over a dot that's nearer the cursor, and the nearest of two dots", () => {
        const view = { centerX: 0, centerZ: 0, scale: 12, heading: 0 };
        const probe = iconWorld(prefab(DOT, 0, 0, 30, 0), prefab(low, 20, 0));
        const names = shown(DOT, low);
        expect(probe.under(view, VIEWPORT, at(view, 0, 0), names).entity).toMatchObject({ prefab: low });
        expect(probe.under(view, VIEWPORT, at(view, 0.3, 0, 0, -2), shown(DOT)).entity).toMatchObject({ prefab: DOT, index: 1 });
    });

    it("never picks the icon of a hidden prefab, and picks it again when it's searched for", () => {
        const view = { centerX: 0, centerZ: 0, scale: 12, heading: 0 };
        const probe = iconWorld(prefab(low, 0, 0));
        expect(probe.under(view, VIEWPORT, at(view, 0, 0), shown()).entity).toBeNull();
        expect(probe.under(view, VIEWPORT, at(view, 0, 0), shown(), { kind: "prefab", name: low }).entity)
            .toMatchObject({ prefab: low });
    });
});

const setPiece = (name: string, bounds: number[], members: number[] = []) => ({
    name,
    source: "room" as const,
    transform: 1,
    xk: (bounds[0] + bounds[2]) / 2,
    zk: (bounds[1] + bounds[3]) / 2,
    bounds: new Int32Array(bounds),
    members: new Uint32Array(members)
});

const KINGDOM: GeneratedWorld = {
    ...GRASSLAND,
    prefabs: [prefab("evergreen", 150, -400, -1, 25, 3000, 3000), prefab("pigking", 1000, 2000), prefab("sanityrock", 1400, 2000)],
    setPieces: [
        setPiece("DefaultPigking", [-600, 400, 2600, 3600], [1, 0, 2, 0]),
        setPiece("Grove", [2600, 2600, 3400, 3400], [0, 2]),
        setPiece("CropCircle", [0, 1600, 800, 2400])
    ]
};

const shownWith = (...setPieces: string[]) => ({ prefabs: ALL_SHOWN.prefabs, setPieces: new Set(setPieces) });

describe("the map probe on set pieces", () => {
    it("says which set piece an entity is part of", () => {
        const probe = createMapProbe(KINGDOM);
        expect(probe.at({ x: 10, z: 20 }, 1, ALL_SHOWN).entity).toMatchObject({
            prefab: "pigking",
            setPiece: { index: 0, name: "DefaultPigking" }
        });
        expect(probe.at({ x: 30, z: 30 }, 1, ALL_SHOWN).entity).toMatchObject({
            prefab: "evergreen",
            setPiece: { index: 1, name: "Grove" }
        });
        expect(probe.at({ x: 1.5, z: -4 }, 1, ALL_SHOWN).entity).toMatchObject({ prefab: "evergreen", setPiece: null });
    });

    it("picks the shown set piece whose bounds hold the point when there's no dot near it, with its details", () => {
        const probe = createMapProbe(KINGDOM);
        const found = probe.at({ x: 0, z: 30 }, 1, shownWith("DefaultPigking"));
        expect(found).toMatchObject({
            entity: null,
            tile: { name: "GRASS" },
            setPiece: { index: 0, name: "DefaultPigking", source: "room" }
        });
        expect(found.setPiece!.members.map(({ prefab }) => prefab).sort()).toEqual(["pigking", "sanityrock"]);
        expect(probe.at({ x: -7, z: 30 }, 1, shownWith("DefaultPigking")).setPiece).toBeNull();
        expect(probe.at({ x: 0, z: 30 }, 1, ALL_SHOWN).setPiece).toBeNull();
    });

    it("picks a dot over the set piece it's in", () => {
        const found = createMapProbe(KINGDOM).at({ x: 10.5, z: 20 }, 1, shownWith("DefaultPigking"));
        expect(found).toMatchObject({ entity: { prefab: "pigking" }, setPiece: null });
    });

    it("picks the smallest of the shown set pieces that hold the point", () => {
        const probe = createMapProbe(KINGDOM);
        const all = shownWith("DefaultPigking", "CropCircle", "Grove");
        expect(probe.at({ x: 4, z: 20 }, 1, all).setPiece).toMatchObject({ name: "CropCircle" });
        expect(probe.at({
            x: 4,
            z: 20
        }, 1, shownWith("DefaultPigking")).setPiece).toMatchObject({ name: "DefaultPigking" });
        expect(probe.at({ x: 27, z: 34 }, 0.1, all).setPiece).toMatchObject({ name: "Grove" });
    });

    it("picks the instances of the set piece searched for even when they're hidden", () => {
        const probe = createMapProbe(KINGDOM);
        expect(probe.at({ x: 4, z: 20 }, 1, ALL_SHOWN, {
            kind: "set piece",
            name: "CropCircle"
        }).setPiece).toMatchObject({ name: "CropCircle" });
        expect(probe.at({ x: 4, z: 20 }, 1, ALL_SHOWN, { kind: "prefab", name: "CropCircle" }).setPiece).toBeNull();
    });

    it("gives a set piece's details, with the tile at its centre", () => {
        expect(createMapProbe(KINGDOM).setPiece(2)).toMatchObject({
            entity: null,
            tile: { name: "GRASS" },
            setPiece: { index: 2, name: "CropCircle", x: 4, z: 20, width: 2, height: 2 }
        });
    });

    it("has no set pieces when the dump doesn't say where they are", () => {
        const probe = createMapProbe(GRASSLAND);
        expect(probe.at({ x: 10, z: 20 }, 1, shownWith("DefaultPigking")).entity).toMatchObject({ setPiece: null });
        expect(probe.at({ x: 0, z: 30 }, 1, shownWith("DefaultPigking")).setPiece).toBeNull();
    });
});
