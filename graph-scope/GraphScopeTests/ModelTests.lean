import GraphScopeTests.Helpers

/-! # Model tests: normalization, adjacency, degrees, labels -/

namespace GraphScopeTests

open GraphScope

/-! ## Edge normalization (`GraphData.ofEdges` / `normalizeEdges`) -/

-- Reversed pairs are oriented to (min, max).
#guard (GraphData.ofEdges 3 #[(1, 0)]).edges == #[(0, 1)]

-- Duplicates (including reversed duplicates) collapse.
#guard (GraphData.ofEdges 3 #[(0, 1), (1, 0), (0, 1)]).edges == #[(0, 1)]

-- Self-loops are dropped (simple graphs are irreflexive).
#guard (GraphData.ofEdges 3 #[(1, 1), (0, 1)]).edges == #[(0, 1)]

-- Out-of-range endpoints are dropped.
#guard (GraphData.ofEdges 3 #[(0, 5), (7, 1), (0, 2)]).edges == #[(0, 2)]

-- Output is sorted lexicographically.
#guard (GraphData.ofEdges 4 #[(2, 3), (0, 1), (1, 2), (0, 3)]).edges
  == #[(0, 1), (0, 3), (1, 2), (2, 3)]

-- Everything at once: swap + dedup + loop + range + sort.
#guard (GraphData.ofEdges 4 #[(3, 2), (1, 1), (2, 3), (9, 0), (1, 0)]).edges
  == #[(0, 1), (2, 3)]

-- Well-formedness of a normalized graph, including the empty ones.
#guard (GraphData.ofEdges 4 #[(3, 2), (1, 1), (2, 3), (9, 0), (1, 0)]).wellFormed
#guard (empty 0).wellFormed
#guard (empty 3).wellFormed

-- Manually built non-normalized data is rejected by `wellFormed`.
#guard !(GraphData.mk 2 #[(1, 0)] #["0", "1"]).wellFormed  -- unoriented edge
#guard !(GraphData.mk 2 #[(0, 1)] #["0"]).wellFormed       -- label count off
#guard !(GraphData.mk 2 #[(0, 2)] #["0", "1"]).wellFormed  -- endpoint ≥ n
#guard !(GraphData.mk 3 #[(1, 2), (0, 1)] #["0", "1", "2"]).wellFormed  -- unsorted

/-! ## Labels -/

#guard (GraphData.ofEdges 3 #[]).labels == #["0", "1", "2"]
#guard (GraphData.ofEdges 3 #[] #["a"]).labels == #["a", "1", "2"]
#guard (GraphData.ofEdges 2 #[] #["a", "b", "c"]).labels == #["a", "b"]
#guard (GraphData.ofEdges 2 #[] #["x", "y"]).label 1 == "y"
#guard (GraphData.ofEdges 2 #[] #["x", "y"]).label 5 == "5"  -- out-of-range fallback

/-! ## Adjacency and degree queries -/

#guard (path 4).adjacent 1 2
#guard (path 4).adjacent 2 1        -- symmetric
#guard !(path 4).adjacent 0 2       -- non-edge
#guard !(path 4).adjacent 2 2       -- irreflexive
#guard !(path 4).adjacent 1 9       -- out of range

#guard (path 4).degree 0 == 1
#guard (path 4).degree 1 == 2
#guard (star 6).degree 0 == 5
#guard (star 6).degree 3 == 1
#guard (empty 3).degree 1 == 0

#guard (path 4).edgeCount == 3
#guard (complete 4).edgeCount == 6
#guard (cycle 5).edgeCount == 5

/-! ## Neighbors (ascending order) -/

#guard (cycle 5).neighbors 0 == #[1, 4]
#guard (path 4).neighbors 2 == #[1, 3]
#guard (star 6).neighbors 0 == #[1, 2, 3, 4, 5]
#guard (empty 3).neighbors 0 == #[]

end GraphScopeTests
