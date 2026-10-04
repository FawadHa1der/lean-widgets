import TreeScopeTests.Helpers

/-! # Binomial-heap instance tests

Forest shape and rank sublabels pinned in text mode; the heap-property
checker (`heapOrdered`) catches crafted violating raw nodes (which could
never carry a `WF` proof) and passes real push-fold heaps; rank checkers
(`ranksValid`); and the `deleteMin` filmstrip pinned.
-/

namespace TreeScopeTests

open TreeScope TreeScope.HeapView
open Batteries.BinomialHeap.Imp (Heap HeapNode)
open Batteries (BinomialHeap)

/-! ## Crafted raw heaps (no `WF` proof possible) -/

/-- Heap-property violation: parent 5 with child 3 under `· ≤ ·`. -/
def hViol : Heap Nat := .cons 1 5 (.node 3 .nil .nil) .nil

/-- Deeper violation: the bad edge is `2 → 1` inside the second tree. -/
def hViolDeep : Heap Nat :=
  .cons 0 0 .nil (.cons 1 2 (.node 1 .nil .nil) .nil)

/-- Sibling violation: first child fine, second child (sibling) bad. -/
def hViolSib : Heap Nat :=
  .cons 2 4 (.node 5 (.node 6 .nil .nil) (.node 3 .nil .nil)) .nil

/-- Valid crafted forest: ranks 0 then 1, all edges ordered. -/
def hOk : Heap Nat := .cons 0 2 .nil (.cons 1 1 (.node 3 .nil .nil) .nil)

/-- Stored rank 2 disagrees with the structural rank 1. -/
def hRankBad : Heap Nat := .cons 2 1 (.node 2 .nil .nil) .nil

/-- Ranks not strictly increasing (1 then 1). -/
def hRankOrderBad : Heap Nat :=
  .cons 1 1 (.node 2 .nil .nil) (.cons 1 3 (.node 4 .nil .nil) .nil)

/-! ## `heapOrdered` -/

#guard heapOrdered (· ≤ ·) hViol == false
#guard heapOrdered (· ≤ ·) hViolDeep == false
#guard heapOrdered (· ≤ ·) hViolSib == false
#guard heapOrdered (· ≤ ·) hOk == true
#guard heapOrdered (· ≤ ·) (Heap.nil : Heap Nat) == true
-- The *same* forest under the reversed order: violations flip.
#guard heapOrdered (· ≥ ·) hViol == true

/-! ## `ranksValid` -/

#guard ranksValid hOk == true
#guard ranksValid hRankBad == false
#guard ranksValid hRankOrderBad == false
#guard ranksValid (Heap.nil : Heap Nat) == true

/-! ## Real heaps (push folds) always pass -/

/-- 3-element push fold. -/
def bh3 : BinomialHeap Nat (· ≤ ·) := [3, 1, 2].foldl (·.insert ·) .empty
/-- 9-element push fold (the demo heap). -/
def bh9 : BinomialHeap Nat (· ≤ ·) := TreeScope.Demo.heapSample
/-- 16-element push fold (a single rank-4 tree). -/
def bh16 : BinomialHeap Nat (· ≤ ·) := (List.range 16).foldl (·.insert ·) .empty
/-- After one `deleteMin` (forest restructured). -/
def bh9' : BinomialHeap Nat (· ≤ ·) := (bh9.deleteMin.map (·.2)).getD .empty

#guard heapOrdered (· ≤ ·) bh3.1 == true
#guard heapOrdered (· ≤ ·) bh9.1 == true
#guard heapOrdered (· ≤ ·) bh16.1 == true
#guard heapOrdered (· ≤ ·) bh9'.1 == true
#guard ranksValid bh3.1 == true
#guard ranksValid bh9.1 == true
#guard ranksValid bh16.1 == true
#guard ranksValid bh9'.1 == true

-- Healthy heaps produce violation-free views; the crafted ones do not.
#guard RB.violationCount (toTreeView bh9) == 0
#guard RB.violationCount (toTreeView bh16) == 0
#guard RB.violationCount (heapView (fun n => toString n) (· ≤ ·) hViol) == 1
#guard RB.violationCount (heapView (fun n => toString n) (· ≤ ·) hViolSib) == 1
#guard RB.violationCount (heapView (fun n => toString n) (· ≤ ·) hRankBad) == 1

-- The violating child carries the `heap` badge (flagged node, not parent).
#guard Render.textReport (heapView (fun n => toString n) (· ≤ ·) hViol)
  == "tree: 3 nodes, depth 3\nheap · n=2\n  5 · rank=1\n    3 [heap] <violation>\n⚠ r.0.0 (heap)"

