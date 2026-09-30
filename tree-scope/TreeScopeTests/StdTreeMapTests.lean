import TreeScopeTests.Helpers

/-! # `Std.TreeMap` instance tests (stretch)

The size-balanced-BST view: stored `size` fields as sublabels checked against
recomputed sizes, BST order checked with the type's comparator; crafted raw
`Impl` trees for both violations; `ofList` maps always healthy.
-/

namespace TreeScopeTests

open TreeScope TreeScope.STM
open Std.DTreeMap.Internal (Impl)

/-! ## Crafted raw trees -/

/-- Valid: sizes correct, order correct. -/
def impOk : Impl Nat (fun _ => Nat) :=
  .inner 3 2 20 (.inner 1 1 10 .leaf .leaf) (.inner 1 3 30 .leaf .leaf)

/-- Stored root size lies (5 ≠ 3). -/
def impSzBad : Impl Nat (fun _ => Nat) :=
  .inner 5 2 20 (.inner 1 1 10 .leaf .leaf) (.inner 1 3 30 .leaf .leaf)

/-- Order violation: 7 in the left subtree of 5. -/
def impOrdBad : Impl Nat (fun _ => Nat) :=
  .inner 3 5 50 (.inner 1 7 70 .leaf .leaf) (.inner 1 9 90 .leaf .leaf)

#guard realSize impOk == 3
#guard realSize (Impl.leaf : Impl Nat (fun _ => Nat)) == 0
#guard sizesConsistent impOk == true
#guard sizesConsistent impSzBad == false
#guard ordered compare impOk == true
#guard ordered compare impOrdBad == false

-- The view flags exactly the guilty nodes.
#guard RB.violationCount (implView (fun n => toString n) (fun v => toString v) compare impOk) == 0
#guard RB.violationCount (implView (fun n => toString n) (fun v => toString v) compare impSzBad) == 1
#guard Render.textReport (implView (fun n => toString n) (fun v => toString v) compare impOrdBad)
  == "tree: 3 nodes, depth 2\n5:50 · sz=3\n  7:70 · sz=1 [ord] <violation>\n  9:90 · sz=1\n⚠ r.0 (ord)"

/-! ## Pinned instance rendering

A checked-and-clean non-empty map carries the `ok` tone on its root, so the
generic caption reports `invariants ok` — exactly like a clean RB tree. -/

/--
info: tree: 4 nodes, depth 3
2:"b" · sz=4 <ok>
  1:"a" · sz=1
  3:"c" · sz=2
    4:"d" · sz=1
invariants ok
-/
#guard_msgs in
#tree_scope (text := true) (Std.TreeMap.ofList [(3, "c"), (1, "a"), (2, "b"), (4, "d")] compare)

-- The empty map stays the neutral `(empty)` node: nothing checked, no caption.
/--
info: tree: 1 nodes, depth 1
(empty)
-/
#guard_msgs in
#tree_scope (text := true) (Std.TreeMap.empty : Std.TreeMap Nat Nat compare)

-- A violating tree never gets the `ok` root (the guilty node keeps its tone).
#guard (implView (fun n => toString n) (fun v => toString v) compare impOk).tone == .ok
#guard (implView (fun n => toString n) (fun v => toString v) compare impSzBad).tone == .violation
#guard (implView (fun n => toString n) (fun v => toString v) compare impOrdBad).tone != .ok

/-! ## Library maps are always healthy -/

/-- 20 sorted inserts. -/
def tmSorted : Std.TreeMap Nat Nat compare := Std.TreeMap.ofList ((List.range 20).map fun i => (i, i))
/-- 20 reversed inserts. -/
def tmRev : Std.TreeMap Nat Nat compare := Std.TreeMap.ofList ((List.range 20).reverse.map fun i => (i, i))
/-- Shuffled (full cycle mod 20). -/
def tmShuf : Std.TreeMap Nat Nat compare := Std.TreeMap.ofList ((List.range 20).map fun i => ((i * 7) % 20, i))

#guard sizesConsistent tmSorted.inner.inner == true
#guard sizesConsistent tmRev.inner.inner == true
#guard sizesConsistent tmShuf.inner.inner == true
#guard ordered compare tmSorted.inner.inner == true
#guard ordered compare tmRev.inner.inner == true
#guard ordered compare tmShuf.inner.inner == true
#guard RB.violationCount (toTreeView tmSorted) == 0
#guard RB.violationCount (toTreeView tmRev) == 0
#guard RB.violationCount (toTreeView tmShuf) == 0

end TreeScopeTests
