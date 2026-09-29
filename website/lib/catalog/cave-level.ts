import { CAVE_OPTIONAL_TASK_IDS, CAVE_PIECES, CAVE_REQUIRED_TASK_IDS, CAVE_SWAPS, type CavePieceVocab } from "./cave-vocab";
import { SET_PIECE_BY_ID, SET_PIECE_KINDS, SWAPS } from "./level";
import type { SetPieceInfo, SwapInfo, TaskInfo } from "./level-types";

interface Text {
    name: string;
    description: string;
}

const EXIT_SINKHOLE = "A sinkhole area with a way up to the surface, the cave world's spawn. The world spawns you in one of ten.";
const TOADSTOOL_ARENA = "A clearing for the Toadstool boss, ringed by mushrooms.";

const TASK_TEXT: Record<string, Text> = {
    MudWorld: {
        name: "Light bulb mud plains",
        description: "Muddy floor covered in Light Bulb plants and Worm plants, with ferns, Slurtle mounds and rabbit holes."
    },
    MudCave: {
        name: "Worm plant mud",
        description: "Mud with Worm plants, Slurtle mounds and rabbit holes."
    },
    MudLights: {
        name: "Light bulb fields",
        description: "Mud dotted with many Light Bulb plants and a Worm plant."
    },
    MudPit: {
        name: "Slurtle mud pits",
        description: "Mud with Slurtle mounds and a lot of bottomless pits."
    },
    BigBatCave: {
        name: "Bat caves",
        description: "Cave floor with Bat colonies, ferns and bottomless pits."
    },
    RockyLand: {
        name: "Rocky caverns",
        description: "Rocky cave floor with Slurtle canyons, Rock Lobster hatching grounds and bats."
    },
    RedForest: {
        name: "Red mushtree forest",
        description: "Red Mushtrees, Spider dens in the red fungus and stalagmites."
    },
    GreenForest: {
        name: "Green mushtree forest",
        description: "Green Mushtrees around ponds, with rabbit holes and sinkholes."
    },
    BlueForest: {
        name: "Blue mushtree forest",
        description: "Blue Mushtrees, meadows, Dangling Depth Dwellers and Spiders."
    },
    SpillagmiteCaverns: {
        name: "Spilagmite caverns",
        description: "Spilagmites, Dangling Depth Dwellers, Spiders and Bats, with Thulecite debris."
    },
    MoonCaveForest: {
        name: "Moon Grotto",
        description: "Lunar Mushtrees around the entrance to the Grotto."
    },
    ArchiveMaze: {
        name: "Ancient Archive",
        description: "The Ancient Archive maze of security desks, moon statues and the Orchestrina, in the Ruins."
    },
    CentipedeCaveTask: {
        name: "Centipede cave",
        description: "Vents and rock trees around the Centipede nest, with a way down to the Ruins."
    },
    LichenLand: {
        name: "Lichen land",
        description: "Ruins wetlands with Lichen meadows and mud."
    },
    Residential: {
        name: "Ruined houses",
        description: "Ancient pig ruins: vacant houses in the Ruins."
    },
    Military: {
        name: "Ruined barracks",
        description: "The Ruins' military maze and Barracks with Clockwork Knights, Bishops and Rooks."
    },
    Sacred: {
        name: "Sacred grounds",
        description: "Barracks, Clockwork Bishops, spirals and a Broken Altar in the Ruins."
    },
    TheLabyrinth: {
        name: "The Labyrinth",
        description: "A big maze in the Ruins, with the Ancient Guardian and its garden."
    },
    SacredAltar: {
        name: "Ancient Pseudoscience Station",
        description: "The Ruins' Ancient Pseudoscience Station, where you make Thulecite items."
    },
    AtriumMaze: {
        name: "The Atrium",
        description: "The Ancient Atrium maze with the Ancient Fuelweaver, behind the Ancient Gateway."
    },
    SwampySinkhole: {
        name: "Swampy sinkhole",
        description: "A sinkhole swamp with Tentacles, trees and mud."
    },
    CaveSwamp: {
        name: "Cave swamp",
        description: "A dark swamp with Tentacles."
    },
    UndergroundForest: {
        name: "Underground forest",
        description: "Sinkhole forests and copses of trees."
    },
    PleasantSinkhole: {
        name: "Pleasant sinkhole",
        description: "Grassy sinkholes with oases."
    },
    FungalNoiseForest: {
        name: "Mixed mushtree forest",
        description: "Forest that blends red, green and blue Mushtrees."
    },
    FungalNoiseMeadow: {
        name: "Mixed mushroom meadow",
        description: "Meadows that blend the fungal biomes, with Spilagmites."
    },
    BatCloister: {
        name: "Bat cloister",
        description: "Bottomless pits around a Bat cave."
    },
    RabbitTown: {
        name: "Rabbit town",
        description: "A settlement of Bunnymen with their rabbit holes."
    },
    RabbitCity: {
        name: "Rabbit city",
        description: "A big Bunnyman city."
    },
    SpiderLand: {
        name: "Spider land",
        description: "Spider incursions and a spider marsh."
    },
    RabbitSpiderWar: {
        name: "Rabbit and spider war",
        description: "Bunnymen and Spiders fighting over the same ground."
    },
    MoreAltars: {
        name: "Another Broken Altar",
        description: "An extra Broken Altar area in the Ruins."
    },
    CaveJungle: {
        name: "Cave jungle",
        description: "Ruins jungle with Lichen meadows, wet wilds and Monkey meadows."
    },
    SacredDanger: {
        name: "Dangerous sacred grounds",
        description: "Barracks and sacred ground in the Ruins, with more Clockwork Knights."
    },
    MilitaryPits: {
        name: "Military pits",
        description: "The Ruins' military maze and Barracks, cut by pits."
    },
    MuddySacred: {
        name: "Muddy sacred grounds",
        description: "Sacred ground in the Ruins with wet wilds and Monkey meadows."
    },
    Residential2: {
        name: "Ruined city",
        description: "A ruined city with vacant houses and cave jungle."
    },
    Residential3: {
        name: "Ruined suburb",
        description: "Rows of vacant houses in the Ruins."
    }
};

