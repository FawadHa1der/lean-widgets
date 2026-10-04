import Mathlib
import IntervalInspector

/-! # Interval Inspector: interval goals as a labeled number line
Cursor on a `#interval_inspect` line: an "HTML Display" panel draws the sets
as bars on one axis (filled dot = closed end, hollow = open), shades regions
that break `⊆`/`=` in red, and lists the Mathlib lemmas that apply, with each
side condition marked ready ✓ / missing ✗.
Cursor on `interval_inspect?` inside a proof: the same panel for the current
goal, and every suggested tactic is a link — click one to replace the
`interval_inspect?` line with it (each proof's last line closes the goal both
before and after any click).  Shift-click `hx` in the goal view (last proof)
to draw that hypothesis instead of the goal. -/

namespace Showcase.IntervalInspector

-- Two half-open bars meeting at 2; suggests `Set.Ioc_union_Ioc_eq_Ioc`.
#interval_inspect (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)

-- A mismatch: [0, 3] ⊄ [1, 2]; the uncovered regions are shaded red.
#interval_inspect (Set.Icc (0:ℝ) 3 ⊆ Set.Icc 1 2)

-- Membership: a purple marker for the member.
#interval_inspect ((3:ℝ) ∈ Set.Icc 1 4)

-- Nonemptiness: the caption ties the shape to its order condition.
#interval_inspect (Set.Ioc (1:ℝ) 2).Nonempty

-- Honest over ℕ: no `DenselyOrdered`, so no mismatch shading on (1, 2).
#interval_inspect (Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1)

-- Each proof's last line has one branch for before a click and one for after
-- it; these two linters would flag whichever branch does not run.
set_option linter.unreachableTactic false
set_option linter.unusedTactic false

-- In a proof: both side conditions of the suggestion are ✓ ready from h₁ h₂.
-- Clicking `refine …` leaves exactly those two goals, closed by `assumption`.
example {a b c : ℝ} (h₁ : a ≤ b) (h₂ : b ≤ c) :
    Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c := by
  interval_inspect?
  all_goals first | exact Set.Ioc_union_Ioc_eq_Ioc h₁ h₂ | assumption

-- A set-builder goal recognised as `Ico`: click `exact Set.Ico_subset_Icc_self`.
example : {x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1 := by
  interval_inspect?
  all_goals exact Set.Ico_subset_Icc_self

-- Shift-click `hx`: the panel switches to the hypothesis.  Both views suggest
-- `refine Set.mem_Ioo.mpr ⟨?_, ?_⟩`; its goals `0 < x`, `x < 2` close below.
example {x : ℝ} (hx : x ∈ Set.Ioo (0:ℝ) 1) : x ∈ Set.Ioo (0:ℝ) 2 := by
  interval_inspect?
  all_goals first
    | exact ⟨hx.1, hx.2.trans one_lt_two⟩ | exact hx.1 | exact hx.2.trans one_lt_two

end Showcase.IntervalInspector
