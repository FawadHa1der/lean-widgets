import TreeScopeTests.Helpers

/-! # Layout tests

The four required properties — (a) no overlap, (b) exact parent centering,
(c) determinism, (d) subtree translation invariance — plus row alignment and
bounds containment, each run as a pure checker over the 12-tree family, and
pinned exact coordinates for three small trees and the grid renderer.
-/

namespace TreeScopeTests

open TreeScope TreeScope.TreeView

/-! ## (a) No overlap -/

#guard noOverlap (layoutTree c1)
#guard noOverlap (layoutTree c2)
#guard noOverlap (layoutTree c3)
#guard noOverlap (layoutTree c4)
#guard noOverlap (layoutTree c5)
#guard noOverlap (layoutTree c6)
#guard noOverlap (layoutTree c7)
#guard noOverlap (layoutTree c8)
#guard noOverlap (layoutTree c9)
#guard noOverlap (layoutTree c10)
#guard noOverlap (layoutTree c11)
#guard noOverlap (layoutTree c12)

/-! ## (b) Parents centered exactly over first/last child midpoint -/

#guard parentsCentered (layoutTree c1)
#guard parentsCentered (layoutTree c2)
#guard parentsCentered (layoutTree c3)
#guard parentsCentered (layoutTree c4)
#guard parentsCentered (layoutTree c5)
#guard parentsCentered (layoutTree c6)
#guard parentsCentered (layoutTree c7)
#guard parentsCentered (layoutTree c8)
#guard parentsCentered (layoutTree c9)
#guard parentsCentered (layoutTree c10)
#guard parentsCentered (layoutTree c11)
#guard parentsCentered (layoutTree c12)

/-! ## (c) Determinism -/

#guard deterministic c1
#guard deterministic c2
#guard deterministic c3
#guard deterministic c4
#guard deterministic c5
#guard deterministic c6
#guard deterministic c7
#guard deterministic c8
#guard deterministic c9
#guard deterministic c10
#guard deterministic c11
#guard deterministic c12

/-! ## (d) Subtree translation invariance -/

#guard translationInvariant c1
#guard translationInvariant c2
#guard translationInvariant c3
#guard translationInvariant c4
#guard translationInvariant c5
#guard translationInvariant c6
#guard translationInvariant c7
#guard translationInvariant c8
#guard translationInvariant c9
#guard translationInvariant c10
#guard translationInvariant c11
#guard translationInvariant c12

/-! ## Row alignment -/

#guard rowsAligned (layoutTree c1)
#guard rowsAligned (layoutTree c2)
#guard rowsAligned (layoutTree c3)
#guard rowsAligned (layoutTree c4)
#guard rowsAligned (layoutTree c5)
#guard rowsAligned (layoutTree c6)
#guard rowsAligned (layoutTree c7)
#guard rowsAligned (layoutTree c8)
#guard rowsAligned (layoutTree c9)
#guard rowsAligned (layoutTree c10)
#guard rowsAligned (layoutTree c11)
#guard rowsAligned (layoutTree c12)

/-! ## Bounds containment -/

#guard inBounds (layoutTree c1)
#guard inBounds (layoutTree c2)
#guard inBounds (layoutTree c3)
#guard inBounds (layoutTree c4)
#guard inBounds (layoutTree c5)
#guard inBounds (layoutTree c6)
#guard inBounds (layoutTree c7)
#guard inBounds (layoutTree c8)
#guard inBounds (layoutTree c9)
#guard inBounds (layoutTree c10)
#guard inBounds (layoutTree c11)
#guard inBounds (layoutTree c12)

/-! ## Pinned exact coordinates (hand-computed: `nodeW = 76`, `nodeH = 36`,
`hGap = 20`, `vGap = 28`, `levelStep = 64`) -/

/-- Root with two leaves. -/
private def tB : TreeView := make "r" #[leaf "a", leaf "b"]
/-- Lopsided: leaf on the left, 2-leaf node on the right. -/
private def tD : TreeView := make "r" #[leaf "a", make "s" #[leaf "c", leaf "d"]]

-- Single node: centered in its own box.
#guard (layoutTree c1).nodes.map (fun pn => (pn.path, pn.x, pn.y)) == #[(#[], 38, 18)]
#guard (layoutTree c1).width == 76
#guard (layoutTree c1).height == 36

-- Two leaves: boxes at [0,76] and [96,172]; root exactly between 38 and 134.
#guard (layoutTree tB).nodes.map (fun pn => (pn.path, pn.x, pn.y))
    == #[(#[], 86, 18), (#[0], 38, 82), (#[1], 134, 82)]
#guard (layoutTree tB).width == 172
#guard (layoutTree tB).height == 100

-- Lopsided: right subtree box starts at 96, its root at 96 + 86 = 182;
-- the root is the exact midpoint (38 + 182)/2 = 110.
#guard (layoutTree tD).nodes.map (fun pn => (pn.path, pn.x, pn.y))
    == #[(#[], 110, 18), (#[0], 38, 82), (#[1], 182, 82),
         (#[1, 0], 134, 146), (#[1, 1], 230, 146)]
#guard (layoutTree tD).width == 268

-- Collapsed subtree is laid out as a stub leaf carrying the hidden count.
#guard (layoutTree (tD.collapseAt #[1])).nodes.map (fun pn => (pn.path, pn.x, pn.y))
    == #[(#[], 86, 18), (#[0], 38, 82), (#[1], 134, 82)]
#guard ((layoutTree (tD.collapseAt #[1])).at? #[1]).map (fun pn => (pn.hidden, pn.collapsed))
    == some (2, true)

-- Single-child parents sit directly above their child.
#guard ((layoutTree c8).at? #[]).map (·.x) == ((layoutTree c8).at? #[0]).map (·.x)

/-! ## Grid layout -/

-- Three 172-wide trees, max row width 400: two fit per row (172 + 24 + 172 = 368),
-- the third starts a new row at y = 100 + 24 = 124.
#guard (gridLayout #[tB, tB, tB] (maxRowWidth := 400)).cells.map
    (fun c => (c.index, c.offsetX, c.offsetY)) == #[(0, 0, 0), (1, 196, 0), (2, 0, 124)]
#guard (gridLayout #[tB, tB, tB] (maxRowWidth := 400)).width == 368
#guard (gridLayout #[tB, tB, tB] (maxRowWidth := 400)).height == 224

-- A tree wider than the bound still gets its own row (honest overflow).
#guard (gridLayout #[tB] (maxRowWidth := 100)).cells.map
    (fun c => (c.offsetX, c.offsetY)) == #[(0, 0)]
#guard (gridLayout #[tB] (maxRowWidth := 100)).width == 172

-- Mixed sizes: rows are as tall as their tallest tree.
#guard (gridLayout #[tB, c1, c1] (maxRowWidth := 300)).cells.map
    (fun c => (c.index, c.offsetX, c.offsetY)) == #[(0, 0, 0), (1, 196, 0), (2, 0, 124)]

-- Empty and singleton grids.
#guard (gridLayout #[] (maxRowWidth := 400)) == ⟨#[], 0, 0⟩
#guard (gridLayout #[c1]).width == 76

-- Grid determinism.
#guard gridLayout family == gridLayout family

end TreeScopeTests
