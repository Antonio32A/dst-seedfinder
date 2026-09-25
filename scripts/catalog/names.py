"""Hand-written display names and groups for the catalog (the game has no names for spawners and markers)."""

PREFAB_NAMES = {
    "antlion_spawner": "Antlion",
    "dragonfly_spawner": "Dragonfly",
    "crabking_spawner": "Crab King",
    "beequeenhive": "Bee Queen (Gigantic Beehive)",
    "moose_nesting_ground": "Moose/Goose nest",
    "deerspawningground": "Klaus / No-Eyed Deer spawning ground",
    "walrus_camp": "MacTusk (Walrus Camp)",
    "leif": "Treeguard",
    "buzzardspawner": "Buzzards (circling)",
    "cookiecutter_spawner": "Cookie Cutters (spawner)",
    "oceanfish_shoalspawner": "Fish shoal",
    "tumbleweedspawner": "Tumbleweeds (spawner)",
    "meteorspawner": "Meteor field",
    "worm_spawner": "Depths Worm (spawner)",
    "seastack_spawner_swell": "Sea Stack cluster (swell)",
    "seastack_spawner_rough": "Sea Stack cluster (rough)",
    "waterplant_spawner_rough": "Sea Weed cluster",
    "wobster_den_spawner_shore": "Wobster Mound cluster",
    "hermithouse_construction1": "Crabby Hermit (Pearl's ruined house)",
    "hermitcrab_marker": "Crabby Hermit island (marker)",
    "hermitcrab_marker_fishing": "Crabby Hermit fishing spot (marker)",
    "hermitcrab_lure_marker": "Crabby Hermit lure spot (marker)",
    "monkeyisland_center": "Monkey Island centre (marker)",
    "monkeyisland_direction": "Monkey Island direction (marker)",
    "monkeyisland_dockgen_safeareacenter": "Monkey Island dock area (marker)",
    "dock_tile_registrator": "Monkey Island dock tile (marker)",
    "moon_altar_astral_marker_1": "Celestial Sanctum Icon spot (marker)",
    "moon_altar_astral_marker_2": "Celestial Sanctum Ward spot (marker)",
    "wagstaff_machinery_marker": "Wagstaff machinery spot (marker)",
    "spawnpoint_master": "Spawn point (master)",
    "spawnpoint_multiplayer": "Spawn point",
    "shadow_container": "Shadow container (pocket dimension, internal)",
    "rabbitkinghorn_container": "Rabbit King horn container (pocket dimension, internal)",
    "burntground_faded": "Scorched ground (faded)",
    "scorchedground": "Scorched ground",
    "sculpture_rook": "Suspicious Marble (Rook)",
    "sculpture_knight": "Suspicious Marble (Knight)",
    "sculpture_bishop": "Suspicious Marble (Bishop)",
    "statue_marble_muse": "Marble Sculpture (muse)",
    "statue_marble_pawn": "Marble Sculpture (pawn)",
    "statue_marble": "Marble Sculpture (vase)",
    "gargoyle_houndatk": "Suspicious Moonrock (hound, attacking)",
    "gargoyle_hounddeath": "Suspicious Moonrock (hound, dying)",
    "gargoyle_werepighowl": "Suspicious Moonrock (werepig, howling)",
    "bullkelp_beachedroot": "Beached Bull Kelp Stalk",
    "driftwood_small1": "Driftwood (small 1)",
    "driftwood_small2": "Driftwood (small 2)",
    "driftwood_tall": "Driftwood (tall)",
    "mast_broken": "Broken Mast",
    "oasis_cactus": "Cactus (oasis)",
    "oceanvine_deco": "Mossy Vine (decoration)",
    "sapling_moon": "Sapling (lunar)",
    "flower_rose": "Rose",
    "moon_tree_blossom_worldgen": "Lune Tree (blossoming)",
    "mushtree_tall_stump": "Blue Mushtree (stump)",
    "flower_cave_double": "Light Flower (double)",
    "flower_cave_triple": "Light Flower (triple)",
    "multiplayer_portal": "Florid Postern (spawn portal)",
    "twiggy_normal": "Twiggy Tree (normal)",
    "twiggy_tall": "Twiggy Tree (tall)",
}

