import SimpLens.Trace

/-!
# SimpLens.Exclude — exclusion previews

For each lemma `L` used by a traced `simp` run, re-run the *same* simp call
with `L` erased from the simp set and record where the goal lands. This shows
the user which lemmas are load-bearing (excluding them changes the landing
goal) and which are incidental.

Erasure uses core's `SimpTheoremsArray.eraseTheorem`; simproc origins are
additionally erased from the simproc set via `SimprocsArray.erase` (they live
in a separate data structure).

## Failure containment

Removing a lemma can change the complexity class of the re-run (e.g. dropping
a normalization workhorse like `Nat.reduceAdd` can make simp diverge), so a
single preview can be unboundedly more expensive than the original call.
Two mechanisms keep previews from ever failing (or starving) the tactic:

* every preview runs under `tryCatchRuntimeEx` — plain `try ... catch` on
  `CoreM`-based monads *rethrows* runtime exceptions (`Core.tryCatch` checks
  `Exception.isRuntime`), so a heartbeat/recursion-depth blowup inside a
  preview would otherwise escape and hard-fail the whole tactic;
* every preview may be given its own heartbeat sub-budget (`budget?`), so one
  pathological re-run cannot run away even under `maxHeartbeats 0`.

A contained failure is reported as an `ExclusionOutcome` with a non-`ok`
`status` (`errored` for regular errors, `timedOut` for resource-limit ones —
the latter usually means the excluded lemma is what keeps the call fast).
-/

namespace SimpLens

open Lean Meta Simp

/-- Cap on the number of exclusion previews computed (re-running simp once per
used lemma is quadratic in the worst case). -/
def maxExclusions : Nat := 12

/-- How an exclusion re-run terminated. -/
inductive PreviewStatus where
  /-- The re-run completed (goal closed or landed somewhere). -/
  | ok
  /-- The re-run failed with a regular error. -/
  | errored
  /-- The re-run hit a resource limit (heartbeats or recursion depth) — this
  usually means the excluded lemma is what keeps the call fast. -/
  | timedOut
  deriving Repr, BEq, Inhabited

/-- Outcome of re-running the simp call with one lemma excluded. -/
structure ExclusionOutcome where
  /-- The excluded origin. -/
  origin : Origin
  /-- Pretty-printed landing goal; `none` if the goal was closed anyway. -/
  landingGoal? : Option String
  /-- `true` if excluding the lemma changed the outcome relative to the full
  run (different landing goal, or closed vs. not closed). -/
  essential : Bool
  /-- How the re-run terminated (failures are contained, never propagated). -/
  status : PreviewStatus
  deriving Inhabited

/-- `true` if the exclusion re-run failed (error or resource limit). -/
def ExclusionOutcome.errored (oc : ExclusionOutcome) : Bool :=
  oc.status != .ok

/-- Result of computing exclusion previews. -/
structure ExclusionReport where
  /-- One outcome per excluded lemma, in used-order. -/
  outcomes : Array ExclusionOutcome
  /-- `true` if the used-lemma list was longer than `maxExclusions` and was
  truncated. -/
  truncated : Bool
  /-- The hypothesis (by user-facing name) whose landing state the previews
  report; `none` means the previews report the goal target. Only set for
  location runs that do not include the target. -/
  watch? : Option Name := none
  /-- `true` if preview computation was skipped (`simp_lens -previews`). -/
  disabled : Bool := false
  deriving Inhabited

/--
Per-preview heartbeat budget derived from the measured cost of the traced
run: a small multiple plus a fixed floor (in raw heartbeats; the floor keeps
tiny runs from flagging legitimate previews, the multiple keeps a preview in
the same complexity ballpark as the original call). A preview that exceeds
its budget is reported as `PreviewStatus.timedOut`, never as a tactic error.
-/
def previewBudgetOf (tracedCost : Nat) : Nat :=
  2 * tracedCost + 1000000

/-- Run `k` under its own heartbeat sub-budget of `budget?` raw heartbeats
(counted from now); `none` keeps the ambient budget. -/
def withPreviewBudget [Monad m] [MonadControlT CoreM m] [MonadWithReaderOf Core.Context m]
    (budget? : Option Nat) (k : m α) : m α :=
  match budget? with
  | none => k
  | some b =>
    withTheReader Core.Context (fun c => { c with maxHeartbeats := b }) do
      withCurrHeartbeats k

