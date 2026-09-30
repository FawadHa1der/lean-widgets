import SimpLens.Tactic

/-!
# Tactic tests — `simp_lens` behaves exactly like `simp`, plus suggestions

`#guard_msgs` pins the exact emitted `Try this: simp only [...]` messages, and
twin examples (`simp_lens` vs `simp`, with `show`-pinned intermediate states)
prove the goal transformation is identical. Error cases must fail with the
byte-identical `simp` error.
-/

namespace SimpLensTests.Tactic

set_option linter.unusedVariables false

/-! ## suggestion pinning -/

/-- info: Try this:
  [apply] simp only [Nat.zero_add]
-/
#guard_msgs in
example (n : Nat) : 0 + n = n := by simp_lens

/-- info: Try this:
  [apply] simp only [Nat.add_zero]
-/
#guard_msgs in
example (n : Nat) : n + 0 + 0 = n := by simp_lens

/-- info: Try this:
  [apply] simp only [List.append_nil]
-/
#guard_msgs in
example (l : List Nat) : l ++ [] = l := by simp_lens

/-- info: Try this:
  [apply] simp only [and_true, or_false]
-/
#guard_msgs in
example (p : Prop) : (p ∧ True) ∨ False ↔ p := by simp_lens

/-- info: Try this:
  [apply] simp only [↓reduceIte]
-/
#guard_msgs in
example (a b : Nat) : (if true then a else b) = a := by simp_lens

/-- info: Try this:
  [apply] simp only [Nat.zero_add]
-/
#guard_msgs in
example (n : Nat) : 0 + n = n := by simp_lens only [Nat.zero_add]

-- an unused supplied lemma is dropped from the suggestion AND flagged by
-- core's `linter.unusedSimpArgs`, exactly like plain `simp` (the linter picks
-- up the info leaf `simp_lens` pushes on its rebuilt `simp` syntax; the
-- hint's one-click fix rewrites the call as the equivalent plain `simp`)
/--
info: Try this:
  [apply] simp only [Nat.zero_add]
---
warning: This simp argument is unused:
  Nat.mul_one

Hint: Omit it from the simp argument list.
  simp_̵l̵e̵n̵s̵ ̵[̵N̵a̵t̵.̵m̵u̵l̵_̵o̵n̵e̵]̵

Note: This linter can be disabled with `set_option linter.unusedSimpArgs false`
-/
#guard_msgs in
example (n : Nat) : 0 + n = n := by simp_lens [Nat.mul_one]

-- the plain `simp` twin of the linter warning above (byte-identical modulo
-- the struck-through call text)
/--
warning: This simp argument is unused:
  Nat.mul_one

Hint: Omit it from the simp argument list.
  simp ̵[̵N̵a̵t̵.̵m̵u̵l̵_̵o̵n̵e̵]̵

Note: This linter can be disabled with `set_option linter.unusedSimpArgs false`
-/
#guard_msgs in
example (n : Nat) : 0 + n = n := by simp [Nat.mul_one]

-- duplicate lemma arguments: only the firing occurrence is suggested
/-- info: Try this:
  [apply] simp only [Nat.add_zero]
-/
#guard_msgs in
example (n : Nat) : n + 0 = n := by simp_lens [Nat.add_zero, Nat.add_zero]

-- a local hypothesis passed as a simp argument (fvar/stx origin)
/-- info: Try this:
  [apply] simp only [h, Nat.add_zero]
-/
#guard_msgs in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by simp_lens [h]

-- `simp_lens only` with a hypothesis
/-- info: Try this:
  [apply] simp only [h]
-/
#guard_msgs in
example (p q : Prop) (h : p ↔ q) (hq : q) : p ↔ q := by simp_lens only [h]

-- partial simplification: suggestion emitted, remaining goal must be exact
/-- info: Try this:
  [apply] simp only [Nat.add_zero]
-/
#guard_msgs in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by simp_lens; exact h

-- goal closed outright
/-- info: Try this:
  [apply] simp only
-/
#guard_msgs in
example : True := by simp_lens

/-! ## error parity: `simp_lens` must fail byte-identically to `simp` -/

/-- error: `simp` made no progress -/
#guard_msgs in
example (p : Prop) (h : p) : p := by simp_lens