QUALIFIERS = {
    "rock1": "flint",
    "rock2": "gold",
    "rock_flintless": "flintless",
    "rock_moon": "moon rock",
    "berrybush": "regular",
    "berrybush2": "variant 2",
    "sanityrock": "sane",
    "insanityrock": "insane",
    "pond": "frog",
    "pond_mos": "mosquito",
    "marsh_bush": "marsh",
    "burnt_marsh_bush": "burnt",
    "beebox_hermit": "Crabby Hermit",
    "meatrack_hermit": "Crabby Hermit",
    "carrat_planted": "Carrat",
    "boatfragment03": "3",
    "boatfragment04": "4",
    "boatfragment05": "5",
    "moon_altar_rock_glass": "Celestial Altar base",
    "moon_altar_rock_idol": "Celestial Altar idol",
    "moon_altar_rock_seed": "Celestial Altar orb",
    "evergreen_sparse": "lumpy",
}

VARIANT_BASES = [
    "evergreen_sparse", "evergreen", "deciduoustree", "twiggy", "moon_tree", "palmconetree", "driftwood",
    "flower_cave", "statue_marble", "sculpture", "gargoyle", "seastack_spawner", "boatfragment",
    "berrybush", "singingshell_octave", "moon_altar_rock", "moon_altar_astral_marker", "oceanfishinglure",
    "oceanfishingbobber", "spoiled_fish", "junk_pile", "hermitcrab", "monkeyisland",
]

VARIANT_GROUPS = {
    "rock1": "rock", "rock2": "rock", "rock_flintless": "rock", "rock_moon": "rock",
    "berrybush": "berrybush", "berrybush2": "berrybush", "berrybush_juicy": "berrybush",
    "twiggytree": "twiggy", "twiggy_normal": "twiggy", "twiggy_tall": "twiggy",
    "evergreen": "evergreen", "evergreen_sparse": "evergreen_sparse",
    "moon_tree": "moon_tree", "pond": "pond", "pond_mos": "pond",
    "sculpture_rook": "sculpture", "sculpture_knight": "sculpture", "sculpture_bishop": "sculpture",
    "statue_marble": "statue_marble",
}


ICON_OVERRIDES = {
    "rock1": "rock.png",
    "rock2": "rock_gold.png",
    "moonglass_rock": "rock_moonglass.png",
    "evergreen_normal": "evergreen.png",
    "evergreen_short": "evergreen.png",
    "evergreen_tall": "evergreen.png",
    "evergreen_sparse": "evergreen_lumpy.png",
    "evergreen_stump": "evergreen_stump.png",
    "twiggy_normal": "twiggy.png",
    "twiggy_tall": "twiggy.png",
    "deciduoustree_stump": "tree_leaf_stump.png",
    "twiggytree": "twiggy.png",
    "hermithouse_construction1": "hermitcrab_home.png",
    "beebox_hermit": "beebox_hermitcrab.png",
    "cave_entrance": "cave_closed.png",
    "sculpture_rook": "sculpture_rookbody_full.png",
    "sculpture_knight": "sculpture_knightbody_full.png",
    "sculpture_bishop": "sculpture_bishopbody_full.png",
    "moon_altar_rock_glass": "moon_altar_glass_rock.png",
    "moon_altar_rock_idol": "moon_altar_idol_rock.png",
    "moon_altar_rock_seed": "moon_altar_seed_rock.png",
    "antlion_spawner": "antlion.png",
    "deerspawningground": "klaus_sack.png",
    "flower_cave": "bulb_plant.png",
    "flower_cave_double": "bulb_plant.png",
    "flower_cave_triple": "bulb_plant.png",
}


