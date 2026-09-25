import Base
import ../../data/tile_groups.bend as TD

# TileGroupManager predicates of the C++ tile stages and forest_map.lua's ValidateGroundTile.

def within(+t: U32, +lo: U32, +hi: U32) -> Bool:
  (t >= lo : U32) && (t <= hi : U32)

def is_land(+t: U32) -> Bool:
  within(t, TD.land_0_lo(), TD.land_0_hi()) || within(t, TD.land_1_lo(), TD.land_1_hi())

def is_ocean(+t: U32) -> Bool:
  within(t, TD.ocean_0_lo(), TD.ocean_0_hi()) || within(t, TD.ocean_1_lo(), TD.ocean_1_hi())

def is_noise(+t: U32) -> Bool:
  within(t, TD.noise_0_lo(), TD.noise_0_hi()) || within(t, TD.noise_1_lo(), TD.noise_1_hi())

def is_impassable(+t: U32) -> Bool:
  U32.is_eq(t, TD.tile_impassable()) || within(t, TD.impassable_0_lo(), TD.impassable_0_hi())
    || within(t, TD.impassable_1_lo(), TD.impassable_1_hi())

def is_invalid(+t: U32) -> Bool:
  is_impassable(t) || U32.is_eq(t, TD.tile_invalid())

def impassable() -> U32:
  TD.tile_impassable()

def invalid() -> U32:
  TD.tile_invalid()

# ValidateGroundTile: noise tiles become DIRT, other non-land tiles ROCKY.
def validate_ground(+t: U32) -> U32:
  Bool.pick(U32, is_noise(t), TD.tile_dirt(), Bool.pick(U32, is_land(t), t, TD.tile_rocky()))
