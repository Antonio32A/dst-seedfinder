import type { SetPieceInfo, SetPieceKind, SetPieceKindInfo, SwapInfo, TaskInfo } from "./catalog-types";

export const TASKS: TaskInfo[] = [
    {
        id: "Make a pick",
        name: "Starting meadow",
        kind: "required",
        description: "The area around the Florid Postern where you spawn, with forest, grassy plains with rabbit holes and a clearing."
    },
    {
        id: "Dig that rock",
        name: "Graveyard and boulders",
        kind: "required",
        description: "Rocky ground with boulders, Tallbird nests and a meteor field, plus a graveyard with diggable graves and the Rock Den for critter pets."
    },
    {
        id: "Great Plains",
        name: "Great Plains",
        kind: "required",
        description: "Wide savanna with Beefalo herds, grass and rabbit holes."
    },
    {
        id: "Squeltch",
        name: "Big swamp",
        kind: "required",
        description: "A large marsh full of Tentacles, Reeds, mosquito ponds and a few Merm houses."
    },
    {
        id: "Beeeees!",
        name: "Bee Queen's meadow",
        kind: "required",
        description: "Flower fields with beehives, Killer Bee hives and the Honey Patch where the Bee Queen lives."
    },
    {
        id: "Speak to the king",
        name: "Pig King's birch forest",
        kind: "required",
        description: "Home of the Pig King and his pig houses, in a birchnut forest with Glommer's Statue, Hollow Stumps and No-Eyed Deer."
    },
    {
        id: "Forest hunters",
        name: "Moon Stone forest",
        kind: "required",
        description: "Evergreen forest with the Moon Stone, a MacTusk Walrus Camp and Moleworm burrows."
    },
    {
        id: "Badlands",
        name: "Dragonfly desert",
        kind: "required",
        description: "Dry badlands with the Dragonfly arena, Hound Mounds, Buzzards, cacti and tumbleweeds."
    },
    {
        id: "For a nice walk",
        name: "Mandrake forest",
        kind: "required",
        description: "Dense evergreen forest with Mandrakes and a Beefalo field."
    },
    {
        id: "Lightning Bluff",
        name: "Oasis desert",
        kind: "required",
        description: "The desert with the Antlion, the Oasis lake and Volt Goats."
    },
    {
        id: "Befriend the pigs",
        name: "Pig village",
        kind: "optional",
        description: "A village of 4 to 7 pig houses with farm plots, surrounded by forest and a bit of marsh."
    },
    {
        id: "Kill the spiders",
        name: "Spider rocks",
        kind: "optional",
        description: "Rocky ground crowded with spider dens and loose gold nuggets, next to a sparse forest."
    },
    {
        id: "Killer bees!",
        name: "Killer bees!",
        kind: "optional",
        description: "Flower fields full of Killer Bee hives mixed with regular beehives."
    },
    {
        id: "Make a Beehat",
        name: "Beehat fields",
        kind: "optional",
        description: "Flower patches with beehives next to rocky ground with boulders, Tallbird nests and a meteor field."
    },
    {
        id: "The hunters",
        name: "Walrus hunting grounds",
        kind: "optional",
        description: "Savanna, grass and rocky patches with three MacTusk Walrus Camps."
    },
    {
        id: "Magic meadow",
        name: "Magic meadow",
        kind: "optional",
        description: "Clearings full of ponds with Frogs, grass and saplings."
    },
    {
        id: "Frogs and bugs",
        name: "Frogs and bugs",
        kind: "optional",
        description: "Grassland with frog ponds, beehives, flower patches and a Moleworm colony."
    },
    {
        id: "Mole Colony Deciduous",
        name: "Mole colony (birch forest)",
        kind: "optional",
        description: "Birchnut forest riddled with Moleworm burrows, with mushrooms and Hollow Stumps."
    },
    {
        id: "Mole Colony Rocks",
        name: "Mole colony (rocky)",
        kind: "optional",
        description: "Rocky ground with boulders, Moleworm burrows and Buzzards."
    },
    {
        id: "MooseBreedingTask",
        name: "Moose/Goose nesting grounds",
        kind: "optional",
        description: "A grassy area with four Moose/Goose nesting spots, berry bushes, carrots and trees."
    },
    {
        id: "MoonIsland_IslandShards",
        name: "Lunar Island: Shard islets",
        kind: "moon",
        description: "The small islets around Lunar Island, with driftwood, Anenemies, moon glass and Celestial Fissures."
    },
    {
        id: "MoonIsland_Beach",
        name: "Lunar Island: Beach",
        kind: "moon",
        description: "The Lunar Island shore with Shattered Spider Holes, driftwood, bull kelp and Anenemies."
    },
    {
        id: "MoonIsland_Forest",
        name: "Lunar Island: Lune forest",
        kind: "moon",
        description: "Lune trees, Stone Fruit bushes, Carrats and Shattered Spider Holes, with a Moon Glass Axe hidden among the trees."
    },
    {
        id: "MoonIsland_Baths",
        name: "Lunar Island: Hot springs",
        kind: "moon",
        description: "Hot springs with Saladmanders, Lune trees, Stone Fruit bushes and Celestial Fissures."
    },
    {
        id: "MoonIsland_Mine",
        name: "Lunar Island: Moon glass mine",
        kind: "moon",
        description: "Moon glass and moon rock boulders, plus the three Inviting Formations that hold the Celestial Altar pieces."
    }
];

