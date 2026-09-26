import Base
import ../../data/tile_groups.bend as TileGroupsData

# TileGroupManager predicates of the C++ tile stages and forest_map.lua's ValidateGroundTile.

def within(+t: U32, +lo: U32, +hi: U32) -> Bool:
  (t >= lo : U32) && (t <= hi : U32)

def is_land(+t: U32) -> Bool:
  within(t, TileGroupsData.land_0_lo(), TileGroupsData.land_0_hi()) || within(t, TileGroupsData.land_1_lo(), TileGroupsData.land_1_hi())

def is_ocean(+t: U32) -> Bool:
  within(t, TileGroupsData.ocean_0_lo(), TileGroupsData.ocean_0_hi()) || within(t, TileGroupsData.ocean_1_lo(), TileGroupsData.ocean_1_hi())

def is_noise(+t: U32) -> Bool:
  within(t, TileGroupsData.noise_0_lo(), TileGroupsData.noise_0_hi()) || within(t, TileGroupsData.noise_1_lo(), TileGroupsData.noise_1_hi())

def is_impassable(+t: U32) -> Bool:
  U32.is_eq(t, TileGroupsData.tile_impassable()) || within(t, TileGroupsData.impassable_0_lo(), TileGroupsData.impassable_0_hi())
    || within(t, TileGroupsData.impassable_1_lo(), TileGroupsData.impassable_1_hi())

def is_invalid(+t: U32) -> Bool:
  is_impassable(t) || U32.is_eq(t, TileGroupsData.tile_invalid())

def impassable() -> U32:
  TileGroupsData.tile_impassable()

def invalid() -> U32:
  TileGroupsData.tile_invalid()

# ValidateGroundTile: noise tiles become DIRT, other non-land tiles ROCKY.
def validate_ground(+t: U32) -> U32:
  Bool.pick(U32, is_noise(t), TileGroupsData.tile_dirt(), Bool.pick(U32, is_land(t), t, TileGroupsData.tile_rocky()))
