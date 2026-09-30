import GraphScopeTests.Helpers

/-! # `#graph_scope` command tests

Message-exact `#guard_msgs` pins of the deterministic `(text := true)` mode —
extraction through real Mathlib `SimpleGraph` terms and their `Decidable`
instances — plus every user-facing error message.
-/

namespace GraphScopeTests

open SimpleGraph GraphScope.Demo

/-! ## Concrete Mathlib graphs -/

/--
info: graph: 4 vertices, 3 edges
edges: 0-1 1-2 2-3
degrees: 1 2 2 1 (min 1, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2} / {1, 3})
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4)

-- Count-1 nouns are singular: `1 vertex` (and `1 edge`, pinned further down).
/--
info: graph: 1 vertex, 0 edges
edges: (none)
degrees: 0 (min 0, max 0)
components: 1 (connected)
bipartite: yes (parts: {0} / {})
isolated: 0
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 1)

/--
info: graph: 2 vertices, 1 edge
edges: 0-1
degrees: 1 1 (min 1, max 1)
components: 1 (connected)
bipartite: yes (parts: {0} / {1})
-/
#guard_msgs in
#graph_scope (text := true) (⊤ : SimpleGraph (Fin 2))

/--
info: graph: 5 vertices, 5 edges
edges: 0-1 0-4 1-2 2-3 3-4
degrees: 2 2 2 2 2 (min 2, max 2)
components: 1 (connected)
bipartite: no (odd cycle: 2-1-0-4-3)
-/
#guard_msgs in
#graph_scope (text := true) (cycleGraph 5)

/--
info: graph: 6 vertices, 6 edges
edges: 0-1 0-5 1-2 2-3 3-4 4-5
degrees: 2 2 2 2 2 2 (min 2, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2, 4} / {1, 3, 5})
-/
#guard_msgs in
#graph_scope (text := true) (cycleGraph 6)

/--
info: graph: 4 vertices, 6 edges
edges: 0-1 0-2 0-3 1-2 1-3 2-3
degrees: 3 3 3 3 (min 3, max 3)
components: 1 (connected)
bipartite: no (odd cycle: 1-0-2)
-/
#guard_msgs in
#graph_scope (text := true) (completeGraph (Fin 4))

/--
info: graph: 3 vertices, 0 edges
edges: (none)
degrees: 0 0 0 (min 0, max 0)
components: 3 (disconnected)
bipartite: yes (parts: {0, 1, 2} / {})
isolated: 0, 1, 2
-/
#guard_msgs in
#graph_scope (text := true) (⊥ : SimpleGraph (Fin 3))

/--
info: graph: 0 vertices, 0 edges
edges: (none)
degrees: (none)
components: 0 (empty)
bipartite: yes (parts: {} / {})
-/
#guard_msgs in
#graph_scope (text := true) (⊥ : SimpleGraph (Fin 0))

-- `fromEdgeSet` over `Set` literals on a `DecidableEq` vertex type is
-- decidable out of the box: the empty literal…
/--
info: graph: 3 vertices, 0 edges
edges: (none)
degrees: 0 0 0 (min 0, max 0)
components: 3 (disconnected)
bipartite: yes (parts: {0, 1, 2} / {})
isolated: 0, 1, 2
-/
#guard_msgs in
#graph_scope (text := true) (SimpleGraph.fromEdgeSet (∅ : Set (Sym2 (Fin 3))))

-- …and a nonempty `insert` literal both extract without any local instance.
/--
info: graph: 3 vertices, 2 edges
edges: 0-1 1-2
degrees: 1 2 1 (min 1, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2} / {1})
-/
#guard_msgs in
#graph_scope (text := true) (SimpleGraph.fromEdgeSet {s(0, 1), s(1, 2)} : SimpleGraph (Fin 3))

/--
info: graph: 6 vertices, 6 edges
edges: 0-1 0-2 1-2 3-4 3-5 4-5
degrees: 2 2 2 2 2 2 (min 2, max 2)
components: 2 (disconnected)
bipartite: no (odd cycle: 1-0-2)
-/
#guard_msgs in
#graph_scope (text := true) twoTriangles

/--
info: graph: 6 vertices, 5 edges
edges: 0-1 0-2 0-3 0-4 0-5
degrees: 5 1 1 1 1 1 (min 1, max 5)
components: 1 (connected)
bipartite: yes (parts: {0} / {1, 2, 3, 4, 5})
-/
#guard_msgs in
#graph_scope (text := true) star5

