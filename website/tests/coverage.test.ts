import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { endpointKey, ENDPOINTS } from "./endpoints";

const WEBSITE = fileURLToPath(new URL("..", import.meta.url));
const APP = join(WEBSITE, "app");
const SERVER_CODE = ["app", "components", "lib"];
const HTTP_METHOD = "GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS";
const DECLARED_METHOD = new RegExp(`export\\s+(?:(?:async\\s+)?function\\s*\\*?|const|let|var)\\s+(${HTTP_METHOD})\\b`, "g");
const EXPORT_LIST = /export\s*(?:type\s*)?\{([^}]*)\}/g;
const LISTED_METHOD = new RegExp(`(?:^|\\s|,)(?:\\w+\\s+as\\s+)?(${HTTP_METHOD})\\s*(?:,|$)`, "g");

const sourceFiles = (directory: string) =>
    readdirSync(directory, { recursive: true, encoding: "utf8" }).filter((file) => /\.(ts|tsx)$/.test(file));

const routeEndpoints = sourceFiles(APP)
    .filter((file) => /(^|\/)route\.ts$/.test(file))
    .flatMap((file) => {
        const source = readFileSync(join(APP, file), "utf8");
        const declared = [...source.matchAll(DECLARED_METHOD)].map((match) => match[1]);
        const listed = [...source.matchAll(EXPORT_LIST)].flatMap((list) => [...list[1].matchAll(LISTED_METHOD)].map((match) => match[1]));
        return [...declared, ...listed].map((method) => endpointKey({ method, route: `/${dirname(file)}` }));
    });

describe("API coverage", () => {
    it("finds the API routes", () => {
        expect(routeEndpoints.length).toBeGreaterThan(0);
    });

    it("classifies every app/api route method in tests/endpoints.ts, and nothing else", () => {
        expect([...routeEndpoints].sort()).toEqual(ENDPOINTS.map(endpointKey).sort());
    });

    it("checks CSRF on every non-GET endpoint a browser session can reach", () => {
        const unguarded = ENDPOINTS.filter(({ method, access, csrf }) =>
            method !== "GET" && access !== "runner" && !csrf
        );
        expect(unguarded.map(endpointKey)).toEqual([]);
    });

    it("has no server actions, which would be endpoints outside the table", () => {
        const actions = SERVER_CODE.flatMap((folder) => sourceFiles(join(WEBSITE, folder)).map((file) => join(folder, file)))
            .filter((file) => /["']use server["']/.test(readFileSync(join(WEBSITE, file), "utf8")));
        expect(actions).toEqual([]);
    });
});
