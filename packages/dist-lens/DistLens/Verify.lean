import Mathlib.Probability.ProbabilityMassFunction.Constructions
import Mathlib.Probability.ProbabilityMassFunction.Binomial
import Mathlib.Probability.Distributions.Uniform
import Mathlib.Probability.ProbabilityMassFunction.Integrals
import Mathlib.Tactic.NormNum
import Mathlib.Tactic.Finiteness
-- Already in the import closure; imported directly only so the typed option
-- constant `Meta.backward.isDefEq.respectTransparency.types` is in scope.
import Lean.Meta.ExprDefEq

/-! # DistLens: verified weight goals — the `pmf_num` tactic

The proof side of the picture+proof contract.  For every weight DistLens
displays, it offers the goal `p x = (a/b : ℝ≥0∞)` with the suggested proof
`by pmf_num`.  This file ships that tactic; the test suite *compiles* such
examples for every demo distribution, so the recipe is proven to work, not
just printed.

The recipe is exactly the probe-validated chain (both tactics are
elaborators, not macros, that run these steps as flat `evalTactic` calls; see
the implementation note below for why — browser stack depth):

1. `simp` with the PMF application lemma set (`bind_apply`, `map_apply`,
   `pure_apply`, `bernoulli_apply`, `uniformOfFintype_apply`,
   `uniformOfFinset_apply`, `binomial_apply`, `ofFintype_apply`,
   `tsum_fintype`, `tsum_bool`, `Fin.sum_univ_succ`, plus the
   `Matrix.cons_val*` lemmas so `![…]`-literal weight functions and
   `![…]`-vectors of PMFs reduce), leaving a ground ℝ≥0∞ arithmetic residue;
2. `ennreal_num` closes the residue:
   * `done` — `simp` already closed it;
   * `norm_num` — for residues plain `norm_num` can do (e.g. after
     `binomial_apply`);
   * the `toReal` bridge — `ENNReal.toReal_eq_toReal_iff'` with `finiteness`
     side goals, push `toReal` through `+ * / ⁻¹ ^`, finish with `norm_num`
     in ℝ (there is **no** ENNReal `norm_num` extension in Mathlib, so this
     bridge is mandatory for goals like `6⁻¹ + 6⁻¹ + 6⁻¹ = 2⁻¹`);
   * the truncated-subtraction branch — `ENNReal.sub_eq_of_eq_add` first
     (for `bernoulli`'s `1 − p` residue at `false`), then the same bridge.

Every branch ends in `done`, so a partial simplification never "succeeds"
with goals left over; if no branch closes the goal, the tactic fails with a
deterministic message (pinned by the negative tests) — honest failure over
silent wrongness.

`ennreal_num` is exposed separately because it is also the right tool for
`PMF.ofFintype`'s sum-to-1 side goal (after `simp [Fin.sum_univ_succ]`).
-/

namespace DistLens

open ENNReal

/-! ### Implementation note: elaborators, not macros

Both tactics used to be macros (`ennreal_num` = `first | done | (norm_num; done)
| (rw …; simp …; norm_num; done) | (apply …; rw …; …; done) | fail …`, and
`pmf_num` = `set_option … in ((try (set_option … in simp …)) <;> ennreal_num)`).
Every combinator layer (macro expansion, `first`, paren/sequence nodes, `<;>`,
`try`, `set_option … in`) adds elaborator frames, and in the WebAssembly build
(QED64, ~500 KiB engine stack per worker, guarded by a stack probe) that extra
depth made true `twoDice` claims fail while the same steps written flat pass.
Measured natively (`lean --tstack=N -DElab.async=false`, smallest passing N,
same machine and session): `twoDice 5 = 1/6` needs ~265 KB of thread stack
with the macros and ~197 KB with these elaborators, against a ~88 KB floor
for just importing this file's dependencies (1.35x in total, 1.6x above the
floor); native depth is only a proxy for the WebAssembly engine's frames.
The same steps typed by hand as a flat tactic sequence also need ~197 KB, so
the remaining depth is inside the steps themselves (`simp`, `finiteness`,
`norm_num`), not in this wrapping.
So both are now elaborators that run the SAME steps, in the SAME order, as flat
`evalTactic` calls, setting the options programmatically (`withOptions`, which
is what the tactic `set_option … in` does, BuiltinTactic.lean:215-227) and
iterating goals in a loop (what `<;>` = `focus (t; all_goals s)` does,
Init/Tactics.lean:408-413).

