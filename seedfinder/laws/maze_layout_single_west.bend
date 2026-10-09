import Base
import ../lawkit/maze_layout_probe.bend as MazeLayoutProbe

# Positioned maze layouts against the real game: golden values of the unmodified map/object_layout.lua (Place with a recording
# world and add_fn, run by scripts/harness/bin/lua-dst on the caves' data) under math.randomseed.

# Positioned maze layouts against the real game: golden values of the unmodified map/object_layout.lua (Place with a recording
# world and add_fn, run by scripts/harness/bin/lua-dst on the caves' data) under math.randomseed.

# obj_layout.Place({6, 24}, "SINGLE_WEST", add_fn, {"archive_end"}) under math.randomseed(3) after 11 draws: the FNV-1a of the 18 x 18 tiles set from the position, the entities in order as prefab:x:z in hundredths and the draw count.
law maze_layout_single_west_matches_the_game:
  {MazeLayoutProbe.case_string(3, 11, "SINGLE_WEST", ["archive_end"], 6, 24) == "4015603541|14|archive_security_waypoint:4294886502:4294893702;archive_chandelier:4294886477:4294893708;archive_switch:4294886183:4294893696;archive_switch:4294886664:4294893971;archive_switch:4294886683:4294893408;archive_switch_base:4294886489:4294893696;archive_lockbox_dispencer_temp:4294887496:4294893689;archive_lockbox_dispencer_temp:4294886489:4294892696;archive_lockbox_dispencer_temp:4294886496:4294894696;archive_ambient_sfx:4294886934:4294893824;archive_pillar:4294885496:4294894689;archive_pillar:4294885489:4294892696;archive_pillar:4294887496:4294892696;archive_pillar:4294887496:4294894696|18" : String}

def maze_layout_single_west_matches_the_game():
  {==}
