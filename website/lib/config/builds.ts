import { GAME_BUILDS, type GameBuild, LATEST_BUILD } from "./game-builds";

export { BUILD_NUMBERS_TEXT } from "./game-builds";
import type { Shard } from "./seedfinder-config";

export type GameBuildEntry = (typeof GAME_BUILDS)[number];
/** The build whose catalog a build's shard uses. */
export type CatalogBuild<S extends Shard = Shard> = GameBuildEntry["catalog"][S];

const ENTRIES: ReadonlyMap<unknown, GameBuildEntry> = new Map(GAME_BUILDS.map((entry) => [entry.number, entry]));

/** The registered build `value` names, or none when it isn't one. */
export const gameBuildOf = (value: unknown): GameBuild | undefined => ENTRIES.get(value)?.number;

export const buildEntry = (build: GameBuild): GameBuildEntry => ENTRIES.get(build)!;

/** The build's number, tagged "latest" or with its channel when that isn't a release. */
export const buildLabel = (build: GameBuild): string => {
    const { channel } = buildEntry(build);
    const tag = build === LATEST_BUILD ? "latest" : channel === "release" ? undefined : channel;
    return tag ? `${build} (${tag})` : String(build);
};

export const hasShard = (build: GameBuild, shard: Shard): boolean =>
    (buildEntry(build).shards as readonly Shard[]).includes(shard);

export const catalogBuild = <S extends Shard>(build: GameBuild, shard: S): CatalogBuild<S> =>
    buildEntry(build).catalog[shard];

/** The registered build that generated a world, or the latest when it names none. */
export const generatedBy = ({ gameBuild }: { gameBuild?: number }): GameBuild => gameBuildOf(gameBuild) ?? LATEST_BUILD;
