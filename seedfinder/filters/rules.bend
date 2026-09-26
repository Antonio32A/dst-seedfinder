import Base
import ./json.bend as Json
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ./parse.bend as Parse
import ../data/search_vocab.bend as SearchVocab

# Parts B-E of a criteria entry (docs/config.md section 4). A prefab set is a list of distinct
# data/search_vocab.bend prefab ids in first-occurrence order; a tile set is a list of vocabulary tile ids.
type Metric is Data:
  Metric{walk: Bool, wormholes: Bool}

type Near is Data:
  Near{prefabs: List<&2, U32>, within: F64Repr.F64, metric: Metric}

type Count is Data:
  Count{prefabs: List<&2, U32>, min: Maybe<&2, U32>, max: Maybe<&2, U32>, near: Maybe<&2, Near>}

type Distance is Data:
  Distance{from: List<&2, U32>, to: List<&2, U32>, min: Maybe<&2, F64Repr.F64>, max: Maybe<&2, F64Repr.F64>, metric: Metric}

type Tiles is Data:
  Tiles{from: List<&2, U32>, to: List<&2, U32>, max: U32}

type Route is Data:
  Route{from: List<&2, U32>, visit: List<&2, List<&2, U32>>, to: Maybe<&2, List<&2, U32>>, max: F64Repr.F64, fixed: Bool, metric: Metric}

# The counts, distances, tiles and routes rules of one criteria entry.
type Later is Data:
  Later{counts: List<&2, Count>, distances: List<&2, Distance>, tiles: List<&2, Tiles>, routes: List<&2, Route>}

def nothing_later() -> Later:
  Later{Nil{}, Nil{}, Nil{}, Nil{}}

# True when the entry has at least one rule in counts, distances, tiles or routes.
def has_rules(+later: Later) -> Bool:
  match later:
    case Later{+counts, +distances, +tiles, +routes}:
      Bool.not(List.is_empty(&2, Count, counts) && List.is_empty(&2, Distance, distances) && List.is_empty(&2, Tiles, tiles)
        && List.is_empty(&2, Route, routes))

def listed_as_set(json: Json.Json, +kind: String, +path: String) -> Result<&1, &1, U32 & String, List<&2, Json.Json>>:
  match json:
    case Json.JStr{+name}:
      Done{[Json.JStr{name}]}
    case Json.JArr{items}:
      Done{items}
    case _:
      Fail{Parse.failure(path ++ " must be a " ++ kind ++ " or a list of " ++ kind ++ "s")}

def group_hint(+name: String) -> String:
  Bool.pick(String, Parse.is_member(SearchVocab.groups(), name), " (a catalog group name: list its prefab ids)", "")

def prefab_id(found: Maybe<&2, U32>, +name: String, +path: String) -> Result<&1, &1, U32 & String, U32>:
  match found:
    case None{}:
      Fail{Parse.failure("unknown prefab " ++ Parse.quoted(name) ++ " in " ++ path ++ group_hint(name))}
    case Some{id}:
      Done{id}

def prefab_ids(items: List<&2, Json.Json>, +path: String, +i: U32) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, U32>>:
        +name : String <- Parse.string_of(item, Parse.indexed(path, i))
        id : U32 <- prefab_id(Parse.index_of(SearchVocab.prefabs(), name, 0), name, path)
        others : List<&2, U32> <- prefab_ids(rest, path, (i + 1 : U32))
        return id <> others

