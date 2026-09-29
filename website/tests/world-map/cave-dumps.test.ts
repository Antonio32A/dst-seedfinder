import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { TILES } from "@/lib/catalog/world";
import { prefabName } from "@/lib/catalog/prefab-sets";
import { entityLayer, mapWorld } from "@/lib/world-map/legend/entity-layer";
import { iconLayer } from "@/lib/world-map/legend/icon-layer";
import { mapLegend } from "@/lib/world-map/legend/prefab-visibility";
import { type GeneratedWorld, parseWorldDump } from "@/lib/world-map/world/world-dump";

const DUMPS = fileURLToPath(new URL("../../../build/groundtruth/dstw_caves", import.meta.url));
const SAMPLE = 12;

const worlds = (): GeneratedWorld[] => readdirSync(DUMPS).filter((file) => file.endsWith(".dstw")).sort().slice(0, SAMPLE)
    .map((file) => parseWorldDump(readFileSync(`${DUMPS}/${file}`)))
    .filter((dump) => dump.status === "generated");

describe.skipIf(!existsSync(DUMPS))("the real cave worlds", () => {
    const sampled = worlds();

    it("read as the caves shard with their tentacle pillar links", () => {
        expect(sampled.length).toBeGreaterThan(0);
        for (const world of sampled) {
            expect(world.shard).toBe("caves");
            expect(world.pillarLinks.length).toBeGreaterThan(0);
            expect(world.links).toHaveLength(0);
        }
    });

    it("have every prefab named and drawn from the caves catalog", () => {
        const { byId } = shardCatalog("caves");
        const unknown = new Set(sampled.flatMap(({ prefabs }) => prefabs.map(({ name }) => name).filter((name) => !byId.has(name))));
        expect([...unknown]).toEqual([]);
        for (const { name } of sampled.flatMap(({ prefabs }) => prefabs)) expect(prefabName(name, "caves")).not.toBe(name);
    });

    it("have a minimap noise texture for every land tile", () => {
        const missing = new Set(sampled.flatMap(({ tileNames, tiles }) => [...new Set(tiles)]
            .map((tile) => tileNames.get(tile)!)
            .filter((name) => TILES[name].kind === "land" && TILES[name].minimapNoise === undefined)));
        expect([...missing]).toEqual([]);
    });

    it("map to one link per pillar link and icons for the prefabs the catalog has one for", () => {
        for (const world of sampled) {
            const mapped = mapWorld(world);
            const layer = entityLayer(mapped);
            expect(layer.links).toHaveLength(world.pillarLinks.length);
            expect(iconLayer(layer).instances.length).toBeGreaterThan(0);
            expect(mapLegend(mapped).reduce((sum, { count }) => sum + count, 0)).toBe(layer.positions.length / 2);
        }
    });
});