def variant_base(prefab):
    """The id this prefab is a variant of (for grouping in the UI), or None."""
    if prefab in VARIANT_GROUPS:
        return VARIANT_GROUPS[prefab]
    for base in VARIANT_BASES:
        if prefab.startswith(base + "_") or (prefab.startswith(base) and prefab[len(base):].isdigit()):
            return base
    return None


def _group(names, group):
    return {n: group for n in names.split()}


GROUPS = {}
GROUPS.update(_group("multiplayer_portal spawnpoint_master spawnpoint_multiplayer wormhole cave_entrance", "spawn & travel"))
GROUPS.update(_group("dragonfly_spawner antlion_spawner crabking_spawner beequeenhive moose_nesting_ground "
                     "deerspawningground leif monkeyqueen hermithouse_construction1 walrus_camp", "bosses & spawners"))
GROUPS.update(_group("rook knight bishop", "clockwork"))
GROUPS.update(_group("sculpture_rook sculpture_knight sculpture_bishop", "sculptures"))
GROUPS.update(_group("statue_marble statue_marble_muse statue_marble_pawn statuemaxwell statueharp marblepillar marbletree "
                     "gargoyle_houndatk gargoyle_hounddeath gargoyle_werepighowl", "statues"))
GROUPS.update(_group("pigking moonbase critterlab statueglommer oasislake balatro_machine charlie_stage_post "
                     "statueharp_hedgespawner terrariumchest junk_pile_big junk_pile storage_robot resurrectionstone "
                     "moon_altar_rock_glass moon_altar_rock_idol moon_altar_rock_seed moon_fissure moon_fissure_plugged "
                     "livingtree chester_eyebone hotspring wagstaff_machinery_marker stagehand lava_pond "
                     "oceanwhirlbigportal sunkenchest monkeyisland_portal monkeyisland_portal_debris "
                     "moon_altar_astral_marker_1 moon_altar_astral_marker_2", "landmarks"))
GROUPS.update(_group("evergreen evergreen_sparse evergreen_normal evergreen_short evergreen_tall evergreen_stump "
                     "deciduoustree deciduoustree_stump twiggytree twiggy_normal twiggy_tall marsh_tree moon_tree "
                     "moon_tree_blossom_worldgen moon_tree_normal moon_tree_short moon_tree_tall palmconetree_normal "
                     "palmconetree_short palmconetree_tall mushtree_tall_stump driftwood_small1 driftwood_small2 "
                     "driftwood_tall oceantree watertree_pillar watertree_root", "trees"))
GROUPS.update(_group("rock1 rock2 rock_flintless rock_moon rock_ice moonglass_rock basalt seastack saltstack "
                     "moonrock_pieces", "rocks"))
GROUPS.update(_group("grass grassgekko sapling sapling_moon berrybush berrybush2 berrybush_juicy reeds flower flower_evil "
                     "flower_rose flower_cave flower_cave_double flower_cave_triple carrot_planted mandrake_planted cactus "
                     "oasis_cactus marsh_bush burnt_marsh_bush red_mushroom green_mushroom blue_mushroom rock_avocado_bush "
                     "bananabush monkeytail pumpkin farm_plant_pumpkin wormlight_plant trap_starfish fireflies bullkelp_plant "
                     "bullkelp_beachedroot waterplant oceanvine oceanvine_deco", "plants"))
GROUPS.update(_group("beefalo lightninggoat pigman merm spider_warrior firehound icehound bat fruitdragon carrat_planted "
                     "lightcrab tentacle pighouse mermhouse spiderden moonspiderden rabbithole molehill beehive wasphive "
                     "tallbirdnest houndmound catcoonden pond pond_mos monkeyhut monkeypillar boat_otterden "
                     "oceanvine_cocoon wobster_den moonglass_wobster_den buzzardspawner oceanfish_shoalspawner "
                     "cookiecutter_spawner worm_spawner tumbleweedspawner", "mobs & dens"))
