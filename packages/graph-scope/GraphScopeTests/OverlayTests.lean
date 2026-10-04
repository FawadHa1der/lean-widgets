import GraphScopeTests.Helpers

/-! # Overlay tests: walk/highlight validation and formatting (pure layer) -/

namespace GraphScopeTests

open GraphScope GraphScope.Render

/-! ## Walk validation -/

#guard (path 4).walkError? #[0, 1, 2, 3] == none
#guard (path 4).walkError? #[3, 2, 1] == none          -- direction-free
#guard (path 4).walkError? #[1] == none                -- trivial walk
#guard (cycle 4).walkError? #[3, 0, 1] == none         -- wrap-around edge 0-3

#guard (path 4).walkError? #[] == some "a walk needs at least one vertex"
#guard (path 4).walkError? #[0, 2]
  == some "walk step 1: vertices 0 and 2 are not adjacent"
#guard (path 4).walkError? #[0, 1, 3]
  == some "walk step 2: vertices 1 and 3 are not adjacent"
#guard (path 4).walkError? #[1, 1]
  == some "walk step 1: vertices 1 and 1 are not adjacent"  -- no self-steps
#guard (path 4).walkError? #[7]
  == some "walk vertex 7 is out of range (the graph has 4 vertices)"
#guard (path 4).walkError? #[0, 1, 9]
  == some "walk vertex 9 is out of range (the graph has 4 vertices)"

-- A walk may revisit vertices and edges (it is a walk, not a path).
#guard (path 4).walkError? #[0, 1, 0, 1, 2] == none

/-! ## Highlight validation -/

#guard (path 4).highlightError? #[] == none
#guard (path 4).highlightError? #[0, 3] == none
#guard (path 4).highlightError? #[0, 0] == none        -- duplicates tolerated
#guard (path 4).highlightError? #[4]
  == some "highlighted vertex 4 is out of range (the graph has 4 vertices)"

/-! ## Walk-edge computation and formatting -/

#guard walkEdges #[0, 1, 2] == #[(0, 1), (1, 2)]
#guard walkEdges #[2, 1, 0] == #[(1, 2), (0, 1)]       -- normalized to (min, max)
#guard walkEdges #[1] == #[]
#guard walkEdges #[0, 1, 0] == #[(0, 1), (0, 1)]       -- revisits kept per step

#guard walkLine #[0, 1, 2] == "walk: 0 → 1 → 2 (2 steps)"
#guard walkLine #[5] == "walk: 5 (0 steps)"
#guard walkLine #[3, 4] == "walk: 3 → 4 (1 step)"      -- singular
#guard highlightLine #[0, 2, 4] == "highlight: 0, 2, 4"

/-! ## Step numbering appears once per step, even on a revisited edge -/

#guard countOccurrences
  (htmlToDebugString (renderPanel (path 4) (walk? := some #[0, 1, 0])))
  "data-step=" == 2

end GraphScopeTests
