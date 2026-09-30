import TreeScopeTests.Helpers

/-! # Catalan gallery tests

`allBinTrees n` (the deterministic gallery enumeration) against Mathlib's
`BinaryTree.treesOfNumNodesEq` and `catalan`: counts agree (`14 = catalan 4`),
every enumerated tree is a member with the right node count, no duplicates —
so the gallery renders *exactly* the Mathlib finset — and the grid render
contains all 14 tree groups.
-/

namespace TreeScopeTests

open TreeScope TreeScope.BinTree

/-! ## Counts -/

#guard (allBinTrees 4).length == 14
#guard (BinaryTree.treesOfNumNodesEq 4).card == 14
#guard (BinaryTree.treesOfNumNodesEq 4).card == catalan 4
#guard catalan 4 == 14

-- The Catalan sequence start, both through Mathlib and our enumeration.
#guard ((List.range 6).map fun n => (allBinTrees n).length) == [1, 1, 2, 5, 14, 42]
#guard ((List.range 6).map fun n => (BinaryTree.treesOfNumNodesEq n).card) == [1, 1, 2, 5, 14, 42]
#guard ((List.range 6).map catalan) == [1, 1, 2, 5, 14, 42]

/-! ## `allBinTrees` = `treesOfNumNodesEq` as a set -/

-- Every enumerated tree is a member of the Mathlib finset…
#guard (allBinTrees 4).all fun t => decide (t ∈ BinaryTree.treesOfNumNodesEq 4)
#guard (allBinTrees 3).all fun t => decide (t ∈ BinaryTree.treesOfNumNodesEq 3)
-- …has exactly 4 internal nodes…
#guard (allBinTrees 4).all fun t => t.numNodes == 4
-- …and the list has no duplicates, so (with matching cardinality above) the
-- gallery is exactly the finset.
#guard (allBinTrees 4).eraseDups.length == 14

/-! ## The gallery render -/

/-- The serialized 14-tree grid. -/
private def gallery4 : String := htmlToDebugString (renderForest (catalanGallery 4) (maxRowWidth := 900))

#guard (catalanGallery 4).size == 14
#guard countOccurrences gallery4 "data-cell=" == 14
-- Every gallery view uses the `•` shape label and only `∅` stubs otherwise.
#guard (catalanGallery 4).all fun tv =>
  (tv.preorderPaths.all fun p => (tv.get? p).any fun n => n.label == "•" || n.label == "∅")
-- Grid render is deterministic.
#guard gallery4 == htmlToDebugString (renderForest (catalanGallery 4) (maxRowWidth := 900))
-- React style contract (see RenderTests): no string styles in the gallery.
#guard reactContractViolations (renderForest (catalanGallery 4) (maxRowWidth := 900)) == []

end TreeScopeTests
