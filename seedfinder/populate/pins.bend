import Base
import ../data/closures.bend as Closures
import ../data/builds.bend as Builds

# The hand-ported closures, each pinned to the game code it ports: the id in data/closures.bend (the same in every
# build) and the fingerprint of a closure variant the port handles, one row per variant when builds differ. A
# regeneration that renumbers or changes a closure breaks the pin (LawsWorldGeneration.ported_closures_line_up) instead
# of leaving the port to count 0 silently. Rows: scripts/gen/closure_pins.py.
type Pin is Data:
  Pin{id: U32, fingerprint: U32}

def is_listed(pins: List<&2, Pin>, +id: U32, +fingerprint: U32) -> Bool:
  match pins:
    case Nil{}:
      False{}
    case Con{Pin{+pinned, +listed}, rest}:
      (U32.is_eq(pinned, id) && U32.is_eq(listed, fingerprint)) || is_listed(rest, id, fingerprint)

def each_listed(+build: Builds.Build, +all: List<&2, Pin>, pins: List<&2, Pin>) -> Bool:
  match pins:
    case Nil{}:
      True{}
    case Con{Pin{+id, _}, rest}:
      is_listed(all, id, Closures.closure_fingerprint(build, id)) && each_listed(build, all, rest)

def line_up(+build: Builds.Build, +pins: List<&2, Pin>) -> Bool:
  each_listed(build, pins, pins)

def is_pinned(pins: List<&2, Pin>, +id: U32) -> Bool:
  match pins:
    case Nil{}:
      False{}
    case Con{Pin{+pinned, _}, rest}:
      U32.is_eq(pinned, id) || is_pinned(rest, id)

def is_ported_category(categories: List<&2, U32>) -> Bool:
  match categories:
    case Nil{}:
      False{}
    case Con{+category, rest}:
      U32.is_eq(category, 1) || U32.is_eq(category, 2) || is_ported_category(rest)

# Every closure of the room (1) and layout area (2) categories, the ones ported by hand, is pinned: a closure that a
# regeneration adds has to be ported and pinned before the proofs pass.
def all_pinned(+build: Builds.Build, n: Nat, +pins: List<&2, Pin>, +id: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      (Bool.not(is_ported_category(Closures.closure_categories(build, id))) || is_pinned(pins, id)) && all_pinned(build, p, pins, (id + 1 : U32))

# counts.bend: the room count closures of countprefabs and countstaticlayouts (66-97; the Halloween ones 66, 67, 78 and 82 count 0 with events disabled) and the caves' 100 and 141-143, and the prefabdata closures 85, 144 and 145.
def room_counts() -> List<&2, Pin>:
  [
    Pin{66, 174856483},
    Pin{67, 1556505063},
    Pin{68, 3756617080},
    Pin{69, 2643160928},
    Pin{70, 3150626357},
    Pin{71, 2091343730},
    Pin{72, 2583317702},
    Pin{73, 971615032},
    Pin{74, 1472448460},
    Pin{75, 1050936477},
    Pin{76, 3103357341},
    Pin{77, 2981764058},
    Pin{78, 3001817498},
    Pin{79, 954386634},
    Pin{80, 4158584623},
    Pin{81, 2669206603},
    Pin{82, 3973861712},
    Pin{83, 2806875068},
    Pin{84, 883618436},
    Pin{85, 2197934726},
    Pin{86, 2702907852},
    Pin{87, 2541343546},
    Pin{88, 1975178788},
    Pin{89, 1788631474},
    Pin{90, 3711590502},
    Pin{91, 2046275582},
    Pin{92, 2130249437},
    Pin{93, 2540936723},
    Pin{94, 217607774},
    Pin{95, 1596172272},
    Pin{96, 1745828564},
    Pin{97, 3909775485},
    Pin{100, 1535741508},
    Pin{141, 2481868297},
    Pin{142, 4256983687},
    Pin{143, 2025470634},
    Pin{144, 836593942},
    Pin{145, 1380369169}
  ]

# layout.bend: the layout area closures of boons.lua (0-23), layouts.lua (25-44), and the caves' 117-122, 132-140.
def layout_areas() -> List<&2, Pin>:
  [
    Pin{0, 17657100},
    Pin{0, 2795307625},
    Pin{1, 1703926460},
    Pin{2, 505030364},
    Pin{3, 3531382424},
    Pin{4, 5188855},
    Pin{4, 3608101107},
    Pin{5, 3082611440},
    Pin{6, 281286396},
    Pin{6, 4259319841},
    Pin{7, 4221329158},
    Pin{7, 1319824574},
    Pin{8, 2195007775},
    Pin{9, 1342917352},
    Pin{10, 1155159405},
    Pin{11, 2403530622},
    Pin{12, 1873028712},
    Pin{13, 2314619736},
    Pin{14, 2478288762},
    Pin{15, 877107766},
    Pin{16, 1498292862},
    Pin{17, 3248346329},
    Pin{18, 1941161665},
    Pin{19, 1448543221},
    Pin{20, 1029678979},
    Pin{21, 4014879959},
    Pin{22, 216786127},
    Pin{23, 3328451696},
    Pin{25, 1469912293},
    Pin{26, 2917047723},
    Pin{27, 851723751},
    Pin{28, 1028356673},
    Pin{29, 771928440},
    Pin{30, 2045876681},
    Pin{31, 3499496693},
    Pin{32, 533263659},
    Pin{33, 538253591},
    Pin{34, 1524692537},
    Pin{35, 1807540115},
    Pin{36, 3474294810},
    Pin{37, 1476185273},
    Pin{38, 3627474620},
    Pin{39, 992883335},
    Pin{40, 3227569123},
    Pin{41, 2969397272},
    Pin{42, 1006294179},
    Pin{43, 2045327520},
    Pin{44, 610691548},
    Pin{117, 61795433},
    Pin{118, 725791138},
    Pin{119, 2094535461},
    Pin{120, 2281266208},
    Pin{121, 2717497842},
    Pin{122, 2140115965},
    Pin{139, 2520797282},
    Pin{140, 2415982983},
    Pin{132, 1695747383},
    Pin{133, 4226768656},
    Pin{134, 3448157450},
    Pin{135, 2681572488},
    Pin{136, 4015825677},
    Pin{137, 2137454257},
    Pin{138, 3760957056}
  ]

# ocean/bunches.bend: the bunch prefab closure of bunches.lua (24), whose results extract_ocean.lua lists for the data and
# for gen_ocean.py's spawner check.
def bunch_prefabs() -> List<&2, Pin>:
  [
    Pin{24, 3510559995}
  ]

def ported() -> List<&2, Pin>:
  List.concat(&2, Pin, [room_counts(), layout_areas(), bunch_prefabs()])

def every_ported_closure_is_pinned(+build: Builds.Build) -> Bool:
  all_pinned(build, U32.to_nat(Closures.closure_count(build)), ported(), 0)

# The pins line up and cover every ported closure in each of the builds.
def hold_in(numbers: List<&2, U32>) -> Bool:
  match numbers:
    case Nil{}:
      True{}
    case Con{+number, rest}:
      line_up(Builds.Build{number}, ported()) && every_ported_closure_is_pinned(Builds.Build{number}) && hold_in(rest)
