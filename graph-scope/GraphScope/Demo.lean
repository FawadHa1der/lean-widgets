import GraphScope.Widget
import Mathlib.Combinatorics.SimpleGraph.Hasse
import Mathlib.Combinatorics.SimpleGraph.CycleGraph

/-! # GraphScope demos

Open this file in the editor and put the cursor on any `#graph_scope` line to
see the rendered graph in the InfoView.  Clicking a drawn edge, a vertex, or
the components stats line inserts a verified `example : … := by decide` on a
new line after the command (the local `DecidableRel` instances below are what
make those examples compile here — see the README's scoping caveat).

Mathlib's concrete graphs differ in how much decidability they ship:

* `cycleGraph n`, `⊥`, `⊤` / `completeGraph V` have `DecidableRel` instances
  out of the box;
* `pathGraph n` (defined via the Hasse diagram of `Fin n`, whose covering
  relation has no decidability instance) and `completeBipartiteGraph V W` do
  *not* — the idiomatic workaround, shown below, is a local instance via
  `decidable_of_iff` from the graph's `simp`-normal adjacency description;
* graphs built with `SimpleGraph.fromRel r` are decidable whenever `r` is
  (Mathlib provides the instance), which makes `fromRel` the most convenient
  constructor for ad-hoc finite examples.  `SimpleGraph.fromEdgeSet` over a
  `Set` literal (`∅`, `{s(0, 1), s(1, 2)}`, …) on a `DecidableEq` vertex type
  is likewise decidable out of the box — see the passing `fromEdgeSet` tests
  in `GraphScopeTests.CommandTests`; only genuinely undecidable edge-set
  membership (e.g. a set-builder over an undecidable predicate) needs a
  hand-written instance.
-/

namespace GraphScope.Demo

open SimpleGraph

/-- `pathGraph n` is `hasse (Fin n)` and `CovBy` has no `Decidable` instance;
the characterization `pathGraph_adj` makes adjacency decidable. -/
instance (n : ℕ) : DecidableRel (pathGraph n).Adj := fun _ _ =>
  decidable_of_iff _ pathGraph_adj.symm

/-- `completeBipartiteGraph` adjacency is a Boolean formula over `Sum.isLeft` /
`Sum.isRight`; `Iff.rfl` suffices because the structure literal reduces. -/
instance {V W : Type*} : DecidableRel (completeBipartiteGraph V W).Adj := fun v w =>
  decidable_of_iff (v.isLeft ∧ w.isRight ∨ v.isRight ∧ w.isLeft) Iff.rfl

/-- Two disjoint triangles `{0,1,2}` and `{3,4,5}` — a disconnected,
non-bipartite graph via `fromRel` on an explicit pair list. -/
def twoTriangles : SimpleGraph (Fin 6) :=
  SimpleGraph.fromRel fun a b =>
    (a, b) ∈ [((0 : Fin 6), (1 : Fin 6)), (1, 2), (0, 2), (3, 4), (4, 5), (3, 5)]

instance : DecidableRel twoTriangles.Adj := by
  unfold twoTriangles; infer_instance

/-- The star with center `0` and 5 leaves: `fromRel` symmetrizes
`a = 0` into "one endpoint is `0`" (and irreflexivity drops `0-0`). -/
def star5 : SimpleGraph (Fin 6) :=
  SimpleGraph.fromRel fun a _ => a = 0

instance : DecidableRel star5.Adj := by
  unfold star5; infer_instance

/-! ## The graphs -/

-- A path on 5 vertices: connected, bipartite.
#graph_scope (pathGraph 5)

-- A 6-cycle: bipartite (even).
#graph_scope (cycleGraph 6)

-- A 5-cycle: not bipartite — the stats block shows an odd-cycle witness.
#graph_scope (cycleGraph 5)

-- The complete graph on 5 vertices.
#graph_scope (completeGraph (Fin 5))

-- The empty graph (no edges): every vertex isolated, 4 components.
#graph_scope (⊥ : SimpleGraph (Fin 4))

-- A custom disconnected graph: two disjoint triangles.
#graph_scope twoTriangles

-- A star: bipartite with parts {center} / {leaves}.  Being a tree, it is
-- drawn as a layered rooted tree (center on top, leaves below).
#graph_scope star5

-- `fromEdgeSet` over a `Set` literal works out of the box.
#graph_scope (SimpleGraph.fromEdgeSet {s(0, 1), s(1, 2)} : SimpleGraph (Fin 3))

-- Bipartite demo: K_{2,3}; vertices are labeled by their `Repr` form
-- (`Sum.inl 0`, …), indices follow the `Fintype` enumeration (left part first).
#graph_scope (completeBipartiteGraph (Fin 2) (Fin 3))

/-! ## Overlays -/

-- A walk along the path, with step numbers 1..3.
#graph_scope (pathGraph 5) walk [0, 1, 2, 3]

-- A closed walk around the 6-cycle, revisiting vertex 0.
#graph_scope (cycleGraph 6) walk [5, 0, 1, 2]

-- Highlight one part of the 6-cycle's bipartition.
#graph_scope (cycleGraph 6) highlight [0, 2, 4]

-- Both overlays at once (the clauses may come in either order).
#graph_scope (pathGraph 5) walk [1, 2, 3] highlight [0, 4]
#graph_scope (pathGraph 5) highlight [0, 4] walk [1, 2, 3]

/-! ## Layout modes

Forests (paths, stars, …) are laid out as BFS-layered rooted trees by default;
`layout circle` forces the classic circular layout, and `layout layered` forces
BFS layers even for cyclic graphs. -/

-- The path as a circle (the pre-layered look).
#graph_scope (pathGraph 5) layout circle

-- A cycle in BFS layers: the non-tree edge becomes a chord in the bottom row.
#graph_scope (cycleGraph 6) layout layered

end GraphScope.Demo
