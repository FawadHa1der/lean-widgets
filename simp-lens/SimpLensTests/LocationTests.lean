import SimpLensTests.Helpers

/-!
# Location tests — `simp_lens at h`, `at h ⊢`, `at *`

Four layers, mirroring the target-only suites:
1. pure `#guard` tests for the location data structures (`LocTag`,
   `LocResult`, `GoalTraceResult.films`/`steps`, `watchOf`,
   `LensAtSpec.suffix`);
2. `#lens_at_*` commands running the traced `simpGoal` mirror: per-location
   films (used sets, origins, step counts, before/after subterms), landing
   hypotheses/targets, union minimization with location clauses, per-location
   equivalence against real `simp`, exclusion previews at locations, and
   chain invariants;
3. `#guard_msgs`-pinned `Try this:` messages and error parity for the
   `simp_lens` tactic with location clauses;
4. twin examples (`simp_lens` vs `simp`) proving identical goal/hypothesis
   transformations, pinned with `guard_hyp ... :ₛ` / `show`.
-/

namespace SimpLensTests.Location

open Lean Meta Simp SimpLens

set_option linter.unusedVariables false

/-! ## 1. Pure data-structure tests -/

#guard LocTag.target.label == "⊢"
#guard (LocTag.hyp `h).label == "h"
#guard (LocTag.hyp `h₂).label == "h₂"
#guard LocTag.target == LocTag.target
#guard (LocTag.hyp `h : LocTag) != .target
#guard (LocTag.hyp `h : LocTag) != .hyp `h'

-- location suffixes used to build genuine `simp ... at ...` syntax
#guard ({} : LensAtSpec).suffix == ""
#guard ({ wildcard := true } : LensAtSpec).suffix == " at *"
#guard ({ atHyps := #[`h], atTarget := false } : LensAtSpec).suffix == " at h"
#guard ({ atHyps := #[`h₁, `h₂], atTarget := true } : LensAtSpec).suffix == " at h₁ h₂ ⊢"

/-- Synthetic step tagged as fired at hypothesis `h`. -/
def stH : TraceStep :=
  { origins := #[.decl `foo], before := mkConst `a, after := mkConst `b,
    phase := .post, depth := 0, loc := .hyp `h }

/-- Synthetic unchanged-hypothesis location (processed first). -/
def locH2 : LocResult :=
  { loc := .hyp `h₂, steps := #[], before := mkConst `a, after := mkConst `a,
    changed := false, closedGoal := false }

/-- Synthetic changed-hypothesis location. -/
def locH : LocResult :=
  { loc := .hyp `h, steps := #[stH], before := mkConst `a, after := mkConst `b,
    changed := true, closedGoal := false }

/-- Synthetic unchanged-target location. -/
def locT : LocResult :=
  { loc := .target, steps := #[], before := mkConst `a, after := mkConst `a,
    changed := false, closedGoal := false }

/-- Synthetic multi-location trace result (`at h₂ h ⊢`-shaped). -/
def synthRes : GoalTraceResult :=
  { goal? := none, locs := #[locH2, locH, locT],
    usedTheorems := ({} : UsedSimps).insert (.decl `foo), diag := {}, progress := true }

-- flattened steps: only locH contributes
#guard synthRes.steps.size == 1
#guard synthRes.steps[0]!.loc == .hyp `h
#guard synthRes.steps[0]!.before == mkConst `a

-- one film section per location, in processing order, frames renumbered
#guard synthRes.films.size == 3
#guard synthRes.films.map (·.loc.label) == #["h₂", "h", "⊢"]
#guard synthRes.films.map (·.film.length) == #[0, 1, 0]
#guard synthRes.films[1]!.film.frames[0]!.index == 0
#guard synthRes.films.map (·.closedGoal) == #[false, false, false]
#guard synthRes.films[1]!.film.chainConsistent

-- watch location of exclusion previews: target when included, else the first
-- *changed* hypothesis, else the first hypothesis
#guard watchOf synthRes true == none
#guard watchOf synthRes false == some `h
#guard watchOf { synthRes with locs := #[locH2, locT] } false == some `h₂
#guard watchOf { synthRes with locs := #[locT] } false == none
#guard watchOf { synthRes with locs := #[locT] } true == none

/-! ## 2a. Films at hypotheses: used sets, origins, step counts, before/after -/

