import Base
import ../filters/json.bend as Json
import ../filters/walk.bend as Walk
import ../filters/anchor.bend as Anchor
import ../filters/straight.bend as Straight
import ../filters/world.bend as FilterWorld
import ../f64/repr.bend as F64Repr

# Lane F (filters and search) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: tiny U32 golden values, each probed alone first.
# Golden values: Python (json.loads grammar, world.py tile_coordinate, numpy distances as IEEE bits).

law json_number_grammar_accepts_exponent:
  {Json.is_number_end(Json.number_state("-0.5e+3", 0)) == True{} : Bool}

def json_number_grammar_accepts_exponent():
  {==}

law json_number_grammar_rejects_leading_zero:
  {Json.number_state("01", 0) == 9 : U32}

def json_number_grammar_rejects_leading_zero():
  {==}

# world.py tile_coordinate(-512, 425) = 85, (283.99, 425) = 283, (284, 425) = 284 (x in hundredths).
law anchor_tile_coordinate_left:
  {Anchor.tile_coordinate(4294916096, 425) == 85 : U32}

def anchor_tile_coordinate_left():
  {==}

law anchor_tile_coordinate_edge:
  {Anchor.tile_coordinate(28399, 425) == 283 : U32}

def anchor_tile_coordinate_edge():
  {==}

# One diagonal step (4*sqrt 2 = 5.65685...) is longer than 5.6568 (q1 = floor(0.6568 * 2^32)).
law walk_diagonal_above_rational:
  {Walk.compare(Walk.Length{0, 0, 0, 1}, Walk.Length{5, 2820934520, 0, 0}) == 2 : U32}

def walk_diagonal_above_rational():
  {==}

law walk_same_diagonals_compare_rational:
  {Walk.compare(Walk.Length{8, 0, 0, 3}, Walk.Length{8, 0, 1, 3}) == 0 : U32}

def walk_same_diagonals_compare_rational():
  {==}

# numpy sqrt((46 - -512)^2 + (402 - -120)^2) = 764.0994699644805 (portal to pigking on world 1).
law straight_distance_portal_pigking:
  {Straight.distance(FilterWorld.Inst{0, 0, F64Repr.F64{1078394880, 0}, F64Repr.F64{1081679872, 0}, 4600, 40200, 3}, FilterWorld.Inst{1, 0, F64Repr.F64{3229614080, 0}, F64Repr.F64{3227385856, 0}, 4294916096, 4294955296, 3}) == F64Repr.F64{1082646731, 3068699398} : F64Repr.F64}

def straight_distance_portal_pigking():
  {==}