Semantics kept from the macros:
* each `ennreal_num` branch runs without error recovery and must leave no goal
  (`done`); an ordinary failure restores the state (messages included) and
  tries the next branch, as `first` (BuiltinTactic.lean:631-640,
  `Tactic.orElse`, Tactic/Basic.lean:436-437);
* runtime exceptions (`maxRecDepth`/`maxHeartbeats`, including the
  WebAssembly stack guard, which is tagged `runtime.maxRecDepth`) and
  interrupts are never caught: `Tactic.tryCatch` bottoms out in
  `Core.tryCatch` (CoreM.lean:792-800), exactly as `first`/`try`/`all_goals`;
* if every branch fails, the error is exactly what
  `fail "ennreal_num: cannot close this ℝ≥0∞ goal"` printed (`evalFail`,
  BuiltinTactic.lean:642-647) — pinned by the negative tests.

One addition: the guard can be *converted* into an ordinary error before it
reaches us (instance synthesis rethrows it as "failed to synthesize …",
SynthInstance.lean:682-688), and backtracking then erases that evidence.  So
before restoring, each failed attempt's error and logged messages are kept,
and — only if every branch fails — rendered and searched for the guard's
texts; if found, the error says Lean ran out of stack instead of claiming the
goal is false.  Goal text is not evidence: if the goals themselves mention a
guard text (`done`'s "unsolved goals" report, `fail` and many errors print
them), there is no relabel.  Scanning the logged messages is defensive, for
tactics that log an error and then fail (`done` logs its report, then
aborts).  The `(by finiteness)` arguments of `rewrite`/`apply` do not log:
recovery is off inside a branch, so `Tactic.runTermElab` elaborates them under
`Term.withoutErrToSorry` (ElabTerm.lean:29-39), their `by` blocks keep that in
their saved context (`SavedContext.errToSorry`), and `runTactic` rethrows
their errors (SyntheticMVars.lean:529-537) — a runtime guard escapes as a
runtime error, an ordinary error becomes the branch's error.

Limit: detection only sees guard text that reaches a branch's error or the
messages it logged.  A guard converted by instance synthesis and then
swallowed inside `finiteness` (Aesop reports only "failed to prove the goal
after exhaustive search") or `norm_num` (which drops a failing extension's
error and tries the next) is invisible here, so such a case still shows
"cannot close".  The full fix is on the QED64/kernel side: a guard-trip
counter that backtracking cannot erase. -/

open Lean Elab Tactic Meta

/-- One step of an `ennreal_num` branch. -/
private inductive EnnrealNumStep where
  /-- `evalTactic tac`. -/
  | run (tac : Syntax)
  /-- `try tac` (= `first | tac | skip`): run without recovery; on an ordinary
  error restore the state and continue; runtime errors propagate. -/
  | attempt (tac : Syntax)
  /-- `done`. -/
  | done

private def EnnrealNumStep.eval : EnnrealNumStep → TacticM Unit
  | .run tac => evalTactic tac
  -- TacticM's `try … catch` is the restoring `Tactic.tryCatchRestore`.
  | .attempt tac => try withoutRecover (evalTactic tac) catch _ => pure ()
  | .done => Tactic.done

/-- The four branches of `ennreal_num`, in the macro's order, each a FLAT list
of steps.  `rw [r]` is spelled as its v4.34 expansion, `rewrite [r]` then
`try (with_reducible rfl)` (Init/Tactics.lean:612-616), so the `(by finiteness)`
arguments run without the macro/paren/seq/`try`/`first` layers around them.
Keep in sync with `rw` if a toolchain bump changes that macro. -/
private def ennrealNumBranches : TacticM (Array (Array EnnrealNumStep)) := do
  let bridge : Array EnnrealNumStep := #[
    .run (← `(tactic| rewrite [← ENNReal.toReal_eq_toReal_iff' (by finiteness) (by finiteness)])),
    .attempt (← `(tactic| with_reducible rfl)),
    .run (← `(tactic| simp (disch := finiteness) only [ENNReal.toReal_add, ENNReal.toReal_inv,
           ENNReal.toReal_mul, ENNReal.toReal_div, ENNReal.toReal_pow,
           ENNReal.toReal_ofNat, ENNReal.toReal_one, ENNReal.toReal_natCast])),
    .run (← `(tactic| norm_num)),
    .done]
  return #[
    #[.done],
    #[.run (← `(tactic| norm_num)), .done],
    bridge,
    #[.run (← `(tactic| apply ENNReal.sub_eq_of_eq_add (by finiteness)))] ++ bridge]

