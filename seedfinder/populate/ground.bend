import Base
import ../rng/pcg.bend as Pcg
import ../data/layouts.bend as Layouts
import ../worldsim/points.bend as Points
import ./counts.bend as PopulateCounts
import ./layout.bend as PopulateLayout
import ./nodes.bend as PopulateNodes
import ./place.bend as PopulatePlace
import ./state.bend as PopulateState

# Node:ConvertGround (graphnode.lua) over Graph:ConvertGround's node order: per node with terrain_contents, each
# countstaticlayouts entry (closures called with the site area) that many times, then the map tag static layouts,
# each through object_layout.Convert (LayoutForDefinition, ConvertLayoutToEntitylist, ReserveAndPlaceLayout).

def objs_of(items: List<&2, PopulateLayout.Item>) -> List<&2, PopulateState.Obj>:
  match items:
    case Nil{}:
      Nil{}
    case Con{PopulateLayout.Item{+prefab, +x, +y, _}, rest}:
      PopulateState.Obj{prefab, x, y} <> objs_of(rest)

def converted(got: List<&2, PopulateLayout.Item> & Pcg.Rng, +c: PopulateState.Ctx, +node: U32, +name: U32, +v: U32, +before: Pcg.Rng, l: PopulateState.Land) -> PopulateState.Land:
  (+items, +rng) = got
  PopulatePlace.place(c, node, v, items, PopulateState.noted(PopulateState.with_rng(l, rng), PopulateState.EItems{name, objs_of(items), before, rng}))

def placed_note(got: PopulateState.Land & Pcg.Rng) -> PopulateState.Land:
  (l, +after) = got
  PopulateState.noted(l, PopulateState.EPlaced{after})

# object_layout.Convert(node, name, add_fn) for layout index `layout`.
def convert(+c: PopulateState.Ctx, +node: U32, +name: U32, +layout: U32, l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      +v = Layouts.variant(layout, PopulateState.swaps_of(c))
      placed_note(PopulateState.rng_of(converted(PopulateLayout.convert(PopulateState.swaps_of(c), layout, rng), c, node, name, v, rng,
        PopulateState.noted(PopulateState.Land{g, rng, ents, events}, PopulateState.ELayout{node, name, rng}))))

def repeat(n: Nat, l: PopulateState.Land, +c: PopulateState.Ctx, +node: U32, +name: U32, +layout: U32) -> PopulateState.Land:
  match n:
    case 0n:
      l
    case 1n+p:
      repeat(p, convert(c, node, name, layout, l), c, node, name, layout)

def counted_statics(got: U32 & Pcg.Rng, +c: PopulateState.Ctx, +node: U32, +name: U32, +layout: U32, l: PopulateState.Land) -> PopulateState.Land:
  (+n, rng) = got
  repeat(U32.to_nat(n), PopulateState.with_rng(l, rng), c, node, name, layout)

def statics_loop(xs: List<&2, PopulateNodes.Static>, l: PopulateState.Land, +c: PopulateState.Ctx, +node: U32, +area: U32) -> PopulateState.Land:
  match xs:
    case Nil{}:
      l
    case Con{PopulateNodes.Static{+key, +kind, +value, +layout}, rest}:
      match l:
        case PopulateState.Land{g, +rng, +ents, +events}:
          statics_loop(rest, counted_statics(PopulateCounts.value_of(kind, value, area, PopulateState.width_of(c), rng), c, node, key, layout,
            PopulateState.Land{g, rng, ents, events}), c, node, area)

def extras_loop(xs: List<&2, U32>, l: PopulateState.Land, +c: PopulateState.Ctx, +node: U32) -> PopulateState.Land:
  match xs:
    case Nil{}:
      l
    case Con{+layout, rest}:
      extras_loop(rest, convert(c, node, Layouts.name(Layouts.variant(layout, PopulateState.swaps_of(c))), layout, l), c, node)

def ground_body(on: Bool, l: PopulateState.Land, +c: PopulateState.Ctx, +node: U32) -> PopulateState.Land:
  match on:
    case False{}:
      l
    case True{}:
      +s = PopulateState.story_of(c)
      +area = Points.site_area(PopulateState.sites_of(c), PopulateState.site_of(c, node))
      extras_loop(PopulateNodes.extra_layouts(s, node), statics_loop(PopulateNodes.statics(s, node), l, c, node, area), c, node)

def noted_node(got: PopulateState.Land & Pcg.Rng, +node: U32, +before: Pcg.Rng) -> PopulateState.Land:
  (l, +after) = got
  PopulateState.noted(l, PopulateState.EConvertNode{node, before, after})

def ground_node(+c: PopulateState.Ctx, +node: U32, l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      noted_node(PopulateState.rng_of(ground_body(PopulateNodes.has_contents(PopulateState.story_of(c), node), PopulateState.Land{g, rng, ents, events}, c, node)), node, rng)

def ground_loop(nodes: List<&2, U32>, l: PopulateState.Land, +c: PopulateState.Ctx) -> PopulateState.Land:
  match nodes:
    case Nil{}:
      l
    case Con{+node, rest}:
      ground_loop(rest, ground_node(c, node, l), c)

def noted_land(got: PopulateState.Land & Pcg.Rng, +c: PopulateState.Ctx, +before: Pcg.Rng) -> PopulateState.Land:
  (l, +after) = got
  PopulateState.digest(PopulateState.noted(l, PopulateState.ELand{False{}, before, after}), c, 0)

# Graph:ConvertGround on the root: every node of pairs(root:GetNodes(true)).
def convert_ground(+c: PopulateState.Ctx, l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      noted_land(PopulateState.rng_of(ground_loop(PopulateNodes.convert_order(PopulateState.story_of(c)), PopulateState.Land{g, rng, ents, events}, c)), c, rng)