export const SWAPS: SwapInfo[] = [
    {
        id: "grass",
        name: "Grass",
        description: "Which kind of grass the world has.",
        options: [
            {
                id: "regular grass",
                name: "Regular grass",
                description: "Normal grass tufts that you pick and that regrow in place."
            },
            {
                id: "grass gekko",
                name: "Grass Gekkos",
                description: "Most grass tufts are replaced by Grass Gekkos, lizards that run away and drop cut grass."
            }
        ]
    },
    {
        id: "twigs",
        name: "Twigs",
        description: "Where twigs come from.",
        options: [
            { id: "regular twigs", name: "Saplings", description: "Normal saplings that you pick for twigs." },
            {
                id: "twiggy trees",
                name: "Twiggy Trees",
                description: "Saplings are replaced by Twiggy Trees that you chop for twigs, with loose twigs on the ground."
            }
        ]
    },
    {
        id: "berries",
        name: "Berries",
        description: "Which berry bushes the world has.",
        options: [
            { id: "regular berries", name: "Berry Bushes", description: "Normal Berry Bushes." },
            {
                id: "juicy berries",
                name: "Juicy Berry Bushes",
                description: "Berry Bushes are replaced by Juicy Berry Bushes, which give more berries at once that spoil faster."
            }
        ]
    }
];

export const SET_PIECE_KINDS: SetPieceKindInfo[] = [
    {
        id: "boon",
        name: "Boons (Failed Survivors)",
        description: "3 to 8 spawn per world."
    },
    {
        id: "trap",
        name: "Traps",
        description: "At most one per world: tempting loot with a nasty surprise, like sleeping hounds or a spoiling stink cloud."
    },
    {
        id: "poi",
        name: "Points of interest",
        description: "At most one per world: a small scene, usually a skeleton with themed gear."
    },
    {
        id: "protected",
        name: "Guarded resources",
        description: "At most one per world: a rich patch of resources guarded by monsters."
    },
    {
        id: "fixed",
        name: "Landmarks",
        description: "Always present with a fixed count (Touch Stones, Worm Holes, cave entrances, Moose/Goose nests, Lunar Island pieces). Only the areas they land in change."
    },
    {
        id: "random",
        name: "Random set pieces",
        description: "Marble sculptures, Maxwell statues, clockwork chess areas and pig vs. merm warzones. Two are always placed, plus four random picks."
    }
];

const MAINLAND_TASK_IDS = TASKS.filter((task) => task.kind !== "moon").map((task) => task.id);