-- Non-`Fin` vertex type: labels come from `Repr`, indices from the
-- `Fintype` enumeration (left part first).
/--
info: graph: 5 vertices, 6 edges
labels: Sum.inl 0, Sum.inl 1, Sum.inr 0, Sum.inr 1, Sum.inr 2
edges: 0-2 0-3 0-4 1-2 1-3 1-4
degrees: 3 3 2 2 2 (min 2, max 3)
components: 1 (connected)
bipartite: yes (parts: {0, 1} / {2, 3, 4})
-/
#guard_msgs in
#graph_scope (text := true) (completeBipartiteGraph (Fin 2) (Fin 3))

/-! ## Overlays -/

/--
info: graph: 5 vertices, 4 edges
edges: 0-1 1-2 2-3 3-4
degrees: 1 2 2 2 1 (min 1, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2, 4} / {1, 3})
walk: 0 → 1 → 2 → 3 (3 steps)
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 5) walk [0, 1, 2, 3]

/--
info: graph: 6 vertices, 6 edges
edges: 0-1 0-5 1-2 2-3 3-4 4-5
degrees: 2 2 2 2 2 2 (min 2, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2, 4} / {1, 3, 5})
walk: 5 → 0 → 1 (2 steps)
-/
#guard_msgs in
#graph_scope (text := true) (cycleGraph 6) walk [5, 0, 1]

/--
info: graph: 6 vertices, 6 edges
edges: 0-1 0-5 1-2 2-3 3-4 4-5
degrees: 2 2 2 2 2 2 (min 2, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2, 4} / {1, 3, 5})
highlight: 0, 2, 4
-/
#guard_msgs in
#graph_scope (text := true) (cycleGraph 6) highlight [0, 2, 4]

/--
info: graph: 5 vertices, 4 edges
edges: 0-1 1-2 2-3 3-4
degrees: 1 2 2 2 1 (min 1, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2, 4} / {1, 3})
walk: 1 → 2 (1 step)
highlight: 0, 4
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 5) walk [1, 2] highlight [0, 4]

-- The clauses may come in either order: `highlight` before `walk` gives the
-- exact same report (the walk is applied, not silently dropped).
/--
info: graph: 5 vertices, 4 edges
edges: 0-1 1-2 2-3 3-4
degrees: 1 2 2 2 1 (min 1, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2, 4} / {1, 3})
walk: 1 → 2 (1 step)
highlight: 0, 4
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 5) highlight [0, 4] walk [1, 2]

-- A `layout` clause is accepted (it only affects the panel; the text report
-- is layout-independent).
/--
info: graph: 5 vertices, 4 edges
edges: 0-1 1-2 2-3 3-4
degrees: 1 2 2 2 1 (min 1, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2, 4} / {1, 3})
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 5) layout circle

/--
info: graph: 4 vertices, 3 edges
edges: 0-1 1-2 2-3
degrees: 1 2 2 1 (min 1, max 2)
components: 1 (connected)
bipartite: yes (parts: {0, 2} / {1, 3})
walk: 0 (0 steps)
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) walk [0]

-- Panel mode elaborates cleanly (no messages; the widget is attached to stx).
#guard_msgs in
#graph_scope (pathGraph 4)

#guard_msgs in
#graph_scope (cycleGraph 5) walk [0, 1] highlight [3]

#guard_msgs in
#graph_scope (cycleGraph 5) highlight [3] walk [0, 1]

#guard_msgs in
#graph_scope (pathGraph 4) layout circle

#guard_msgs in
#graph_scope (cycleGraph 5) layout layered walk [0, 1]

/-! ## Error cases -/

/--
error: #graph_scope: expected a term of type `SimpleGraph V`, but `42` has type `ℕ`
-/
#guard_msgs in
#graph_scope (text := true) (42 : Nat)

/--
error: #graph_scope: cannot synthesize `Fintype ℕ` — GraphScope needs [Fintype V], [DecidableEq V] and [DecidableRel g.Adj] to evaluate the graph
-/
#guard_msgs in
#graph_scope (text := true) (⊥ : SimpleGraph ℕ)

/-- A two-element type deliberately *without* `DecidableEq` (but *with* a
hand-built `Fintype`), to pin the `DecidableEq` branch of `synthOrExplain`.
The `Finset` is built from a raw list (the `{…, …}` insert notation would
itself require `DecidableEq`). -/
inductive NoDeq where
  | a | b

instance : Fintype NoDeq where
  elems := ⟨[NoDeq.a, NoDeq.b], by simp⟩
  complete x := by cases x <;> simp

/--
error: #graph_scope: cannot synthesize `DecidableEq NoDeq` — GraphScope needs [Fintype V], [DecidableEq V] and [DecidableRel g.Adj] to evaluate the graph
-/
#guard_msgs in
#graph_scope (text := true) (⊥ : SimpleGraph NoDeq)

