import { CAVE_OPTIONAL_PICKED } from "./cave-vocab";
import { CAVE_SET_PIECE_KINDS, CAVE_SET_PIECES, CAVE_SWAP_INFOS, CAVE_TASKS } from "./cave-level";
import { SET_PIECE_KINDS, SET_PIECES, SWAPS, TASKS } from "./level";
import type { SetPieceInfo, SetPieceKind, SetPieceKindInfo, SwapInfo, TaskInfo } from "./level-types";
import { type CatalogBuild, catalogBuild } from "@/lib/config/builds";
import { GAME_BUILDS, type GameBuild } from "@/lib/config/game-builds";
import { DEFAULT_SHARD, type Shard } from "@/lib/config/seedfinder-config";

/** What a shard's level table is made of: the words the level-table filters and the results use. */
export interface LevelCatalog {
    shard: Shard;
    tasks: TaskInfo[];
    swaps: SwapInfo[];
    setPieceKinds: SetPieceKindInfo[];
    setPieces: SetPieceInfo[];
    taskById: ReadonlyMap<string, TaskInfo>;
    setPieceById: ReadonlyMap<string, SetPieceInfo>;
    setPieceKindById: Record<SetPieceKind, SetPieceKindInfo>;
    optionalTasks: TaskInfo[];
    optionalTaskIds: string[];
    optionalPicked: number;
}

function catalogOf(
    shard: Shard,
    parts: Pick<LevelCatalog, "tasks" | "swaps" | "setPieceKinds" | "setPieces" | "optionalPicked">
): LevelCatalog {
    const optionalTasks = parts.tasks.filter((task) => task.kind === "optional");
    return {
        shard,
        ...parts,
        taskById: new Map(parts.tasks.map((task) => [task.id, task])),
        setPieceById: new Map(parts.setPieces.map((piece) => [piece.id, piece])),
        setPieceKindById: Object.fromEntries(
            parts.setPieceKinds.map((kind) => [kind.id, kind])
        ) as Record<SetPieceKind, SetPieceKindInfo>,
        optionalTasks,
        optionalTaskIds: optionalTasks.map((task) => task.id)
    };
}

const FOREST_OPTIONAL_PICKED = 5;

const CAVE_LEVEL_CATALOG = catalogOf("caves", {
    tasks: CAVE_TASKS,
    swaps: CAVE_SWAP_INFOS,
    setPieceKinds: CAVE_SET_PIECE_KINDS,
    setPieces: CAVE_SET_PIECES,
    optionalPicked: CAVE_OPTIONAL_PICKED
});

/** Every build's caves level table is the latest build's (cave-vocab.ts), which scripts/gen/regen.sh checks. */
const LEVEL_CATALOGS: { [S in Shard]: Record<CatalogBuild<S>, LevelCatalog> } = {
    forest: {
        756039: catalogOf("forest", {
            tasks: TASKS,
            swaps: SWAPS,
            setPieceKinds: SET_PIECE_KINDS,
            setPieces: SET_PIECES,
            optionalPicked: FOREST_OPTIONAL_PICKED
        })
    },
    caves: Object.fromEntries(GAME_BUILDS.map((build) => [build.catalog.caves, CAVE_LEVEL_CATALOG])) as Record<
        CatalogBuild<"caves">,
        LevelCatalog
    >
};

const levelCatalogIn = <S extends Shard>(shard: S, build: GameBuild): LevelCatalog =>
    LEVEL_CATALOGS[shard][catalogBuild(build, shard)];

/** The level table of the shard of the build, through the catalog the build's registry entry names. */
export function levelCatalogOf(shard: Shard | undefined, build: GameBuild): LevelCatalog {
    const known = shard ?? DEFAULT_SHARD;
    return levelCatalogIn(known, build);
}
