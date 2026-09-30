import GraphScope

/-! # Test helpers

Pure builders for standard test graphs (over vertex indices, mirroring what
extraction produces for the corresponding Mathlib graphs), string-search
helpers for render tests, reusable property checks, and a throwing assertion
command that runs the real extraction pipeline and validates every model
invariant on the result (one compile-time assertion per use).
-/

namespace GraphScopeTests

open GraphScope

/-! ## Pure test graphs -/

/-- Path `0-1-…-(n-1)`. -/
def path (n : Nat) : GraphData :=
  .ofEdges n ((Array.range (n - 1)).map fun i => (i, i + 1))

/-- Cycle `0-1-…-(n-1)-0` (intended for `n ≥ 3`). -/
def cycle (n : Nat) : GraphData :=
  .ofEdges n (((Array.range (n - 1)).map fun i => (i, i + 1)).push (0, n - 1))

/-- Complete graph on `n` vertices. -/
def complete (n : Nat) : GraphData :=
  .ofEdges n <| Id.run do
    let mut es := #[]
    for i in [0:n] do
      for j in [i+1:n] do
        es := es.push (i, j)
    return es

/-- Star with center `0` and `n - 1` leaves. -/
def star (n : Nat) : GraphData :=
  .ofEdges n ((Array.range (n - 1)).map fun i => (0, i + 1))

/-- Two disjoint paths `0-1-2` and `3-4-5`. -/
def twoPaths : GraphData := .ofEdges 6 #[(0, 1), (1, 2), (3, 4), (4, 5)]

/-- The edgeless graph on `n` vertices. -/
def empty (n : Nat) : GraphData := .ofEdges n #[]

/-! ## String helpers for render tests -/

/-- Does `s` contain `sub`? (`sub` nonempty.) -/
def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

/-- Number of (non-overlapping) occurrences of `sub` in `s`. -/
def countOccurrences (s sub : String) : Nat :=
  (s.splitOn sub).length - 1

/-! ## Property checks (used by PropertyTests and `#assert_graph_invariants`) -/

/-- Handshake lemma: the degree sum is twice the edge count. -/
def degreeSumOk (d : GraphData) : Bool :=
  d.degreeSequence.foldl (· + ·) 0 == 2 * d.edgeCount

/-- Component ids: one per vertex, each below the component count, the count is
`0` iff the graph is empty, every edge joins vertices of the *same* component
(broken BFS merging fails here), and every id below the count is actually used
(over-counting fails here). -/
def componentsOk (d : GraphData) : Bool :=
  d.componentIds.size == d.n
    && d.componentIds.all (· < d.componentCount)
    && ((d.componentCount == 0) == (d.n == 0))
    && d.edges.all (fun (u, v) => d.componentIds.getD u 0 == d.componentIds.getD v 1)
    && (List.range d.componentCount).all (d.componentIds.contains ·)

/-- The bipartition evidence validates: a proper 2-coloring, or a genuine odd
cycle. -/
def bipartitionOk (d : GraphData) : Bool :=
  match d.bipartition with
  | .parts color => d.isProperColoring color
  | .oddCycle c => d.isValidOddCycle c

/-- Isolated vertices are exactly the degree-0 vertices. -/
def isolatedOk (d : GraphData) : Bool :=
  d.isolatedVertices == (Array.range d.n).filter (fun i => d.degree i == 0)

/-- All invariants at once. -/
def allInvariants (d : GraphData) : Bool :=
  d.wellFormed && degreeSumOk d && componentsOk d && bipartitionOk d && isolatedOk d

/-! ## Extraction assertion -/

open Lean Elab Command in
/-- `#assert_graph_invariants g`: run the real extraction pipeline on the graph
term `g` and check every model invariant (`wellFormed`, degree sum, components,
bipartition evidence, isolated vertices) on the extracted `GraphData`.  The
build fails with a descriptive error on any violation. -/
elab "#assert_graph_invariants " t:term:max : command =>
  liftTermElabM do
    let g ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    let d ← extractGraphData (← instantiateMVars g)
    unless d.wellFormed do
      throwError "extracted graph is not well-formed: {repr d}"
    unless degreeSumOk d do
      throwError "degree-sum invariant fails: {repr d.degreeSequence} vs {d.edgeCount} edges"
    unless componentsOk d do
      throwError "component invariant fails: {repr d.componentIds}"
    unless bipartitionOk d do
      throwError "bipartition evidence invalid: {repr d.bipartition}"
    unless isolatedOk d do
      throwError "isolated-vertex invariant fails: {repr d.isolatedVertices}"

end GraphScopeTests
