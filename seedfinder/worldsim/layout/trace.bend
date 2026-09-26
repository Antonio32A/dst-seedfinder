import Base
import ../../f64/word.bend as F64Word
import ../../f64/repr.bend as F64Repr
import ../../trace/canon.bend as Canon
import ./space.bend as LayoutSpace
import ./hops.bend as LayoutHops
import ./kk.bend as KK

# Trace stages `hops` and `kk` (.scratch/port/CONVENTIONS.md "Trace mode"). The input is the oracle's graph
# stage (`vertex` and `outedge` records of every VoronoiPass); `kk` replays each attempt's passes from
# InitializeNodePoints (100 runs, then AddNewPositions and 50 runs), `hops` hashes each pass's hop matrix.

type Pass is Data:
  Pass{a: U32, g: U32, n: U32}

type Edge is Data:
  Edge{a: U32, g: U32, from: U32, to: U32}

type Fnv is Data:
  Fnv{hi: U32, lo: U32}

type Out is Type:
  Out{ws: Array<U32>, lines: List<&2, String>}

type JobOut is Type:
  JobOut{job: KK.Job, lines: List<&2, String>}

type Hashing is Type:
  Hashing{ws: Array<U32>, row: Fnv, all: Fnv, rows: List<&2, Fnv>}

def handles(+stage: String) -> Bool:
  String.eq(stage, "kk") || String.eq(stage, "hops")

def fnv_offset() -> Fnv:
  Fnv{3421674724, 2216829733}

def fnv_byte(h: Fnv, +b: U32) -> Fnv:
  match h:
    case Fnv{+hi, +lo}:
      +x = (lo .^. b : U32)
      Fnv{((hi * 435) + F64Word.mul_hi(x, 435) + (x << 8n) : U32), (x * 435 : U32)}

def fnv_u32(h: Fnv, +w: U32) -> Fnv:
  fnv_byte(fnv_byte(fnv_byte(fnv_byte(h, (w .&. 255 : U32)), ((w >> 8n) .&. 255 : U32)), ((w >> 16n) .&. 255 : U32)), (w >> 24n : U32))

def fnv_hex(h: Fnv) -> String:
  match h:
    case Fnv{+hi, +lo}:
      Canon.hex64(hi, lo)

def f64_hex(x: F64Repr.F64) -> String:
  match x:
    case F64Repr.F64{+hi, +lo}:
      Canon.hex64(hi, lo)

def key(+fields: List<&2, String>, +name: String) -> U32:
  Canon.number_or(Canon.value_of(name, fields), 0)

def same_pass(same: Bool, +head: Pass, tail: List<&2, Pass>, +a: U32, +g: U32) -> List<&2, Pass>:
  match same:
    case True{}:
      match head:
        case Pass{pa, pg, pn}:
          Pass{pa, pg, (pn + 1 : U32)} <> tail
    case False{}:
      Pass{a, g, 1} <> head <> tail

def counted(acc: List<&2, Pass>, +a: U32, +g: U32) -> List<&2, Pass>:
  match acc:
    case Nil{}:
      [Pass{a, g, 1}]
    case Con{+head, tail}:
      match head:
        case Pass{+pa, +pg, pn}:
          same_pass(U32.is_eq(pa, a) && U32.is_eq(pg, g), head, tail, a, g)

def group(records: List<&2, List<&2, String>>, acc: List<&2, Pass>) -> List<&2, Pass>:
  match records:
    case Nil{}:
      List.reverse(&2, Pass, acc)
    case Con{+fields, rest}:
      group(rest, counted(acc, key(fields, "a"), key(fields, "g")))

def edge_of(+fields: List<&2, String>) -> Edge:
  Edge{key(fields, "a"), key(fields, "g"), key(fields, "v"), key(fields, "to")}

def edges_of(records: List<&2, List<&2, String>>) -> List<&2, Edge>:
  match records:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      edge_of(fields) <> edges_of(rest)

def kept_arc(keep: Bool, +from: U32, +to: U32, rest: List<&2, LayoutHops.Arc>) -> List<&2, LayoutHops.Arc>:
  match keep:
    case True{}:
      LayoutHops.Arc{from, to} <> rest
    case False{}:
      rest

def arcs_of(edges: List<&2, Edge>, +a: U32, +g: U32) -> List<&2, LayoutHops.Arc>:
  match edges:
    case Nil{}:
      Nil{}
    case Con{Edge{+ea, +eg, +from, +to}, rest}:
      kept_arc(U32.is_eq(ea, a) && U32.is_eq(eg, g), from, to, arcs_of(rest, a, g))