-- ## at h: a single hypothesis rewrite
#lens_at_used ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h => [Nat.add_zero]
#lens_at_locs ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h => ["h"]
#lens_at_steps ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h => [1]
#lens_at_step ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h frame 0 of h =>
  Nat.add_zero, "n + 0" ~> "n"
#lens_at_hyp ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h => h : "n = 5"
#lens_at_lands ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h => "n = 5"
#lens_at_progress ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h => true

-- ## at h ⊢: one film per location, target processed last
#lens_at_locs ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ => ["h", "⊢"]
#lens_at_steps ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ => [1, 2]
#lens_at_step ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ frame 0 of h =>
  Nat.add_zero, "n + 0" ~> "n"
#lens_at_step ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ frame 0 of ⊢ =>
  Nat.add_zero, "n + 0" ~> "n"
#lens_at_step ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ frame 1 of ⊢ =>
  Nat.add_zero, "n + 0" ~> "n"
#lens_at_hyp ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ => h : "n = 5"
#lens_at_lands ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ => "n = 5"

-- ## at *: wildcard resolves to all non-dependent prop hypotheses + target
#lens_at_locs ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at * => ["h", "⊢"]
#lens_at_locs ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * =>
  ["h₁", "h₂", "⊢"]
#lens_at_steps ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * => [1, 1, 0]
#lens_at_used ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * =>
  [and_true, or_false]
#lens_at_step ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * frame 0 of h₁ =>
  and_true, "p ∧ True" ~> "p"
#lens_at_step ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * frame 0 of h₂ =>
  or_false, "q ∨ False" ~> "q"
#lens_at_hyp ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * => h₁ : "p"
#lens_at_hyp ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * => h₂ : "q"
#lens_at_lands ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * => "p ∧ q"

-- ## a hypothesis simplifying to False closes the goal
#lens_at_used ∀ (p : Prop) (h : ¬True), p at h => [not_true_eq_false]
#lens_at_locs ∀ (p : Prop) (h : ¬True), p at h => ["h"]
#lens_at_step ∀ (p : Prop) (h : ¬True), p at h frame 0 of h =>
  not_true_eq_false, "¬True" ~> "False"
#lens_at_closes ∀ (p : Prop) (h : ¬True), p at h

-- ## fvar origin: h₁ used as a rewrite lemma while simping h₂
#lens_at_used ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂ =>
  [h₁, Nat.add_zero, eq_self]
#lens_at_steps ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂ => [3]
#lens_at_step ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂ frame 0 of h₂ =>
  h₁, "n" ~> "5"
#lens_at_hyp ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂ => h₂ : "True"

-- ## duplicate locations (`at h h`, allowed by core): both passes are traced
#lens_at_locs ∀ (n : Nat) (h : n + 0 + 0 = 5), n = 5 at h h => ["h", "h"]
#lens_at_steps ∀ (n : Nat) (h : n + 0 + 0 = 5), n = 5 at h h => [2, 2]

-- ## explicit `at ⊢` equals the target-only default
#lens_at_locs ∀ n : Nat, n + 0 = n at ⊢ => ["⊢"]
#lens_at_used ∀ n : Nat, n + 0 = n at ⊢ => [Nat.add_zero, eq_self]
#lens_at_closes ∀ n : Nat, n + 0 = n at ⊢

-- ## no progress at the only location
#lens_at_progress ∀ (n : Nat) (h : n = 5), n + 0 = 5 at h => false
#lens_at_steps ∀ (n : Nat) (h : n = 5), n + 0 = 5 at h => [0]
-- progress at ANY location counts (h stuck, ⊢ progresses)
#lens_at_progress ∀ (n : Nat) (h : n = 5), n + 0 = 5 at h ⊢ => true

/-! ## 2b. Minimal calls: location clause preserved, used set is the union -/

#lens_at_min ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h => "simp only [Nat.add_zero] at h"
#lens_at_min ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ =>
  "simp only [Nat.add_zero] at h ⊢"
#lens_at_min ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at * =>
  "simp only [Nat.add_zero] at *"
#lens_at_min ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at * =>
  "simp only [and_true, or_false] at *"
#lens_at_min ∀ (p : Prop) (h : ¬True), p at h => "simp only [not_true_eq_false] at h"
#lens_at_min ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂ =>
  "simp only [Nat.add_zero, h₁] at h₂"

