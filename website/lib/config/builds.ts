import { GAME_BUILDS, type GameBuild, LATEST_BUILD } from "./game-builds";

export { BUILD_NUMBERS_TEXT } from "./game-builds";
import type { Shard } from "./seedfinder-config";

export type GameBuildEntry = (typeof GAME_BUILDS)[number];
/** The build whose catalog a build's shard uses. */
export type CatalogBuild = GameBuildEntry["catalog"][Shard];

const ENTRIES: ReadonlyMap<unknown, GameBuildEntry> = new Map(GAME_BUILDS.map((entry) => [entry.number, entry]));

/** The registered build `value` names, or none when it isn't one. */
export const gameBuildOf = (value: unknown): GameBuild | undefined => ENTRIES.get(value)?.number;

export const buildEntry = (build: GameBuild): GameBuildEntry => ENTRIES.get(build)!;

export const buildLabel = (build: GameBuild): string => buildEntry(build).label;

export const hasShard = (build: GameBuild, shard: Shard): boolean =>
    (buildEntry(build).shards as readonly Shard[]).includes(shard);

export const catalogBuild = (build: GameBuild, shard: Shard): CatalogBuild => buildEntry(build).catalog[shard];

/** The registered build that generated a world, or the latest when it names none. */
export const generatedBy = ({ gameBuild }: { gameBuild?: number }): GameBuild => gameBuildOf(gameBuild) ?? LATEST_BUILD;
