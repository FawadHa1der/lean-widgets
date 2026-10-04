import Mathlib
import SimpLens

/-! # Simp Lens: watch every rewrite `simp` makes
Swap `simp` for `simp_lens` and put the cursor on it.  The InfoView shows a
"Simp Lens" panel: the rewrite count (✓ when the goal closed), the minimal
`simp only [...]` call, a filmstrip of numbered frames (lemma badge, pre/post
phase, the rewritten subterm before → after — hover a term for its type) and
exclusion previews (does the call still work without each lemma?).
The Messages panel says `Try this:` — click `[apply]` to replace the
`simp_lens` call by the minimal call (the lightbulb code action does the same). -/

namespace Showcase.SimpLens

-- Repeated and mixed rewrites on the target.
example (n : Nat) : 0 + (n + 0 + 0) = n := by simp_lens

-- List normalization: append, map, id.
example (l : List Nat) : (l ++ []).map id = l.map id ++ [].map id := by simp_lens

-- The code-review scenario: a fat call where only two supplied lemmas fire.
set_option linter.unusedSimpArgs false in
example (n : Nat) (l : List Nat) : n + 0 = n ∧ l ++ [] = l := by
  simp_lens [Nat.add_zero, Nat.zero_add, List.append_nil, List.map_cons, Nat.mul_one]

-- Locations: one filmstrip section per location; the suggestion keeps `at h ⊢`.
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp_lens at h ⊢
  exact h

-- A hypothesis that simplifies to `False` closes the goal ("✓ closes the goal").
example (p : Prop) (h : ¬True) : p := by simp_lens at h

-- `-previews` skips the exclusion re-runs (keeps slow, fat calls cheap).
example (a b : Nat) : (if true then a else b) = a := by simp_lens -previews

end Showcase.SimpLens
