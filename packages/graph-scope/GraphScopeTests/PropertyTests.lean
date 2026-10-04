import GraphScopeTests.Helpers

/-! # Property tests

Cross-cutting invariants on every test graph (pure layer), and the same
invariants on `GraphData` extracted from every demo `SimpleGraph` term through
the real elaboration pipeline (`#assert_graph_invariants`, a throwing
compile-time assertion).

Invariants: normalization well-formedness, handshake lemma
(`Σ deg = 2·|E|`), component-id sanity, validated bipartition evidence, and
isolated = degree-0.
-/

namespace GraphScopeTests

open SimpleGraph GraphScope GraphScope.Demo

/-! ## Pure layer -/

#guard allInvariants (path 0)
#guard allInvariants (path 1)
#guard allInvariants (path 5)
#guard allInvariants (cycle 3)
#guard allInvariants (cycle 6)
#guard allInvariants (cycle 9)
#guard allInvariants (complete 5)
#guard allInvariants (star 7)
#guard allInvariants twoPaths
#guard allInvariants (empty 4)
#guard allInvariants (GraphData.ofEdges 5 #[(0, 1), (1, 2), (2, 3), (3, 4), (2, 4)])
#guard allInvariants (GraphData.ofEdges 8 #[(3, 2), (1, 1), (2, 3), (9, 0), (1, 0), (6, 5)])

-- Exhaustive sweep: paths, cycles, stars and complete graphs up to 12 vertices.
#guard ((Array.range 12).map fun n => allInvariants (path (n + 1))).all id
#guard ((Array.range 10).map fun n => allInvariants (cycle (n + 3))).all id
#guard ((Array.range 11).map fun n => allInvariants (star (n + 1))).all id
#guard ((Array.range 8).map fun n => allInvariants (complete (n + 1))).all id

-- Handshake lemma spelled out on a few pinned cases.
#guard (path 5).degreeSequence.foldl (· + ·) 0 == 8
#guard (complete 6).degreeSequence.foldl (· + ·) 0 == 30
#guard (star 9).degreeSequence.foldl (· + ·) 0 == 16

-- Bipartiteness of cycles alternates with parity (C₃ … C₁₂).
#guard ((Array.range 10).map fun n => (cycle (n + 3)).isBipartite)
  == #[false, true, false, true, false, true, false, true, false, true]

/-! ## Extraction layer: every demo graph -/

#assert_graph_invariants (pathGraph 5)
#assert_graph_invariants (pathGraph 1)
#assert_graph_invariants (cycleGraph 5)
#assert_graph_invariants (cycleGraph 6)
#assert_graph_invariants (completeGraph (Fin 5))
#assert_graph_invariants (⊥ : SimpleGraph (Fin 4))
#assert_graph_invariants (⊥ : SimpleGraph (Fin 0))
#assert_graph_invariants twoTriangles
#assert_graph_invariants star5
#assert_graph_invariants (completeBipartiteGraph (Fin 2) (Fin 3))
#assert_graph_invariants (completeGraph (Fin 64))  -- exactly at the cap

end GraphScopeTests
