import Mathlib
import GraphScope

/-! # GraphScope: draw a `SimpleGraph`, click facts into the file
Cursor on a `#graph_scope` line: the panel draws the graph (forests as layered
trees, other graphs on a circle) plus a stats block — degrees, components,
connectivity, bipartiteness with evidence (a 2-colouring or an odd cycle).
The drawing is clickable: an EDGE inserts `example : G.Adj a b := by decide`,
a VERTEX its degree fact, the components line `G.Connected` (or `¬`), each on
a new line after the command and verified to compile before it is offered.
`walk [...]` numbers the steps of a walk, `highlight [...]` rings vertices,
`layout circle|layered` forces a layout.  (`pathGraph` is decidable here via
the global instance shipped by GraphScope's demo module.) -/

open SimpleGraph

namespace Showcase.GraphScope

-- An odd cycle: not bipartite, and the stats name an odd-cycle witness.
#graph_scope (cycleGraph 5)

-- The complete graph K₄.
#graph_scope (completeGraph (Fin 4))

/-- Two disjoint triangles via `fromRel`: disconnected. -/
def twoTriangles : SimpleGraph (Fin 6) :=
  SimpleGraph.fromRel fun a b =>
    (a, b) ∈ [((0 : Fin 6), (1 : Fin 6)), (1, 2), (0, 2), (3, 4), (4, 5), (3, 5)]
instance : DecidableRel twoTriangles.Adj := by unfold twoTriangles; infer_instance
#graph_scope twoTriangles

-- Overlays on a path (a tree, drawn in layers): a walk and highlighted ends.
#graph_scope (pathGraph 5) walk [1, 2, 3] highlight [0, 4]

-- A 6-cycle forced into BFS layers: the non-tree edge becomes a chord.
#graph_scope (cycleGraph 6) layout layered

end Showcase.GraphScope