/-! ## 2c. Equivalence per location: traced = plain `simp`, minimal call
replays to the same hypotheses AND goal (full `ppGoal` state compare) -/

#lens_at_equiv ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h
#lens_at_equiv ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢
#lens_at_equiv ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at *
#lens_at_equiv ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at *
#lens_at_equiv ∀ (p : Prop) (h : ¬True), p at h
#lens_at_equiv ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂
#lens_at_equiv ∀ (n : Nat) (h : n + 0 + 0 = 5), n = 5 at h h
#lens_at_equiv ∀ n : Nat, n + 0 = n at ⊢
#lens_at_equiv ∀ (n : Nat) (h : n = 5), n + 0 = 5 at h          -- no-progress parity
#lens_at_equiv ∀ (n : Nat) (h : n = 5), n + 0 = 5 at h ⊢
#lens_at_equiv ∀ (l : List Nat) (h : (l ++ []).length = 3), l.length = 3 at h
#lens_at_equiv ∀ (a b : Nat) (h : (if true then a else b) = a), a = a at h ⊢

/-! ## 2d. Exclusion previews re-run at the same locations -/

-- target not included: previews watch the (first changed) hypothesis
#lens_at_exclude ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h without Nat.add_zero =>
  "n + 0 = 5"
#lens_at_essential ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h without Nat.add_zero => true
-- target included: previews watch the target
#lens_at_exclude ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ without Nat.add_zero =>
  "n + 0 + 0 = 5"
#lens_at_essential ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢ without Nat.add_zero =>
  true
-- excluding the fvar lemma h₁: h₂ still loses its `+ 0` but keeps `n`
#lens_at_exclude ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂ without h₁ =>
  "n = 5"
#lens_at_essential ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂ without h₁ =>
  true

-- ## definitional-only detection at a hypothesis location: h changes by beta
-- reduction alone (no lemma origin), the target closes lemma-driven — only h
-- is flagged definitional-only
#lens_at_defonly ∀ (y : Nat) (h : (fun x : Nat => x) 5 = y), y + 0 = 7 at h ⊢ => ["h"]
#lens_at_hyp ∀ (y : Nat) (h : (fun x : Nat => x) 5 = y), y + 0 = 7 at h ⊢ => h : "5 = y"
#lens_at_steps ∀ (y : Nat) (h : (fun x : Nat => x) 5 = y), y + 0 = 7 at h ⊢ => [0, 1]
#lens_at_lands ∀ (y : Nat) (h : (fun x : Nat => x) 5 = y), y + 0 = 7 at h ⊢ => "y = 7"

/-! ## 2e. Chain-consistency invariants of every location film -/

#lens_at_chain ∀ (n : Nat) (h : n + 0 = 5), n = 5 at h
#lens_at_chain ∀ (n : Nat) (h : n + 0 = 5), n + 0 + 0 = 5 at h ⊢
#lens_at_chain ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at *
#lens_at_chain ∀ (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5), True hyps [h₁] at h₂
#lens_at_chain ∀ (p : Prop) (h : ¬True), p at h

end SimpLensTests.Location

namespace SimpLensTests.Location.Tactic

set_option linter.unusedVariables false

/-! ## 3. `Try this:` pinning with location clauses -/

/-- info: Try this:
  [apply] simp only [Nat.add_zero] at h
-/
#guard_msgs in
example (n : Nat) (h : n + 0 = 5) : n = 5 := by
  simp_lens at h
  exact h

/-- info: Try this:
  [apply] simp only [Nat.add_zero] at h ⊢
-/
#guard_msgs in
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp_lens at h ⊢
  exact h

/-- info: Try this:
  [apply] simp only [Nat.add_zero] at *
-/
#guard_msgs in
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp_lens at *
  exact h

/-- info: Try this:
  [apply] simp only [Nat.add_zero] at ⊢
-/
#guard_msgs in
example (n : Nat) : n + 0 = n := by simp_lens at ⊢

/-- info: Try this:
  [apply] simp only [Nat.add_zero] at h
-/
#guard_msgs in
example (n : Nat) (h : n + 0 = 5) : n = 5 := by
  simp_lens only [Nat.add_zero] at h
  exact h

-- the fvar-origin suggestion names the hypothesis lemma
/-- info: Try this:
  [apply] simp only [h₁, Nat.add_zero] at h₂
