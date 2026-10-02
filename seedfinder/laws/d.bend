import Base
import ../lawkit/maze_layout_probe.bend as MazeLayoutProbe

# Positioned maze layouts against the real game: golden values of the unmodified map/object_layout.lua (Place with a recording
# world and add_fn, run by scripts/harness/bin/lua-dst on the caves' data) under math.randomseed.

# obj_layout.Place({24, 8}, "THREE_WAY_N", add_fn, {"pit_room_armoury", "pit_hallway_armoury", "pit_room_armoury_two"}) under math.randomseed(12) after 40 draws: the FNV-1a of the 18 x 18 tiles set from the position, the entities in order as prefab:x:z in hundredths and the draw count.
law maze_layout_d_matches_the_game:
  {MazeLayoutProbe.case_string(12, 40, "THREE_WAY_N", ["pit_room_armoury", "pit_hallway_armoury", "pit_room_armoury_two"], 24, 8) == "1667237801|4|ruins_statue_head_nogem_spawner:4294892702:4294886708;knight_nightmare_spawner:4294894489:4294888039;bishop_nightmare_spawner:4294894502:4294886583;ruins_statue_mage_spawner:4294892696:4294887796|44" : String}

def maze_layout_d_matches_the_game():
  {==}

# obj_layout.Place({8, 28}, "L_SOUTH", add_fn, {"atrium_hallway", "atrium_hallway_two", "atrium_hallway_three"}) under math.randomseed(5) after 3 draws: the FNV-1a of the 18 x 18 tiles set from the position, the entities in order as prefab:x:z in hundredths and the draw count.
law maze_layout_e_matches_the_game:
  {MazeLayoutProbe.case_string(5, 3, "L_SOUTH", ["atrium_hallway", "atrium_hallway_two", "atrium_hallway_three"], 8, 28) == "3683074699|5|atrium_light:4294887896:4294894896;atrium_light:4294886896:4294895896;atrium_light:4294886696:4294894696;dropperweb:4294887471:4294894533;dropperweb:4294887089:4294894339|7" : String}

def maze_layout_e_matches_the_game():
  {==}