const BOONS: SetPieceInfo[] = [
    {
        id: "WoodBoon",
        name: "Wood boon",
        kind: "boon",
        description: "A skeleton with a wood-gathering tool and a few logs.",
        contents: ["Axe or Shovel", "3-5 Logs"],
        rare: false,
        maxCount: 7
    },
    {
        id: "RockBoon",
        name: "Rock boon",
        kind: "boon",
        description: "A skeleton with mining gear and some rocks.",
        contents: ["Pickaxe (usually), Boulder or Gunpowder", "3-5 Rocks or Flint"],
        rare: false,
        maxCount: 7
    },
    {
        id: "GrassBoon",
        name: "Grass boon",
        kind: "boon",
        description: "A skeleton with a basic tool and a pile of cut grass.",
        contents: ["Torch or Trap", "3-5 Cut Grass"],
        rare: false,
        maxCount: 7
    },
    {
        id: "TwigsBoon",
        name: "Twigs boon",
        kind: "boon",
        description: "A skeleton with a small pile of twigs.",
        contents: ["3-5 Twigs"],
        rare: false,
        maxCount: 7
    },
    {
        id: "CookingBoon",
        name: "Cooking boon",
        kind: "boon",
        description: "A skeleton next to a Crock Pot, with a cookbook, recipe cards and some spoiled food.",
        contents: ["Crock Pot", "Cookbook", "2 Recipe Cards", "3-4 spoiled food"],
        rare: false,
        maxCount: 7
    },
    {
        id: "FishingBoon",
        name: "Fishing boon",
        kind: "boon",
        description: "A skeleton with sea fishing tackle.",
        contents: ["Sea Fishing Rod", "Random spoon or spinnerbait lure", "Random bobber", "Spoiled Fish Morsel"],
        rare: false,
        maxCount: 8
    },
    {
        id: "FarmingBoon",
        name: "Farming boon",
        kind: "boon",
        description: "A skeleton with farming tools and fertilizer.",
        contents: ["Garden Digamajig", "Gardeneer Hat", "2 Manure", "Guano", "3 Rot"],
        rare: false,
        maxCount: 7
    },
    {
        id: "Level2WoodBoon",
        name: "Level 2 wood boon",
        kind: "boon",
        description: "A skeleton with a Log Suit or an axe and a stack of boards.",
        contents: ["Log Suit or Axe", "3-5 Boards"],
        rare: false,
        maxCount: 8
    },
    {
        id: "Level2RockBoon",
        name: "Level 2 rock boon",
        kind: "boon",
        description: "A skeleton with mining gear and a stack of cut stone.",
        contents: ["Pickaxe (usually), Boulder or Gunpowder", "3-5 Cut Stone"],
        rare: false,
        maxCount: 7
    },
    {
        id: "Level2GrassBoon",
        name: "Level 2 grass boon",
        kind: "boon",
        description: "A skeleton with a basic tool and a stack of rope.",
        contents: ["Torch or Trap", "3-5 Rope"],
        rare: false,
        maxCount: 7
    },
    {
        id: "Level2TwigsBoon",
        name: "Level 2 twigs boon",
        kind: "boon",
        description: "A skeleton with a Grass Suit and some twigs.",
        contents: ["Grass Suit", "3-5 Twigs"],
        rare: false,
        maxCount: 8
    },
    {
        id: "MiscBoon",
        name: "Misc boon",
        kind: "boon",
        description: "A skeleton with one piece of clothing: a hat, a vest or a Walking Cane.",
        contents: ["One of: Winter Hat, Top Hat, Bush Hat, Feather Hat, Puffy Vest, Breezy Vest, Walking Cane, Dapper Vest"],
        rare: false,
        maxCount: 7
    },
    {
        id: "WeaponBoon",
        name: "Weapon boon",
        kind: "boon",
        description: "A skeleton with a ranged weapon.",
        contents: ["One of: Sleep Dart, Fire Dart, Blow Dart, Boomerang"],
        rare: false,
        maxCount: 7
    },
    {
        id: "Level4Boon",
        name: "Level 4 boon",
        kind: "boon",
        description: "A rare skeleton with one powerful item.",
        contents: ["One of: Fire Staff, Ice Staff, Marble Suit, Pan Flute, Walking Cane, Ham Bat, Dark Sword, One-man Band"],
        rare: true,
        maxCount: 5
    }
];

const TRAPS: SetPieceInfo[] = [
    {
        id: "Sleeping Spider",
        name: "Sleeping Spider",
        kind: "trap",
        description: "A Spider Warrior sleeping inside a hay-wall pen in the forest. Hitting it calls three more Spider Warriors.",
        contents: ["Spider Warrior (+3 more when attacked)", "44 Hay Walls", "Pig Head", "6 Saplings", "6 Grass", "3 Twiggy Trees", "6 Bones"],
        rare: false,
        maxCount: 1
    },
    {
        id: "Rotted Base",
        name: "Rotted Base",
        kind: "trap",
        description: "An abandoned swamp camp with a chest. Opening it releases a stink cloud that half-spoils the food you carry.",
        contents: ["Chest: 10 Rot, 4 Blueprints", "Skeleton", "Pig Head", "2 Ponds", "3 Reeds", "4 Rot"],
        rare: false,
        maxCount: 1
    },
    {
        id: "Beefalo Farm",
        name: "Beefalo Farm",
        kind: "trap",
        description: "A big wood-walled pen on the savanna with a booby-trapped chest that explodes when opened.",
        contents: ["Chest: Fire Staff, 10 Ashes, 4 Gunpowder, 4 Logs", "96 Wood Walls", "12 Grass", "4 Beefalo Wool", "Pig Head"],
        rare: false,
        maxCount: 1
    },
    {
        id: "Fire Hounds",
        name: "Fire Hounds",
        kind: "trap",
        description: "A Fire Staff lying among five sleeping Fire Hounds. Picking it up wakes them, drains sanity and starts rain.",
        contents: ["Fire Staff", "5 Fire Hounds"],
        rare: false,
        maxCount: 1
    },
    {
        id: "Ice Hounds",
        name: "Ice Hounds",
        kind: "trap",
        description: "An Ice Staff lying among five sleeping Ice Hounds. Picking it up wakes them, drains sanity and starts rain.",
        contents: ["Ice Staff", "5 Ice Hounds"],
        rare: false,
        maxCount: 1
    },
    {
        id: "Dev Graveyard",
        name: "Developer graveyard",
        kind: "trap",
        description: "A rare graveyard of 18 headstones named after Klei developers. Digging up every grave summons ghosts.",
        contents: ["18 Headstones", "Shovel", "2 Maxwell Statues", "4 Marble Pillars", "10 Evil Flowers", "Ghosts"],
        rare: true,
        maxCount: 1
    }
];