const EXIT_TASKS = Array.from({ length: 10 }, (_, index) => `CaveExitTask${index + 1}`);
EXIT_TASKS.forEach((id, index) => (TASK_TEXT[id] = { name: `Exit sinkhole ${index + 1}`, description: EXIT_SINKHOLE }));
["ToadStoolTask1", "ToadStoolTask2", "ToadStoolTask3"].forEach(
    (id, index) => (TASK_TEXT[id] = { name: `Toadstool arena ${index + 1}`, description: TOADSTOOL_ARENA })
);

const PIECE_TEXT: Record<string, Omit<SetPieceInfo, "id" | "kind" | "rare" | "maxCount">> = {
    TentaclePillar: {
        name: "Tentacle Pillar",
        description: "A Big Tentacle pillar that teleports to its paired pillar, the caves' Worm Hole.",
        contents: ["Tentacle Pillar"]
    },
    TentaclePillarToAtrium: {
        name: "Tentacle Pillar to the Atrium",
        description: "The pillar that links the caves to the Atrium's gateway.",
        contents: ["Tentacle Pillar"]
    },
    skeleton_notplayer: {
        name: "Skeleton of a nobody",
        description: "A lone skeleton next to a small light with some silk.",
        contents: ["Skeleton", "Silk", "Light"]
    },
    skeleton_mushjack: {
        name: "Mushroom lumberjack's remains",
        description: "A skeleton next to mushtree stumps with an axe and some logs.",
        contents: ["Straw Hat", "Axe", "Logs", "Cut Grass", "Twigs"]
    },
    skeleton_lightfarmer: {
        name: "Light farmer's remains",
        description: "A skeleton among Light Bulb plants with a lantern and a pitchfork.",
        contents: ["Lantern", "Pitchfork", "Light Bulb plants"]
    },
    skeleton_batfight: {
        name: "Bat fighter's remains",
        description: "A skeleton surrounded by Bats with a Bat Bat.",
        contents: ["Miner Hat", "Bat Bat", "Batilisk Wing", "Guano"]
    },
    lures_and_worms: {
        name: "Lure plants and worms",
        description: "A patch of Lureplants guarding the mud they grow in.",
        contents: ["Lureplants"]
    }
};

function pieceInfo(vocab: CavePieceVocab): SetPieceInfo {
    const known = Object.hasOwn(PIECE_TEXT, vocab.id) ? PIECE_TEXT[vocab.id] : undefined;
    const forest = Object.hasOwn(SET_PIECE_BY_ID, vocab.id) ? SET_PIECE_BY_ID[vocab.id] : undefined;
    const text = known ?? (forest && { name: forest.name, description: forest.description, contents: forest.contents });
    if (!text) throw new Error(`no text for the cave set piece ${vocab.id}`);
    return {
        id: vocab.id,
        kind: vocab.kind,
        rare: vocab.rare,
        maxCount: vocab.maxCount,
        ...(vocab.fixedCount === undefined ? {} : { fixedCount: vocab.fixedCount, alwaysPlaced: true }),
        ...(vocab.candidateTasks === undefined ? {} : { candidateTasks: [...vocab.candidateTasks] }),
        ...text
    };
}

function taskInfo(id: string, kind: TaskInfo["kind"]): TaskInfo {
    const text = Object.hasOwn(TASK_TEXT, id) ? TASK_TEXT[id] : undefined;
    if (!text) throw new Error(`no text for the cave task ${id}`);
    return { id, kind, ...text };
}

export const CAVE_TASKS: TaskInfo[] = [
    ...CAVE_REQUIRED_TASK_IDS.map((id) => taskInfo(id, "required")),
    ...CAVE_OPTIONAL_TASK_IDS.map((id) => taskInfo(id, "optional"))
];

export const CAVE_SET_PIECES: SetPieceInfo[] = CAVE_PIECES.map(pieceInfo);

const FIXED_DESCRIPTION =
    "Always present with a fixed count. Only the biomes they land in change.";

export const CAVE_SET_PIECE_KINDS = SET_PIECE_KINDS.filter((kind) => CAVE_SET_PIECES.some((piece) => piece.kind === kind.id)).map((kind) =>
    kind.id === "fixed" ? { ...kind, name: "Landmarks", description: FIXED_DESCRIPTION } : kind
);

export const CAVE_SWAP_INFOS: SwapInfo[] = SWAPS.flatMap((swap) => {
    const allowed = CAVE_SWAPS.find((cave) => cave.category === swap.id)?.options ?? [];
    return allowed.length < swap.options.length ? [] : [swap];
});
