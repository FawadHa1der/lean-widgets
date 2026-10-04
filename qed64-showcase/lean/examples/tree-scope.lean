import Mathlib
import TreeScope

/-! # TreeScope: any tree-shaped value, drawn
Cursor on a `#tree_scope v` line: an "HTML Display" panel draws `v` as a tree.
Types with a semantic instance (red–black maps, binomial heaps, Mathlib
`BinaryTree`, `Std.TreeMap`) show their meaning — node colours, `bh=` / `rank=`
sublabels, and a caption that checks the invariants (violations are flagged
on the guilty nodes); any other concrete inductive value is shown as its
constructor tree by reflection (no `Repr` needed).
`#tree_evolve init [op₁, …]` shows a filmstrip of frames with `new` badges;
`#html renderForest …` lays out a gallery of small trees. -/

namespace Showcase.TreeScope

-- Reflection: a list is a `cons` chain; literals fold into the labels.
#tree_scope [10, 20, 30]

/-- A tiny arithmetic AST (no `Repr` instance: pure term reflection). -/
inductive Arith where
  | num (n : Nat)
  | add (a b : Arith)
  | mul (a b : Arith)

/-- `(1 + 2 * 3) * (4 + 5)` as an `Arith` value. -/
def sample : Arith := .mul (.add (.num 1) (.mul (.num 2) (.num 3))) (.add (.num 4) (.num 5))
#tree_scope sample

/-- A red–black map: colours, black-heights and an `invariants ok` caption. -/
def rbSample : Lean.RBMap Nat String compare :=
  Lean.RBMap.ofList [(5, "e"), (2, "b"), (8, "h"), (1, "a"), (4, "d"), (7, "g"), (3, "c")]
#tree_scope rbSample

/-- Hand-built and INVALID: a red-red chain and a black-height mismatch. -/
def brokenRB : Lean.RBNode Nat (fun _ => String) :=
  .node .black (.node .red (.node .red .leaf 1 "a" .leaf) 2 "b" .leaf) 5 "e"
    (.node .black .leaf 8 "h" (.node .black .leaf 9 "i" .leaf))
#tree_scope brokenRB

-- Filmstrip: five inserts into a red–black map, rotations lighting up `new`.
#tree_evolve (Lean.RBMap.empty : Lean.RBMap Nat String compare) [
  (·.insert 1 "a"), (·.insert 2 "b"), (·.insert 3 "c"), (·.insert 4 "d"), (·.insert 5 "e")]

-- All 5 = catalan 3 binary-tree shapes with 3 internal nodes.
open _root_.TreeScope in
#html renderForest (BinTree.catalanGallery 3) (maxRowWidth := 600)

end Showcase.TreeScope
