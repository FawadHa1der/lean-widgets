import TreeScope.Model

/-! # TreeScope: tidy tree layout in exact ℚ

Recursive bounding-box packing, entirely in `Rat` (pixel units, but exact):

* every subtree occupies a bounding box `[0, width]` horizontally;
* children boxes are laid side by side, separated by `hGap`;
* the parent is centered exactly over the midpoint of its first and last
  child's *root* positions (a single-child parent therefore sits directly
  above its child);
* row `d` (depth `d`) has its node centers at `y = nodeH/2 + d·levelStep`.

`layoutTree` emits per-node positions (node *centers*, in preorder, addressed
by structural path) plus the overall bounds.  Collapsed nodes are laid out as
leaves (their descendants get no position) and carry a hidden-descendant count.

Guaranteed properties (re-checked as pure checkers in `TreeScopeTests.LayoutTests`):

(a) **no overlap** — nodes on the same row are at least `nodeW` apart
    (in fact at least `nodeW + hGap`), distinct rows are `levelStep ≥ nodeH + vGap`
    apart;
(b) **centering** — every parent's `x` is exactly the midpoint of its first
    and last child's `x`;
(c) **determinism** — the layout is a pure function of the tree, all
    arithmetic exact in `Rat`;
(d) **translation invariance** — a subtree's internal relative geometry is
    independent of its siblings: the recursion positions every subtree in its
    own local frame and only ever *translates* it.

The optional contour-based tightening (narrower layouts by letting sibling
subtrees interleave their outlines) is **not** implemented — boxes never
overlap even when they could safely interleave.  See README limitations.

`gridLayout` arranges several trees in rows of bounded width for the
stage-2 gallery: greedy row filling, deterministic.
-/

namespace TreeScope

namespace Layout

/-- Node box width, px (exact). -/
def nodeW : Rat := 76
/-- Node box height, px (exact). -/
def nodeH : Rat := 36
/-- Horizontal gap between sibling subtree bounding boxes, px. -/
def hGap : Rat := 20
/-- Vertical gap between rows, px. -/
def vGap : Rat := 28
/-- Vertical distance between consecutive row centers: `nodeH + vGap`. -/
def levelStep : Rat := nodeH + vGap

end Layout

/-- A positioned node: display data copied from the `TreeView` node plus the
exact center position and the structural path addressing it. -/
structure PlacedNode where
  /-- Structural path from the root (`#[]` = root). -/
  path : Array Nat
  /-- Center x, exact. -/
  x : Rat
  /-- Center y, exact. -/
  y : Rat
  /-- Node label. -/
  label : String
  /-- Optional sublabel. -/
  sublabel : Option String
  /-- Badges. -/
  badges : Array String
  /-- Semantic tone. -/
  tone : NodeTone
  /-- Is this node a collapsed stub? -/
  collapsed : Bool
  /-- Number of hidden descendants (`0` unless collapsed). -/
  hidden : Nat
  /-- Number of *laid-out* children (`0` for collapsed nodes and leaves). -/
  childCount : Nat
  deriving Repr, BEq, Inhabited

/-- Layout of one tree: placed nodes in preorder plus the overall bounds
(the bounding box is `[0, width] × [0, height]`). -/
structure TreeLayout where
  /-- Placed nodes, in preorder (`nodes[0]` is the root). -/
  nodes : Array PlacedNode
  /-- Total width, exact. -/
  width : Rat
  /-- Total height, exact. -/
  height : Rat
  deriving Repr, BEq, Inhabited

namespace TreeLayout

/-- The placed node at structural path `p`, if it was laid out. -/
def at? (l : TreeLayout) (p : Array Nat) : Option PlacedNode :=
  l.nodes.find? (·.path == p)

/-- The placed root (defaults for the impossible empty case). -/
def root (l : TreeLayout) : PlacedNode :=
  l.nodes[0]?.getD default

end TreeLayout

namespace Layout

