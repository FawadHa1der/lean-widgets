import GraphScopeTests.Helpers

/-! # Algorithm tests: degrees, components, connectivity, bipartiteness -/

namespace GraphScopeTests

open GraphScope

/-! ## Degree sequences -/

#guard (path 5).degreeSequence == #[1, 2, 2, 2, 1]
#guard (cycle 5).degreeSequence == #[2, 2, 2, 2, 2]
#guard (complete 4).degreeSequence == #[3, 3, 3, 3]
#guard (star 5).degreeSequence == #[4, 1, 1, 1, 1]
#guard (empty 3).degreeSequence == #[0, 0, 0]
#guard (empty 0).degreeSequence == #[]

#guard (path 5).minDegree? == some 1
#guard (path 5).maxDegree? == some 2
#guard (star 5).minDegree? == some 1
#guard (star 5).maxDegree? == some 4
#guard (empty 0).minDegree? == none
#guard (empty 0).maxDegree? == none
#guard (empty 3).maxDegree? == some 0

/-! ## Isolated vertices -/

#guard (empty 3).isolatedVertices == #[0, 1, 2]
#guard (path 4).isolatedVertices == #[]
#guard (GraphData.ofEdges 4 #[(1, 2)]).isolatedVertices == #[0, 3]

/-! ## Connected components -/

#guard (path 5).componentIds == #[0, 0, 0, 0, 0]
#guard (path 5).componentCount == 1
#guard (path 5).isConnected

#guard twoPaths.componentIds == #[0, 0, 0, 1, 1, 1]
#guard twoPaths.componentCount == 2
#guard !twoPaths.isConnected

#guard (empty 3).componentIds == #[0, 1, 2]
#guard (empty 3).componentCount == 3

-- The empty graph has 0 components and is (by convention) not connected.
#guard (empty 0).componentCount == 0
#guard !(empty 0).isConnected

-- A single vertex is connected.
#guard (empty 1).isConnected

-- Component ids are numbered by first occurrence, not by edge order.
#guard (GraphData.ofEdges 5 #[(3, 4), (0, 1)]).componentIds == #[0, 0, 1, 2, 2]

#guard (cycle 6).isConnected
#guard (complete 4).isConnected

/-! ## Forest detection (`|E| + #components = n`) -/

#guard (path 5).isForest
#guard (path 1).isForest
#guard (star 6).isForest
#guard twoPaths.isForest
#guard (empty 4).isForest
#guard (empty 0).isForest
#guard !(cycle 3).isForest
#guard !(cycle 6).isForest
#guard !(complete 4).isForest
-- A forest plus one extra edge closing a cycle is no longer a forest.
#guard (GraphData.ofEdges 4 #[(0, 1), (1, 2), (2, 3)]).isForest
#guard !(GraphData.ofEdges 4 #[(0, 1), (1, 2), (2, 3), (0, 3)]).isForest
-- Disconnected mix: a triangle plus an isolated vertex is not a forest.
#guard !(GraphData.ofEdges 4 #[(0, 1), (1, 2), (0, 2)]).isForest

/-! ## Bipartiteness: positive cases (pinned colorings, then validated) -/

#guard (path 5).bipartition == .parts #[false, true, false, true, false]
#guard (cycle 4).bipartition == .parts #[false, true, false, true]
#guard (cycle 6).isBipartite
#guard (star 5).bipartition == .parts #[false, true, true, true, true]
#guard (empty 3).bipartition == .parts #[false, false, false]
#guard (empty 0).bipartition == .parts #[]
#guard twoPaths.bipartition == .parts #[false, true, false, false, true, false]

-- The pinned colorings really are proper 2-colorings.
#guard (path 5).isProperColoring #[false, true, false, true, false]
#guard (cycle 4).isProperColoring #[false, true, false, true]
#guard !(cycle 4).isProperColoring #[false, false, false, true]  -- validator rejects bad ones
#guard !(path 5).isProperColoring #[false, true]                 -- wrong size

/-! ## Bipartiteness: negative cases (odd-cycle witnesses, validated) -/

#guard !(cycle 3).isBipartite
#guard !(cycle 5).isBipartite
#guard !(complete 4).isBipartite
#guard (cycle 7).isBipartite == false

-- Pinned witnesses…
#guard (cycle 3).bipartition == .oddCycle #[1, 0, 2]
#guard (cycle 5).bipartition == .oddCycle #[2, 1, 0, 4, 3]

-- …and programmatic validation of every witness the algorithm produces.
#guard match (cycle 3).bipartition with
  | .oddCycle c => (cycle 3).isValidOddCycle c
  | .parts _ => false
#guard match (cycle 5).bipartition with
  | .oddCycle c => (cycle 5).isValidOddCycle c
  | .parts _ => false
#guard match (complete 5).bipartition with
  | .oddCycle c => (complete 5).isValidOddCycle c
  | .parts _ => false
#guard match (cycle 9).bipartition with
  | .oddCycle c => (cycle 9).isValidOddCycle c
  | .parts _ => false

-- An odd cycle hiding in a bigger graph: path 0-1-2-3-4 plus chord 2-4.
#guard match (GraphData.ofEdges 5 #[(0, 1), (1, 2), (2, 3), (3, 4), (2, 4)]).bipartition with
  | .oddCycle c =>
    (GraphData.ofEdges 5 #[(0, 1), (1, 2), (2, 3), (3, 4), (2, 4)]).isValidOddCycle c
  | .parts _ => false

/-! ## The odd-cycle validator itself -/

#guard (cycle 5).isValidOddCycle #[0, 1, 2, 3, 4]
#guard !(cycle 5).isValidOddCycle #[0, 1, 2, 3]        -- even length
#guard !(cycle 5).isValidOddCycle #[0]                 -- too short
#guard !(cycle 5).isValidOddCycle #[0, 2, 4]           -- non-adjacent steps
#guard !(cycle 5).isValidOddCycle #[0, 1, 0]           -- repeated vertex
#guard !(cycle 5).isValidOddCycle #[0, 1, 7]           -- out of range
#guard !(path 5).isValidOddCycle #[0, 1, 2]            -- open: ends not adjacent
#guard (complete 4).isValidOddCycle #[3, 1, 2]

end GraphScopeTests
