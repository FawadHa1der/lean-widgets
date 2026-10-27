import GraphScopeTests.InsertTests
-- `Finset`'s `Repr` instance lives in `Mathlib.Data.Finset.Sort`, which the
-- rest of the suite does not import (there, `Finset` vertices fall back to
-- index labels, which fail the round-trip gate).  `import Mathlib` — e.g.
-- QED64's showcase file — brings it in, and then Hasse diagrams of `Finset`s
-- get edge and vertex links with `Finset`-literal labels (`∅`, `{0}`, …).
import Mathlib.Data.Finset.Sort

/-! # Click-to-insert on Hasse diagrams through Mathlib's quantifying instance
(v4.35.0 post-audit)

Since Mathlib v4.35.0, `hasse α` is decidable through an instance that decides
`a ⋖ b` by quantifying over `α`, so every single adjacency costs a pass over
the vertex type.  The adjacency-cost guard (`GraphScope/Gate.lean`) withholds
the connectivity link for such graphs; edge and vertex links are still
offered.  This file compiles *every* offered text on the configurations where
that cost is highest: non-linear Hasse diagrams with `Finset`-literal labels
(where `<` is itself a `Finset` computation), including the audit's
`hasse (Finset (Fin 4))`, and the 64-vertex cap on `hasse (Fin 64)`. -/

namespace GraphScopeTests

open SimpleGraph

/-- info: compiled 8 insertions (4 edges, 4 degrees, connectivity: no; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (hasse (Finset (Fin 2)))

/-- info: compiled 20 insertions (12 edges, 8 degrees, connectivity: no; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (hasse (Finset (Fin 3)))

-- The audit's graph: all 32 edge and 16 vertex links compile; the
-- connectivity link, whose `decide` exhausts `maxHeartbeats 200000`, is not
-- offered.
/-- info: compiled 48 insertions (32 edges, 16 degrees, connectivity: no; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (hasse (Finset (Fin 4)))

-- The same 4-cube through a non-quantifying adjacency (`⊆` and `card`, which
-- the adjacency-cost guard validates; round-2 re-audit): the connectivity
-- example still exceeds the default budget (822363 heartbeats), so the cost
-- model withholds it; every edge and vertex link compiles.
/-- info: compiled 48 insertions (32 edges, 16 degrees, connectivity: no; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true)
  (SimpleGraph.fromRel fun a b : Finset (Fin 4) => a ⊆ b ∧ a.card + 1 = b.card)

-- The vertex cap with the quantifying instance: every degree fact decides 64
-- adjacencies, each a pass over `Fin 64`.
/-- info: compiled 127 insertions (63 edges, 64 degrees, connectivity: no; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (hasse (Fin 64))

end GraphScopeTests
