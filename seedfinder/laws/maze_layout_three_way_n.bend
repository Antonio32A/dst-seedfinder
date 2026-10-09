import Base
import ../lawkit/maze_layout_probe.bend as MazeLayoutProbe

# Positioned maze layouts against the real game: golden values of the unmodified map/object_layout.lua (Place with a recording
# world and add_fn, run by scripts/harness/bin/lua-dst on the caves' data) under math.randomseed.

# obj_layout.Place({24, 8}, "THREE_WAY_N", add_fn, {"pit_room_armoury", "pit_hallway_armoury", "pit_room_armoury_two"}) under math.randomseed(12) after 40 draws: the FNV-1a of the 18 x 18 tiles set from the position, the entities in order as prefab:x:z in hundredths and the draw count.
law maze_layout_three_way_n_matches_the_game:
  {MazeLayoutProbe.case_string(12, 40, "THREE_WAY_N", ["pit_room_armoury", "pit_hallway_armoury", "pit_room_armoury_two"], 24, 8) == "1667237801|4|ruins_statue_head_nogem_spawner:4294892702:4294886708;knight_nightmare_spawner:4294894489:4294888039;bishop_nightmare_spawner:4294894502:4294886583;ruins_statue_mage_spawner:4294892696:4294887796|44" : String}

def maze_layout_three_way_n_matches_the_game():
  {==}
