import Base
import ../rng/pcg.bend as R
import ../f64/repr.bend as FR
import ../trace/canon.bend as CN
import ../level/summary.bend as W
import ../data/strings.bend as ST
import ../worldsim/grid.bend as GR
import ../worldsim/tiles/input.bend as TN
import ./rows.bend as ORW
import ./ents.bend as OE
import ./state.bend as OS
import ./post.bend as OT
import ./ocean.bend as OO

# Lane G's ocean trace stage `oceanpost` (.scratch/port/status/M10.md): from the oracle's land_done state (`oin`,
# `orow at="land"`, `oent`, `oreq`), the prefill, then the oracle's grid after the conversion (`orow at="void"`,
# `odig at="void"` for the counter) and everything after it; prints the oracle's `ocean` records of those steps.

def names_loop(n: Nat, m: Map<&2, U32>, +i: U32) -> Map<&2, U32>:
  match n:
    case 0n:
      m
    case 1n+p:
      names_loop(p, Map.set(&2, U32, m, ST.name(i), i), (i + 1 : U32))

# Every constant string's id by name.
def names() -> Map<&2, U32>:
  names_loop(U32.to_nat(ST.strings_count()), Map.new(&2, U32), 0)

def unquoted(+s: String) -> String:
  String.from_list(List.reverse(&2, Char, List.drop(&2, Char, List.reverse(&2, Char, List.drop(&2, Char, String.to_list(s), 1n)), 1n)))

def got_id(got: Map<&2, U32> & U32) -> U32:
  (_, +id) = got
  id

def id_of(+m: Map<&2, U32>, +name: String) -> U32:
  got_id(Map.get(U32, 4294967295, m, unquoted(name)))

def ents_loop(recs: List<&2, List<&2, String>>, +m: Map<&2, U32>, +acc: List<&2, OE.Ent>) -> List<&2, OE.Ent>:
  match recs:
    case Nil{}:
      acc
    case Con{+fields, rest}:
      +e = {OE.Ent{id_of(m, TN.text("prefab", fields)), TN.f64_field("x", fields), TN.f64_field("z", fields), 0, 0} : OE.Ent}
      ents_loop(rest, m, e <> acc)

def reqs_loop(recs: List<&2, List<&2, String>>, +m: Map<&2, U32>) -> List<&2, OT.Req>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      OT.Req{id_of(m, TN.text("prefab", fields)), TN.num("count", fields)} <> reqs_loop(rest, m)

def f64_text(+x: FR.F64) -> String:
  match x:
    case FR.F64{+hi, +lo}:
      CN.hex64(hi, lo)

def hash_text(+h: GR.Hash) -> String:
  match h:
    case GR.Hash{+hi, +lo}:
      CN.hex64(hi, lo)

def prefab_text(+id: U32) -> String:
  CN.quoted(ST.name(id))

# What the records share: seed, attempt, map size, and the running opieces / oadd indices.
type Out is Data:
  Out{seed: U32, a: String, w: U32, h: U32, pieces: U32, adds: U32}

def ctr(+o: Out, +rng: R.Rng) -> U32:
  match o:
    case Out{+seed, _, _, _, _, _}:
      R.counter(seed, rng)

def attempt_field(+o: Out) -> String:
  match o:
    case Out{_, +a, _, _, _, _}:
      CN.field("a", a)

def digest_name(+at: U32) -> String:
  match at:
    case 0:
      "prefill"
    case 1:
      "fills"
    case 2:
      "noise"
    case 3:
      "blend"
    case 4:
      "shoreline"
    case 5:
      "void"
    case 6:
      "populate"
    case 7:
      "docks"
    case 8:
      "post"
    case 9:
      "bunches"
    case _:
      "encoded"

def digest_line(+o: Out, +at: U32, +rng: R.Rng, +tiles: GR.Hash, +mflags: GR.Hash, +ids: GR.Hash) -> String:
  match o:
    case Out{_, _, +w, +h, _, _}:
      CN.record("odig", [attempt_field(o), CN.field("at", CN.quoted(digest_name(at))), CN.number("ctr", ctr(o, rng)),
        CN.number("w", w), CN.number("h", h), CN.field("tiles", hash_text(tiles)), CN.field("mflags", hash_text(mflags)),
        CN.field("ids", hash_text(ids))])

