import TreeScope

/-! # Test helpers

Pure builders for crafted test trees, string-search helpers for render tests,
and the four required layout properties as reusable pure checkers
(no-overlap, exact parent centering, determinism, subtree translation
invariance) plus two bonus checkers (row alignment, bounding-box containment).
-/

namespace TreeScopeTests

open TreeScope TreeScope.TreeView

/-! ## String helpers for render tests -/

/-- Does `s` contain `sub`? (`sub` nonempty.) -/
def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

/-- Number of (non-overlapping) occurrences of `sub` in `s`. -/
def countOccurrences (s sub : String) : Nat :=
  (s.splitOn sub).length - 1

/-! ## Crafted tree builders -/

/-- Chain of `n + 1` nodes: `n → n-1 → … → 0`. -/
def chain : Nat → TreeView
  | 0 => leaf "0"
  | n + 1 => make s!"{n + 1}" #[chain n]

/-- Star: a root with `n` leaves. -/
def star (n : Nat) : TreeView :=
  make "c" ((Array.range n).map fun i => leaf s!"l{i}")

/-- Full `b`-ary tree of the given depth (depth 0 = a single leaf). -/
def fullTree (b : Nat) : Nat → TreeView
  | 0 => leaf "t"
  | d + 1 => make "t" ((Array.range b).map fun _ => fullTree b d)

/-! ## The 12-tree layout family (chains, stars, balanced, lopsided,
single nodes, wide-vs-deep siblings, collapsed, annotated) -/

/-- Single node. -/
def c1 : TreeView := leaf "a"
/-- Chain of 5 nodes. -/
def c2 : TreeView := chain 4
/-- Star with 6 leaves. -/
def c3 : TreeView := star 6
/-- Balanced binary tree, 7 nodes. -/
def c4 : TreeView := fullTree 2 2
/-- Lopsided: deep chain on the left, leaf on the right. -/
def c5 : TreeView := make "r" #[chain 3, leaf "b"]
/-- Lopsided: leaf on the left, deep chain on the right. -/
def c6 : TreeView := make "r" #[leaf "b", chain 3]
/-- Wide-vs-deep siblings: a 4-leaf star next to a 4-node chain. -/
def c7 : TreeView := make "r" #[star 4, chain 3]
/-- Single-child spine ending in a wide star. -/
def c8 : TreeView := make "r" #[make "m" #[star 3]]
/-- Full ternary tree of depth 2 (13 nodes). -/
def c9 : TreeView := fullTree 3 2
/-- Balanced binary tree with one subtree collapsed. -/
def c10 : TreeView := c4.collapseAt #[1]
/-- Star with tones, badges and sublabels (annotations must not affect layout). -/
def c11 : TreeView :=
  make "r" (tone := .rbBlack) (sublabel := "bh=1") (children := #[
    leaf "x" |>.withTone .violation |>.addBadge "b",
    leaf "y" |>.withTone .added,
    leaf "z" |>.withSublabel "s"])
/-- Children of very different heights. -/
def c12 : TreeView := make "r" #[chain 2, leaf "b", chain 1]

/-- The whole family. -/
def family : Array TreeView := #[c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12]

/-! ## Layout property checkers (pure, reusable) -/

/-- `|q|` for `Rat`. -/
def rabs (q : Rat) : Rat := if q < 0 then -q else q

/-- Is `p` a prefix of `q`? -/
def isPrefixOf (p q : Array Nat) : Bool :=
  p.size ≤ q.size && (List.range p.size).all fun i => p[i]! == q[i]!

/-- Property (a): no two nodes overlap — same-row centers at least `nodeW`
apart, distinct rows at least `nodeH + vGap` apart. -/
def noOverlap (l : TreeLayout) : Bool := Id.run do
  for i in [0:l.nodes.size] do
    for j in [i+1:l.nodes.size] do
      let a := l.nodes[i]!
      let b := l.nodes[j]!
      if a.y == b.y then
        if rabs (a.x - b.x) < Layout.nodeW then return false
      else
        if rabs (a.y - b.y) < Layout.nodeH + Layout.vGap then return false
  return true

/-- Property (b): every parent sits exactly over the midpoint of its first and
last child's roots (for a single child: directly above it). -/
def parentsCentered (l : TreeLayout) : Bool :=
  l.nodes.all fun pn =>
    pn.childCount == 0 ||
      (match l.at? (pn.path.push 0), l.at? (pn.path.push (pn.childCount - 1)) with
       | some f, some g => pn.x * 2 == f.x + g.x
       | _, _ => false)

/-- Property (c): laying out the same tree twice yields identical results
(byte-for-byte: `BEq` on the exact `Rat` layout). -/
def deterministic (t : TreeView) : Bool :=
  layoutTree t == layoutTree t

/-- Property (d): subtree translation invariance — for every laid-out node,
laying out its subtree *standalone* reproduces exactly the relative geometry
it has inside the full tree (same visible-node count, same relative offsets). -/
def translationInvariant (t : TreeView) : Bool :=
  let lf := layoutTree t
  lf.nodes.all fun pn =>
    match t.get? pn.path with
    | none => false
    | some sub =>
      let ls := layoutTree sub
      let placedBelow := lf.nodes.filter fun q => isPrefixOf pn.path q.path
      placedBelow.size == ls.nodes.size &&
        ls.nodes.all fun q =>
          match lf.at? (pn.path ++ q.path) with
          | none => false
          | some fq =>
            fq.x - pn.x == q.x - ls.root.x && fq.y - pn.y == q.y - ls.root.y

/-- Bonus: node at path `p` sits on row `p.size`, at the exact row center. -/
def rowsAligned (l : TreeLayout) : Bool :=
  l.nodes.all fun pn =>
    pn.y == Layout.nodeH / 2 + (pn.path.size : Rat) * Layout.levelStep

/-- Bonus: every node box lies inside the reported bounds. -/
def inBounds (l : TreeLayout) : Bool :=
  l.nodes.all fun pn =>
    0 ≤ pn.x - Layout.nodeW / 2 && pn.x + Layout.nodeW / 2 ≤ l.width
      && 0 ≤ pn.y - Layout.nodeH / 2 && pn.y + Layout.nodeH / 2 ≤ l.height

end TreeScopeTests
