name = "Ground Truth Worldgen"
description = "Worldgen-only research mod. The server's own forest is generated from the first configured seed, and the remaining seeds are generated right after it in the same worldgen run. Every finished world (tasks, set pieces, topology, tiles, entities, RNG checkpoints) is printed to the server log as GTWORLD lines."
author = "dst-seedfinder"
version = "1.0"

api_version_dst = 10
priority = 0

dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
dst_compatible = true

all_clients_require_mod = false
client_only_mod = false
server_only_mod = true

local function option(value, label)
    return { description = label or value, data = value }
end

configuration_options = {
    {
        name = "seeds",
        label = "Seeds",
        hover = "Comma separated seeds or ranges. The first seed becomes the server's own world.",
        options = {
            option("1-10"),
            option("11-20"),
            option("1-3"),
            option("1"),
            option("2"),
            option("3"),
            option("4"),
            option("5"),
            option("6"),
            option("7"),
            option("8"),
            option("9"),
            option("10"),
        },
        default = "1-10",
    },
    {
        name = "loop",
        label = "Generate the other seeds",
        hover = "Yes: generate every seed in one run (WorldSim:ResetAll between worlds). No: only the first seed, the way a normal launch would.",
        options = { option(true, "Yes"), option(false, "No") },
        default = false,
    },
    {
        name = "replay_first",
        label = "Replay the first seed",
        hover = "Generate the first seed again at the end of the loop, to check that looped worlds match a fresh launch.",
        options = { option(true, "Yes"), option(false, "No") },
        default = false,
    },
    {
        name = "chunk_size",
        label = "Log line size",
        hover = "Characters of JSON per GTWORLD log line. Lower it if the server log cuts long lines short.",
        options = { option(3000, "3000"), option(2000, "2000"), option(1000, "1000"), option(500, "500") },
        default = 3000,
    },
}