def pieces_line(+o: Out, +tile: U32, +total: U32, +before: R.Rng, +after: R.Rng) -> String:
  match o:
    case Out{_, _, _, _, +k, _}:
      CN.record("opieces", [attempt_field(o), CN.number("k", k), CN.number("tile", tile), CN.number("total", total),
        CN.number("before", ctr(o, before)), CN.number("after", ctr(o, after))])

def add_line(+o: Out, +prefab: U32, +tx: FR.F64, +ty: FR.F64, +x: FR.F64, +z: FR.F64, +after: R.Rng) -> String:
  match o:
    case Out{_, _, _, _, _, +k}:
      CN.record("oadd", [attempt_field(o), CN.number("k", k), CN.field("prefab", prefab_text(prefab)), CN.field("tx", f64_text(tx)),
        CN.field("ty", f64_text(ty)), CN.field("x", f64_text(x)), CN.field("z", f64_text(z)), CN.number("after", ctr(o, after))])

def bumped(+o: Out, +pieces: U32, +adds: U32) -> Out:
  match o:
    case Out{+seed, +a, +w, +h, +p, +d}:
      Out{seed, a, w, h, (p + pieces : U32), (d + adds : U32)}

def entity_line(+kind: String, +o: Out, +e: OE.Ent, +k: U32) -> String:
  match e:
    case OE.Ent{+prefab, +x, +z, _, _}:
      CN.record(kind, [attempt_field(o), CN.field("prefab", prefab_text(prefab)), CN.number("k", k), CN.field("x", f64_text(x)),
        CN.field("z", f64_text(z))])

def counters() -> Array<U32>:
  [0 : U32^11n]

def keep_line(on: Bool, +line: String, acc: List<&2, String>) -> List<&2, String>:
  match on:
    case True{}:
      line <> acc
    case False{}:
      acc