GROUPS.update(_group("seastack_spawner_swell seastack_spawner_rough waterplant_spawner_rough wobster_den_spawner_shore "
                     "boatfragment03 boatfragment04 boatfragment05 messagebottle driftwood_log boat mast_broken boat_pirate "
                     "boat_cannon dead_sea_bones shell_cluster", "ocean"))
GROUPS.update(_group("dock_tile_registrator monkeyisland_center monkeyisland_direction monkeyisland_dockgen_safeareacenter "
                     "hermitcrab_marker hermitcrab_marker_fishing hermitcrab_lure_marker shadow_container "
                     "rabbitkinghorn_container burntground_faded scorchedground meteorspawner", "markers"))
GROUPS.update(_group("pigtorch wall_hay wall_wood wall_stone cookpot meatrack meatrack_hermit firepit tent researchlab "
                     "researchlab2 researchlab3 beebox beebox_hermit treasurechest tacklecontainer skeleton scorched_skeleton "
                     "gravestone mound insanityrock sanityrock mermhead pighead houndbone dock_woodposts pirate_flag_pole "
                     "winterometer birdtrap", "structures"))

GROUPS.update(_group("twigs flint rocks goldnugget moonglass moonrocknugget marble cutgrass log singingshell_octave3 "
                     "singingshell_octave4 singingshell_octave5 pumpkin_lantern", "items"))
GROUPS.update(_group("playing_card", "set-piece loot"))

TASK_NAMES = {
    "Make a pick": "Make a Pick (spawn: grass and forest)",
    "Dig that rock": "Dig That Rock (rocky, graveyard, Rock Den)",
    "Great Plains": "Great Plains (savanna, beefalo)",
    "Squeltch": "Squeltch (marsh, merms)",
    "Beeeees!": "Beeeees! (bee meadow, Bee Queen)",
    "Speak to the king": "Speak to the King (Pig King, birchnut forest)",
    "Forest hunters": "Forest Hunters (forest, Moon Stone, MacTusk)",
    "Badlands": "Badlands (desert, Dragonfly)",
    "For a nice walk": "For a Nice Walk (forest, mandrakes)",
    "Lightning Bluff": "Lightning Bluff (oasis desert, Antlion)",
    "MoonIsland_IslandShards": "Lunar Island: Shards",
    "MoonIsland_Beach": "Lunar Island: Beach",
    "MoonIsland_Forest": "Lunar Island: Forest",
    "MoonIsland_Baths": "Lunar Island: Hot Springs",
    "MoonIsland_Mine": "Lunar Island: Mine (Celestial Altar)",
    "Befriend the pigs": "Befriend the Pigs (pig village)",
    "Kill the spiders": "Kill the Spiders (spider village)",
    "Killer bees!": "Killer Bees! (killer bee nests)",
    "Make a Beehat": "Make a Beehat (flowers and rocks)",
    "The hunters": "The Hunters (MacTusk camps)",
    "Magic meadow": "Magic Meadow (ponds)",
    "Frogs and bugs": "Frogs and Bugs (ponds, bees, moles)",
    "Mole Colony Deciduous": "Mole Colony (birchnut)",
    "Mole Colony Rocks": "Mole Colony (rocky)",
    "MooseBreedingTask": "Moose/Goose Breeding Grounds",
}

TILE_NAMES = {
    "DIRT": "Dirt",
    "IMPASSABLE": "Impassable",
    "ROAD": "Road",
    "OCEAN_COASTAL": "Ocean (coastal)",
    "OCEAN_COASTAL_SHORE": "Ocean (shore)",
    "OCEAN_SWELL": "Ocean (swell)",
    "OCEAN_ROUGH": "Ocean (rough)",
    "OCEAN_BRINEPOOL": "Ocean (brine pool)",
    "OCEAN_BRINEPOOL_SHORE": "Ocean (brine pool shore)",
    "OCEAN_HAZARDOUS": "Ocean (hazardous)",
    "OCEAN_WATERLOG": "Ocean (waterlogged)",
    "OCEAN_ICE": "Ocean (ice)",
    "MONKEY_DOCK": "Monkey Island dock",
    "FARMING_SOIL": "Farm soil",
}

