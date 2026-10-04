import Lean

/-!
# SimpLens.Trace — tracing engine for `simp`

Runs `simp` on a goal (target and/or hypotheses) with wrapped
`Lean.Meta.Simp.Methods` so that every successful rewrite is recorded (as a
`TraceStep`) into an `IO.Ref`, without changing `simp`'s behavior in any way.
`traceSimpTarget` mirrors core `Lean.Meta.simpTarget`; `traceSimpGoal` mirrors
core `Lean.Meta.simpGoal` (the engine behind `simp at ...`), statement by
statement, so location semantics are identical to plain `simp`.

## How origins are attributed

Core `simp` calls `Simp.recordSimpTheorem` exactly when a rewrite (theorem or
simproc) succeeds; the record goes into `State.usedTheorems : UsedSimps`, an
insertion-ordered map. `UsedSimps.insert` is idempotent, so a plain diff would
miss the second firing of the same lemma. We therefore *reset* `usedTheorems`
to `{}` around each wrapped `pre`/`post`/`dpre`/`dpost` call and afterwards
merge the freshly recorded origins back (in order). Since `insert` is
idempotent and order-preserving, the merged map is identical to what an
un-instrumented run would produce, while the "fresh" part tells us exactly
which origins fired during this one simplification step.
-/

namespace SimpLens

open Lean Meta Simp

/-- The phase of the simplifier during which a rewrite step fired. -/
inductive Phase where
  /-- The `pre` methods (applied before visiting subterms). -/
  | pre
  /-- The `post` methods (applied after visiting subterms). -/
  | post
  /-- The definitional (`dsimp`) `pre` methods. -/
  | dpre
  /-- The definitional (`dsimp`) `post` methods. -/
  | dpost
  deriving Repr, BEq, Inhabited, DecidableEq

/-- Human-readable label for a `Phase`. -/
def Phase.label : Phase → String
  | .pre => "pre"
  | .post => "post"
  | .dpre => "dpre"
  | .dpost => "dpost"

/-- The location (target or a hypothesis) a traced rewrite belongs to. -/
inductive LocTag where
  /-- The goal target (`⊢`). -/
  | target
  /-- The hypothesis with the given user-facing name. -/
  | hyp (userName : Name)
  deriving Repr, BEq, Inhabited

/-- Display label for a `LocTag`: `⊢` for the target, the user-facing name for
a hypothesis. -/
def LocTag.label : LocTag → String
  | .target => "⊢"
  | .hyp n => n.toString

/-- One successful rewrite performed by `simp`, as observed by the tracer. -/
structure TraceStep where
  /-- All `Simp.Origin`s recorded while this step fired, in chronological
  order. The *principal* origin (the theorem/simproc that produced the
  rewrite) is the **last** entry; earlier entries were used to discharge
  side conditions. -/
  origins : Array Origin
  /-- The subterm before the rewrite. -/
  before : Expr
  /-- The subterm after the rewrite. -/
  after : Expr
  /-- Simplifier phase in which the step fired. -/
  phase : Phase
  /-- Discharge depth at which the step fired. `0` means the step happened
  during the traversal of the goal itself; `> 0` means it happened while
  discharging a side condition of another rewrite. -/
  depth : Nat
  /-- The location (target or hypothesis) being simplified when the step
  fired. Target-only runs leave the default. -/
  loc : LocTag := .target
  deriving Inhabited

