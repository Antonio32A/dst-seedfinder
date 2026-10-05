import { CAVE_OPTIONAL_PICKED } from "./cave-vocab";
import { CAVE_SET_PIECE_KINDS, CAVE_SET_PIECES, CAVE_SWAP_INFOS, CAVE_TASKS } from "./cave-level";
import { SET_PIECE_KINDS, SET_PIECES, SWAPS, TASKS } from "./level";
import type { SetPieceInfo, SetPieceKind, SetPieceKindInfo, SwapInfo, TaskInfo } from "./level-types";
import { DEFAULT_SHARD, type Shard } from "@/lib/config/seedfinder-config";

/** What a shard's level table is made of: the words the level-table filters and the results use. */
export interface LevelCatalog {
    shard: Shard;
    tasks: TaskInfo[];
    swaps: SwapInfo[];
    setPieceKinds: SetPieceKindInfo[];
    setPieces: SetPieceInfo[];
    taskById: Record<string, TaskInfo>;
    setPieceById: Record<string, SetPieceInfo>;
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
        taskById: Object.fromEntries(parts.tasks.map((task) => [task.id, task])),
        setPieceById: Object.fromEntries(parts.setPieces.map((piece) => [piece.id, piece])),
        setPieceKindById: Object.fromEntries(
            parts.setPieceKinds.map((kind) => [kind.id, kind])
        ) as Record<SetPieceKind, SetPieceKindInfo>,
        optionalTasks,
        optionalTaskIds: optionalTasks.map((task) => task.id)
    };
}

const FOREST_OPTIONAL_PICKED = 5;

export const LEVEL_CATALOGS: Record<Shard, LevelCatalog> = {
    forest: catalogOf("forest", {
        tasks: TASKS,
        swaps: SWAPS,
        setPieceKinds: SET_PIECE_KINDS,
        setPieces: SET_PIECES,
        optionalPicked: FOREST_OPTIONAL_PICKED
    }),
    caves: catalogOf("caves", {
        tasks: CAVE_TASKS,
        swaps: CAVE_SWAP_INFOS,
        setPieceKinds: CAVE_SET_PIECE_KINDS,
        setPieces: CAVE_SET_PIECES,
        optionalPicked: CAVE_OPTIONAL_PICKED
    })
};

export function levelCatalogOf(shard: Shard | undefined): LevelCatalog {
    return LEVEL_CATALOGS[shard ?? DEFAULT_SHARD];
}
