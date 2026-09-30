import TreeScope.Widget
import TreeScope.Evolve
import TreeScope.Instances.RB
import TreeScope.Instances.Heap
import TreeScope.Instances.MathlibTree
import TreeScope.Instances.StdTreeMap

/-! # TreeScope demos (stage 1: reflection)

Open this file in the editor and put the cursor on any `#tree_scope` line to
see the rendered constructor tree in the InfoView.

Reflection shows the *evaluated* value: definitions unfold, arithmetic
reduces, and `Nat`/`Int`/`String`/`Char` literals fold into their parent
node's label.
-/

namespace TreeScope.Demo

/-! ## Built-in types -/

-- A list: a `cons` chain, with the `Nat` elements folded into the labels.
#tree_scope [10, 20, 30]

-- Option nesting: children only where the field type is an inductive.
#tree_scope (some (some (none : Option Nat)))

-- The value is *evaluated*, not shown as syntax: this renders the single node `4`.
#tree_scope (2 + 2)

-- Pairs: the second component is a literal that comes after the nested-pair
-- child, so the label uses positional `_` placeholders.
#tree_scope ((1, some 2), 3)

-- Floats fold like any other literal (compiled-evaluated, `toString`-printed):
-- this renders the single node `mk 1.500000 -2.500000`.
#tree_scope ((1.5 : Float), (-2.5 : Float))

-- A cons chain deeper than the 64-level cap is compacted to a depth-2
-- sequence (`chain · n=71`) instead of being refused.
#tree_scope (List.range 70)

/-! ## A user-defined inductive: a small arithmetic AST -/

/-- A tiny arithmetic expression AST for the reflection demo. -/
inductive Arith where
  /-- Literal. -/
  | num (n : Nat)
  /-- Addition. -/
  | add (a b : Arith)
  /-- Multiplication. -/
  | mul (a b : Arith)

/-- `(1 + 2 * 3) * (4 + 5)` as an `Arith` value. -/
def sample : Arith :=
  .mul (.add (.num 1) (.mul (.num 2) (.num 3))) (.add (.num 4) (.num 5))

-- The AST as a tree (note: no `Repr` instance exists — this is term-structure
-- reflection, not `Repr`).
#tree_scope sample

/-! ## A hand-annotated `TreeView` and a gallery (the pure model directly) -/

open ProofWidgets TreeView in
/-- A hand-built red–black-ish tree showing tones, badges and a collapsed stub. -/
def annotated : TreeView :=
  make "8" (tone := .rbBlack) (sublabel := "bh=2") (children := #[
    make "4" (tone := .rbRed) (children := #[
      leaf "2" |>.withTone .rbBlack |>.addBadge "min",
      leaf "6" |>.withTone .rbBlack]),
    make "12" (tone := .rbBlack) (children := #[
      leaf "10" |>.withTone .violation,
      make "14" (collapsed := true) (children := #[leaf "13", leaf "15"])
        |>.withTone .added])])

#html renderPanel annotated

open TreeView in
-- A grid of small trees (the stage-2 Catalan gallery uses this renderer).
#html renderForest #[
    make "a" #[leaf "x", leaf "y"],
    make "b" #[make "c" #[leaf "z"]],
    leaf "d",
    make "e" #[leaf "p", leaf "q", leaf "r"]]
  (maxRowWidth := 500)

/-! # Stage-2 demos: semantic instances -/

/-! ## Red–black maps (`Lean.RBMap`)

The semantic instance shows node colors, black-heights, and the health
caption — all invariants checked with the map's own comparator. -/

/-- An 8-entry map for the semantic-view and reflection-comparison demos. -/
def rbSample : Lean.RBMap Nat String compare :=
  Lean.RBMap.ofList [(5, "e"), (2, "b"), (8, "h"), (1, "a"), (4, "d"),
                     (7, "g"), (3, "c"), (6, "f")]

-- The semantic view (colors, `bh=` sublabels, `invariants ok` caption).
#tree_scope rbSample

-- The same value, forced through stage-1 reflection: the raw constructor
-- tree (`Subtype.mk` / `node` / color constructors), no semantics.
#tree_scope (reflect := true) rbSample

/-! ### RB evolution: 8 inserts, recoloring and rotations across frames

Watch the `new` badges: an insert that triggers a rotation re-labels interior
paths, so several nodes light up at once. -/

#tree_evolve (Lean.RBMap.empty : Lean.RBMap Nat String compare) [
  (·.insert 1 "a"), (·.insert 2 "b"), (·.insert 3 "c"), (·.insert 4 "d"),
  (·.insert 5 "e"), (·.insert 6 "f"), (·.insert 7 "g"), (·.insert 8 "h")]

-- A shrinking step reads as removal, not growth: the `erase` frame is
-- captioned `(+a new, −r gone)` with the vanished `(label, path)` pairs
-- counted by the mirror diff.
#tree_evolve ((Lean.RBMap.empty : Lean.RBMap Nat String compare).insert 1 "a"
    |>.insert 2 "b" |>.insert 3 "c") [
  (·.erase 2)]

/-! ### The teaching money-shot: a hand-crafted *invalid* red–black tree

Raw constructors, deliberately broken: a red-red chain on the left and a
black-height mismatch — both flagged in the view and listed in the caption.
(A real `RBMap` can never reach this state; its text mode is pinned by the
tests.) -/

open Lean in
/-- Invalid on purpose: `1` is a red child of red `2` (red-red), and `8`'s
subtrees have black-heights 0 and 1 (bh mismatch). -/
def brokenRB : RBNode Nat (fun _ => String) :=
  .node .black
    (.node .red (.node .red .leaf 1 "a" .leaf) 2 "b" .leaf)
    5 "e"
    (.node .black .leaf 8 "h" (.node .black .leaf 9 "i" .leaf))

#tree_scope brokenRB

/-! ## Binomial heaps (`Batteries.BinomialHeap`) -/

/-- A 9-element heap built by a fold of pushes (`insert`). -/
def heapSample : Batteries.BinomialHeap Nat (· ≤ ·) :=
  [5, 3, 8, 1, 9, 2, 7, 4, 6].foldl (fun h a => h.insert a) .empty

-- The forest view: one binomial tree per rank, `rank=` sublabels.
#tree_scope heapSample

-- Push fold, then one `deleteMin`: the forest restructures in the last frame.
#tree_evolve (Batteries.BinomialHeap.empty : Batteries.BinomialHeap Nat (· ≤ ·)) [
  (·.insert 5), (·.insert 3), (·.insert 8), (·.insert 1),
  (fun h => (h.deleteMin.map (·.2)).getD .empty)]

/-! ## Mathlib binary trees and the Catalan gallery -/

-- A `BinaryTree` via its instance: both-nil children elided, single-`nil`
-- children shown as `∅` stubs.
#tree_scope (BinaryTree.node 2 (.node 1 .nil .nil) (.node 3 (.node 4 .nil .nil) .nil))

-- The order overlay is a helper, not the instance: a broken BST, flagged.
#html renderPanel (BinTree.treeWithOrderCheck (fun n => toString n)
  (BinaryTree.node 5 (.node 7 .nil .nil) (.node 9 .nil .nil)) compare)

-- All 14 = catalan 4 binary-tree shapes with 4 internal nodes.
#html renderForest (BinTree.catalanGallery 4) (maxRowWidth := 900)

/-! ## `Std.TreeMap` (stretch): stored sizes checked, order checked -/

#tree_scope (Std.TreeMap.ofList [(3, "c"), (1, "a"), (2, "b"), (4, "d")] compare)

end TreeScope.Demo