/-- error: `simp` made no progress -/
#guard_msgs in
example (p : Prop) (h : p) : p := by simp

-- `failIfUnchanged := false` disables the error, exactly like `simp`
/-- info: Try this:
  [apply] simp (failIfUnchanged := false) only
-/
#guard_msgs in
example (p : Prop) (h : p) : p := by
  simp_lens (failIfUnchanged := false)
  exact h

/-! ## twin behavior: identical goal transformations, pinned via `show` -/

#guard_msgs (drop info) in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by
  simp_lens
  show n = 5   -- fails if simp_lens lands anywhere else
  exact h

#guard_msgs (drop info) in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by
  simp
  show n = 5   -- the `simp` twin of the example above
  exact h

#guard_msgs (drop info) in
example (f : Nat → Nat) (n : Nat) (h : f n = 7) : f (n + 0 + 0) = 7 := by
  simp_lens
  show f n = 7
  exact h

#guard_msgs (drop info) in
example (f : Nat → Nat) (n : Nat) (h : f n = 7) : f (n + 0 + 0) = 7 := by
  simp
  show f n = 7
  exact h

-- twin closing behavior on a goal simp closes outright
#guard_msgs (drop info) in
example (l : List Nat) : (l ++ []).length = l.length := by simp_lens

#guard_msgs (drop info) in
example (l : List Nat) : (l ++ []).length = l.length := by simp

-- `simp_lens only [...]` transforms exactly like `simp only [...]`
#guard_msgs (drop info) in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by
  simp_lens only [Nat.add_zero]
  show n = 5
  exact h

#guard_msgs (drop info) in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by
  simp only [Nat.add_zero]
  show n = 5
  exact h

-- erasure arguments work: `simp_lens [-lemma]` skips that lemma,
-- landing at a goal `or_false` would otherwise have simplified further
#guard_msgs (drop info) in
example (p : Prop) (h : p ∨ False) : (p ∧ True) ∨ False := by
  simp_lens [-or_false]
  show p ∨ False
  exact h

#guard_msgs (drop info) in
example (p : Prop) (h : p ∨ False) : (p ∧ True) ∨ False := by
  simp [-or_false]
  show p ∨ False
  exact h

-- star argument: hypotheses used via `[*]` are named in the suggestion
/-- info: Try this:
  [apply] simp only [Nat.add_zero, h]
-/
#guard_msgs in
example (n : Nat) (h : n = 5) : n + 0 = 5 := by simp_lens [*]

-- custom discharger: side conditions discharged by `assumption`, and the
-- discharger is preserved in the suggestion
/-- info: Try this:
  [apply] simp (disch := assumption) only [h, Nat.add_zero]
-/
#guard_msgs in
example (p : Prop) (hp : p) (f : Nat → Nat) (h : p → f 0 = 0) : f 0 + 0 = 0 := by
  simp_lens (disch := assumption) [h]

/-! ## previews flag: `-previews` / `(previews := false)` skips exclusion
previews (near-1x cost); the suggestion and filmstrip are unaffected -/

/-- info: Try this:
  [apply] simp only [Nat.add_zero]
-/
#guard_msgs in
example (n : Nat) : n + 0 + 0 = n := by simp_lens -previews

/-- info: Try this:
  [apply] simp only [Nat.add_zero]
-/
#guard_msgs in
example (n : Nat) : n + 0 + 0 = n := by simp_lens (previews := false)

/-- info: Try this:
  [apply] simp only [Nat.add_zero]
-/
#guard_msgs in
example (n : Nat) : n + 0 + 0 = n := by simp_lens +previews

-- the flag combines with ordinary simp config (which must still reach core)
/-- info: Try this:
  [apply] simp (failIfUnchanged := false) only
-/
#guard_msgs in
example (p : Prop) (h : p) : p := by
  simp_lens -previews (failIfUnchanged := false)
  exact h

-- a non-literal value is rejected at the value position
/-- error: 'previews' expects a literal 'true' or 'false' -/
#guard_msgs in
example (n : Nat) : n + 0 = n := by simp_lens (previews := 1)

/-! ## timeout parity: `simp_lens` succeeds wherever `simp` does