/-- Run `x` as one `first` alternative: without error recovery; `none` on
success.  On an ordinary error, return the evidence — the error and every
message `x` logged, with their context attached — then restore the saved state
(which erases those messages, as `first` does).  Runtime errors propagate
without restoring, as with `first`. -/
private def attemptBranch (x : TacticM Unit) : TacticM (Option (Array MessageData)) := do
  let s ← saveState
  -- `reportedPlusUnreported`, not `unreported`: its length is unchanged if
  -- messages are marked reported meanwhile (`MessageLog.markAllReported`).
  let n0 := (← Core.getMessageLog).reportedPlusUnreported.size
  -- Non-restoring catch, so the attempt's logged messages are still readable.
  let err? ← Tactic.tryCatch (do withoutRecover x; pure none) (fun ex => pure (some ex))
  let some ex := err? | return none
  let logged :=
    ((← Core.getMessageLog).reportedPlusUnreported.toArray.extract n0).map (·.data)
  let evidence := #[← addMessageContext ex.toMessageData] ++ logged
  s.restore
  return some evidence

/-- The QED64 WebAssembly engine-stack guard texts (Lean and kernel side).
The generic "maximum recursion depth" text is deliberately absent, so a
genuine `maxRecDepth` is never relabelled. -/
private def stackGuardMarkers : List String :=
  ["the WebAssembly runtime's stack is exhausted",
   "the WebAssembly engine's stack is exhausted"]

/-- Whether `m`'s rendering mentions an engine-stack guard text.  Used only once
every branch has failed, so successful proofs never pay for the rendering. -/
private def mentionsStackGuard (m : MessageData) : MetaM Bool := do
  let s ← try m.toString catch _ => pure ""
  return stackGuardMarkers.any fun k => (s.splitOn k).length > 1

namespace Internal

