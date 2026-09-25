import Base
import ../rng/pcg.bend as R
import ../data/layouts.bend as LY
import ../worldsim/points.bend as PT
import ./counts.bend as PC
import ./layout.bend as PL
import ./nodes.bend as PN
import ./place.bend as PP
import ./state.bend as PS

# Node:ConvertGround (graphnode.lua) over Graph:ConvertGround's node order: per node with terrain_contents, each
# countstaticlayouts entry (closures called with the site area) that many times, then the map tag static layouts,
# each through object_layout.Convert (LayoutForDefinition, ConvertLayoutToEntitylist, ReserveAndPlaceLayout).

def objs_of(items: List<&2, PL.Item>) -> List<&2, PS.Obj>:
  match items:
    case Nil{}:
      Nil{}
    case Con{PL.Item{+prefab, +x, +y, _}, rest}:
      PS.Obj{prefab, x, y} <> objs_of(rest)

def converted(got: List<&2, PL.Item> & R.Rng, +c: PS.Ctx, +node: U32, +name: U32, +v: U32, +before: R.Rng, l: PS.Land) -> PS.Land:
  (+items, +rng) = got
  PP.place(c, node, v, items, PS.noted(PS.with_rng(l, rng), PS.EItems{name, objs_of(items), before, rng}))

def placed_note(got: PS.Land & R.Rng) -> PS.Land:
  (l, +after) = got
  PS.noted(l, PS.EPlaced{after})

# object_layout.Convert(node, name, add_fn) for layout index `layout`.
def convert(+c: PS.Ctx, +node: U32, +name: U32, +layout: U32, l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      +v = LY.variant(layout, PS.swaps_of(c))
      placed_note(PS.rng_of(converted(PL.convert(PS.swaps_of(c), layout, rng), c, node, name, v, rng,
        PS.noted(PS.Land{g, rng, ents, events}, PS.ELayout{node, name, rng}))))

def repeat(n: Nat, l: PS.Land, +c: PS.Ctx, +node: U32, +name: U32, +layout: U32) -> PS.Land:
  match n:
    case 0n:
      l
    case 1n+p:
      repeat(p, convert(c, node, name, layout, l), c, node, name, layout)

def counted_statics(got: U32 & R.Rng, +c: PS.Ctx, +node: U32, +name: U32, +layout: U32, l: PS.Land) -> PS.Land:
  (+n, rng) = got
  repeat(U32.to_nat(n), PS.with_rng(l, rng), c, node, name, layout)

def statics_loop(xs: List<&2, PN.Static>, l: PS.Land, +c: PS.Ctx, +node: U32, +area: U32) -> PS.Land:
  match xs:
    case Nil{}:
      l
    case Con{PN.Static{+key, +kind, +value, +layout}, rest}:
      match l:
        case PS.Land{g, +rng, +ents, +events}:
          statics_loop(rest, counted_statics(PC.value_of(kind, value, area, PS.width_of(c), rng), c, node, key, layout,
            PS.Land{g, rng, ents, events}), c, node, area)

def extras_loop(xs: List<&2, U32>, l: PS.Land, +c: PS.Ctx, +node: U32) -> PS.Land:
  match xs:
    case Nil{}:
      l
    case Con{+layout, rest}:
      extras_loop(rest, convert(c, node, LY.name(LY.variant(layout, PS.swaps_of(c))), layout, l), c, node)

def ground_body(on: Bool, l: PS.Land, +c: PS.Ctx, +node: U32) -> PS.Land:
  match on:
    case False{}:
      l
    case True{}:
      +s = PS.story_of(c)
      +area = PT.site_area(PS.sites_of(c), PS.site_of(c, node))
      extras_loop(PN.extra_layouts(s, node), statics_loop(PN.statics(s, node), l, c, node, area), c, node)

def noted_node(got: PS.Land & R.Rng, +node: U32, +before: R.Rng) -> PS.Land:
  (l, +after) = got
  PS.noted(l, PS.EConvertNode{node, before, after})

def ground_node(+c: PS.Ctx, +node: U32, l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      noted_node(PS.rng_of(ground_body(PN.has_contents(PS.story_of(c), node), PS.Land{g, rng, ents, events}, c, node)), node, rng)

def ground_loop(nodes: List<&2, U32>, l: PS.Land, +c: PS.Ctx) -> PS.Land:
  match nodes:
    case Nil{}:
      l
    case Con{+node, rest}:
      ground_loop(rest, ground_node(c, node, l), c)

def noted_land(got: PS.Land & R.Rng, +c: PS.Ctx, +before: R.Rng) -> PS.Land:
  (l, +after) = got
  PS.digest(PS.noted(l, PS.ELand{False{}, before, after}), c, 0)

# Graph:ConvertGround on the root: every node of pairs(root:GetNodes(true)).
def convert_ground(+c: PS.Ctx, l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      noted_land(PS.rng_of(ground_loop(PN.convert_order(PS.story_of(c)), PS.Land{g, rng, ents, events}, c)), c, rng)
