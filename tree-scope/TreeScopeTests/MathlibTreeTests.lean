import TreeScopeTests.Helpers

/-! # Mathlib `BinaryTree` instance tests

The instance's `nil` convention pinned (both-`nil` elision, single-`nil` `∅`
stub, `∅` root); the BST order overlay flagging a crafted violation and
passing a valid BST.
-/

namespace TreeScopeTests

open TreeScope TreeScope.BinTree

/-! ## Instance pins -/

-- Both-nil children elided; single-nil rendered as a `∅` stub.
/--
info: tree: 5 nodes, depth 3
2
  1
  3
    4
    ∅
-/
#guard_msgs in
#tree_scope (text := true) (BinaryTree.node 2 (.node 1 .nil .nil) (.node 3 (.node 4 .nil .nil) .nil))

-- A nil root is the single node `∅`.
/--
info: tree: 1 nodes, depth 1
∅
-/
#guard_msgs in
#tree_scope (text := true) (BinaryTree.nil : BinaryTree Nat)

-- A single internal node has no children at all (both nil elided).
/--
info: tree: 1 nodes, depth 1
7
-/
#guard_msgs in
#tree_scope (text := true) (BinaryTree.node 7 .nil .nil)

-- Left-nil (mirror of the pinned right-nil case): stub keeps the side visible.
/--
info: tree: 3 nodes, depth 2
3
  ∅
  4
-/
#guard_msgs in
#tree_scope (text := true) (BinaryTree.node 3 .nil (.node 4 .nil .nil))

-- Pure view shape checks: the stub is a childless `∅` leaf, never elided
-- when its sibling is real.
#guard (binTreeView (fun n : Nat => toString n) (.node 3 .nil (.node 4 .nil .nil))).children.size == 2
#guard (binTreeView (fun n : Nat => toString n) (.node 3 .nil (.node 4 .nil .nil))).children[0]!.label == "∅"
#guard (binTreeView (fun n : Nat => toString n) (.node 7 .nil .nil)).children.size == 0

/-! ## `bstOrdered` -/

#guard bstOrdered compare (BinaryTree.node 2 (.node 1 .nil .nil) (.node 3 .nil .nil)) == true
#guard bstOrdered compare (BinaryTree.node 5 (.node 7 .nil .nil) (.node 9 .nil .nil)) == false
#guard bstOrdered compare (BinaryTree.nil : BinaryTree Nat) == true
-- Deep violation: 6 in the left subtree of 5, below an in-order parent.
#guard bstOrdered compare
  (BinaryTree.node 5 (.node 2 (.node 1 .nil .nil) (.node 6 .nil .nil)) (.node 8 .nil .nil)) == false

/-! ## The order overlay (helper, not the instance) -/

-- A valid BST: every node toned `ok`, `invariants ok` caption.
#guard Render.textReport (treeWithOrderCheck (fun n : Nat => toString n)
    (.node 2 (.node 1 .nil .nil) (.node 3 .nil .nil)) compare)
  == "tree: 3 nodes, depth 2\n2 <ok>\n  1 <ok>\n  3 <ok>\ninvariants ok"

-- A crafted violation: both out-of-place children flagged with `ord`.
#guard Render.textReport (treeWithOrderCheck (fun n : Nat => toString n)
    (.node 5 (.node 7 .nil .nil) (.node 9 .nil .nil)) compare)
  == "tree: 3 nodes, depth 2\n5 <ok>\n  7 [ord] <violation>\n  9 <ok>\n⚠ r.0 (ord)"

-- The deep violation is flagged at the guilty node only.
#guard RB.violationCount (treeWithOrderCheck (fun n : Nat => toString n)
    (.node 5 (.node 2 (.node 1 .nil .nil) (.node 6 .nil .nil)) (.node 8 .nil .nil)) compare) == 1

-- The overlay respects the comparator: reversed order flips the verdicts.
#guard RB.violationCount (treeWithOrderCheck (fun n : Nat => toString n)
    (.node 2 (.node 3 .nil .nil) (.node 1 .nil .nil)) (fun a b => compare b a)) == 0

end TreeScopeTests
