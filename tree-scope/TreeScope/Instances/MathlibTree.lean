import TreeScope.Render
import TreeScope.ToTreeView
import Mathlib.Data.Tree.Basic
import Mathlib.Combinatorics.Enumerative.Catalan.Tree

/-! # TreeScope instances: Mathlib's `BinaryTree`

In this Mathlib pin the classic `Tree α` has been renamed to `BinaryTree α`
(`Tree` survives only as a deprecated alias), with constructors `nil` and
`node (value) (left) (right)`.

`nil` convention (chosen, documented, tested): a node whose children are
**both** `nil` renders as a childless leaf; when exactly one child is `nil`,
*both* children are rendered — the `nil` as a small `∅` stub — so the
left/right shape is never ambiguous (unlike RB trees, plain binary trees have
no keys to disambiguate a single child's side).  A `nil` at the *root*
renders as the single node `∅`.

The optional order overlay `treeWithOrderCheck` (a helper, deliberately not
the instance) checks the BST property w.r.t. an explicit comparator: nodes in
order are toned `ok`, violating nodes `violation` with an `ord` badge, and
`∅` stubs stay neutral.

## Catalan gallery

`allBinTrees n` enumerates the shapes with `n` internal nodes directly (a
deterministic list, ordered by left-subtree size); it is proven equal to
Mathlib's `BinaryTree.treesOfNumNodesEq n` *as a set* by the tests
(`length = card = catalan n`, no duplicates, and every element a member —
`Finset` order itself is a quotient artifact, so the gallery keeps its own
deterministic order).  `catalanGallery n` maps the shapes to `•`-labeled
views for `renderForest`.
-/

namespace TreeScope.BinTree

universe u

variable {α : Type u}

/-! ## The instance view -/

/-- The view of a `BinaryTree` (see the module docstring for the `nil`
convention). -/
def binTreeView (rep : α → String) : BinaryTree α → TreeView
  | .nil => .leaf "∅"
  | .node v l r =>
    let kids : Array TreeView :=
      match l, r with
      | .nil, .nil => #[]
      | l, r => #[binTreeView rep l, binTreeView rep r]
    .make (rep v) kids

/-! ## The order overlay (helper, not the instance) -/

/-- Is the tree a BST w.r.t. `cmp` (every key strictly inside its ancestor
bounds)? -/
def bstOrderedWithin (cmp : α → α → Ordering) :
    BinaryTree α → Option α → Option α → Bool
  | .nil, _, _ => true
  | .node v l r, lo, hi =>
    (lo.all fun a => cmp a v == .lt) && (hi.all fun b => cmp v b == .lt)
      && bstOrderedWithin cmp l lo (some v) && bstOrderedWithin cmp r (some v) hi

/-- Is the tree a BST w.r.t. `cmp`? -/
def bstOrdered (cmp : α → α → Ordering) (t : BinaryTree α) : Bool :=
  bstOrderedWithin cmp t none none

/-- The order-overlay recursion: carries the open ancestor interval. -/
def orderGo (rep : α → String) (cmp : α → α → Ordering) :
    BinaryTree α → Option α → Option α → TreeView
  | .nil, _, _ => .leaf "∅"
  | .node v l r, lo, hi =>
    let bad := !((lo.all fun a => cmp a v == .lt) && (hi.all fun b => cmp v b == .lt))
    let kids : Array TreeView :=
      match l, r with
      | .nil, .nil => #[]
      | l, r => #[orderGo rep cmp l lo (some v), orderGo rep cmp r (some v) hi]
    .mk (rep v) none (if bad then #["ord"] else #[])
      (if bad then .violation else .ok) false kids

/-- The BST-order overlay of a binary tree: in-order nodes toned `ok`,
violators `violation` + `ord` badge (`∅` stubs neutral).  A helper on top of
the plain instance view — pass the comparator explicitly. -/
def treeWithOrderCheck (rep : α → String) (t : BinaryTree α)
    (cmp : α → α → Ordering) : TreeView :=
  orderGo rep cmp t none none

/-! ## Catalan gallery -/

/-- All binary-tree *shapes* with `n` internal nodes, as a deterministic list
ordered by left-subtree size (0, 1, …, n−1).  Set-equal to Mathlib's
`BinaryTree.treesOfNumNodesEq n` (pinned by the tests, together with
`length = catalan n`). -/
def allBinTrees : Nat → List (BinaryTree Unit)
  | 0 => [.nil]
  | n + 1 =>
    (List.range (n + 1)).attach.flatMap fun ⟨i, _hi⟩ =>
      (allBinTrees i).flatMap fun l =>
        (allBinTrees (n - i)).map fun r => .node () l r
  decreasing_by
    all_goals (have := List.mem_range.mp _hi; omega)

/-- The gallery: every shape with `n` internal nodes as a `•`-labeled view
(in `allBinTrees` order), ready for `renderForest`. -/
def catalanGallery (n : Nat) : Array TreeView :=
  (allBinTrees n).toArray.map (binTreeView fun _ => "•")

end BinTree

/-- `BinaryTree` semantic view: values as labels, both-`nil` children elided,
single `nil` children shown as `∅` stubs. -/
instance {α : Type u} [Repr α] : ToTreeView (BinaryTree α) :=
  ⟨BinTree.binTreeView reprStr⟩

end TreeScope