# A prefab set: an id or a list of 1..16 ids.
def prefab_set(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  do Result<&1, &1, U32 & String, List<&2, U32>>:
    +items : List<&2, Json.Json> <- listed_as_set(json, "prefab id", path)
    +listed : List<&2, Json.Json> <- Parse.nonempty_capped(items, 16, "prefab ids", path)
    +ids : List<&2, U32> <- prefab_ids(listed, path, 0)
    return Parse.distinct(ids)

def tile_names(tiles: List<&2, SearchVocab.Tile>) -> List<&2, String>:
  match tiles:
    case Nil{}:
      Nil{}
    case Con{SearchVocab.Tile{+name, _}, rest}:
      name <> tile_names(rest)

def is_land_id(tiles: List<&2, SearchVocab.Tile>, +id: U32) -> Bool:
  match tiles:
    case Nil{}:
      False{}
    case Con{SearchVocab.Tile{_, +land}, rest}:
      Bool.pick(Bool, U32.is_zero(id), land, is_land_id(rest, (id - 1 : U32)))

def land_tile_id(+id: U32, +name: String, +path: String) -> Result<&1, &1, U32 & String, U32>:
  Bool.pick(Result<&1, &1, U32 & String, U32>, is_land_id(SearchVocab.tiles(), id), Done{id},
    Fail{Parse.failure("tile " ++ Parse.quoted(name) ++ " in " ++ path ++ " is not a land tile")})

def tile_id(found: Maybe<&2, U32>, +name: String, +path: String) -> Result<&1, &1, U32 & String, U32>:
  match found:
    case None{}:
      Fail{Parse.failure("unknown tile " ++ Parse.quoted(name) ++ " in " ++ path)}
    case Some{+id}:
      land_tile_id(id, name, path)

def tile_ids(items: List<&2, Json.Json>, +path: String, +i: U32) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, U32>>:
        +name : String <- Parse.string_of(item, Parse.indexed(path, i))
        id : U32 <- tile_id(Parse.index_of(tile_names(SearchVocab.tiles()), name, 0), name, path)
        others : List<&2, U32> <- tile_ids(rest, path, (i + 1 : U32))
        return id <> others

# A tile set: a land tile name or a list of 1..16 of them.
def tile_set(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  do Result<&1, &1, U32 & String, List<&2, U32>>:
    +items : List<&2, Json.Json> <- listed_as_set(json, "tile name", path)
    +listed : List<&2, Json.Json> <- Parse.nonempty_capped(items, 16, "tiles", path)
    +ids : List<&2, U32> <- tile_ids(listed, path, 0)
    return Parse.distinct(ids)

def required_prefab_set(+fields: List<&2, Json.Json>, +path: String, +key: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  do Result<&1, &1, U32 & String, List<&2, U32>>:
    json : Json.Json <- Parse.required_field(fields, path, key)
    prefab_set(json, path ++ "." ++ key)

def metric_of(+fields: List<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, Metric>:
  do Result<&1, &1, U32 & String, Metric>:
    walk : Bool <- Parse.binary_choice(Parse.field(fields, "metric"), "straight", "walk", path ++ ".metric")
    wormholes : Bool <- Parse.optional_flag(Parse.field(fields, "wormholes"), path ++ ".wormholes")
    return Metric{walk, wormholes}

def near_of(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Near>:
  do Result<&1, &1, U32 & String, Near>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["prefab", "within", "metric", "wormholes"], path)
    prefabs : List<&2, U32> <- required_prefab_set(fields, path, "prefab")
    raw_within : Json.Json <- Parse.required_field(fields, path, "within")
    within : F64Repr.F64 <- Parse.distance(raw_within, path ++ ".within")
    metric : Metric <- metric_of(fields, path)
    return Near{prefabs, within, metric}

def optional_near(m: Maybe<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, Maybe<&2, Near>>:
  match m:
    case None{}:
      Done{None{}}
    case Some{json}:
      do Result<&1, &1, U32 & String, Maybe<&2, Near>>:
        near : Near <- near_of(json, path)
        return Some{near}

def count_of(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Count>:
  do Result<&1, &1, U32 & String, Count>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["prefab", "min", "max", "near"], path)
    prefabs : List<&2, U32> <- required_prefab_set(fields, path, "prefab")
    min : Maybe<&2, U32> <- Parse.optional_integer(Parse.field(fields, "min"), path ++ ".min")
    max : Maybe<&2, U32> <- Parse.optional_integer(Parse.field(fields, "max"), path ++ ".max")
    near : Maybe<&2, Near> <- optional_near(Parse.field(fields, "near"), path ++ ".near")
    return Count{prefabs, min, max, near}

def distance_of(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Distance>:
  do Result<&1, &1, U32 & String, Distance>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["from", "to", "min", "max", "metric", "wormholes"], path)
    from : List<&2, U32> <- required_prefab_set(fields, path, "from")
    to : List<&2, U32> <- required_prefab_set(fields, path, "to")
    min : Maybe<&2, F64Repr.F64> <- Parse.optional_distance(Parse.field(fields, "min"), path ++ ".min")
    max : Maybe<&2, F64Repr.F64> <- Parse.optional_distance(Parse.field(fields, "max"), path ++ ".max")
    metric : Metric <- metric_of(fields, path)
    return Distance{from, to, min, max, metric}

def required_tile_set(+fields: List<&2, Json.Json>, +path: String, +key: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  do Result<&1, &1, U32 & String, List<&2, U32>>:
    json : Json.Json <- Parse.required_field(fields, path, key)
    tile_set(json, path ++ "." ++ key)

def tiles_of(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Tiles>:
  do Result<&1, &1, U32 & String, Tiles>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["from", "to", "max"], path)
    from : List<&2, U32> <- required_tile_set(fields, path, "from")
    to : List<&2, U32> <- required_tile_set(fields, path, "to")
    raw_max : Json.Json <- Parse.required_field(fields, path, "max")
    max : U32 <- Parse.integer(raw_max, path ++ ".max")
    return Tiles{from, to, max}

def stop_sets(stops: List<&2, Json.Json>, +path: String, +i: U32) -> Result<&1, &1, U32 & String, List<&2, List<&2, U32>>>:
  match stops:
    case Nil{}:
      Done{Nil{}}
    case Con{stop, rest}:
      do Result<&1, &1, U32 & String, List<&2, List<&2, U32>>>:
        ids : List<&2, U32> <- prefab_set(stop, Parse.indexed(path ++ ".visit", i))
        others : List<&2, List<&2, U32>> <- stop_sets(rest, path, (i + 1 : U32))
        return ids <> others

def optional_prefab_set(m: Maybe<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, Maybe<&2, List<&2, U32>>>:
  match m:
    case None{}:
      Done{None{}}
    case Some{json}:
      do Result<&1, &1, U32 & String, Maybe<&2, List<&2, U32>>>:
        ids : List<&2, U32> <- prefab_set(json, path)
        return Some{ids}

type Seen is Data:
  Seen{prefab: U32, stop: U32}

def seen_stop(seen: List<&2, Seen>, +prefab: U32) -> Maybe<&2, U32>:
  match seen:
    case Nil{}:
      None{}
    case Con{Seen{+id, +stop}, rest}:
      Bool.pick(Maybe<&2, U32>, U32.is_eq(id, prefab), Some{stop}, seen_stop(rest, prefab))

def prefab_name(+id: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, SearchVocab.prefabs(), U32.to_nat(id)), "")

def unseen(found: Maybe<&2, U32>, +prefab: U32, +stop: U32, +path: String) -> Result<&1, &1, U32 & String, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case Some{+earlier}:
      Fail{Parse.failure(path ++ ": " ++ Parse.quoted(prefab_name(prefab)) ++ " is in both visit[" ++ U32.show(earlier) ++ "] and visit[" ++ U32.show(stop) ++ "]")}

def mark_stop(ids: List<&2, U32>, +stop: U32, +path: String, +seen: List<&2, Seen>) -> Result<&1, &1, U32 & String, List<&2, Seen>>:
  match ids:
    case Nil{}:
      Done{seen}
    case Con{+id, rest}:
      do Result<&1, &1, U32 & String, List<&2, Seen>>:
        fresh : Unit <- unseen(seen_stop(seen, id), id, stop, path)
        mark_stop(rest, stop, path, List.append(&2, Seen, seen, [Seen{id, stop}]))

def mark_stops(stops: List<&2, List<&2, U32>>, +stop: U32, +path: String, +seen: List<&2, Seen>) -> Result<&1, &1, U32 & String, List<&2, Seen>>:
  match stops:
    case Nil{}:
      Done{seen}
    case Con{ids, rest}:
      do Result<&1, &1, U32 & String, List<&2, Seen>>:
        +more : List<&2, Seen> <- mark_stop(ids, stop, path, seen)
        mark_stops(rest, (stop + 1 : U32), path, more)

def shared_names(ends: List<&2, U32>, +seen: List<&2, Seen>, +acc: List<&2, String>) -> List<&2, String>:
  match ends:
    case Nil{}:
      acc
    case Con{+id, rest}:
      shared_names(rest, seen, Bool.pick(List<&2, String>, Maybe.is_some(&2, U32, seen_stop(seen, id)), prefab_name(id) <> acc, acc))

def least_name(names: List<&2, String>, +best: String) -> String:
  match names:
    case Nil{}:
      best
    case Con{+name, rest}:
      least_name(rest, Bool.pick(String, String.is_lt(name, best), name, best))

def endpoint_free(names: List<&2, String>, +path: String) -> Result<&1, &1, U32 & String, Unit>:
  match names:
    case Nil{}:
      Done{Unit{}}
    case Con{+first, +rest}:
      Fail{Parse.failure(path ++ ": " ++ Parse.quoted(least_name(rest, first)) ++ " is both a visit stop and the route's from/to")}

def route_ends(+from: List<&2, U32>, to: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match to:
    case None{}:
      from
    case Some{ids}:
      List.append(&2, U32, from, ids)

# Visit stops are pairwise disjoint and disjoint from `from` and `to` (config.py check_route_stops).
def disjoint_stops(+route: Route, +path: String) -> Result<&1, &1, U32 & String, Route>:
  match route:
    case Route{+from, +visit, +to, _, _, _}:
      do Result<&1, &1, U32 & String, Route>:
        +seen : List<&2, Seen> <- mark_stops(visit, 0, path, Nil{})
        ok : Unit <- endpoint_free(shared_names(route_ends(from, to), seen, Nil{}), path)
        return route

def route_of(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Route>:
  do Result<&1, &1, U32 & String, Route>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["from", "visit", "to", "max", "metric", "wormholes", "order"], path)
    from : List<&2, U32> <- required_prefab_set(fields, path, "from")
    raw_visit : Json.Json <- Parse.required_field(fields, path, "visit")
    stops : List<&2, Json.Json> <- Parse.items_of(raw_visit, path ++ ".visit")
    listed : List<&2, Json.Json> <- Parse.nonempty_capped(stops, 6, "stops", path ++ ".visit")
    visit : List<&2, List<&2, U32>> <- stop_sets(listed, path, 0)
    to : Maybe<&2, List<&2, U32>> <- optional_prefab_set(Parse.field(fields, "to"), path ++ ".to")
    raw_max : Json.Json <- Parse.required_field(fields, path, "max")
    max : F64Repr.F64 <- Parse.distance(raw_max, path ++ ".max")
    fixed : Bool <- Parse.binary_choice(Parse.field(fields, "order"), "any", "fixed", path ++ ".order")
    metric : Metric <- metric_of(fields, path)
    disjoint_stops(Route{from, visit, to, max, fixed, metric}, path)

def section_items(+fields: List<&2, Json.Json>, +path: String, +section: String) -> Result<&1, &1, U32 & String, List<&2, Json.Json>>:
  do Result<&1, &1, U32 & String, List<&2, Json.Json>>:
    +items : List<&2, Json.Json> <- Parse.optional_items(Parse.field(fields, section), path ++ "." ++ section)
    Parse.capped(items, 16, "rules", path ++ "." ++ section)

def counts_of(items: List<&2, Json.Json>, +path: String, +i: U32) -> Result<&1, &1, U32 & String, List<&2, Count>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Count>>:
        rule : Count <- count_of(item, Parse.indexed(path, i))
        others : List<&2, Count> <- counts_of(rest, path, (i + 1 : U32))
        return rule <> others

def distances_of(items: List<&2, Json.Json>, +path: String, +i: U32) -> Result<&1, &1, U32 & String, List<&2, Distance>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Distance>>:
        rule : Distance <- distance_of(item, Parse.indexed(path, i))
        others : List<&2, Distance> <- distances_of(rest, path, (i + 1 : U32))
        return rule <> others

def tiles_rules_of(items: List<&2, Json.Json>, +path: String, +i: U32) -> Result<&1, &1, U32 & String, List<&2, Tiles>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Tiles>>:
        rule : Tiles <- tiles_of(item, Parse.indexed(path, i))
        others : List<&2, Tiles> <- tiles_rules_of(rest, path, (i + 1 : U32))
        return rule <> others

def routes_of(items: List<&2, Json.Json>, +path: String, +i: U32) -> Result<&1, &1, U32 & String, List<&2, Route>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Route>>:
        rule : Route <- route_of(item, Parse.indexed(path, i))
        others : List<&2, Route> <- routes_of(rest, path, (i + 1 : U32))
        return rule <> others

# Parses the counts, distances, tiles and routes sections of an entry's fields, in that order.
def later_of(+fields: List<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, Later>:
  do Result<&1, &1, U32 & String, Later>:
    count_items : List<&2, Json.Json> <- section_items(fields, path, "counts")
    counts : List<&2, Count> <- counts_of(count_items, path ++ ".counts", 0)
    distance_items : List<&2, Json.Json> <- section_items(fields, path, "distances")
    distances : List<&2, Distance> <- distances_of(distance_items, path ++ ".distances", 0)
    tile_items : List<&2, Json.Json> <- section_items(fields, path, "tiles")
    tiles : List<&2, Tiles> <- tiles_rules_of(tile_items, path ++ ".tiles", 0)
    route_items : List<&2, Json.Json> <- section_items(fields, path, "routes")
    routes : List<&2, Route> <- routes_of(route_items, path ++ ".routes", 0)
    return Later{counts, distances, tiles, routes}
