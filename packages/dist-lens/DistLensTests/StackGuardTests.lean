import DistLens.Verify

/-! # Stack-guard relabel tests

`ennreal_num` relabels its final failure as "Lean ran out of stack …" when a
failed branch's error, or a message it logged before failing, mentions the
QED64 WebAssembly stack-guard text (see the implementation note in
`DistLens/Verify.lean`).  The guard cannot be triggered natively, so these
tests drive `ennreal_num`'s engine (`DistLens.Internal.ennrealNumCoreWith`)
with simulated branches: `fail "…"` for a converted (ordinary) guard error,
`log_error_msg` + `fail` for one logged before an ordinary failure, and
`throw_max_rec_depth` for a runtime error, which must propagate unchanged.
-/

namespace DistLensTests.StackGuard

open Lean Elab Tactic

-- Failed alternatives are rolled back, so Mathlib's unused-tactic linter
-- reports them as doing nothing when a later one closes the goal (test (c)).
set_option linter.unusedTactic false

/-- `ennreal_num`'s engine run on the given branches instead of its own: each
`| tac` is one `first` alternative (no error recovery, state restored on an
ordinary failure). -/
syntax (name := ennrealNumWith)
  "ennreal_num_with " withPosition((ppDedent(ppLine) colGe "| " tacticSeq)+) : tactic

@[tactic ennrealNumWith] def evalEnnrealNumWith : Tactic := fun stx =>
  DistLens.Internal.ennrealNumCoreWith (stx[1].getArgs.map fun alt => evalTactic alt[1])

/-- Log `msg` as an error and continue. -/
elab "log_error_msg " msg:str : tactic => logError msg.getString

/-- Throw the runtime `maxRecDepth` exception (the WebAssembly stack guard has
the same `runtime.maxRecDepth` tag). -/
elab "throw_max_rec_depth" : tactic => do throwMaxRecDepthAt (← getRef)

/-! (a) Guard text in a branch's thrown (ordinary) error: relabelled. -/

/--
error: ennreal_num: Lean ran out of stack while checking this goal, so it could not decide it (the claim may well be true):
  failed to synthesize: the WebAssembly runtime's stack is exhausted
  ⊢ True
⊢ True
-/
#guard_msgs in
example : True := by
  ennreal_num_with
  | fail "no progress"
  | fail "failed to synthesize: the WebAssembly runtime's stack is exhausted"
  | fail "no progress either"

/-! (b) Guard text only in a message the branch logged before failing:
relabelled (the logged message itself is erased by the restore). -/

/--
error: ennreal_num: Lean ran out of stack while checking this goal, so it could not decide it (the claim may well be true):
  kernel: the WebAssembly engine's stack is exhausted
⊢ True
-/
#guard_msgs in
example : True := by
  ennreal_num_with
  | log_error_msg "kernel: the WebAssembly engine's stack is exhausted"; fail "rule failed"
  | fail "no progress"

/-! (c) A guard-mentioning branch, then a later branch that closes the goal:
success, no message. -/

#guard_msgs in
example : True := by
  ennreal_num_with
  | fail "failed to synthesize: the WebAssembly runtime's stack is exhausted"
  | log_error_msg "the WebAssembly engine's stack is exhausted"; fail "rule failed"
  | trivial

/-! (d) A runtime `maxRecDepth` error propagates unchanged — never caught, so
never relabelled, even after a guard-mentioning branch. -/

/--
error: maximum recursion depth has been reached
use `set_option maxRecDepth <num>` to increase limit
use `set_option diagnostics true` to get diagnostic information
-/
#guard_msgs in
example : True := by
  ennreal_num_with
  | fail "failed to synthesize: the WebAssembly runtime's stack is exhausted"
  | throw_max_rec_depth
  | trivial

/-! (e) A false goal, no guard anywhere: the pinned "cannot close" text. -/

/--
error: ennreal_num: cannot close this ℝ≥0∞ goal
⊢ False
-/
#guard_msgs in
example : False := by
  ennreal_num_with
  | done
  | fail "no progress"
  | log_error_msg "some other failure"; fail "rule failed"

/-! (f) Goal text is not evidence: a false goal whose own text mentions a
guard string is echoed by `done`'s "unsolved goals" report and by `fail`, but
still gets the pinned "cannot close" text. -/

/--
error: ennreal_num: cannot close this ℝ≥0∞ goal
⊢ "the WebAssembly runtime's stack is exhausted" = ""
-/
#guard_msgs in
example : "the WebAssembly runtime's stack is exhausted" = "" := by
  ennreal_num_with
  | done
  | fail "no progress"

end DistLensTests.StackGuard