def ids(+a: U32, +g: U32) -> List<&2, String>:
  [Canon.number("a", a), Canon.number("g", g)]

def pos_line(+kind: String, +a: U32, +g: U32, +run: U32, +v: U32, p: LayoutSpace.Vec) -> String:
  match p:
    case LayoutSpace.Vec{x, y}:
      Canon.record(kind, List.append(&2, String, ids(a, g), [Canon.number("run", run), Canon.number("v", v),
        Canon.field("x", f64_hex(x)), Canon.field("y", f64_hex(y))]))

def pos_lines(ps: List<&2, LayoutSpace.Vec>, +kind: String, +a: U32, +g: U32, +run: U32, +v: U32, acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      acc
    case Con{p, rest}:
      pos_lines(rest, kind, a, g, run, (v + 1 : U32), pos_line(kind, a, g, run, v, p) <> acc)

def run_line(+a: U32, +g: U32, +run: U32, ok: Bool, clock: KK.Clock) -> String:
  match clock:
    case KK.Clock{inner, outer, last, +outers, +newtons, left}:
      Canon.record("kkrun", List.append(&2, String, ids(a, g), [Canon.number("run", run), Canon.number("ok", Bool.to_u32(ok)),
        Canon.number("outer", outers), Canon.number("newton", newtons)]))

def ran(got: Array<U32> & List<&2, LayoutSpace.Vec>, +n: U32, +p: U32, +delta: F64Repr.F64, +clock: KK.Clock, +ok: Bool, +a: U32, +g: U32, +run: U32, acc: List<&2, String>) -> JobOut:
  (ws, ps) = got
  JobOut{KK.restart(KK.Job{ws, n, KK.Ended{}, p, delta, clock, ok}, 0),
    pos_lines(ps, "kkpos", a, g, run, 0, run_line(a, g, run, ok, clock) <> acc)}

def run_once(job: KK.Job, +a: U32, +g: U32, +run: U32, acc: List<&2, String>) -> JobOut:
  match job:
    case KK.Job{ws, +n, phase, +p, +delta, +clock, +ok}:
      ran(KK.positions(ws, n), n, p, delta, clock, ok, a, g, run, acc)

def run_loop(fuel: Nat, +run: U32, +a: U32, +g: U32, st: JobOut) -> JobOut:
  match fuel:
    case 0n:
      st
    case 1n+f:
      match st:
        case JobOut{job, lines}:
          run_loop(f, (run + 1 : U32), a, g, run_once(KK.advance(KK.run_fuel(), job), a, g, run, lines))

def job_out(st: JobOut) -> Out:
  match st:
    case JobOut{job, lines}:
      match job:
        case KK.Job{ws, n, phase, p, delta, clock, ok}:
          Out{ws, lines}

def runs_of(+g: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(g, 1), 100n, 50n)

def initial(got: Array<U32> & List<&2, LayoutSpace.Vec>, +n: U32, +p: U32, +delta: F64Repr.F64, +clock: KK.Clock, +ok: Bool, +a: U32, +g: U32, acc: List<&2, String>) -> JobOut:
  (ws, ps) = got
  JobOut{KK.Job{ws, n, KK.Start{}, p, delta, clock, ok}, pos_lines(ps, "kkinit", a, g, 0, 0, acc)}

def with_initial(job: KK.Job, +a: U32, +g: U32, acc: List<&2, String>) -> JobOut:
  match job:
    case KK.Job{ws, +n, phase, +p, +delta, +clock, +ok}:
      initial(KK.positions(ws, n), n, p, delta, clock, ok, a, g, acc)

def kk_pass(ws: Array<U32>, +first: U32, +pass: Pass, +edges: List<&2, Edge>, acc: List<&2, String>) -> Out:
  match pass:
    case Pass{+a, +g, +n}:
      job_out(run_loop(runs_of(g), 1, a, g, with_initial(KK.pass_job(ws, first, n, arcs_of(edges, a, g), 0), a, g, acc)))

def workspace_for(same: Bool, ws: Array<U32>) -> Array<U32>:
  match same:
    case True{}:
      ws
    case False{}:
      LayoutSpace.new_workspace()

def row_hashed(got: Array<U32> & U32, +row: Fnv, +all: Fnv, rows: List<&2, Fnv>) -> Hashing:
  (ws, +h) = got
  Hashing{ws, fnv_u32(row, h), fnv_u32(all, h), rows}

def hash_row(fuel: Nat, +s: U32, +v: U32, st: Hashing) -> Hashing:
  match fuel:
    case 0n:
      st
    case 1n+f:
      match st:
        case Hashing{ws, +row, +all, rows}:
          hash_row(f, s, (v + 1 : U32), row_hashed(ws[LayoutSpace.hop_at(s, v)], row, all, rows))

def row_done(st: Hashing) -> Hashing:
  match st:
    case Hashing{ws, +row, all, rows}:
      Hashing{ws, fnv_offset(), all, row <> rows}

def hash_rows(fuel: Nat, +s: U32, +n: U32, st: Hashing) -> Hashing:
  match fuel:
    case 0n:
      st
    case 1n+f:
      hash_rows(f, (s + 1 : U32), n, row_done(hash_row(U32.to_nat(n), s, 0, st)))

def row_lines(rows: List<&2, Fnv>, +a: U32, +g: U32, +v: U32, acc: List<&2, String>) -> List<&2, String>:
  match rows:
    case Nil{}:
      acc
    case Con{row, rest}:
      row_lines(rest, a, g, (v + 1 : U32), Canon.record("hoprow", List.append(&2, String, ids(a, g), [Canon.number("v", v),
        Canon.field("hash", fnv_hex(row))])) <> acc)

def hops_lines(st: Hashing, +a: U32, +g: U32, +n: U32, +edges: U32, +ok: Bool, acc: List<&2, String>) -> Out:
  match st:
    case Hashing{ws, row, all, rows}:
      +head = Canon.record("hops", List.append(&2, String, ids(a, g), [Canon.number("n", n), Canon.number("edges", edges),
        Canon.number("connected", Bool.to_u32(ok)), Canon.field("hash", fnv_hex(all))]))
      Out{ws, row_lines(List.reverse(&2, Fnv, rows), a, g, 0, head <> acc)}

def hops_hashed(got: Array<U32> & Bool, +a: U32, +g: U32, +n: U32, +edges: U32, acc: List<&2, String>) -> Out:
  (ws, +ok) = got
  hops_lines(hash_rows(U32.to_nat(n), 0, n, Hashing{ws, fnv_offset(), fnv_offset(), Nil{}}), a, g, n, edges, ok, acc)

def hops_pass(ws: Array<U32>, +pass: Pass, +edges: List<&2, Edge>, acc: List<&2, String>) -> Out:
  match pass:
    case Pass{+a, +g, +n}:
      +arcs = arcs_of(edges, a, g)
      +counted_edges = (U32.from_nat(List.length(&2, LayoutHops.Arc, arcs)) >> 1n : U32)
      hops_hashed(LayoutHops.connected(n, LayoutHops.hop_matrix(n, LayoutHops.load_arcs(n, arcs, ws))), a, g, n, counted_edges, acc)

def stage_pass(hops: Bool, ws: Array<U32>, +first: U32, +pass: Pass, +edges: List<&2, Edge>, acc: List<&2, String>) -> Out:
  match hops:
    case True{}:
      hops_pass(ws, pass, edges, acc)
    case False{}:
      kk_pass(ws, first, pass, edges, acc)

def pass_attempt(pass: Pass) -> U32:
  match pass:
    case Pass{a, g, n}:
      a

def pass_size(pass: Pass) -> U32:
  match pass:
    case Pass{a, g, n}:
      n

def all_passes(passes: List<&2, Pass>, +hops: Bool, +edges: List<&2, Edge>, +prev_a: U32, +prev_n: U32, st: Out) -> List<&2, String>:
  match passes:
    case Nil{}:
      match st:
        case Out{ws, lines}:
          List.reverse(&2, String, lines)
    case Con{+pass, rest}:
      match st:
        case Out{ws, lines}:
          +same = U32.is_eq(pass_attempt(pass), prev_a)
          all_passes(rest, hops, edges, pass_attempt(pass), pass_size(pass),
            stage_pass(hops, workspace_for(same, ws), F64Word.pick(same, prev_n, 0), pass, edges, lines))

# The `hops` or `kk` records of every VoronoiPass in the input's graph records.
def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  +lines = String.split(input, '\n')
  +edges = edges_of(Canon.records("outedge", lines))
  all_passes(group(Canon.records("vertex", lines), Nil{}), String.eq(stage, "hops"), edges, 0, 0, Out{LayoutSpace.new_workspace(), Nil{}})