const POINTS_OF_INTEREST: SetPieceInfo[] = [
    {
        id: "skeleton_lumberjack",
        name: "Lumberjack's remains",
        kind: "poi",
        description: "A forest skeleton with an axe, a Straw Hat and some basic materials.",
        contents: ["Axe", "Straw Hat", "3 Logs", "2 Cut Grass", "2 Twigs"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_trapper",
        name: "Trapper's remains",
        kind: "poi",
        description: "A forest skeleton with a Bush Hat and trapping gear.",
        contents: ["Bush Hat", "2 Traps", "2 Bird Traps", "Bird Trap blueprint", "2 Rope", "3 Rot"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_miner_dirt",
        name: "Miner guarded by Treeguards",
        kind: "poi",
        description: "A miner's skeleton with gold in the badlands, watched over by four Treeguards.",
        contents: ["Miner Hat", "Pickaxe", "3 Gold Nuggets", "5 Rocks", "4 Treeguards"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_hunter_swamp",
        name: "Hunter in the swamp",
        kind: "poi",
        description: "A hunter's skeleton in the marsh, surrounded by 19 Tentacles.",
        contents: ["Beefalo Hat", "Spear", "4 Hound's Teeth", "3 Beefalo Wool", "3 Bones", "19 Tentacles"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_miner",
        name: "Miner's remains",
        kind: "poi",
        description: "A skeleton on rocky ground with mining gear and some gold.",
        contents: ["Miner Hat", "Pickaxe", "3 Gold Nuggets", "5 Rocks"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_camper",
        name: "Camper's remains",
        kind: "poi",
        description: "A savanna skeleton with camping gear, including a Backpack.",
        contents: ["Backpack", "Straw Roll", "Straw Hat", "2 Rope", "2 Rot"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_hunter",
        name: "Hunter's remains",
        kind: "poi",
        description: "A savanna skeleton with a Beefalo Hat and a spear.",
        contents: ["Beefalo Hat", "Spear", "4 Hound's Teeth", "3 Beefalo Wool", "3 Bones"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_farmer",
        name: "Farmer's remains",
        kind: "poi",
        description: "A grassland skeleton with a pitchfork, seeds and manure.",
        contents: ["Pitchfork", "Straw Hat", "4 Seeds", "4 Manure"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_entomologist",
        name: "Beekeeper's remains",
        kind: "poi",
        description: "A grassland skeleton with beekeeping gear and a Bee Box blueprint.",
        contents: ["Beekeeper Hat", "Bug Net", "2 Bee Mines", "3 Stingers", "Bee Box blueprint"],
        rare: false,
        maxCount: 1
    },
    {
        id: "grass_spots",
        name: "Patchy turf",
        kind: "poi",
        description: "A patch of mixed turf on the grassland and nothing else. The game calls it a point of no interest.",
        contents: [],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_warrior",
        name: "Warrior's remains",
        kind: "poi",
        description: "A skeleton with basic armor and a spear.",
        contents: ["Log Suit", "Football Helmet", "Spear", "4 Bones"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_wizard_ice",
        name: "Ice wizard's remains",
        kind: "poi",
        description: "A skeleton with an Ice Staff and a Puffy Vest.",
        contents: ["Ice Staff", "Puffy Vest", "3 Beard Hair", "6 Bones"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_wizard_fire",
        name: "Fire wizard's remains",
        kind: "poi",
        description: "A skeleton with a Fire Staff among burnt trees and ashes.",
        contents: ["Fire Staff", "2 Gunpowder", "5 Beard Hair", "8 Ashes", "4 Bones"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_rain_coat",
        name: "Rain-geared remains",
        kind: "poi",
        description: "A skeleton dressed for the rain.",
        contents: ["Rain Coat", "Rain Hat", "Pig Skin", "Cut Grass"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_fisher",
        name: "Angler's remains",
        kind: "poi",
        description: "A skeleton with a fishing rod and a Feather Hat.",
        contents: ["Freshwater Fishing Rod", "Feather Hat", "2 Rope", "3 Rot"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_graverobber",
        name: "Grave robber's remains",
        kind: "poi",
        description: "A skeleton by a headstone with a Life Giving Amulet, a Backpack and dug-up trinkets.",
        contents: ["Life Giving Amulet", "Backpack", "Shovel", "Headstone", "Melty Marbles", "Gord's Knot"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_night_hunter",
        name: "Night hunter's remains",
        kind: "poi",
        description: "A skeleton with a Morning Star, Moggles and a Log Suit.",
        contents: ["Morning Star", "Moggles", "Log Suit"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_construction",
        name: "Builder's remains",
        kind: "poi",
        description: "A skeleton with building materials, a hammer and a Birdcage blueprint.",
        contents: ["Hammer", "Football Helmet", "3 Boards", "2 Cut Stone", "2 Rope", "Birdcage blueprint"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_summer",
        name: "Summer explorer's remains",
        kind: "poi",
        description: "A skeleton with summer gear.",
        contents: ["Summer Frest", "Moggles", "Pickaxe"],
        rare: false,
        maxCount: 1
    },
    {
        id: "skeleton_dapper",
        name: "Dapper gentleman's remains",
        kind: "poi",
        description: "A rare skeleton with fancy clothes, gems and a Life Giving Amulet.",
        contents: ["Life Giving Amulet", "Top Hat", "Dapper Vest", "Red Gem", "Blue Gem", "3 Gold Nuggets"],
        rare: true,
        maxCount: 1
    },
    {
        id: "skeleton_researchlab1",
        name: "Abandoned camp: Science Machine",
        kind: "poi",
        description: "A rare prebuilt camp with a Science Machine and drying racks.",
        contents: ["Science Machine", "2 Drying Racks", "Chest (empty)", "Pitchfork", "Straw Hat"],
        rare: true,
        maxCount: 1
    },
    {
        id: "skeleton_researchlab2",
        name: "Abandoned camp: Alchemy Engine",
        kind: "poi",
        description: "A rare prebuilt walled camp with an Alchemy Engine, a fire pit and a tent.",
        contents: ["Alchemy Engine", "Fire Pit", "Tent", "Thermal Measurer", "Axe", "Beefalo Hat", "25 Wood Walls", "Pig Head"],
        rare: true,
        maxCount: 1
    },
    {
        id: "skeleton_researchlab3",
        name: "Abandoned camp: Shadow Manipulator",
        kind: "poi",
        description: "A rare, fully built stone-walled base with a Shadow Manipulator, a Crock Pot, bee boxes and a small farm of bushes.",
        contents: [
            "Shadow Manipulator",
            "Crock Pot",
            "2 Bee Boxes",
            "Fire Pit",
            "Tent",
            "Chest (empty)",
            "Opulent Pickaxe",
            "Miner Hat",
            "40 Stone Walls",
            "4 Berry Bushes",
            "4 Juicy Berry Bushes",
            "4 Saplings",
            "5 Twiggy Trees"
        ],
        rare: true,
        maxCount: 1
    }
];

const GUARDED_RESOURCES: SetPieceInfo[] = [
    {
        id: "leif_forest",
        name: "Treeguard grove",
        kind: "protected",
        description: "A patch of evergreens hiding ten sleeping Treeguards.",
        contents: ["10 Treeguards (sleeping)", "41 Evergreens"],
        rare: false,
        maxCount: 1
    },
    {
        id: "spider_forest",
        name: "Spider forest",
        kind: "protected",
        description: "A dense forest packed with twelve spider dens, almost all fully grown.",
        contents: ["12 Spider Dens", "52 Evergreens"],
        rare: false,
        maxCount: 1
    },
    {
        id: "hound_rocks",
        name: "Hound-guarded boulders",
        kind: "protected",
        description: "A big boulder field in the badlands guarded by ten Hound Mounds.",
        contents: ["10 Hound Mounds", "43 Boulders (11 with gold)"],
        rare: false,
        maxCount: 1
    },
    {
        id: "tenticle_reeds",
        name: "Tentacle reed bed",
        kind: "protected",
        description: "A huge reed bed in the swamp guarded by dozens of Tentacles.",
        contents: ["55 Reeds", "76 Tentacles"],
        rare: false,
        maxCount: 1
    },
    {
        id: "tallbird_rocks",
        name: "Tallbird boulders",
        kind: "protected",
        description: "A boulder field full of Tallbird nests.",
        contents: ["17 Tallbird Nests", "43 Boulders (11 with gold)"],
        rare: false,
        maxCount: 1
    },
    {
        id: "pigguard_grass_easy",
        name: "Guarded grass (small)",
        kind: "protected",
        description: "A savanna grass field guarded by four Pig Torches with Guard Pigs.",
        contents: ["44 Grass", "4 Pig Torches (Guard Pigs)"],
        rare: false,
        maxCount: 1
    },
    {
        id: "pigguard_grass",
        name: "Guarded grass (large)",
        kind: "protected",
        description: "A savanna grass field guarded by eight Pig Torches with Guard Pigs.",
        contents: ["50 Grass", "8 Pig Torches (Guard Pigs)"],
        rare: false,
        maxCount: 1
    },
    {
        id: "pigguard_berries_easy",
        name: "Guarded berries (small)",
        kind: "protected",
        description: "A big berry patch on the grassland with a single Pig Torch and its Guard Pig.",
        contents: ["22 Berry Bushes", "16 Juicy Berry Bushes", "Pig Torch (Guard Pig)"],
        rare: false,
        maxCount: 1
    },
    {
        id: "pigguard_berries",
        name: "Guarded berries (large)",
        kind: "protected",
        description: "A big berry patch on the grassland guarded by eight Pig Torches with Guard Pigs.",
        contents: ["20 Berry Bushes", "12 Juicy Berry Bushes", "8 Pig Torches (Guard Pigs)"],
        rare: false,
        maxCount: 1
    },
    {
        id: "wasphive_grass_easy",
        name: "Killer bee grass",
        kind: "protected",
        description: "A dense grass field guarded by three Killer Bee hives.",
        contents: ["46 Grass", "3 Killer Bee Hives"],
        rare: false,
        maxCount: 1
    }
];

const LANDMARKS: SetPieceInfo[] = [
    {
        id: "ResurrectionStone",
        name: "Touch Stone",
        kind: "fixed",
        description: "A Touch Stone that revives a dead player, surrounded by four Pig Heads.",
        contents: ["Touch Stone", "4 Pig Heads"],
        rare: false,
        maxCount: 2,
        fixedCount: 2,
        alwaysPlaced: true,
        candidateTasks: ["Make a pick", "Dig that rock", "Great Plains", "Squeltch", "Beeeees!", "Speak to the king", "Forest hunters", "Badlands"]
    },
    {
        id: "WormholeGrass",
        name: "Worm Hole",
        kind: "fixed",
        description: "A Worm Hole that links to another one somewhere else on the map.",
        contents: ["Worm Hole"],
        rare: false,
        maxCount: 8,
        fixedCount: 8,
        alwaysPlaced: true,
        candidateTasks: [
            "Make a pick",
            "Dig that rock",
            "Great Plains",
            "Squeltch",
            "Beeeees!",
            "Speak to the king",
            "Forest hunters",
            "Befriend the pigs",
            "For a nice walk",
            "Kill the spiders",
            "Killer bees!",
            "Make a Beehat",
            "The hunters",
            "Magic meadow",
            "Frogs and bugs",
            "Badlands"
        ]
    },
    {
        id: "MooseNest",
        name: "Moose/Goose nest",
        kind: "fixed",
        description: "A spring nesting spot for the Moose/Goose, with berry bushes, carrots, a pond and a few trees.",
        contents: ["Moose/Goose nesting ground", "5 Berry Bushes", "3 Juicy Berry Bushes", "3 Carrots", "Pond", "5 trees"],
        rare: false,
        maxCount: 9,
        fixedCount: 9,
        alwaysPlaced: true,
        candidateTasks: [
            "Make a pick",
            "Beeeees!",
            "Speak to the king",
            "Forest hunters",
            "Befriend the pigs",
            "For a nice walk",
            "Make a Beehat",
            "Magic meadow",
            "Frogs and bugs"
        ]
    },
    {
        id: "CaveEntrance",
        name: "Cave entrance",
        kind: "fixed",
        description: "A Plugged Sinkhole that leads down to the caves once opened.",
        contents: ["Plugged Sinkhole"],
        rare: false,
        maxCount: 10,
        fixedCount: 10,
        alwaysPlaced: true,
        candidateTasks: [
            "Make a pick",
            "Dig that rock",
            "Great Plains",
            "Squeltch",
            "Beeeees!",
            "Speak to the king",
            "Forest hunters",
            "Befriend the pigs",
            "For a nice walk",
            "Kill the spiders",
            "Killer bees!",
            "Make a Beehat",
            "The hunters",
            "Magic meadow",
            "Frogs and bugs"
        ]
    },
    {
        id: "MoonAltarRockGlass",
        name: "Inviting Formation (Altar Base)",
        kind: "fixed",
        description: "A rock formation on Lunar Island that holds the Celestial Altar Base.",
        contents: ["Inviting Formation with the Celestial Altar Base"],
        rare: false,
        maxCount: 1,
        fixedCount: 1,
        alwaysPlaced: true,
        candidateTasks: ["MoonIsland_Mine"]
    },
    {
        id: "MoonAltarRockIdol",
        name: "Inviting Formation (Altar Idol)",
        kind: "fixed",
        description: "A rock formation on Lunar Island that holds the Celestial Altar Idol.",
        contents: ["Inviting Formation with the Celestial Altar Idol"],
        rare: false,
        maxCount: 1,
        fixedCount: 1,
        alwaysPlaced: true,
        candidateTasks: ["MoonIsland_Mine"]
    },
    {
        id: "MoonAltarRockSeed",
        name: "Inviting Formation (Altar Orb)",
        kind: "fixed",
        description: "A rock formation on Lunar Island that holds the Celestial Altar Orb.",
        contents: ["Inviting Formation with the Celestial Altar Orb"],
        rare: false,
        maxCount: 1,
        fixedCount: 1,
        alwaysPlaced: true,
        candidateTasks: ["MoonIsland_Mine"]
    },
    {
        id: "BathbombedHotspring",
        name: "Bath-bombed hot spring",
        kind: "fixed",
        description: "A Lunar Island hot spring that already has a Bath Bomb in it, next to a skeleton.",
        contents: ["Hot Spring (bath-bombed)", "Bath Bomb", "Skeleton", "2 Lune Trees"],
        rare: false,
        maxCount: 1,
        fixedCount: 1,
        alwaysPlaced: true,
        candidateTasks: ["MoonIsland_Baths"]
    },
    {
        id: "MoonFissures",
        name: "Celestial Fissures",
        kind: "fixed",
        description: "A cluster of three Celestial Fissures on Lunar Island.",
        contents: ["3 Celestial Fissures"],
        rare: false,
        maxCount: 1,
        fixedCount: 1,
        alwaysPlaced: true,
        candidateTasks: ["MoonIsland_Mine", "MoonIsland_Forest"]
    }
];

const RANDOM_SET_PIECES: SetPieceInfo[] = [
    {
        id: "Sculptures_1",
        name: "Sculpture garden",
        kind: "random",
        description: "The main marble sculpture garden with the rook, knight and bishop sculptures that awaken the Shadow Chess Pieces. Every world has one.",
        contents: [
            "Rook Marble Sculpture",
            "Knight Marble Sculpture",
            "Bishop Marble Sculpture",
            "Muse and Pawn Marble Statues",
            "Skeleton with a Pickaxe",
            "2 Marble"
        ],
        rare: false,
        maxCount: 1,
        alwaysPlaced: true,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Sculptures_2",
        name: "Flower sculpture garden",
        kind: "random",
        description: "A flower bed with marble statues and extra knight and bishop sculptures.",
        contents: ["Knight Marble Sculpture", "Bishop Marble Sculpture", "Muse Marble Statue", "2 random marble statues or sculptures", "9 Flowers"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Sculptures_3",
        name: "Rook sculpture",
        kind: "random",
        description: "An extra rook sculpture next to a pawn statue.",
        contents: ["Rook Marble Sculpture", "Pawn Marble Statue"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Sculptures_4",
        name: "Knight sculptures",
        kind: "random",
        description: "Two extra knight sculptures.",
        contents: ["2 Knight Marble Sculptures"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Sculptures_5",
        name: "Large sculpture garden",
        kind: "random",
        description: "A second full set of rook, knight and bishop sculptures with marble statues around them.",
        contents: [
            "Rook Marble Sculpture",
            "Knight Marble Sculpture",
            "Bishop Marble Sculpture",
            "2 Marble Sculptures",
            "Up to 4 random marble pillars, statues or sculptures"
        ],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Maxwell1",
        name: "Clockwork marble grove",
        kind: "random",
        description: "Marble trees and pillars in a bed of Evil Flowers, guarded by clockwork monsters.",
        contents: ["3 Clockwork Knights", "Clockwork Rook", "9 Marble Trees", "4 Marble Pillars", "24 Evil Flowers"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Maxwell2",
        name: "Maxwell statue with clockworks",
        kind: "random",
        description: "A Maxwell Statue among marble trees, guarded by clockwork knights and a rook.",
        contents: ["Maxwell Statue", "4 Clockwork Knights", "Clockwork Rook", "8 Marble Trees"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Maxwell3",
        name: "Maxwell statue with knights",
        kind: "random",
        description: "A Maxwell Statue guarded by five clockwork knights.",
        contents: ["Maxwell Statue", "5 Clockwork Knights"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Maxwell4",
        name: "Maxwell statue grove",
        kind: "random",
        description: "A Maxwell Statue surrounded by marble trees.",
        contents: ["Maxwell Statue", "4 Marble Trees"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Maxwell5",
        name: "Maxwell statue and harps",
        kind: "random",
        description: "A Maxwell Statue in a ring of Harp Statues, with a clockwork knight. Every world has one.",
        contents: ["Maxwell Statue", "8 Harp Statues", "Clockwork Knight", "3 Evil Flowers"],
        rare: false,
        maxCount: 1,
        alwaysPlaced: true,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Maxwell6",
        name: "Marble tree grove",
        kind: "random",
        description: "A small grove of marble trees.",
        contents: ["5 Marble Trees"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Maxwell7",
        name: "Maxwell statue with two knights",
        kind: "random",
        description: "A Maxwell Statue among marble trees, guarded by two clockwork knights.",
        contents: ["Maxwell Statue", "2 Clockwork Knights", "4 Marble Trees", "2 Evil Flowers"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Chessy_1",
        name: "Knights and a fallen fighter",
        kind: "random",
        description: "Two clockwork knights next to a skeleton with a spear.",
        contents: ["2 Clockwork Knights", "2 Gears", "Skeleton", "Spear"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Chessy_2",
        name: "Bishops and a Maxwell statue",
        kind: "random",
        description: "Two clockwork bishops next to a Maxwell Statue.",
        contents: ["2 Clockwork Bishops", "2 Gears", "Maxwell Statue"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Chessy_3",
        name: "Rook and a fallen traveller",
        kind: "random",
        description: "A clockwork rook next to a skeleton with a Backpack.",
        contents: ["Clockwork Rook", "Skeleton", "Backpack", "Honey Poultice", "2 Rot"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Chessy_4",
        name: "Rook and a fallen miner",
        kind: "random",
        description: "A clockwork rook near a Maxwell Statue and a skeleton with a pickaxe.",
        contents: ["Clockwork Rook", "Maxwell Statue", "Marble Tree", "2 Marble Pillars", "2 Marble", "Skeleton", "Pickaxe"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Chessy_5",
        name: "Clockworks by a harp statue",
        kind: "random",
        description: "A clockwork knight and bishop by a Harp Statue in a flower bed.",
        contents: ["Clockwork Knight", "Clockwork Bishop", "Harp Statue", "9 Flowers"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Chessy_6",
        name: "Knight and bishop",
        kind: "random",
        description: "A lone clockwork knight and bishop.",
        contents: ["Clockwork Knight", "Clockwork Bishop"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Warzone_1",
        name: "Pig vs. merm battle",
        kind: "random",
        description: "Four Pig Men and four Merms fighting each other.",
        contents: ["4 Pig Men", "4 Merms"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Warzone_2",
        name: "Merm raid on a pig house",
        kind: "random",
        description: "Three Merms attacking a Pig Man and his house.",
        contents: ["3 Merms", "Pig Man", "Pig House"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    },
    {
        id: "Warzone_3",
        name: "Pig raid on a merm shack",
        kind: "random",
        description: "Four Pig Men attacking a Merm and its Leaky Shack.",
        contents: ["4 Pig Men", "Merm", "Leaky Shack"],
        rare: false,
        maxCount: 4,
        candidateTasks: MAINLAND_TASK_IDS
    }
];

export const SET_PIECES: SetPieceInfo[] = [
    ...BOONS,
    ...TRAPS,
    ...POINTS_OF_INTEREST,
    ...GUARDED_RESOURCES,
    ...LANDMARKS,
    ...RANDOM_SET_PIECES
];

export const TASK_BY_ID: Record<string, TaskInfo> = Object.fromEntries(TASKS.map((task) => [task.id, task]));

export const SET_PIECE_BY_ID: Record<string, SetPieceInfo> = Object.fromEntries(
    SET_PIECES.map((piece) => [piece.id, piece])
);

export const SET_PIECE_KIND_BY_ID = Object.fromEntries(SET_PIECE_KINDS.map((kind) => [kind.id, kind])) as Record<
    SetPieceKind,
    SetPieceKindInfo
>;

export const OPTIONAL_TASKS: TaskInfo[] = TASKS.filter((task) => task.kind === "optional");

export const OPTIONAL_TASK_IDS: string[] = OPTIONAL_TASKS.map((task) => task.id);
