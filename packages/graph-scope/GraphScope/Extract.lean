import GraphScope.Model
import Mathlib.Combinatorics.SimpleGraph.Basic
import Mathlib.Data.Quot

/-! # GraphScope: extraction of `GraphData` from a `SimpleGraph` term

The single impure layer of the package.  Given an elaborated term
`g : SimpleGraph V` with `[Fintype V]`, `[DecidableEq V]` and
`[DecidableRel g.Adj]`, `extractGraphData`:

1. rejects underdetermined terms (a vertex type that is still a metavariable)
   with a `#graph_scope`-branded error instead of leaking internal exceptions;
2. synthesizes the three instances, naming the missing one in a clear error —
   and rejects *noncomputable* synthesized instances (e.g. the classical
   fallback `Classical.propDecidable` that `open scoped Classical` puts in
   scope) with an equally clear error, instead of letting `evalExpr` fail
   later with raw compiler advice;
3. evaluates `Fintype.card V` and enforces the honest hard cap of
   `maxVertices = 64` vertices *before* deciding any adjacency;
4. compiles `rawEdgesRows g` **once** (via the standard `Lean.Meta.evalExpr`
   pattern, `safety := .unsafe`, exactly as Mathlib commands do) into a
   `Nat → Array Nat` closure, then calls it row by row from `MetaM`, running
   `Lean.Core.checkSystem` between rows — so a slow `DecidableRel` instance
   can be interrupted between rows (editor cancellation, heartbeats) instead
   of hanging the whole command in one opaque evaluation;
5. labels vertices via `Repr V` when available (`reprStr` of each vertex in
   enumeration order), falling back to plain indices (also when the `Repr`
   instance is noncomputable).

Vertex indices are positions in the `Fintype.elems` enumeration, so extraction
is deterministic by construction: the same term and instances always produce
the same `GraphData` (for `Fin n`, vertex `i` is literally `i`).

Note the row closure is created once (its `let vs := enumVerts V` is forced at
closure creation), so `Fintype.elems` is evaluated a single time.  A single
adjacency decision is still arbitrary user code and cannot be bounded from
here; see the README's limitations section.
-/

namespace GraphScope

open Lean Meta Elab SimpleGraph

/-- The vertices of `V` in `Fintype` enumeration order.  Unsafe because it
reveals the runtime representative of the `elems` multiset — which is exactly
the deterministic "enumeration order" the widget indexes vertices by.  Only
ever run through `evalExpr (safety := .unsafe)`. -/
unsafe def enumVerts (V : Type u) [Fintype V] : Array V :=
  ((Fintype.elems (α := V)).val.unquot).toArray

/-- Adjacency, one row at a time: `rawEdgesRows g i` is the ascending array of
partners `j > i` of vertex `i` (indices into the enumeration).  The vertex
enumeration is computed once, when the closure is created; the caller
(`extractGraphData`) evaluates this closure once with `evalExpr` and then calls
it per row from `MetaM`, checking for interrupts between rows.  Evaluated
(never type-checked as safe code) at elaboration time. -/
unsafe def rawEdgesRows {V : Type u} [Fintype V] [DecidableEq V]
    (g : SimpleGraph V) [DecidableRel g.Adj] : Nat → Array Nat :=
  let vs := enumVerts V
  fun i => Id.run do
    let mut out : Array Nat := #[]
    if h : i < vs.size then
      let v := vs[i]
      let mut j := i + 1
      for w in vs[i+1:] do
        if g.Adj v w then
          out := out.push j
        j := j + 1
    return out

/-- Vertex labels in enumeration order, via `Repr`. -/
unsafe def rawLabels (V : Type u) [Fintype V] [Repr V] : Array String :=
  (enumVerts V).map fun v => reprStr v

/-- Hard cap on the number of vertices GraphScope will evaluate and draw. -/
def maxVertices : Nat := 64

/-- Pretty-print an expression to a single line (deterministic error text). -/
def ppOneLine (e : Expr) : MetaM String := do
  return (← ppExpr e).pretty (width := 100000)