Regression tests for the escaped-timeout finding: exclusion previews re-run
the full simp call once per used lemma, so they used to (a) multiply the
heartbeat spend inside the surrounding command's budget and (b) leak
heartbeat exceptions through the preview `catch _` (runtime exceptions pass
through `Core.tryCatch`), hard-failing the tactic on goals plain `simp`
handles comfortably. Previews are now heartbeat-neutral and individually
contained, so at a budget plain `simp` barely fits, `simp_lens` must fit
too. -/

-- 8 used lemmas => (1 traced + 8 preview) runs used to share one 250-unit
-- budget; plain simp fits it, so simp_lens must as well
#guard_msgs (drop info) in
set_option maxHeartbeats 250 in
example (a b c d e : Nat) (l : List Nat) :
    ((l ++ []).map (fun x => x + 0)).length = l.length ∧
    (a + 0) * 1 = a ∧ (if true then b else c) = b ∧
    (d + 0 = d ∧ True) ∧ (e ∣ e ↔ True) := by
  simp_lens

-- the plain `simp` twin (documents that the budget is genuinely tight)
#guard_msgs (drop info) in
set_option maxHeartbeats 250 in
example (a b c d e : Nat) (l : List Nat) :
    ((l ++ []).map (fun x => x + 0)).length = l.length ∧
    (a + 0) * 1 = a ∧ (if true then b else c) = b ∧
    (d + 0 = d ∧ True) ∧ (e ∣ e ↔ True) := by
  simp

-- and the explicit opt-out works under the same budget
#guard_msgs (drop info) in
set_option maxHeartbeats 250 in
example (a b c d e : Nat) (l : List Nat) :
    ((l ++ []).map (fun x => x + 0)).length = l.length ∧
    (a + 0) * 1 = a ∧ (if true then b else c) = b ∧
    (d + 0 = d ∧ True) ∧ (e ∣ e ↔ True) := by
  simp_lens -previews

/-! ## slow-discharger parity: every preview re-run repeats the (expensive)
side-condition discharge, so a slow discharger used to multiply into a
timeout; the budget below fits plain `simp` with little slack (it fails at
maxHeartbeats 40), and `simp_lens` must fit it too -/

/-- Identity wrapper whose unfolding lemma carries a side condition. -/
def slowG (n : Nat) : Nat := n

/-- Conditional rewrite: firing it makes the discharger *compute* the range
sum (`decide` burns heartbeats on every attempt, including preview re-runs). -/
theorem slowG_eq (n : Nat) (h : (List.range 40).sum = 780) : slowG n = n := rfl

/-- info: Try this:
  [apply] simp (disch := decide) only [Nat.add_zero, slowG_eq]
-/
#guard_msgs in
set_option maxHeartbeats 60 in
example (n : Nat) : slowG (n + 0) = n := by
  simp_lens (disch := decide) [slowG_eq]

-- the plain `simp` twin under the same tight budget
#guard_msgs (drop info) in
set_option maxHeartbeats 60 in
example (n : Nat) : slowG (n + 0) = n := by
  simp (disch := decide) [slowG_eq]

/-! ## purely definitional progress (finding repro): the tactic succeeds,
transforms the goal by beta reduction, and suggests the replayable
`simp only` — the panel reports "definitional reductions only" instead of a
bare "0 rewrites" (pinned at the data level in TraceTests/FilmTests) -/

/-- info: Try this:
  [apply] simp only
-/
#guard_msgs in
example (y : Nat) (h : 5 = y) : (fun x : Nat => x) 5 = y := by
  simp_lens only []
  show 5 = y   -- fails if the beta-only run lands anywhere else
  exact h

-- the plain `simp` twin: identical transformation
#guard_msgs (drop info) in
example (y : Nat) (h : 5 = y) : (fun x : Nat => x) 5 = y := by
  simp only []
  show 5 = y
  exact h

/-! ## the executed suggestion really replays the proof -/

#guard_msgs (drop info) in
example (n : Nat) : n + 0 + 0 = n := by simp only [Nat.add_zero]

#guard_msgs (drop info) in
example (p : Prop) : (p ∧ True) ∨ False ↔ p := by simp only [and_true, or_false]

end SimpLensTests.Tactic