/--
Run `k` without consuming the surrounding command's heartbeat budget: the
global heartbeat counter is restored afterwards (the same snapshot/restore
pattern core uses in `Environment` realization), and `k` itself starts a
fresh count against the ambient limit. Wall-clock time is still spent, but a
heavy sub-computation can no longer starve the rest of the command.
-/
def withHeartbeatsNeutral [Monad m] [MonadControlT CoreM m] (k : m α) : m α :=
  controlAt CoreM fun runInBase => do
    let hb ← IO.getNumHeartbeats
    try
      Core.withCurrHeartbeats (runInBase k)
    finally
      IO.setNumHeartbeats hb

/-- Erase `origin` from a simp context (and from the simproc array when the
origin denotes a simproc). Returns the modified context and simprocs. -/
def eraseOrigin (ctx : Simp.Context) (simprocs : Simp.SimprocsArray)
    (origin : Origin) : MetaM (Simp.Context × Simp.SimprocsArray) := do
  let ctx := ctx.setSimpTheorems (ctx.simpTheorems.eraseTheorem origin)
  let simprocs ←
    if let .decl declName _ _ := origin then
      if (← Simp.isSimproc declName) || (← Simp.isBuiltinSimproc declName) then
        pure (simprocs.erase declName)
      else
        pure simprocs
    else
      pure simprocs
  return (ctx, simprocs)

/-- Run the simp call on a *fresh copy* of `mvarId`'s goal with `origin`
erased, and report the landing goal. Never assigns `mvarId`. All failures of
the re-run — including heartbeat/recursion-limit blowups, which a plain
`catch` would rethrow — are contained via `tryCatchRuntimeEx` and reported in
the outcome's `status`; `budget?` optionally caps the re-run's own heartbeat
spend. -/
def runExclusion (mvarId : MVarId) (ctx : Simp.Context)
    (simprocs : Simp.SimprocsArray) (discharge? : Option Simp.Discharge)
    (origin : Origin) (fullRunLanding : Option String)
    (budget? : Option Nat := none) : MetaM ExclusionOutcome :=
  mvarId.withContext do
    let (ctx, simprocs) ← eraseOrigin ctx simprocs origin
    -- never error on "no progress" during a preview
    let ctx := ctx.setFailIfUnchanged false
    let goalCopy ← mkFreshExprSyntheticOpaqueMVar (← mvarId.getType)
    tryCatchRuntimeEx
      (withPreviewBudget budget? do
        let (res, _) ← simpTarget goalCopy.mvarId! ctx simprocs discharge?
        let landingGoal? ← match res with
          | none => pure none
          | some m => pure (some (toString (← ppExpr (← instantiateMVars (← m.getType)))))
        return { origin, landingGoal?, essential := landingGoal? != fullRunLanding, status := .ok })
      fun ex =>
        return { origin, landingGoal? := none, essential := true,
                 status := if ex.isRuntime then .timedOut else .errored }

/--
Compute exclusion previews for every used lemma of a traced run (capped at
`maxExclusions`). `mvarId` must be the goal **before** simplification.
`budget?` is the per-preview heartbeat sub-budget (see `previewBudgetOf`).
-/
def excludeEach (mvarId : MVarId) (ctx : Simp.Context)
    (simprocs : Simp.SimprocsArray) (discharge? : Option Simp.Discharge)
    (res : TraceResult) (budget? : Option Nat := none) : MetaM ExclusionReport :=
  mvarId.withContext do
    let fullLanding ← match res.goal? with
      | none => pure none
      | some m => pure (some (toString (← ppExpr (← instantiateMVars (← m.getType)))))
    let used := res.usedTheorems.toArray
    let truncated := used.size > maxExclusions
    let used := used.take maxExclusions
    let outcomes ← used.mapM fun o =>
      runExclusion mvarId ctx simprocs discharge? o fullLanding budget?
    return { outcomes, truncated }

/-! ## Location-aware exclusion previews -/