/-- Synthesize an instance of `type`, or fail with a `#graph_scope` error naming
exactly the missing instance.  Also rejects noncomputable synthesized instances
(the value mentions a constant tagged `noncomputable`, e.g. the classical
fallback `Classical.propDecidable` under `open scoped Classical`): those would
otherwise surface much later as a raw compiler error from `evalExpr` whose
advice ("mark it as noncomputable") is meaningless for a command. -/
def synthOrExplain (type : Expr) : MetaM Expr := do
  match ← synthInstance? type with
  | none => throwError "#graph_scope: cannot synthesize `{← ppOneLine type}` — \
      GraphScope needs [Fintype V], [DecidableEq V] and [DecidableRel g.Adj] \
      to evaluate the graph"
  | some inst =>
    let inst ← instantiateMVars inst
    let env ← getEnv
    if let some c := inst.getUsedConstants.find? (isNoncomputable env ·) then
      throwError "#graph_scope: the instance synthesized for `{← ppOneLine type}` \
          is noncomputable (it uses `{c}`) — GraphScope evaluates the graph with \
          compiled code, so it needs computable instances; define one by hand \
          (for adjacency, `decidable_of_iff` is the idiomatic fix, see \
          GraphScope/Demo.lean)"
    return inst

/-- Run one evaluation step, rebranding any failure as a `#graph_scope` error
(interrupts and runtime errors pass through untouched). -/
def evalOrExplain (what : String) (act : MetaM α) : MetaM α := do
  try
    act
  catch ex =>
    if ex.isInterrupt || ex.isRuntime then
      throw ex
    throwError "#graph_scope: failed to {what} — {ex.toMessageData}"

/-- Extract a `GraphData` from an elaborated term `g : SimpleGraph V`
(see the module docstring for the contract and error behavior). -/
def extractGraphData (g : Expr) : MetaM GraphData := do
  let g ← instantiateMVars g
  let gty ← whnf (← inferType g)
  let some V := gty.app1? ``SimpleGraph
    | throwError "#graph_scope: expected a term of type `SimpleGraph V`, but \
        `{← ppOneLine g}` has type `{← ppOneLine gty}`"
  -- Underdetermined terms would make instance synthesis throw internal
  -- exceptions (`isDefEqStuck`); reject them with an honest error instead.
  if V.hasExprMVar then
    throwError "#graph_scope: could not infer the vertex type of the graph — it \
        is still a metavariable; annotate the term, e.g. `(⊥ : SimpleGraph (Fin 3))`"
  if g.hasExprMVar then
    throwError "#graph_scope: the graph term still contains metavariables \
        (`_`) — fill in the underscores so the graph is fully determined"
  -- Instances, with a precise error for the missing (or noncomputable) one.
  let finInst ← synthOrExplain (← mkAppM ``Fintype #[V])
  let deqInst ← synthOrExplain (← mkAppM ``DecidableEq #[V])
  let adjRel ← mkAppM ``SimpleGraph.Adj #[g]
  let adjInst ← synthOrExplain (← mkAppM ``DecidableRel #[adjRel])
  -- Vertex-count cap, checked before any adjacency is decided.
  let cardE ← mkAppOptM ``Fintype.card #[V, finInst]
  let n ← evalOrExplain "evaluate the vertex count" <|
    unsafe evalExpr' Nat ``Nat cardE
  if n > maxVertices then
    throwError "#graph_scope: the graph has {n} vertices, more than the \
        limit of {maxVertices} — GraphScope refuses to draw it"
  -- Adjacency: compile the row closure once, then decide row by row with an
  -- interrupt check between rows (the graph's own Decidable instances decide
  -- each adjacency).
  let natT := mkConst ``Nat
  let rowTy ← mkArrow natT (mkApp (mkConst ``Array [.zero]) natT)
  let rowFnE ← mkAppOptM ``rawEdgesRows #[V, finInst, deqInst, g, adjInst]
  let rowFn ← evalOrExplain "compile the graph's adjacency test" <|
    unsafe evalExpr (Nat → Array Nat) rowTy rowFnE (safety := .unsafe)
  let mut edges : Array (Nat × Nat) := #[]
  for i in [0:n] do
    Core.checkSystem "#graph_scope"
    for j in rowFn i do
      edges := edges.push (i, j)
  -- Labels via `Repr V` when available (and computable); indices otherwise.
  let labels ← do
    match ← synthInstance? (← mkAppM ``Repr #[V]) with
    | some reprInst =>
      let reprInst ← instantiateMVars reprInst
      if reprInst.getUsedConstants.any (isNoncomputable (← getEnv) ·) then
        pure #[]
      else
        let labE ← mkAppOptM ``rawLabels #[V, finInst, reprInst]
        let labTy := mkApp (mkConst ``Array [.zero]) (mkConst ``String)
        evalOrExplain "evaluate the vertex labels" <|
          unsafe evalExpr (Array String) labTy labE (safety := .unsafe)
    | none => pure #[]
  return GraphData.ofEdges n edges labels

end GraphScope