-- `hasse (Fin 4)` (= what `pathGraph` unfolds to) has no `DecidableRel`
-- instance in scope, since the `Demo` instance is keyed to `pathGraph`.
/--
error: #graph_scope: cannot synthesize `DecidableRel (hasse (Fin 4)).Adj` — GraphScope needs [Fintype V], [DecidableEq V] and [DecidableRel g.Adj] to evaluate the graph
-/
#guard_msgs in
#graph_scope (text := true) (hasse (Fin 4))

-- With `open scoped Classical`, the same graph *synthesizes* a `DecidableRel`
-- instance — a noncomputable one (`Classical.propDecidable`).  It is rejected
-- with a curated error naming the culprit, not a raw compiler error.
/--
error: #graph_scope: the instance synthesized for `DecidableRel (hasse (Fin 4)).Adj` is noncomputable (it uses `Classical.propDecidable`) — GraphScope evaluates the graph with compiled code, so it needs computable instances; define one by hand (for adjacency, `decidable_of_iff` is the idiomatic fix, see GraphScope/Demo.lean)
-/
#guard_msgs in
open scoped Classical in
#graph_scope (text := true) (hasse (Fin 4))

-- Same classical bypass on the `DecidableEq` branch (`NoDeq` has a computable
-- `Fintype` but no `DecidableEq`; `Classical.propDecidable` fills it in).
/--
error: #graph_scope: the instance synthesized for `DecidableEq NoDeq` is noncomputable (it uses `Classical.propDecidable`) — GraphScope evaluates the graph with compiled code, so it needs computable instances; define one by hand (for adjacency, `decidable_of_iff` is the idiomatic fix, see GraphScope/Demo.lean)
-/
#guard_msgs in
open scoped Classical in
#graph_scope (text := true) (⊥ : SimpleGraph NoDeq)

/-- A vertex type whose only `Fintype` instance is `noncomputable` (as e.g.
`Fintype.ofFinite` produces), to pin the noncomputable-instance error on the
`Fintype` branch. -/
def OpaqueFin3 := Fin 3

/-- The noncomputable `Fintype` instance for `OpaqueFin3`. -/
noncomputable instance ncFintype : Fintype OpaqueFin3 :=
  inferInstanceAs (Fintype (Fin 3))

/--
error: #graph_scope: the instance synthesized for `Fintype OpaqueFin3` is noncomputable (it uses `GraphScopeTests.ncFintype`) — GraphScope evaluates the graph with compiled code, so it needs computable instances; define one by hand (for adjacency, `decidable_of_iff` is the idiomatic fix, see GraphScope/Demo.lean)
-/
#guard_msgs in
#graph_scope (text := true) (⊥ : SimpleGraph OpaqueFin3)

-- An underdetermined vertex type is reported honestly (previously this leaked
-- `internal exception: isDefEqStuck`).
/--
error: #graph_scope: could not infer the vertex type of the graph — it is still a metavariable; annotate the term, e.g. `(⊥ : SimpleGraph (Fin 3))`
-/
#guard_msgs in
#graph_scope (text := true) (⊥ : SimpleGraph _)

-- Same for a graph term with holes when the vertex type itself is known.
/--
error: #graph_scope: the graph term still contains metavariables (`_`) — fill in the underscores so the graph is fully determined
-/
#guard_msgs in
#graph_scope (text := true) (SimpleGraph.fromRel _ : SimpleGraph (Fin 3))

/--
error: #graph_scope: the graph has 65 vertices, more than the limit of 64 — GraphScope refuses to draw it
-/
#guard_msgs in
#graph_scope (text := true) (completeGraph (Fin 65))

/--
error: #graph_scope: invalid walk — walk step 1: vertices 0 and 2 are not adjacent
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) walk [0, 2]

/--
error: #graph_scope: invalid walk — walk vertex 7 is out of range (the graph has 4 vertices)
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) walk [7]

/--
error: #graph_scope: invalid walk — a walk needs at least one vertex
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) walk []

/--
error: #graph_scope: invalid highlight — highlighted vertex 9 is out of range (the graph has 4 vertices)
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) highlight [9]

/--
error: #graph_scope: invalid walk — walk step 1: vertices 1 and 1 are not adjacent
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) walk [1, 1]

-- Duplicate clauses are rejected before anything is extracted or rendered.
/--
error: #graph_scope: duplicate `walk` clause
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) walk [0] walk [1]

/--
error: #graph_scope: duplicate `highlight` clause
-/
#guard_msgs in
#graph_scope (text := true) (pathGraph 4) highlight [0] walk [1] highlight [2]

/--
error: #graph_scope: duplicate `layout` clause
-/
#guard_msgs in
#graph_scope (pathGraph 4) layout circle layout layered

end GraphScopeTests
