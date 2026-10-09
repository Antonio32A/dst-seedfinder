import Base
import ../lawkit/maze_layout_probe.bend as MazeLayoutProbe

# Positioned maze layouts against the real game: golden values of the unmodified map/object_layout.lua (Place with a recording
# world and add_fn, run by scripts/harness/bin/lua-dst on the caves' data) under math.randomseed.

# Positioned maze layouts against the real game: golden values of the unmodified map/object_layout.lua (Place with a recording
# world and add_fn, run by scripts/harness/bin/lua-dst on the caves' data) under math.randomseed.

# obj_layout.Place({10, 10}, "FOUR_WAY", add_fn, {"atrium_hallway"}) under math.randomseed(1) after 0 draws: the FNV-1a of the 18 x 18 tiles set from the position, the entities in order as prefab:x:z in hundredths and the draw count.
law maze_layout_four_way_matches_the_game:
  {MazeLayoutProbe.case_string(1, 0, "FOUR_WAY", ["atrium_hallway"], 10, 10) == "1309828402|12|dropperweb:4294887508:4294888733;dropperweb:4294887952:4294888564;dropperweb:4294887308:4294888233;dropperweb:4294888277:4294887433;dropperweb:4294887614:4294887483;dropperweb:4294888564:4294888746;dropperweb:4294889239:4294888221;dropperweb:4294888077:4294889296;atrium_fence:4294887771:4294888783;atrium_fence:4294887608:4294888564;atrium_fence:4294887433:4294888396;atrium_fence:4294887558:4294888252|4" : String}

def maze_layout_four_way_matches_the_game():
  {==}
