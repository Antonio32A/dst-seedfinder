import Base
import ../filters/json.bend as J
import ../filters/walk.bend as WL
import ../filters/anchor.bend as AN
import ../filters/straight.bend as ST
import ../filters/world.bend as WD
import ../f64/repr.bend as FR

# Lane F (filters and search) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: .scratch/port/CONVENTIONS.md "Laws" (tiny U32 golden values, each probed alone first).
# Golden values: Python (json.loads grammar, world.py tile_coordinate, numpy distances as IEEE bits).

law json_number_grammar_accepts_exponent:
  {J.is_number_end(J.number_state("-0.5e+3", 0)) == True{} : Bool}

def json_number_grammar_accepts_exponent():
  {==}

law json_number_grammar_rejects_leading_zero:
  {J.number_state("01", 0) == 9 : U32}

def json_number_grammar_rejects_leading_zero():
  {==}

# world.py tile_coordinate(-512, 425) = 85, (283.99, 425) = 283, (284, 425) = 284 (x in hundredths).
law anchor_tile_coordinate_left:
  {AN.tile_coordinate(4294916096, 425) == 85 : U32}

def anchor_tile_coordinate_left():
  {==}

law anchor_tile_coordinate_edge:
  {AN.tile_coordinate(28399, 425) == 283 : U32}

def anchor_tile_coordinate_edge():
  {==}

# One diagonal step (4*sqrt 2 = 5.65685...) is longer than 5.6568 (q1 = floor(0.6568 * 2^32)).
law walk_diagonal_above_rational:
  {WL.compare(WL.Length{0, 0, 0, 1}, WL.Length{5, 2820934520, 0, 0}) == 2 : U32}

def walk_diagonal_above_rational():
  {==}

law walk_same_diagonals_compare_rational:
  {WL.compare(WL.Length{8, 0, 0, 3}, WL.Length{8, 0, 1, 3}) == 0 : U32}

def walk_same_diagonals_compare_rational():
  {==}

# numpy sqrt((46 - -512)^2 + (402 - -120)^2) = 764.0994699644805 (portal to pigking on world 1).
law straight_distance_portal_pigking:
  {ST.distance(WD.Inst{0, 0, FR.F64{1078394880, 0}, FR.F64{1081679872, 0}, 4600, 40200, 3}, WD.Inst{1, 0, FR.F64{3229614080, 0}, FR.F64{3227385856, 0}, 4294916096, 4294955296, 3}) == FR.F64{1082646731, 3068699398} : FR.F64}

def straight_distance_portal_pigking():
  {==}