/-- Lay out a subtree in its own local frame: the subtree's bounding box
starts at `x = 0`, the root row is centered at `y = nodeH/2`, and all paths
are relative to the subtree root.  Returns the placed nodes (preorder) and
the bounding-box width.  Parents only *translate* child results (property (d)). -/
def layoutSub : TreeView → Array PlacedNode × Rat
  | t@(.mk l s b tn cflag cs) =>
    let mkRoot (x : Rat) (childCount : Nat) : PlacedNode :=
      { path := #[], x, y := nodeH / 2, label := l, sublabel := s, badges := b
        tone := tn, collapsed := cflag
        hidden := if cflag then t.hiddenCount else 0
        childCount }
    if cflag || cs.isEmpty then
      (#[mkRoot (nodeW / 2) 0], nodeW)
    else
      -- Fold state: (accumulated shifted nodes, next child offset,
      --              first child root x, last child root x, child index).
      let (nodes, off, firstX, lastX, _) :=
        cs.attach.foldl
          (fun (acc, off, firstX, _lastX, i) ⟨c, _⟩ =>
            let (cnodes, cw) := layoutSub c
            let shifted := cnodes.map fun pn =>
              { pn with
                  path := #[i] ++ pn.path
                  x := pn.x + off
                  y := pn.y + levelStep }
            let rootX := (shifted[0]?.map (·.x)).getD 0
            (acc ++ shifted, off + cw + hGap,
             if i == 0 then rootX else firstX, rootX, i + 1))
          ((#[] : Array PlacedNode), (0 : Rat), (0 : Rat), (0 : Rat), 0)
      let width := off - hGap
      let rootX := (firstX + lastX) / 2
      (#[mkRoot rootX cs.size] ++ nodes, width)

end Layout

/-- Tidy layout of a whole tree (see the module docstring for the guaranteed
properties).  Deterministic: exact `Rat` arithmetic, no floating point. -/
def layoutTree (t : TreeView) : TreeLayout :=
  let (nodes, width) := Layout.layoutSub t
  let maxY := nodes.foldl (fun acc pn => max acc pn.y) 0
  { nodes, width, height := maxY + Layout.nodeH / 2 }

/-! ## Grid layout (galleries of several trees) -/

/-- One tree of a grid: its index in the input array, its layout, and the
translation of its bounding box within the grid. -/
structure GridCell where
  /-- Index into the input array. -/
  index : Nat
  /-- Horizontal offset of the tree's bounding box. -/
  offsetX : Rat
  /-- Vertical offset of the tree's bounding box. -/
  offsetY : Rat
  /-- The tree's own layout (local frame). -/
  layout : TreeLayout
  deriving Repr, BEq, Inhabited

/-- A grid of tree layouts with overall bounds. -/
structure GridLayout where
  /-- Cells in input order. -/
  cells : Array GridCell
  /-- Total width, exact. -/
  width : Rat
  /-- Total height, exact. -/
  height : Rat
  deriving Repr, BEq, Inhabited

namespace Layout

/-- Gap between grid cells (both axes), px. -/
def cellGap : Rat := 24

end Layout

/-- Arrange several trees in rows of bounded width: trees are taken in order
and packed greedily — a tree starts a new row when adding it would exceed
`maxRowWidth` (a tree wider than `maxRowWidth` still gets a row of its own, so
the resulting `width` can honestly exceed the bound).  Row height is the
maximum tree height in the row.  Deterministic. -/
def gridLayout (ts : Array TreeView) (maxRowWidth : Rat := 640) : GridLayout := Id.run do
  let mut cells : Array GridCell := #[]
  let mut x : Rat := 0
  let mut y : Rat := 0
  let mut rowH : Rat := 0
  let mut totalW : Rat := 0
  let mut i := 0
  for t in ts do
    let l := layoutTree t
    if x > 0 && x + l.width > maxRowWidth then
      -- Start a new row.
      y := y + rowH + Layout.cellGap
      x := 0
      rowH := 0
    cells := cells.push { index := i, offsetX := x, offsetY := y, layout := l }
    totalW := max totalW (x + l.width)
    rowH := max rowH l.height
    x := x + l.width + Layout.cellGap
    i := i + 1
  return { cells, width := totalW, height := if cells.isEmpty then 0 else y + rowH }

end TreeScope