-/
#guard_msgs in
example (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5) : True := by
  simp_lens [h₁] at h₂
  trivial

-- duplicate locations are allowed, exactly like core
/-- info: Try this:
  [apply] simp only [Nat.add_zero] at h h
-/
#guard_msgs in
example (n : Nat) (h : n + 0 + 0 = 5) : n = 5 := by
  simp_lens at h h
  exact h

/-! ## 3b. no-progress parity at locations: byte-identical `simp` errors -/

/-- error: `simp` made no progress -/
#guard_msgs in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by simp_lens at h

/-- error: `simp` made no progress -/
#guard_msgs in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by simp at h

-- progress at ANY location counts: h is stuck but ⊢ moves, so no error
#guard_msgs (drop info) in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by
  simp_lens at h ⊢
  exact h

#guard_msgs in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by
  simp at h ⊢
  exact h

/-! ## 3c. `simp_lens at *` has `simp at *` semantics, NOT `simp_all`'s:
hypotheses are not added to each other's simp sets, so a goal `simp_all`
closes can still be "no progress" for both `simp at *` and `simp_lens at *` -/

/-- error: `simp` made no progress -/
#guard_msgs in
example (p q : Prop) (h₁ : p) (h₂ : p → q) : q := by simp_lens at *

/-- error: `simp` made no progress -/
#guard_msgs in
example (p q : Prop) (h₁ : p) (h₂ : p → q) : q := by simp at *

#guard_msgs in
example (p q : Prop) (h₁ : p) (h₂ : p → q) : q := by simp_all

/-! ## 4. twin behavior: identical hypothesis/goal transformations -/

-- hypothesis landing pinned syntactically with `guard_hyp :ₛ`
#guard_msgs (drop info) in
example (n : Nat) (h : n + 0 = 5) : n = 5 := by
  simp_lens at h
  guard_hyp h :ₛ n = 5
  exact h

#guard_msgs in
example (n : Nat) (h : n + 0 = 5) : n = 5 := by
  simp at h
  guard_hyp h :ₛ n = 5
  exact h

-- both locations, hypothesis and target pinned
#guard_msgs (drop info) in
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp_lens at h ⊢
  guard_hyp h :ₛ n = 5
  show n = 5
  exact h

#guard_msgs in
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp at h ⊢
  guard_hyp h :ₛ n = 5
  show n = 5
  exact h

-- wildcard twins
#guard_msgs (drop info) in
example (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False) : p ∧ q := by
  simp_lens at *
  guard_hyp h₁ :ₛ p
  guard_hyp h₂ :ₛ q
  exact ⟨h₁, h₂⟩

#guard_msgs in
example (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False) : p ∧ q := by
  simp at *
  guard_hyp h₁ :ₛ p
  guard_hyp h₂ :ₛ q
  exact ⟨h₁, h₂⟩

-- a hypothesis simplifying to False closes the goal — twin with `simp`
#guard_msgs (drop info) in
example (p : Prop) (h : ¬True) : p := by simp_lens at h

#guard_msgs in
example (p : Prop) (h : ¬True) : p := by simp at h

-- the target closing during `at h ⊢` closes the goal — twin with `simp`
#guard_msgs (drop info) in
example (n : Nat) (h : n + 0 = 5) : n + 0 = n + 0 := by simp_lens at h ⊢

#guard_msgs in
example (n : Nat) (h : n + 0 = 5) : n + 0 = n + 0 := by simp at h ⊢

-- custom discharger with a location; discharger preserved in the suggestion
/-- info: Try this:
  [apply] simp (disch := assumption) only [hf, Nat.add_zero] at h
-/
#guard_msgs in
example (p : Prop) (hp : p) (f : Nat → Nat) (hf : p → f 0 = 0) (h : f 0 + 0 = 0) : True := by
  simp_lens (disch := assumption) [hf] at h
  trivial

/-! ## 4b. the executed location suggestions really replay the proofs -/

#guard_msgs (drop info) in
example (n : Nat) (h : n + 0 = 5) : n = 5 := by
  simp only [Nat.add_zero] at h
  exact h

#guard_msgs (drop info) in
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp only [Nat.add_zero] at h ⊢
  exact h

#guard_msgs (drop info) in
example (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5) : True := by
  simp only [h₁, Nat.add_zero] at h₂
  trivial

end SimpLensTests.Location.Tactic