SETTING_LABELS = {"traps": "Traps", "poi": "Points of interest", "protected": "Protected resources"}

SWAP_LABELS = {"grass": "Grass", "twigs": "Twigs", "berries": "Berries"}

SETPIECE_NAMES = {
    "WoodBoon": "Skeleton: axe or shovel + logs",
    "RockBoon": "Skeleton: pickaxe/boulder/gunpowder + rocks",
    "GrassBoon": "Skeleton: torch or trap + cut grass",
    "TwigsBoon": "Skeleton: twigs loot",
    "Level2WoodBoon": "Skeleton: wood tier 2 (log suit, boards)",
    "Level2RockBoon": "Skeleton: rock tier 2 (cut stone)",
    "Level2GrassBoon": "Skeleton: grass tier 2 (rope)",
    "Level2TwigsBoon": "Skeleton: twigs tier 2 (grass suit)",
    "MiscBoon": "Skeleton: clothing (hats, vests, cane)",
    "WeaponBoon": "Skeleton: weapon (darts, boomerang)",
    "CookingBoon": "Skeleton: cooking (crock pot, cookbook)",
    "FarmingBoon": "Skeleton: farming (garden tools)",
    "FishingBoon": "Skeleton: sea fishing gear",
    "Level4Boon": "Skeleton: rare loot (staff, marble suit, ...)",
    "Sleeping Spider": "Trap: sleeping spider warriors",
    "Rotted Base": "Trap: rotted base",
    "Beefalo Farm": "Trap: beefalo farm (explosive chest)",
    "Fire Hounds": "Trap: fire hounds and a fire staff",
    "Ice Hounds": "Trap: ice hounds and an ice staff",
    "Dev Graveyard": "Trap: dev graveyard",
    "ResurrectionStone": "Touch Stone",
    "WormholeGrass": "Worm Hole",
    "MooseNest": "Moose/Goose nest",
    "CaveEntrance": "Sinkhole (cave entrance)",
    "MoonAltarRockGlass": "Celestial Altar base (Inviting Formation)",
    "MoonAltarRockIdol": "Celestial Altar idol (Inviting Formation)",
    "MoonAltarRockSeed": "Celestial Altar orb (Inviting Formation)",
    "BathbombedHotspring": "Bath-bombed hot spring",
    "MoonFissures": "Celestial Fissures",
    "Sculptures_1": "Sculptures 1 (all three Suspicious Marbles)",
    "Maxwell5": "Maxwell statue with harps",
    "leif_forest": "Protected: Treeguard forest",
    "spider_forest": "Protected: spider forest",
    "hound_rocks": "Protected: hound mound rocks",
    "tenticle_reeds": "Protected: tentacle reeds",
    "pigguard_grass_easy": "Protected: pig guards on grass (easy)",
    "pigguard_grass": "Protected: pig guards on grass",
    "tallbird_rocks": "Protected: tallbird rocks",
    "pigguard_berries_easy": "Protected: pig guards on berries (easy)",
    "wasphive_grass_easy": "Protected: killer bee hive on grass",
    "pigguard_berries": "Protected: pig guards on berries",
    "lures_and_worms": "Protected: lures and worms (caves)",
    "grass_spots": "POI: grass spots",
}


def setpiece_name(name):
    if name in SETPIECE_NAMES:
        return SETPIECE_NAMES[name]
    if name.startswith("skeleton_"):
        return "POI: skeleton (" + name[len("skeleton_"):].replace("_", " ") + ")"
    return name.replace("_", " ")