/-- The principal origin of a step: the theorem/simproc that actually produced
the rewrite (side-condition lemmas are recorded first, the main one last). -/
def TraceStep.principal (s : TraceStep) : Origin :=
  s.origins.back?.getD (.other `SimpLens.unknown)

/-- Result of a traced run of `simp` on a goal target. -/
structure TraceResult where
  /-- The resulting goal; `none` if `simp` closed it. -/
  goal? : Option MVarId
  /-- All recorded rewrite steps, in the order they fired (all depths). -/
  steps : Array TraceStep
  /-- The used-theorem set of the run, identical to what plain `simp` reports
  (this feeds `simp only [...]` generation). -/
  usedTheorems : UsedSimps
  /-- Diagnostics counters (tried/used per lemma); populated only when the
  `diagnostics` option is enabled. -/
  diag : Simp.Diagnostics
  /-- The target expression before simplification. -/
  target : Expr
  /-- Whether the goal changed (or was closed). -/
  progress : Bool
  deriving Inhabited

/-- Steps that happened on the goal traversal itself (discharge depth 0).
These form the filmstrip; deeper steps are side-condition work. -/
def TraceResult.mainSteps (r : TraceResult) : Array TraceStep :=
  r.steps.filter (·.depth == 0)

/-- Merge `fresh` used-simp records into `saved`, preserving `fresh`'s
insertion order. Because `UsedSimps.insert` is idempotent, this reconstructs
exactly the map an un-instrumented `simp` run would have produced. -/
def mergeUsed (saved fresh : UsedSimps) : UsedSimps :=
  fresh.toArray.foldl (init := saved) (·.insert ·)

/-- Run `k` with `usedTheorems` reset to `{}`, returning `k`'s result together
with the `UsedSimps` recorded *during* `k`. The previously accumulated map is
merged back afterwards (also on exceptions), so the net effect on the state is
identical to running `k` directly. -/
def withUsedIsolated (k : SimpM α) : SimpM (α × UsedSimps) := do
  let saved := (← get).usedTheorems
  modify fun s => { s with usedTheorems := {} }
  try
    let a ← k
    return (a, (← get).usedTheorems)
  finally
    modify fun s => { s with usedTheorems := mergeUsed saved s.usedTheorems }

/-- Extract the result expression of a `Simp.Step`, if any. -/
def stepResultExpr? : Simp.Step → Option Expr
  | .done r => some r.expr
  | .visit r => some r.expr
  | .continue (some r) => some r.expr
  | .continue none => none

/-- Extract the result expression of a `Simp.DStep` (`TransformStep`), if any. -/
def dstepResultExpr? : Simp.DStep → Option Expr
  | .done e => some e
  | .visit e => some e
  | .continue (some e) => some e
  | .continue none => none

/-- Record a step into `ref` if the inner simproc changed the expression and
recorded at least one used theorem. -/
private def recordStep (ref : IO.Ref (Array TraceStep)) (phase : Phase)
    (before : Expr) (after? : Option Expr) (fresh : UsedSimps) : SimpM Unit := do
  let some after := after? | return ()
  if fresh.size == 0 then return ()
  if after == before then return ()
  let depth := (← readThe Simp.Context).dischargeDepth.toNat
  ref.modify (·.push { origins := fresh.toArray, before, after, phase, depth })

/-- Wrap a `Simproc` so that successful rewrites are recorded into `ref`. -/
def tracedSimproc (ref : IO.Ref (Array TraceStep)) (phase : Phase)
    (inner : Simp.Simproc) : Simp.Simproc := fun e => do
  let (step, fresh) ← withUsedIsolated (inner e)
  recordStep ref phase e (stepResultExpr? step) fresh
  return step

/-- Wrap a `DSimproc` so that successful rewrites are recorded into `ref`. -/
def tracedDSimproc (ref : IO.Ref (Array TraceStep)) (phase : Phase)
    (inner : Simp.DSimproc) : Simp.DSimproc := fun e => do
  let (step, fresh) ← withUsedIsolated (inner e)
  recordStep ref phase e (dstepResultExpr? step) fresh
  return step

/-- Wrap all four rewrite methods of `m` with tracing. `discharge?` is passed
through untouched, so the wrapped methods behave exactly like `m`. -/
def wrapMethods (ref : IO.Ref (Array TraceStep)) (m : Simp.Methods) : Simp.Methods :=
  { m with
    pre := tracedSimproc ref .pre m.pre
    post := tracedSimproc ref .post m.post
    dpre := tracedDSimproc ref .dpre m.dpre
    dpost := tracedDSimproc ref .dpost m.dpost }

/-- Build the same `Simp.Methods` that core `Lean.Meta.simpCore` would use for
the given simprocs and optional custom discharger. -/
def mkCoreMethods (simprocs : Simp.SimprocsArray) (discharge? : Option Simp.Discharge) :
    Simp.Methods :=
  match discharge? with
  | none => Simp.mkDefaultMethodsCore simprocs
  | some d => Simp.mkMethods simprocs d (wellBehavedDischarge := false)

/--
Traced version of `Lean.Meta.simpTarget`: simplifies the target of `mvarId`
exactly like `simp` would (same context, simprocs and discharger), while
recording every successful rewrite.

Scope: goal target only (no hypothesis locations). The caller is responsible
for replicating the `failIfUnchanged` error of `Lean.Meta.simpGoal` if
tactic-identical behavior is required (see `SimpLens.throwIfNoProgress`).
-/
def traceSimpTarget (mvarId : MVarId) (ctx : Simp.Context)
    (simprocs : Simp.SimprocsArray := #[]) (discharge? : Option Simp.Discharge := none)
    (mayCloseGoal := true) (stats : Simp.Stats := {}) : MetaM TraceResult :=
  mvarId.withContext do
    mvarId.checkNotAssigned `simp_lens
    let ref ← IO.mkRef (#[] : Array TraceStep)
    let methods := wrapMethods ref (mkCoreMethods simprocs discharge?)
    let target ← instantiateMVars (← mvarId.getType)
    let (r, state) ← Simp.mainCore target ctx { stats with } methods
    let goal? ←
      if mayCloseGoal && r.expr.isTrue then
        match r.proof? with
        | some proof => mvarId.assign (← mkOfEqTrue proof)
        | none => mvarId.assign (mkConst ``True.intro)
        pure none
      else
        pure (some (← applySimpResultToTarget mvarId target r))
    let progress := goal? != some mvarId
    return {
      goal?, target, progress
      steps := ← ref.get
      usedTheorems := state.usedTheorems
      diag := state.diag
    }

/-- Replicate the `failIfUnchanged` behavior of `Lean.Meta.simpGoal` for a
traced run: throw the exact same "no progress" error `simp` would throw. -/
def throwIfNoProgress (ctx : Simp.Context) (res : TraceResult) : MetaM Unit := do
  if ctx.config.failIfUnchanged && !res.progress then
    throwError "`simp` made no progress"

/-! ## Location-aware tracing (`simp ... at h`, `at h ⊢`, `at *`) -/

/-- Traced outcome of simplifying one location of a `simp ... at ...` run. -/
structure LocResult where
  /-- The location (target or hypothesis by user-facing name). -/
  loc : LocTag
  /-- The steps that fired while simplifying this location, in order, each
  tagged with `loc`. -/
  steps : Array TraceStep
  /-- The expression (hypothesis type or target) before simplification. -/
  before : Expr
  /-- The expression after simplification. For a location that closed the goal
  this is the closing expression (`False` for a hypothesis, `True` for the
  target). -/
  after : Expr
  /-- Whether this location's expression changed. -/
  changed : Bool
  /-- Whether simplifying this location closed the goal (a hypothesis
  simplified to `False`, or the target to `True`). -/
  closedGoal : Bool
  deriving Inhabited

/-- Result of a traced run of `simp` over a set of locations, mirroring
`Lean.Meta.simpGoal`. -/
structure GoalTraceResult where
  /-- The resulting goal; `none` if `simp` closed it. -/
  goal? : Option MVarId
  /-- One entry per processed location, in processing order (hypotheses in the
  given order, then the target). Processing stops at the location that closes
  the goal, exactly like `simp`. -/
  locs : Array LocResult
  /-- The used-theorem set of the whole run — the union over all locations, in
  first-use order, identical to what plain `simp at ...` reports. -/
  usedTheorems : UsedSimps
  /-- Diagnostics counters accumulated over all locations. -/
  diag : Simp.Diagnostics
  /-- Whether any location made progress (the resulting goal differs from the
  original), matching core `simpGoal`'s `failIfUnchanged` test. -/
  progress : Bool
  deriving Inhabited

/-- All traced steps of all locations, in firing order. -/
def GoalTraceResult.steps (r : GoalTraceResult) : Array TraceStep :=
  r.locs.flatMap (·.steps)

/--
Traced version of `Lean.Meta.simpGoal`: simplifies the hypotheses
`fvarIdsToSimp` (in order) and then, if `simplifyTarget` is true, the target —
exactly like `simp at ...` would (same contexts, same hypothesis
replacement/assertion logic, same goal-closing behavior when a hypothesis
simplifies to `False`), while recording every successful rewrite tagged with
its location.

Mirrors core `simpGoal` statement by statement; like core, it threads
`Simp.Stats` (not the cache) across locations, erases each hypothesis from its
own simp set while simplifying it, and stops at the first location that closes
the goal. Does *not* throw on no-progress — use `throwIfNoProgressGoal`.
-/
def traceSimpGoal (mvarId : MVarId) (ctx : Simp.Context)
    (simprocs : Simp.SimprocsArray := #[]) (discharge? : Option Simp.Discharge := none)
    (simplifyTarget : Bool := true) (fvarIdsToSimp : Array FVarId := #[]) :
    MetaM GoalTraceResult := do
  mvarId.withContext do
    mvarId.checkNotAssigned `simp_lens
    let ref ← IO.mkRef (#[] : Array TraceStep)
    let methods := wrapMethods ref (mkCoreMethods simprocs discharge?)
    let mut mvarIdNew := mvarId
    let mut toAssert : Array Hypothesis := #[]
    let mut replaced : Array FVarId := #[]
    let mut stats : Simp.Stats := {}
    let mut locs : Array LocResult := #[]
    for fvarId in fvarIdsToSimp do
      let localDecl ← fvarId.getDecl
      let type ← instantiateMVars localDecl.type
      let tag := LocTag.hyp localDecl.userName
      -- core: each hypothesis is erased from its own simp set
      let ctx' := ctx.setSimpTheorems <| ctx.simpTheorems.eraseTheorem (.fvar localDecl.fvarId)
      ref.set #[]
      let (r, state) ← Simp.mainCore type ctx' { stats with } methods
      stats := { usedTheorems := state.usedTheorems, diag := state.diag }
      let steps := (← ref.get).map fun s => { s with loc := tag }
      match r.proof? with
      | some _ =>
        match (← applySimpResult mvarIdNew (mkFVar fvarId) type r) with
        | none =>
          -- the hypothesis simplified to False (with proof): goal closed
          locs := locs.push { loc := tag, steps, before := type, after := r.expr,
                              changed := true, closedGoal := true }
          return { goal? := none, locs, usedTheorems := stats.usedTheorems,
                   diag := stats.diag, progress := true }
        | some (value, type') =>
          toAssert := toAssert.push { userName := localDecl.userName, type := type', value }
          locs := locs.push { loc := tag, steps, before := type, after := r.expr,
                              changed := type != r.expr, closedGoal := false }
      | none =>
        if r.expr.isFalse then
          mvarIdNew.assign (← mkFalseElim (← mvarIdNew.getType) (mkFVar fvarId))
          locs := locs.push { loc := tag, steps, before := type, after := r.expr,
                              changed := true, closedGoal := true }
          return { goal? := none, locs, usedTheorems := stats.usedTheorems,
                   diag := stats.diag, progress := true }
        mvarIdNew ← mvarIdNew.replaceLocalDeclDefEq fvarId r.expr
        replaced := replaced.push fvarId
        locs := locs.push { loc := tag, steps, before := type, after := r.expr,
                            changed := type != r.expr, closedGoal := false }
    if simplifyTarget then
      let tr ← traceSimpTarget mvarIdNew ctx simprocs discharge? (stats := stats)
      stats := { usedTheorems := tr.usedTheorems, diag := tr.diag }
      let steps := tr.steps  -- already tagged `.target` (the default)
      match tr.goal? with
      | none =>
        locs := locs.push { loc := .target, steps, before := tr.target,
                            after := mkConst ``True, changed := true, closedGoal := true }
        return { goal? := none, locs, usedTheorems := stats.usedTheorems,
                 diag := stats.diag, progress := true }
      | some m =>
        locs := locs.push { loc := .target, steps, before := tr.target,
                            after := ← instantiateMVars (← m.getType),
                            changed := tr.progress, closedGoal := false }
        mvarIdNew := m
    let (_, mvarIdNew') ← mvarIdNew.assertHypotheses toAssert
    mvarIdNew := mvarIdNew'
    let toClear := fvarIdsToSimp.filter fun fvarId => !replaced.contains fvarId
    mvarIdNew ← mvarIdNew.tryClearMany toClear
    return { goal? := some mvarIdNew, locs, usedTheorems := stats.usedTheorems,
             diag := stats.diag, progress := mvarIdNew != mvarId }

/-- Replicate the `failIfUnchanged` behavior of `Lean.Meta.simpGoal` for a
traced multi-location run: throw the exact same "no progress" error `simp`
would throw when *no* location made progress. -/
def throwIfNoProgressGoal (ctx : Simp.Context) (res : GoalTraceResult) : MetaM Unit := do
  if ctx.config.failIfUnchanged && !res.progress then
    throwError "`simp` made no progress"

end SimpLens
