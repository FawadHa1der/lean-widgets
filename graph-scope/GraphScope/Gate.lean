import GraphScope.Extract
import GraphScope.Insert
import Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite

/-! # GraphScope: the round-trip honesty gate

A click-to-insert link must never insert a misleading fact.  The vertex terms
in inserted texts are built from `Repr` labels, and a label that parses to a
*different* value than the drawn element would produce a compiling-but-wrong
example (e.g. two vertices sharing a label through a lossy `Repr`, or a label
that is not term syntax at all).  Therefore a link is attached **only when the
candidate label passes a verified round-trip at analysis time**:

1. parse the label as a term (`Parser.runParserCategory`);
2. elaborate it at the vertex type (errors → fail; leftover metavariables,
   e.g. `⟨0, _⟩` anonymous-constructor labels with proof holes → fail);
3. prove it *equal to the drawn element*: evaluate
   `elemMatchesIndex (parsed) i` — the type's own `DecidableEq` compared
   against position `i` of the same `Fintype` enumeration the extractor
   indexed the drawing by — through the same `evalExpr` bridge extraction
   uses.

Labels that fail the gate render as plain text with a muted note.

`Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite` is imported here (not
merely in the tests) so that every file using `#graph_scope` has the
`Decidable G.Connected` instance in scope — the inserted connectivity example
must compile *in the user's file*.
-/

namespace GraphScope

open Lean Meta Elab

/-- Does `v` sit at position `i` of the `Fintype` enumeration?  Decided by the
type's own `DecidableEq` against the exact enumeration (`enumVerts`) the
extractor indexed vertices by.  Unsafe for the same reason as `enumVerts`;
only ever run through `evalExpr (safety := .unsafe)`. -/
unsafe def elemMatchesIndex {V : Type u} [Fintype V] [DecidableEq V]
    (v : V) (i : Nat) : Bool :=
  match (enumVerts V)[i]? with
  | some w => decide (v = w)
  | none => false

/-- The round-trip honesty gate (see the module docstring): does `label` parse,
elaborate at `V` without leftover metavariables or `sorry`, and evaluate as
equal (by `V`'s own `DecidableEq`) to element `idx` of the `Fintype`
enumeration?  `finInst`/`deqInst` are the already-synthesized instances.
Interrupt and runtime exceptions propagate; every other failure means `false`
(the label renders as plain text, never as a link). -/
def labelRoundTrips (V finInst deqInst : Expr) (label : String) (idx : Nat) :
    TermElabM Bool := do
  match Parser.runParserCategory (← getEnv) `term label with
  | .error _ => return false
  | .ok stx =>
    try
      let ve ← Term.withoutErrToSorry do
        let ve ← Term.elabTerm stx (some V)
        Term.synthesizeSyntheticMVarsNoPostponing
        instantiateMVars ve
      if ve.hasExprMVar || ve.hasLevelMVar || ve.hasSorry then
        return false
      let e ← mkAppOptM ``elemMatchesIndex #[V, finInst, deqInst, ve, mkNatLit idx]
      unsafe evalExpr Bool (mkConst ``Bool) e (safety := .unsafe)
    catch ex =>
      if ex.isInterrupt || ex.isRuntime then
        throw ex
      return false

/-- Compute the verified click-to-insert suggestions for an extracted graph:
gate every vertex label through `labelRoundTrips`, then build edge facts (both
endpoints gated), degree facts (endpoint gated) and the connectivity fact
(under `Insert.connectivityInsertable`) from the *pure* text builders.  `gSrc`
is the user's graph term, verbatim from the source file; `g` the elaborated
graph.  Returns `{}` (no links, plain panel) when the term's shape or
instances cannot be re-derived. -/
def computeInsertions (gSrc : String) (g : Expr) (d : GraphData) :
    TermElabM LinkInfo := do
  let g ← instantiateMVars g
  let gty ← whnf (← inferType g)
  let some V := gty.app1? ``SimpleGraph | return {}
  let some finInst ← synthInstance? (← mkAppM ``Fintype #[V]) | return {}
  let some deqInst ← synthInstance? (← mkAppM ``DecidableEq #[V]) | return {}
  let mut okLabel : Array Bool := #[]
  let mut notInsertable : Array (Nat × String) := #[]
  for i in [0:d.n] do
    -- One parse + elaboration + compiled evaluation per vertex: allow editor
    -- cancellation between vertices, like extraction does between rows.
    Core.checkSystem "#graph_scope"
    let ok ← labelRoundTrips V finInst deqInst (d.label i) i
    okLabel := okLabel.push ok
    unless ok do
      notInsertable := notInsertable.push (i, d.label i)
  let mut edges : Array (Nat × Nat × String) := #[]
  for (a, b) in d.edges do
    if okLabel.getD a false && okLabel.getD b false then
      edges := edges.push (a, b, Insert.edgeExampleText gSrc (d.label a) (d.label b))
  let mut degrees : Array (Nat × String) := #[]
  for i in [0:d.n] do
    if okLabel.getD i false then
      degrees := degrees.push (i, Insert.degreeExampleText gSrc (d.label i) (d.degree i))
  let connected? : Option String :=
    if Insert.connectivityInsertable d then
      some (if d.isConnected then Insert.connectedExampleText gSrc
            else Insert.notConnectedExampleText gSrc)
    else none
  return { edges, degrees, connected?, notInsertable }

end GraphScope