/-- The landing state of a (possibly closed) goal, watched at the target
(`watch? = none`) or at the hypothesis with the given user-facing name.
`none` result means the goal was closed. -/
def landingAt (goal? : Option MVarId) (watch? : Option Name) : MetaM (Option String) := do
  match goal? with
  | none => return none
  | some m => m.withContext do
    match watch? with
    | none => return some (toString (← ppExpr (← instantiateMVars (← m.getType))))
    | some n =>
      match (← getLCtx).findFromUserName? n with
      | some ldecl => return some (toString (← ppExpr (← instantiateMVars ldecl.type)))
      | none => return some s!"<hypothesis {n} cleared>"

/-- The watch location of a multi-location run's exclusion previews: the
target when it was included in the run, otherwise the first hypothesis the
original run changed (falling back to the first processed hypothesis). -/
def watchOf (res : GoalTraceResult) (simplifyTarget : Bool) : Option Name :=
  if simplifyTarget then none
  else
    let changedHyp? := res.locs.findSome? fun l => match l.loc with
      | .hyp n => if l.changed then some n else none
      | .target => none
    changedHyp? <|> res.locs.findSome? fun l => match l.loc with
      | .hyp n => some n
      | .target => none

/-- Run the simp call at the *same locations* on a fresh copy of `mvarId`'s
goal with `origin` erased, and report the landing state at `watch?` (target if
`none`). Never assigns `mvarId`. All failures of the re-run — including
heartbeat/recursion-limit blowups, which a plain `catch` would rethrow — are
contained via `tryCatchRuntimeEx` and reported in the outcome's `status`;
`budget?` optionally caps the re-run's own heartbeat spend. -/
def runExclusionAt (mvarId : MVarId) (ctx : Simp.Context)
    (simprocs : Simp.SimprocsArray) (discharge? : Option Simp.Discharge)
    (origin : Origin) (fullRunLanding : Option String)
    (simplifyTarget : Bool) (fvarIdsToSimp : Array FVarId)
    (watch? : Option Name) (budget? : Option Nat := none) : MetaM ExclusionOutcome :=
  mvarId.withContext do
    let (ctx, simprocs) ← eraseOrigin ctx simprocs origin
    -- never error on "no progress" during a preview
    let ctx := ctx.setFailIfUnchanged false
    let goalCopy ← mkFreshExprSyntheticOpaqueMVar (← mvarId.getType)
    tryCatchRuntimeEx
      (withPreviewBudget budget? do
        let (res?, _) ← simpGoal goalCopy.mvarId! ctx simprocs discharge?
          (simplifyTarget := simplifyTarget) (fvarIdsToSimp := fvarIdsToSimp)
        let landingGoal? ← landingAt (res?.map (·.2)) watch?
        return { origin, landingGoal?, essential := landingGoal? != fullRunLanding, status := .ok })
      fun ex =>
        return { origin, landingGoal? := none, essential := true,
                 status := if ex.isRuntime then .timedOut else .errored }

/--
Compute exclusion previews for every used lemma of a traced multi-location
run (capped at `maxExclusions`), re-running at the *same* locations. `mvarId`
must be the goal **before** simplification. The reported landing state is the
target's when the target was included, else the first hypothesis the original
run changed. `budget?` is the per-preview heartbeat sub-budget (see
`previewBudgetOf`).
-/
def excludeEachAt (mvarId : MVarId) (ctx : Simp.Context)
    (simprocs : Simp.SimprocsArray) (discharge? : Option Simp.Discharge)
    (res : GoalTraceResult) (simplifyTarget : Bool) (fvarIdsToSimp : Array FVarId)
    (budget? : Option Nat := none) : MetaM ExclusionReport :=
  mvarId.withContext do
    let watch? := watchOf res simplifyTarget
    let fullLanding ← landingAt res.goal? watch?
    let used := res.usedTheorems.toArray
    let truncated := used.size > maxExclusions
    let used := used.take maxExclusions
    let outcomes ← used.mapM fun o =>
      runExclusionAt mvarId ctx simprocs discharge? o fullLanding
        simplifyTarget fvarIdsToSimp watch? budget?
    return { outcomes, truncated, watch? }

end SimpLens
