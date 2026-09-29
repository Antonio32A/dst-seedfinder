import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { MAP_TEXTURES, PREFABS, TILES } from "@/lib/catalog/world";

const TEXTURES = fileURLToPath(new URL("../../public/world-map", import.meta.url));
const HASHED = /\.[0-9a-f]{10}\.png$/;
const noiseUrls = Object.values(TILES).flatMap((tile) => tile.minimapNoise ?? []);
const roadUrls = Object.values(MAP_TEXTURES.road);
const referenced = [MAP_TEXTURES.mapEdge, MAP_TEXTURES.minimapPaper, MAP_TEXTURES.iconSheet.url, ...noiseUrls, ...roadUrls];

describe("the map textures", () => {
    it("are all referenced by content-hashed names", () => {
        expect(noiseUrls.length).toBeGreaterThan(0);
        for (const url of referenced) expect(url).toMatch(HASHED);
    });

    it("exist on disk and nothing else does but the icon rects", () => {
        for (const url of referenced) expect(existsSync(path.join(TEXTURES, url.replace("/world-map/", "")))).toBe(true);
        const files = readdirSync(TEXTURES, { recursive: true, encoding: "utf8", withFileTypes: true })
            .filter((entry) => entry.isFile())
            .map((entry) => path.join(entry.parentPath, entry.name).replace(`${TEXTURES}/`, "/world-map/"));
        expect(files.filter((file) => !referenced.includes(file) && !/\/minimap_icon_rects\.[0-9a-f]{10}\.json$/.test(file))).toEqual([]);
    });
});

describe("the prefab icons", () => {
    const withIcon = PREFABS.filter((prefab) => prefab.icon);

    it("have rects inside the sprite sheet", () => {
        expect(withIcon.length).toBeGreaterThan(0);
        for (const { icon } of withIcon) {
            expect(icon!.x).toBeGreaterThanOrEqual(0);
            expect(icon!.y).toBeGreaterThanOrEqual(0);
            expect(icon!.x + icon!.w).toBeLessThanOrEqual(MAP_TEXTURES.iconSheet.width);
            expect(icon!.y + icon!.h).toBeLessThanOrEqual(MAP_TEXTURES.iconSheet.height);
        }
    });
});