-- Rank badges land on the offending root.
#guard Render.textReport (heapView (fun n => toString n) (· ≤ ·) hRankBad)
  == "tree: 3 nodes, depth 3\nheap · n=2\n  1 · rank=2 [rank] <violation>\n    2\n⚠ r.0 (rank)"

/-! ## Pinned instance rendering (text mode)

A checked-and-clean non-empty heap carries the `ok` tone on its synthetic
root, so the generic caption reports `invariants ok` — exactly like a clean
RB tree. -/

/--
info: tree: 4 nodes, depth 3
heap · n=3 <ok>
  2 · rank=0
  1 · rank=1
    3
invariants ok
-/
#guard_msgs in
#tree_scope (text := true) bh3

-- The 9-element demo heap: forest of ranks 0 and 3, sibling-order children.
/--
info: tree: 10 nodes, depth 5
heap · n=9 <ok>
  6 · rank=0
  1 · rank=3
    2
      4
        7
      9
    3
      5
    8
invariants ok
-/
#guard_msgs in
#tree_scope (text := true) TreeScope.Demo.heapSample

-- The empty heap: nothing was checked, so no `ok` tone and no caption
-- (mirroring the RB `(empty)` convention).
/--
info: tree: 1 nodes, depth 1
heap · n=0
-/
#guard_msgs in
#tree_scope (text := true) (Batteries.BinomialHeap.empty : Batteries.BinomialHeap Nat (· ≤ ·))

-- Crafted violating forests keep a neutral root: the caption lists the
-- violations, never `invariants ok`.
#guard (heapView (fun n => toString n) (· ≤ ·) hViol).tone == .neutral
#guard (heapView (fun n => toString n) (· ≤ ·) hOk).tone == .ok

/-! ## The `deleteMin` filmstrip (pinned)

The final `deleteMin` step *shrinks* the heap: its caption counts both the
new `(label, path)` pairs and the four that vanished (`+3 new, −4 gone`) —
a deletion never reads as pure growth.  (The reshuffling inserts also show
`gone` counts: binomial-tree merges move values to new paths.) -/

/--
info: filmstrip: 6 frames
== step 0: init
tree: 1 nodes, depth 1
heap · n=0
== step 1: (·.insert 5) (+1 new)
tree: 2 nodes, depth 2
heap · n=1 <ok>
  5 · rank=0 [new] <added>
invariants ok
== step 2: (·.insert 3) (+2 new, −1 gone)
tree: 3 nodes, depth 3
heap · n=2 <ok>
  3 · rank=1 [new] <added>
    5 [new] <added>
invariants ok
== step 3: (·.insert 8) (+3 new, −2 gone)
tree: 4 nodes, depth 3
heap · n=3 <ok>
  8 · rank=0 [new] <added>
  3 · rank=1 [new] <added>
    5 [new] <added>
invariants ok
== step 4: (·.insert 1) (+4 new, −3 gone)
tree: 5 nodes, depth 4
heap · n=4 <ok>
  1 · rank=2 [new] <added>
    3 [new] <added>
      5 [new] <added>
    8 [new] <added>
invariants ok
== step 5: (fun h => (h.deleteMin.map (·.2)).getD .empty) (+3 new, −4 gone)
tree: 4 nodes, depth 3
heap · n=3 <ok>
  8 · rank=0 [new] <added>
  3 · rank=1 [new] <added>
    5 [new] <added>
invariants ok
-/
#guard_msgs in
#tree_evolve (text := true) (Batteries.BinomialHeap.empty : Batteries.BinomialHeap Nat (· ≤ ·)) [
  (·.insert 5), (·.insert 3), (·.insert 8), (·.insert 1),
  (fun h => (h.deleteMin.map (·.2)).getD .empty)]

/-! ## Type-carried `le` wiring pin

A *max*-heap (`· ≥ ·`) rendered through the real `ToTreeView` instance must be
violation-free: the instance forwards the `le` carried by the heap's type, and
a hardcoded `(· ≤ ·)` would flag every max-ordered parent/child edge. -/

def bhMax : BinomialHeap Nat (· ≥ ·) := [3, 1, 4, 1, 5, 9, 2, 6].foldl (·.insert ·) .empty

#guard RB.violationCount (toTreeView bhMax) == 0
-- 8 pushes (duplicates kept) under the synthetic forest root: 9 nodes.
#guard (toTreeView bhMax).size == 9

end TreeScopeTests