/-- `ennreal_num`'s engine: `first | b₁ | … | bₙ | fail msg` without the
combinator layers.  `evidence` carries failures swallowed earlier (the
`try simp` step of `pmf_num`).  Not API: public only so the package tests
(`DistLensTests/StackGuardTests.lean`) can drive the stack-guard relabel with
simulated branches. -/
def ennrealNumCoreWith (branches : Array (TacticM Unit))
    (evidence : Array MessageData := #[]) : TacticM Unit := do
  let mut evidence := evidence
  for branch in branches do
    match ← attemptBranch branch with
    | none => return
    | some ev => evidence := evidence ++ ev
  -- The goals after the last restore, as `evalFail` shows them.
  let goalsMsg := MessageData.joinSep ((← getGoals).map MessageData.ofGoal) m!"\n\n"
  -- Goal text is not evidence: if the goals mention a guard text, every
  -- message that prints them would too, so never relabel then.
  unless (← mentionsStackGuard (← addMessageContext goalsMsg)) do
    if let some m ← evidence.findM? (mentionsStackGuard ·) then
      throwError "ennreal_num: Lean ran out of stack while checking this goal, so it could \
        not decide it (the claim may well be true):{indentD m}\n{goalsMsg}"
  throwError "ennreal_num: cannot close this ℝ≥0∞ goal\n{goalsMsg}"

end Internal

/-- `all_goals tac` (`evalAllGoals`, BuiltinTactic.lean:229-254) with `tac` a
`TacticM` action instead of syntax: under recovery, a failing goal's error is
logged, the goal admitted, the remaining goals still tried, then the tactic
aborts. -/
private def allGoalsWith (tac : TacticM Unit) : TacticM Unit := do
  let mvarIds ← getGoals
  let mut mvarIdsNew := #[]
  let mut abort := false
  for mvarId in mvarIds do
    unless (← mvarId.isAssigned) do
      setGoals [mvarId]
      let saved ← saveState
      abort ← Tactic.tryCatch
        (do tac; pure abort)
        (fun ex => do
          if (← read).recover then
            logException ex
            let msgLog ← Core.getMessageLog
            saved.restore
            Core.setMessageLog msgLog
            admitGoal mvarId
            pure true
          else
            throw ex)
      mvarIdsNew := mvarIdsNew ++ (← getUnsolvedGoals)
  if abort then
    throwAbortTactic
  setGoals mvarIdsNew.toList

/-- Close a ground ℝ≥0∞ arithmetic goal: `done` | `norm_num` | the
`toReal_eq_toReal_iff'`+`finiteness` bridge into ℝ | the
`ENNReal.sub_eq_of_eq_add` branch for truncated-subtraction residues
(`bernoulli`'s `1 − p`).  Fails with a deterministic message when no branch
applies — plain `norm_num` cannot decide most ℝ≥0∞ arithmetic, so the bridge
branches carry the real load. -/
syntax (name := ennrealNum) "ennreal_num" : tactic

@[tactic ennrealNum] def evalEnnrealNum : Tactic := fun _ => do
  Internal.ennrealNumCoreWith ((← ennrealNumBranches).map (·.forM EnnrealNumStep.eval))

/-- Prove a concrete PMF weight equality `p x = (a/b : ℝ≥0∞)` for the
DistLens-supported constructors (`pure`, `bind`, `map`, `uniformOfFintype`,
`uniformOfFinset`, `bernoulli`, `binomial`, `ofFintype` with `![…]`
literals): `simp` with the PMF application lemma set, then `ennreal_num` on
every residue.  Also proves the stationary-chain equalities
`(π.bind step) y = π y`.  Fails deterministically on goals outside this
shape — including *false* weight claims (pinned by the negative tests). -/
syntax (name := pmfNum) "pmf_num" : tactic

@[tactic pmfNum] def evalPmfNum : Tactic := fun _ =>
  -- The simp set names `PMF.bernoulli_apply`/`PMF.binomial_apply`, which are
  -- deprecated at this pin; without the scoped option every `by pmf_num`
  -- inserted into a user file would emit deprecation warnings even for
  -- non-deprecated distributions.
  withOptions (Linter.linter.deprecated.set · false) <|
    -- `try simp … <;> ennreal_num` = `focus (try simp …; all_goals ennreal_num)`.
    focus do
      let simpTac ← `(tactic| simp [PMF.bind_apply, PMF.map_apply, PMF.pure_apply,
              PMF.bernoulli_apply, PMF.uniformOfFintype_apply,
              PMF.uniformOfFinset_apply, PMF.binomial_apply, PMF.ofFintype_apply,
              tsum_fintype, tsum_bool, Fin.sum_univ_succ,
              Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.head_cons,
              Fin.isValue])
      -- `backward.isDefEq.respectTransparency.types` defaults to `true` since
      -- Lean v4.33.0 (`false` at v4.32.2, the pin this package was written
      -- against; see `register_builtin_option` in `Lean/Meta/ExprDefEq.lean`):
      -- when `simp` assigns the `hs : s.Nonempty` metavariable of
      -- `uniformOfFinset_apply`, the type of the user's proof term is now
      -- compared at implicit transparency, and the natural spelling
      -- `⟨1, by simp⟩` elaborates to an `Exists.intro` whose type `∃ x, x ∈ s`
      -- only reaches `Finset.Nonempty s` by unfolding a semireducible `def`.
      -- Without the scoped option the lemma silently fails to fire and
      -- `pmf_num` refuses a true claim.  The option is scoped to the `simp`
      -- step only (the ℝ≥0∞ residue is closed exactly as before).
      -- `try`: an ordinary failure restores the state; its evidence is kept
      -- for `ennreal_num`'s final message.
      let evidence := (← attemptBranch <|
        withOptions (Meta.backward.isDefEq.respectTransparency.types.set · false) <|
          evalTactic simpTac).getD #[]
      let branches := (← ennrealNumBranches).map (·.forM EnnrealNumStep.eval)
      allGoalsWith (Internal.ennrealNumCoreWith branches evidence)

end DistLens