def indexed_loop(xs: List<&2, OE.Ent>, got: Array<U32> & U32, +kind: String, +o: Out, +i: U32, +from: U32, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{OE.Ent{+prefab, +x, +z, +id, +target}, +rest}:
      (counts, +k) = got
      +e = {OE.Ent{prefab, x, z, id, target} : OE.Ent}
      counts[prefab] <- (k + 1 : U32)
      +next_prefab = OE.prefab_of(Maybe.default(&2, OE.Ent, List.head(&2, OE.Ent, rest), e))
      indexed_loop(rest, counts[next_prefab], kind, o, (i + 1 : U32), from, keep_line((i >= from : U32), entity_line(kind, o, e, k), acc))

# Records of kind `kind` for the entities (newest first) from position `from` (oldest first), k = index in its
# prefab's list.
def entity_lines(+kind: String, +o: Out, +ents: List<&2, OE.Ent>, +from: U32) -> List<&2, String>:
  +oldest = List.reverse(&2, OE.Ent, ents)
  +first = OE.prefab_of(Maybe.default(&2, OE.Ent, List.head(&2, OE.Ent, oldest), OE.Ent{0, FR.zero(), FR.zero(), 0, 0}))
  indexed_loop(oldest, counters()[first], kind, o, 0, from, Nil{})

def count_line(nonzero: Bool, +o: Out, +at: String, +i: U32, +c: U32, acc: List<&2, String>) -> List<&2, String>:
  match nonzero:
    case False{}:
      acc
    case True{}:
      CN.record("ocount", [attempt_field(o), CN.field("at", CN.quoted(at)), CN.field("prefab", prefab_text(i)), CN.number("n", c)]) <> acc

def count_lines(n: Nat, got: Array<U32> & U32, +o: Out, +at: String, +i: U32, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+p:
      (counts, +c) = got
      count_lines(p, counts[(i + 1 : U32)], o, at, (i + 1 : U32), count_line(U32.is_ne(c, 0), o, at, i, c, acc))

def bump(got: Array<U32> & U32, +i: U32) -> Array<U32>:
  (counts, +c) = got
  counts[i] <- (c + 1 : U32)

def tally(xs: List<&2, OE.Ent>, counts: Array<U32>) -> Array<U32>:
  match xs:
    case Nil{}:
      counts
    case Con{+e, rest}:
      tally(rest, bump(counts[OE.prefab_of(e)], OE.prefab_of(e)))

def counts_lines(+o: Out, +at: String, +ents: List<&2, OE.Ent>) -> List<&2, String>:
  counts = tally(ents, counters())
  count_lines(U32.to_nat(ST.strings_count()), counts[0], o, at, 0, Nil{})

def wormhole_lines(xs: List<&2, OE.Ent>, +o: Out, +k: U32) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{OE.Ent{_, +x, +z, +id, +target}, rest}:
      CN.record("owormhole", [attempt_field(o), CN.number("k", k), CN.field("x", f64_text(x)), CN.field("z", f64_text(z)),
        CN.number("id", id), CN.number("target", target)]) <> wormhole_lines(rest, o, (k + 1 : U32))

def span_line(+kind: String, +o: Out, +before: R.Rng, +after: R.Rng) -> String:
  CN.record(kind, [attempt_field(o), CN.number("before", ctr(o, before)), CN.number("after", ctr(o, after))])

def added_lines(+kind: String, +span: String, +o: Out, +before: R.Rng, +after: R.Rng, +ents: List<&2, OE.Ent>, +added: U32) -> List<&2, String>:
  +total = U32.from_nat(List.length(&2, OE.Ent, ents))
  span_line(span, o, before, after) <> entity_lines(kind, o, ents, (total - added : U32))

def names_text(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+id, Nil{}}:
      ST.name(id)
    case Con{+id, rest}:
      ST.name(id) ++ "," ++ names_text(rest)

def missing_text(+xs: List<&2, U32>) -> String:
  Bool.pick(String, List.is_empty(&2, U32, xs), "none", CN.quoted(names_text(xs)))

def status_line(+o: Out, +ok: Bool, +missing: List<&2, U32>, +rng: R.Rng) -> String:
  CN.record("ostatus", [attempt_field(o), CN.number("ok", Bool.to_u32(ok)), CN.field("missing", missing_text(missing)),
    CN.number("ctr", ctr(o, rng))])

def req_line(+o: Out, +prefab: U32, +count: U32, +have: U32) -> String:
  CN.record("oreq", [attempt_field(o), CN.field("prefab", prefab_text(prefab)), CN.number("count", count), CN.number("have", have)])

def blend_line(+o: Out, +k: U32, +hash: GR.Hash) -> String:
  match o:
    case Out{_, _, +w, +h, _, _}:
      CN.record("oblend", [attempt_field(o), CN.number("k", k), CN.number("n", (w * h : U32)), CN.field("hash", hash_text(hash))])

def snapshot_name(+at: U32) -> String:
  Bool.pick(String, U32.is_zero(at), "populate", "filter")

def event_lines(evs: List<&2, OS.Ev>, +o: Out) -> List<&2, String>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case OS.EDigest{+at, +rng, +tiles, +mflags, +ids}:
          digest_line(o, at, rng, tiles, mflags, ids) <> event_lines(rest, o)
        case OS.EBlend{+k, +hash}:
          blend_line(o, k, hash) <> event_lines(rest, o)
        case OS.EPieces{+tile, +total, +before, +after}:
          pieces_line(o, tile, total, before, after) <> event_lines(rest, bumped(o, 1, 0))
        case OS.EAdd{+prefab, +tx, +ty, +x, +z, +after}:
          add_line(o, prefab, tx, ty, x, z, after) <> event_lines(rest, bumped(o, 0, 1))
        case OS.ECounts{+at, +ents}:
          List.append(&2, String, counts_lines(o, snapshot_name(at), ents), event_lines(rest, o))
        case OS.EDocks{+before, +after, +ents, +added}:
          List.append(&2, String, added_lines("odock", "odocks", o, before, after, ents, added), event_lines(rest, o))
        case OS.EWormholes{+ents}:
          List.append(&2, String, wormhole_lines(ents, o, 0), event_lines(rest, o))
        case OS.EBunches{+before, +after, +ents, +added}:
          List.append(&2, String, added_lines("obunch", "obunches", o, before, after, ents, added), event_lines(rest, o))
        case OS.EFinal{+ents}:
          List.append(&2, String, entity_lines("ofinal", o, ents, 0), event_lines(rest, o))
        case OS.EReq{+prefab, +count, +have}:
          req_line(o, prefab, count, have) <> event_lines(rest, o)
        case OS.EStatus{+ok, +missing, +rng}:
          status_line(o, ok, missing, rng) <> event_lines(rest, o)

def sea_lines(got: OS.Sea & Bool, +o: Out) -> List<&2, String>:
  (s, _) = got
  match s:
    case OS.Sea{_, _, _, _, _, +events}:
      event_lines(List.reverse(&2, OS.Ev, events), o)

def swaps_of(+level: W.Summary) -> U32:
  match level:
    case W.Summary{+swaps, _, _, _, _, _, _}:
      swaps

def with_void(s: OS.Sea, void: GR.Grid, +rng: R.Rng) -> OS.Sea:
  match s:
    case OS.Sea{_, ids, _, +ents, +topo, +events}:
      OS.Sea{void, ids, rng, ents, topo, events}

def post_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +input = ORW.input(a, lines)
  +w = TN.num("w", input)
  +h = TN.num("h", input)
  +m = names()
  +c = {OS.Ctx{windows, swaps_of(W.summary(seed)), w, h, True{}} : OS.Ctx}
  +ents = ents_loop(TN.of_attempt("oent", a, lines), m, Nil{})
  +reqs = reqs_loop(TN.of_attempt("oreq", a, lines), m)
  +rng = R.at_counter(seed, TN.num("ctr", input))
  +void_rng = R.at_counter(seed, TN.num("ctr", ORW.digest_record(a, "\"void\"", lines)))
  s = {OS.Sea{ORW.grid(a, "\"land\"", w, h, lines), ORW.ids(a, "\"land\"", w, h, lines), rng, ents, TN.num("topo", input), Nil{}} : OS.Sea}
  prefilled = OO.prefill(c, s)
  sea_lines(OO.after_convert(c, reqs, with_void(prefilled, ORW.grid(a, "\"void\"", w, h, lines), void_rng)), {Out{seed, a, w, h, 0, 0} : Out})

def post_all(as: List<&2, String>, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, post_attempt(seed, windows, a, lines), post_all(rest, seed, windows, lines))

# The `oceanpost` records for a seed, platform and the lines of its input.
def run_post(+seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  post_all(ORW.attempts(lines), seed, windows, lines)

def full_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +input = ORW.input(a, lines)
  +w = TN.num("w", input)
  +h = TN.num("h", input)
  +m = names()
  +c = {OS.Ctx{windows, swaps_of(W.summary(seed)), w, h, True{}} : OS.Ctx}
  +ents = ents_loop(TN.of_attempt("oent", a, lines), m, Nil{})
  +reqs = reqs_loop(TN.of_attempt("oreq", a, lines), m)
  +rng = R.at_counter(seed, TN.num("ctr", input))
  s = {OS.Sea{ORW.grid(a, "\"land\"", w, h, lines), ORW.ids(a, "\"land\"", w, h, lines), rng, ents, TN.num("topo", input), Nil{}} : OS.Sea}
  sea_lines(OO.run(c, reqs, s), {Out{seed, a, w, h, 0, 0} : Out})

def full_all(as: List<&2, String>, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, full_attempt(seed, windows, a, lines), full_all(rest, seed, windows, lines))

# The `ocean` records for a seed, platform and the lines of its input.
def run_full(+seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  full_all(ORW.attempts(lines), seed, windows, lines)
