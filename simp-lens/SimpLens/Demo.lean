import SimpLens.Tactic

/-!
# SimpLens.Demo — realistic examples

Open this file in VS Code and put the cursor on any `simp_lens` call: the
InfoView shows the *Simp Lens* filmstrip panel (every rewrite in order with
before/after, the minimal call, exclusion previews), plus a clickable
`Try this: simp only [...]` suggestion.

These examples elaborate on every build, so the whole pipeline (tracing,
minimization, exclusion previews, rendering, widget attachment) is exercised
by `lake build`. The `Try this:` info messages printed during the build are
expected output, and are pinned by `#guard_msgs` so demo drift fails the
build.
-/

namespace SimpLens.Demo

/-- info: Try this:
  [apply] simp only [Nat.zero_add]
-/
#guard_msgs in
/-- Arithmetic: a single rewrite. -/
example (n : Nat) : 0 + n = n := by simp_lens

/-- info: Try this:
  [apply] simp only [Nat.add_zero, Nat.zero_add]
-/
#guard_msgs in
/-- Arithmetic: repeated and mixed rewrites. -/
example (n : Nat) : 0 + (n + 0 + 0) = n := by simp_lens

/-- info: Try this:
  [apply] simp only [List.append_nil, List.map_id_fun, id_eq, List.map_nil]
-/
#guard_msgs in
/-- Lists: append/map normalization. -/
example (l : List Nat) : (l ++ []).map id = l.map id ++ [].map id := by simp_lens

/-- info: Try this:
  [apply] simp only [and_true, or_false]
-/
#guard_msgs in
/-- Logic: connective cleanup. -/
example (p : Prop) : (p ∧ True) ∨ False ↔ p := by simp_lens

/-- info: Try this:
  [apply] simp only [↓reduceIte]
-/
#guard_msgs in
/-- A simproc (`reduceIte`) shows up in the minimal call like any lemma. -/
example (a b : Nat) : (if true then a else b) = a := by simp_lens

/-- info: Try this:
  [apply] simp only [h, Nat.add_zero]
-/
#guard_msgs in
/-- Local hypotheses used as simp lemmas appear by their user-facing name. -/
example (n : Nat) (h : n = 5) : n + 0 = 5 := by simp_lens [h]

/-- info: Try this:
  [apply] simp only [Nat.add_zero, List.append_nil, and_self]
-/
#guard_msgs in
set_option linter.unusedSimpArgs false in  -- 4 warnings; pinned separately below
/-- The review scenario: a deliberately fat `simp` call. Simp Lens shows that
only two of the six supplied lemmas fire (plus default `and_self`), and
suggests the three-lemma minimal call. (The unused-argument linter would also
flag the four unused lemmas, exactly like plain `simp` — demonstrated in the
next example — so it is silenced here to keep this pin focused on the
suggestion.) -/
example (n : Nat) (l : List Nat) : n + 0 = n ∧ l ++ [] = l := by
  simp_lens [Nat.add_zero, Nat.zero_add, List.append_nil, List.map_cons,
             Nat.mul_one, and_true]

/--
info: Try this:
  [apply] simp only [Nat.zero_add]
---
warning: This simp argument is unused:
  Nat.mul_one

Hint: Omit it from the simp argument list.
  [apply] simp

Note: This linter can be disabled with `set_option linter.unusedSimpArgs false`
-/
#guard_msgs in
/-- `linter.unusedSimpArgs` parity: a supplied lemma that never fires gets the
same "This simp argument is unused" warning (with the `[apply] simp` hint;
v4.34's linter renders the hint without a diff, so the text is now
byte-identical to plain `simp`'s)
that plain `simp` produces. -/
example (n : Nat) : 0 + n = n := by simp_lens [Nat.mul_one]

/-- info: Try this:
  [apply] simp only [Nat.add_zero, Nat.zero_add]
-/
#guard_msgs in
/-- `-previews` (or `(previews := false)`) skips the exclusion previews for
near-`simp` cost: the panel shows the filmstrip and minimal call with an
"Exclusion previews disabled" note, and the `Try this:` suggestion is
unchanged. Useful on slow fat calls where re-running simp once per used
lemma is not worth the wait. -/
example (n : Nat) : 0 + (n + 0 + 0) = n := by simp_lens -previews

/-- info: Try this:
  [apply] simp only
-/
#guard_msgs in
/-- Purely definitional progress: beta reduction has no lemma origin, so
there are no frames to show — the panel header says
"0 rewrites (definitional reductions only)" instead of pretending nothing
happened, and the suggested `simp only` replays the same reduction. -/
example (y : Nat) (h : 5 = y) : (fun x : Nat => x) 5 = y := by
  simp_lens only []
  exact h

/-- info: Try this:
  [apply] simp only [Nat.add_zero] at h
-/
#guard_msgs in
/-- Locations: simplify a hypothesis instead of the target. The filmstrip
section is headed `at h`, and the suggestion keeps the location clause. -/
example (n : Nat) (h : n + 0 = 5) : n = 5 := by
  simp_lens at h
  exact h

/-- info: Try this:
  [apply] simp only [Nat.add_zero] at h ⊢
-/
#guard_msgs in
/-- Locations: hypothesis and target together — one filmstrip section per
location, minimal call over the union of used lemmas. -/
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp_lens at h ⊢
  exact h

/-- info: Try this:
  [apply] simp only [and_true, or_false] at *
-/
#guard_msgs in
/-- `at *`: every non-dependent propositional hypothesis plus the target,
exactly like `simp at *` (not `simp_all`). -/
example (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False) : p ∧ q := by
  simp_lens at *
  exact ⟨h₁, h₂⟩

/-- info: Try this:
  [apply] simp only [h₁, Nat.add_zero] at h₂
-/
#guard_msgs in
set_option linter.unusedVariables false in
/-- A hypothesis (`h₁`) used as a rewrite rule while simplifying another
(`h₂`): the fvar origin appears in the film and in the suggestion. -/
example (n : Nat) (h₁ : n = 5) (h₂ : n + 0 = 5) : True := by
  simp_lens [h₁] at h₂
  trivial

/-- info: Try this:
  [apply] simp only [not_true_eq_false] at h
-/
#guard_msgs in
set_option linter.unusedVariables false in
/-- A hypothesis that simplifies to `False` closes the goal, exactly like
`simp at h` — the `at h` filmstrip section shows `✓ closes the goal`. -/
example (p : Prop) (h : ¬True) : p := by simp_lens at h

end SimpLens.Demo
